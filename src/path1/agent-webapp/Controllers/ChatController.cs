using AgentWebApp.Models;
using AgentWebApp.Services;
using Microsoft.AspNetCore.Mvc;

namespace AgentWebApp.Controllers;

/// <summary>
/// Chat API controller for interacting with the conference expert agent
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class ChatController : ControllerBase
{
    private readonly IAgentService _agentService;
    private readonly ILogger<ChatController> _logger;

    public ChatController(IAgentService agentService, ILogger<ChatController> logger)
    {
        _agentService = agentService;
        _logger = logger;
    }

    /// <summary>
    /// Send a message to the agent
    /// </summary>
    /// <param name="request">Chat request containing the user message</param>
    /// <param name="cancellationToken">Cancellation token</param>
    /// <returns>Agent response with citations and metadata</returns>
    [HttpPost]
    [ProducesResponseType(typeof(ChatResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<ChatResponse>> SendMessage(
        [FromBody] ChatRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return BadRequest(new { error = "Message cannot be empty" });
        }

        try
        {
            _logger.LogInformation("Received chat request: {Message}", request.Message);
            
            var response = await _agentService.ProcessMessageAsync(request, cancellationToken);
            
            return Ok(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing chat request");
            return StatusCode(500, new { error = "An error occurred processing your request" });
        }
    }

    /// <summary>
    /// Get agent information
    /// </summary>
    [HttpGet("info")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult<object> GetAgentInfo()
    {
        return Ok(new
        {
            name = "Conference Expert Agent",
            description = "AI agent that answers questions about Microsoft Ignite and Build conferences",
            version = "1.0.0",
            capabilities = new[]
            {
                "Answer questions about conference sessions",
                "Provide information about Expert Meet-up areas",
                "Search conference schedules",
                "Recommend relevant sessions"
            }
        });
    }
}
