#pragma warning disable OPENAI001
using AgentWebApp.Models;
using OpenAI.Responses;
using System.Diagnostics;
using System.Text;

namespace AgentWebApp.Services;

/// <summary>
/// Implementation of the custom AI agent using a model deployed in Microsoft Foundry.
/// This implementation demonstrates the RAG (Retrieval Augmented Generation) pattern:
/// 1. Query Azure AI Search for relevant context
/// 2. Send context + user question to the Foundry Responses API
/// 3. Return intelligent, grounded response
/// </summary>
public class AgentService : IAgentService
{
    private readonly ISearchService _searchService;
    private readonly IConfiguration _configuration;
    private readonly ILogger<AgentService> _logger;
    private readonly ResponsesClient _responsesClient;

    public AgentService(
        ISearchService searchService,
        IConfiguration configuration,
        ILogger<AgentService> logger,
        ResponsesClient responsesClient)
    {
        _searchService = searchService;
        _configuration = configuration;
        _logger = logger;
        _responsesClient = responsesClient ?? throw new ArgumentNullException(nameof(responsesClient));
    }

    public async Task<ChatResponse> ProcessMessageAsync(
        ChatRequest request, 
        CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        var conversationId = request.ConversationId ?? Guid.NewGuid().ToString();

        try
        {
            _logger.LogInformation(
                "Processing message for conversation {ConversationId}: {Message}", 
                conversationId, 
                request.Message
            );

            // Step 1: Search for relevant context using Azure AI Search
            var searchResults = await _searchService.SearchAsync(
                request.Message, 
                maxResults: 5, 
                cancellationToken
            );

            // Step 2: Build context from search results
            var contextBuilder = new StringBuilder();
            var citations = new List<Citation>();

            await foreach (var result in searchResults.GetResultsAsync())
            {
                var document = result.Document;
                
                // Extract content from document
                var content = document.TryGetValue("content", out var contentValue) 
                    ? contentValue?.ToString() ?? string.Empty 
                    : string.Empty;
                
                var source = document.TryGetValue("metadata_storage_name", out var sourceValue)
                    ? sourceValue?.ToString() ?? "Unknown"
                    : "Unknown";

                if (!string.IsNullOrEmpty(content))
                {
                    contextBuilder.AppendLine($"Source: {source}");
                    contextBuilder.AppendLine(content);
                    contextBuilder.AppendLine();

                    citations.Add(new Citation
                    {
                        Source = source,
                        Content = content.Length > 200 ? content.Substring(0, 200) + "..." : content,
                        Confidence = result.Score ?? 0.0
                    });
                }
            }

            // Step 3: Call the model deployed in Foundry with context
            var agentResponse = await CallFoundryModelAsync(
                request.Message,
                contextBuilder.ToString(),
                conversationId,
                cancellationToken
            );

            stopwatch.Stop();

            return new ChatResponse
            {
                Message = agentResponse,
                ConversationId = conversationId,
                Citations = citations.Count > 0 ? citations : null,
                Metadata = new ResponseMetadata
                {
                    Timestamp = DateTime.UtcNow,
                    Model = _configuration["Foundry:ModelDeploymentName"] ?? "gpt-5.4-mini",
                    ProcessingTimeMs = stopwatch.ElapsedMilliseconds
                }
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message for conversation {ConversationId}", conversationId);
            throw;
        }
    }

    private async Task<string> CallFoundryModelAsync(
        string userMessage,
        string context,
        string conversationId,
        CancellationToken cancellationToken)
    {
        try
        {
            var deploymentName = _configuration["Foundry:ModelDeploymentName"] ?? "gpt-5.4-mini";
            
            _logger.LogInformation("Calling Foundry model deployment: {DeploymentName}", deploymentName);

            // Build messages for chat completion
            var systemPrompt = @"You are a helpful conference expert assistant specializing in Microsoft Ignite and Build conferences. 
Your role is to answer questions about the Expert Meet-up sessions at these conferences.

When answering:
- Pay CLOSE ATTENTION to years/dates in the question (e.g., 2024 vs 2025 vs 2026)
- Only use information from the CORRECT year mentioned in the question
- Be concise and direct (3-4 sentences when possible)
- Use the provided context to ground your responses
- If the context doesn't contain information for the specific year requested, say so clearly
- Focus on helping users understand session topics, schedules, and expert areas
- Don't make up information - only use what's in the context
- Always mention which conference and year you're answering about";

            var userPrompt = string.IsNullOrEmpty(context)
                ? userMessage
                : $@"Context from conference documents:
{context}

Question: {userMessage}

Please answer based on the context provided above.";

            var responseOptions = new CreateResponseOptions
            {
                Model = deploymentName,
                MaxOutputTokenCount = 800
            };
            responseOptions.InputItems.Add(ResponseItem.CreateUserMessageItem($"{systemPrompt}\n\n{userPrompt}"));

            _logger.LogDebug("Sending request to the Foundry Responses API...");
            var response = await _responsesClient.CreateResponseAsync(responseOptions, cancellationToken);
            
            var responseText = response.Value.GetOutputText();
            _logger.LogInformation("Received response from Foundry ({Length} characters)", responseText.Length);
            
            return responseText;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error calling the Foundry model deployment");
            
            // Fall back to a simple response if model inference fails.
            return GenerateFallbackResponse(userMessage, context);
        }
    }

    private string GenerateFallbackResponse(string userMessage, string context)
    {
        // Simple fallback for the workshop
        // In production, replace this workshop fallback with an explicit error response.
        
        if (string.IsNullOrEmpty(context))
        {
            return "I don't have enough information to answer that question. Please try rephrasing or asking about Microsoft Ignite or Build conferences.";
        }

        // Extract just the first result to avoid mixing conferences
        var lines = context.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
        var firstSourceIndex = Array.FindIndex(lines, l => l.StartsWith("Source:"));
        
        if (firstSourceIndex >= 0 && lines.Length > firstSourceIndex + 1)
        {
            var source = lines[firstSourceIndex];
            var content = string.Join("\n", lines.Skip(firstSourceIndex + 1)
                .TakeWhile(l => !l.StartsWith("Source:"))
                .Take(15)); // Limit to first 15 lines for readability
            
            return $"Based on the conference information I found:\n\n{source}\n{content}\n\nWould you like to know more about specific topics or sessions?";
        }

        return $"Based on the conference information I found:\n\n{context.Substring(0, Math.Min(400, context.Length))}...\n\nWould you like to know more?";
    }
}
