function New-WorkshopSearchService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnablePrivateEndpoint = $false,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    $searchServiceName = "$Prefix-search-$Environment".ToLower()
    
    Write-InfoLog "Creating Azure AI Search service: $searchServiceName"
    
    # Check if Azure CLI is available (needed for some operations)
    if (-not (Test-AzureCLI)) {
        Write-WarningLog "Azure CLI not found. Some features may be limited."
    }
    
    # Create using Azure CLI (better support for AI Search)
    $existingSearch = az search service show --name $searchServiceName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    
    if ($existingSearch) {
        Write-WarningLog "Search service '$searchServiceName' already exists"
        
        # Ensure Azure AD authentication is enabled
        Write-InfoLog "Enabling Azure AD authentication on existing search service"
        az search service update `
            --name $searchServiceName `
            --resource-group $ResourceGroupName `
            --auth-options aadOrApiKey `
            --aad-auth-failure-mode http403 `
            2>&1 | Out-Null
    } else {
        Write-InfoLog "Creating search service (this may take several minutes)..."
        
        # NOTE (Path 2): Azure AI Search is the backing store for the Foundry
        # Knowledge Base. Unlike Path 1, we do NOT create an index or indexer here.
        # When you connect this Search service to a Foundry Knowledge Base in the
        # portal, Foundry provisions and manages the index, vectorization, and
        # ingestion pipeline for you. We only need the service to exist with a
        # managed identity and Azure AD auth so Foundry can connect to it.
        az search service create `
            --name $searchServiceName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku Basic `
            --partition-count 1 `
            --replica-count 1 `
            --auth-options aadOrApiKey `
            --aad-auth-failure-mode http403 `
            --public-network-access $(if ($EnablePrivateEndpoint) { "disabled" } else { "enabled" }) `
            | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create search service"
        }
        
        Write-SuccessLog "Search service created: $searchServiceName"
    }
    
    # Get search service details to check identity
    $searchService = az search service show `
        --name $searchServiceName `
        --resource-group $ResourceGroupName `
        | ConvertFrom-Json
    
    # Enable managed identity (if not already enabled)
    if (-not $searchService.identity -or $searchService.identity.type -ne "SystemAssigned") {
        Write-InfoLog "Enabling system-assigned managed identity"
        az search service update `
            --name $searchServiceName `
            --resource-group $ResourceGroupName `
            --identity-type SystemAssigned `
            | Out-Null
        
        # Refresh search service details
        $searchService = az search service show `
            --name $searchServiceName `
            --resource-group $ResourceGroupName `
            | ConvertFrom-Json
    } else {
        Write-InfoLog "Managed identity already enabled"
    }
    
    return @{
        Name = $searchServiceName
        Id = $searchService.id
        Endpoint = "https://$searchServiceName.search.windows.net"
        IdentityPrincipalId = $searchService.identity.principalId
    }
}
