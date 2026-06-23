using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using AgentWebApp.Models;
using Azure.Core;

namespace AgentWebApp.Services;

/// <summary>
/// Path 2 agent service. Unlike Path 1 (which performed RAG itself by calling
/// Azure AI Search + Azure OpenAI), this implementation is a thin client over a
/// Microsoft Foundry <b>prompt agent</b>.
///
/// The agent already owns its instructions (persona), model deployment, and the
/// connected knowledge base. A New Foundry prompt agent is invoked through the
/// OpenAI <b>Responses API</b> bound to the agent endpoint and addressed by name:
///
///   POST {projectEndpoint}/agents/{agentName}/endpoint/protocols/openai/responses
///        ?api-version=2025-11-15-preview
///
/// This service only:
///   1. Sends the user's message as the Responses "input",
///   2. Chains multi-turn context via "previous_response_id",
///   3. Returns the agent's grounded reply and any citations.
///
/// Foundry performs the retrieval/grounding against the knowledge base internally.
/// </summary>
public class FoundryAgentService : IAgentService
{
    // Scope for the Foundry data plane (Agents / Responses API).
    private const string FoundryScope = "https://ai.azure.com/.default";
    private const string ApiVersion = "2025-11-15-preview";

    private readonly HttpClient _httpClient;
    private readonly TokenCredential _credential;
    private readonly ILogger<FoundryAgentService> _logger;
    private readonly string _responsesUrl;
    private readonly string _agentName;

    public FoundryAgentService(
        HttpClient httpClient,
        TokenCredential credential,
        IConfiguration configuration,
        ILogger<FoundryAgentService> logger)
    {
        _httpClient = httpClient;
        _credential = credential;
        _logger = logger;

        var projectEndpoint = configuration["Foundry:ProjectEndpoint"]
            ?? throw new InvalidOperationException(
                "Foundry project endpoint is not configured. Ensure the " +
                "Foundry-ProjectEndpoint secret is mounted at /mnt/secrets-store/ " +
                "or configured in appsettings.json.");

        _agentName = configuration["Foundry:AgentName"]
            ?? throw new InvalidOperationException(
                "Foundry agent name is not configured. Ensure the Foundry-AgentName " +
                "secret is mounted at /mnt/secrets-store/ or configured in appsettings.json.");

        _responsesUrl =
            $"{projectEndpoint.TrimEnd('/')}/agents/{_agentName}/endpoint/protocols/openai/responses" +
            $"?api-version={ApiVersion}";
    }

    public async Task<ChatResponse> ProcessMessageAsync(
        ChatRequest request,
        CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            _logger.LogInformation(
                "Calling Foundry agent {AgentName} (previous response: {Previous})",
                _agentName,
                string.IsNullOrWhiteSpace(request.ConversationId) ? "<none>" : request.ConversationId);

            // Build the Responses API request. The agent owns its instructions/model/
            // knowledge, so we only send the user's input plus (optionally) the prior
            // response id to continue the conversation.
            var payload = new Dictionary<string, object?>
            {
                ["input"] = request.Message
            };

            if (!string.IsNullOrWhiteSpace(request.ConversationId))
            {
                payload["previous_response_id"] = request.ConversationId;
            }

            using var httpRequest = new HttpRequestMessage(HttpMethod.Post, _responsesUrl)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json")
            };

            var token = await _credential.GetTokenAsync(
                new TokenRequestContext(new[] { FoundryScope }), cancellationToken);
            httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);

            using var httpResponse = await _httpClient.SendAsync(httpRequest, cancellationToken);
            var responseBody = await httpResponse.Content.ReadAsStringAsync(cancellationToken);

            if (!httpResponse.IsSuccessStatusCode)
            {
                _logger.LogError(
                    "Foundry Responses API returned {Status}: {Body}",
                    (int)httpResponse.StatusCode, responseBody);

                return new ChatResponse
                {
                    Message = "Sorry, I couldn't process that request. Please try again.",
                    ConversationId = request.ConversationId ?? string.Empty,
                    Metadata = BuildMetadata(stopwatch)
                };
            }

            var (answer, citations, responseId) = ParseResponse(responseBody);

            stopwatch.Stop();

            return new ChatResponse
            {
                Message = string.IsNullOrWhiteSpace(answer)
                    ? "I don't have an answer for that right now."
                    : answer,
                // Track the response id so the next turn can continue the conversation.
                ConversationId = string.IsNullOrWhiteSpace(responseId)
                    ? (request.ConversationId ?? string.Empty)
                    : responseId,
                Citations = citations.Count > 0 ? citations : null,
                Metadata = BuildMetadata(stopwatch)
            };
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message through the Foundry agent");
            throw;
        }
    }

    /// <summary>
    /// Extracts the assistant text, citations, and response id from a Responses API payload.
    /// The relevant text lives at: output[] where type == "message" -> content[] where
    /// type == "output_text" -> text. URL citations are in that item's "annotations".
    /// </summary>
    private static (string Answer, List<Citation> Citations, string ResponseId) ParseResponse(string body)
    {
        var citations = new List<Citation>();
        var answer = new StringBuilder();
        var responseId = string.Empty;

        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;

        if (root.TryGetProperty("id", out var idElement))
        {
            responseId = idElement.GetString() ?? string.Empty;
        }

        if (!root.TryGetProperty("output", out var output)
            || output.ValueKind != JsonValueKind.Array)
        {
            return (answer.ToString(), citations, responseId);
        }

        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("type", out var itemType)
                || itemType.GetString() != "message")
            {
                continue;
            }

            if (!item.TryGetProperty("content", out var content)
                || content.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            foreach (var part in content.EnumerateArray())
            {
                if (!part.TryGetProperty("type", out var partType)
                    || partType.GetString() != "output_text")
                {
                    continue;
                }

                if (part.TryGetProperty("text", out var textElement))
                {
                    answer.Append(textElement.GetString());
                }

                if (part.TryGetProperty("annotations", out var annotations)
                    && annotations.ValueKind == JsonValueKind.Array)
                {
                    foreach (var annotation in annotations.EnumerateArray())
                    {
                        if (annotation.TryGetProperty("type", out var annType)
                            && annType.GetString() == "url_citation")
                        {
                            var url = annotation.TryGetProperty("url", out var u) ? u.GetString() : null;
                            var title = annotation.TryGetProperty("title", out var t) ? t.GetString() : null;

                            if (!string.IsNullOrWhiteSpace(url))
                            {
                                citations.Add(new Citation
                                {
                                    Source = title ?? url!,
                                    Content = url!,
                                    Confidence = 1.0
                                });
                            }
                        }
                    }
                }
            }
        }

        return (answer.ToString(), citations, responseId);
    }

    private static ResponseMetadata BuildMetadata(Stopwatch stopwatch)
    {
        stopwatch.Stop();
        return new ResponseMetadata
        {
            Timestamp = DateTime.UtcNow,
            Model = "foundry-agent",
            ProcessingTimeMs = stopwatch.ElapsedMilliseconds
        };
    }
}
