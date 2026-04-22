using Azure;
using Azure.Identity;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;

namespace AgentWebApp.Services;

/// <summary>
/// Implementation of Azure AI Search service
/// </summary>
public class SearchService : ISearchService
{
    private readonly SearchClient _searchClient;
    private readonly ILogger<SearchService> _logger;

    public SearchService(IConfiguration configuration, DefaultAzureCredential credential, ILogger<SearchService> logger)
    {
        var searchEndpoint = configuration["AzureSearch:Endpoint"] 
            ?? throw new InvalidOperationException("AzureSearch:Endpoint not configured");
        var indexName = configuration["AzureSearch:IndexName"] 
            ?? throw new InvalidOperationException("AzureSearch:IndexName not configured");

        _searchClient = new SearchClient(
            new Uri(searchEndpoint),
            indexName,
            credential
        );

        _logger = logger;
    }

    public async Task<SearchResults<SearchDocument>> SearchAsync(
        string query, 
        int maxResults = 5, 
        CancellationToken cancellationToken = default)
    {
        try
        {
            var searchOptions = new SearchOptions
            {
                Size = maxResults,
                IncludeTotalCount = true
            };

            // Add filter based on conference name if mentioned in query
            if (query.Contains("Ignite", StringComparison.OrdinalIgnoreCase))
            {
                searchOptions.Filter = "search.ismatch('Ignite*', 'metadata_storage_name')";
                _logger.LogInformation("Filtering for Ignite documents");
            }
            else if (query.Contains("Build", StringComparison.OrdinalIgnoreCase))
            {
                searchOptions.Filter = "search.ismatch('Build*', 'metadata_storage_name')";
                _logger.LogInformation("Filtering for Build documents");
            }

            _logger.LogInformation("Searching for: {Query}", query);
            
            var response = await _searchClient.SearchAsync<SearchDocument>(
                query, 
                searchOptions, 
                cancellationToken
            );

            return response.Value;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error searching Azure AI Search for query: {Query}", query);
            throw;
        }
    }

    public async Task<SearchDocument?> GetDocumentAsync(
        string documentId, 
        CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _searchClient.GetDocumentAsync<SearchDocument>(
                documentId, 
                cancellationToken: cancellationToken
            );

            return response.Value;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogWarning("Document not found: {DocumentId}", documentId);
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving document: {DocumentId}", documentId);
            throw;
        }
    }
}
