using AgentWebApp.Models;

namespace AgentWebApp.Services;

/// <summary>
/// Interface for AI Agent service
/// </summary>
public interface IAgentService
{
    /// <summary>
    /// Process a chat message through the AI agent
    /// </summary>
    Task<ChatResponse> ProcessMessageAsync(ChatRequest request, CancellationToken cancellationToken = default);
}
