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
        
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageContainerName,
        
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

function Initialize-SearchIndex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$SearchServiceName,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$IndexName
    )
    
    Write-InfoLog "Creating search index: $IndexName"
    
    # Wait for search service to be fully available (can take time after creation)
    Write-InfoLog "Waiting for search service to become available..."
    $maxRetries = 12
    $retryCount = 0
    $searchAvailable = $false
    
    while ($retryCount -lt $maxRetries -and -not $searchAvailable) {
        $searchService = az search service show `
            --name $SearchServiceName `
            --resource-group $ResourceGroupName `
            2>$null | ConvertFrom-Json
        
        if ($searchService -and $searchService.provisioningState -eq "Succeeded") {
            $searchAvailable = $true
        } else {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-InfoLog "Search service not yet available, waiting... (attempt $retryCount/$maxRetries)"
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $searchAvailable) {
        Write-ErrorLog "Could not find search service after waiting: $SearchServiceName"
        return
    }
    
    Write-SuccessLog "Search service is available"
    
    # Get admin key
    $adminKey = az search admin-key show `
        --resource-group $ResourceGroupName `
        --service-name $SearchServiceName `
        --query primaryKey `
        -o tsv
    
    if (-not $adminKey) {
        Write-ErrorLog "Could not retrieve search admin key"
        return
    }
    
    $searchEndpoint = "https://$SearchServiceName.search.windows.net"
    
    # Create index schema (simplified for Basic tier - no semantic search)
    $indexSchema = @{
        name = $IndexName
        fields = @(
            @{ name = "id"; type = "Edm.String"; key = $true; searchable = $false }
            @{ name = "content"; type = "Edm.String"; searchable = $true; analyzer = "standard.lucene" }
            @{ name = "metadata_storage_name"; type = "Edm.String"; searchable = $true; filterable = $true }
            @{ name = "metadata_storage_path"; type = "Edm.String"; searchable = $false; filterable = $true }
            @{ name = "metadata_storage_last_modified"; type = "Edm.DateTimeOffset"; filterable = $true; sortable = $true }
        )
    } | ConvertTo-Json -Depth 10
    
    # Create index
    $headers = @{
        "api-key" = $adminKey
        "Content-Type" = "application/json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2023-11-01" `
            -Method Put `
            -Headers $headers `
            -Body $indexSchema `
            -ErrorAction Stop
        
        Write-SuccessLog "Index created: $IndexName"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 204 -or $_.Exception.Message -match "already exists") {
            Write-WarningLog "Index '$IndexName' already exists"
        } else {
            Write-ErrorLog "Failed to create index: $($_.Exception.Message)"
            Write-WarningLog "Continuing with deployment..."
        }
    }
    
    # Create data source
    Write-InfoLog "Creating data source connection"
    
    $storageConnectionString = az storage account show-connection-string `
        --name $StorageAccountName `
        --query connectionString `
        -o tsv 2>$null
    
    if (-not $storageConnectionString) {
        Write-ErrorLog "Could not retrieve storage connection string for: $StorageAccountName"
        return
    }
    
    $dataSourceSchema = @{
        name = "conference-data-source"
        type = "azureblob"
        credentials = @{
            connectionString = $storageConnectionString
        }
        container = @{
            name = $StorageContainerName
        }
    } | ConvertTo-Json -Depth 10
    
    try {
        Invoke-RestMethod -Uri "$searchEndpoint/datasources/conference-data-source`?api-version=2023-11-01" `
            -Method Put `
            -Headers $headers `
            -Body $dataSourceSchema `
            -ErrorAction Stop | Out-Null
        
        Write-SuccessLog "Data source created"
    } catch {
        if ($_.Exception.Message -match "already exists") {
            Write-InfoLog "Data source already exists"
        } else {
            Write-WarningLog "Data source creation issue: $($_.Exception.Message)"
        }
    }
    
    # Create indexer
    Write-InfoLog "Creating indexer"
    
    $indexerSchema = @{
        name = "conference-indexer"
        dataSourceName = "conference-data-source"
        targetIndexName = $IndexName
        schedule = @{
            interval = "PT2H"
        }
        parameters = @{
            configuration = @{
                dataToExtract = "contentAndMetadata"
                parsingMode = "default"
                imageAction = "none"
            }
        }
        fieldMappings = @(
            @{
                sourceFieldName = "metadata_storage_path"
                targetFieldName = "id"
                mappingFunction = @{
                    name = "base64Encode"
                }
            }
        )
    } | ConvertTo-Json -Depth 10
    
    try {
        Invoke-RestMethod -Uri "$searchEndpoint/indexers/conference-indexer`?api-version=2023-11-01" `
            -Method Put `
            -Headers $headers `
            -Body $indexerSchema `
            -ErrorAction Stop | Out-Null
        
        Write-SuccessLog "Indexer created"
    } catch {
        if ($_.Exception.Message -match "already exists") {
            Write-InfoLog "Indexer already exists"
        } else {
            Write-WarningLog "Indexer creation issue: $($_.Exception.Message)"
        }
    }
    
    # Run indexer immediately
    Write-InfoLog "Starting indexer..."
    try {
        Invoke-RestMethod -Uri "$searchEndpoint/indexers/conference-indexer/run?api-version=2023-11-01" `
            -Method Post `
            -Headers $headers `
            -ErrorAction Stop | Out-Null
        
        Write-SuccessLog "Indexer started. Documents will be indexed in the background."
    } catch {
        if ($_.Exception.Message -match "is currently running") {
            Write-InfoLog "Indexer is already running"
        } else {
            Write-WarningLog "Could not start indexer: $($_.Exception.Message)"
        }
    }
}
