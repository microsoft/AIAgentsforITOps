using AgentWebApp.Models;

namespace AgentWebApp.Services;

/// <summary>
/// Interface for the AI Agent service.
/// </summary>
public interface IAgentService
{
    /// <summary>
    /// Process a chat message through the Foundry-hosted prompt agent.
    /// </summary>
    Task<ChatResponse> ProcessMessageAsync(ChatRequest request, CancellationToken cancellationToken = default);
}
