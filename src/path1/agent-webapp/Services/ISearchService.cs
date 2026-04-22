using Azure.Search.Documents;
using Azure.Search.Documents.Models;

namespace AgentWebApp.Services;

/// <summary>
/// Interface for Azure AI Search service
/// </summary>
public interface ISearchService
{
    /// <summary>
    /// Search for relevant conference information
    /// </summary>
    Task<SearchResults<SearchDocument>> SearchAsync(string query, int maxResults = 5, CancellationToken cancellationToken = default);

    /// <summary>
    /// Get document by ID
    /// </summary>
    Task<SearchDocument?> GetDocumentAsync(string documentId, CancellationToken cancellationToken = default);
}
