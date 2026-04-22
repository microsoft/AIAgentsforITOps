using AgentWebApp.Models;
using Azure.AI.OpenAI;
using Azure.Identity;
using OpenAI.Chat;
using System.Diagnostics;
using System.Text;

namespace AgentWebApp.Services;

/// <summary>
/// Implementation of AI Agent service using Azure OpenAI
/// This implementation demonstrates the RAG (Retrieval Augmented Generation) pattern:
/// 1. Query Azure AI Search for relevant context
/// 2. Send context + user question to Azure OpenAI
/// 3. Return intelligent, grounded response
/// </summary>
public class AgentService : IAgentService
{
    private readonly ISearchService _searchService;
    private readonly IConfiguration _configuration;
    private readonly DefaultAzureCredential _credential;
    private readonly ILogger<AgentService> _logger;
    private readonly HttpClient _httpClient;
    private readonly AzureOpenAIClient _openAIClient;

    public AgentService(
        ISearchService searchService,
        IConfiguration configuration,
        DefaultAzureCredential credential,
        ILogger<AgentService> logger,
        IHttpClientFactory httpClientFactory,
        AzureOpenAIClient openAIClient)
    {
        _searchService = searchService;
        _configuration = configuration;
        _credential = credential;
        _logger = logger;
        _httpClient = httpClientFactory.CreateClient();
        _openAIClient = openAIClient ?? throw new ArgumentNullException(nameof(openAIClient), "Azure OpenAI client is required");
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

            // Step 3: Call Azure OpenAI with context
            var agentResponse = await CallAzureOpenAIAsync(
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
                    Model = _configuration["AzureOpenAI:DeploymentName"] ?? "gpt-4.1-mini",
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

    private async Task<string> CallAzureOpenAIAsync(
        string userMessage,
        string context,
        string conversationId,
        CancellationToken cancellationToken)
    {
        try
        {
            var deploymentName = _configuration["AzureOpenAI:DeploymentName"] ?? "gpt-4.1-mini";
            
            _logger.LogInformation("Calling Azure OpenAI deployment: {DeploymentName}", deploymentName);

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

            var chatClient = _openAIClient.GetChatClient(deploymentName);
            
            var chatMessages = new List<ChatMessage>
            {
                new SystemChatMessage(systemPrompt),
                new UserChatMessage(userPrompt)
            };

            var chatOptions = new ChatCompletionOptions
            {
                MaxOutputTokenCount = 800,
                Temperature = 0.7f
            };

            _logger.LogDebug("Sending request to Azure OpenAI...");
            var response = await chatClient.CompleteChatAsync(chatMessages, chatOptions, cancellationToken);
            
            var responseText = response.Value.Content[0].Text;
            _logger.LogInformation("Received response from Azure OpenAI ({Length} characters)", responseText.Length);
            
            return responseText;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error calling Azure OpenAI");
            
            // Fall back to simple response if OpenAI fails
            return GenerateFallbackResponse(userMessage, context);
        }
    }

    private string GenerateFallbackResponse(string userMessage, string context)
    {
        // Simple fallback for the workshop
        // In production, this would be the actual Foundry agent call
        
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
