<#
.SYNOPSIS
    Deploy complete Azure infrastructure for AI Agents for IT/Ops Workshop - Path 1

.DESCRIPTION
    This script deploys all Azure resources needed for Path 1 (Custom Agent with Azure OpenAI):
    - Resource Group
    - Azure Storage Account (for conference data)
    - Azure AI Search (for indexing and RAG)
    - Azure Container Registry
    - Azure Kubernetes Service
    - Azure Key Vault
    - Application Insights
    - Azure OpenAI (GPT-4.1-mini for LLM reasoning)
    - Managed Identities and RBAC assignments
    - VNet and Private Endpoints (optional)

.PARAMETER ParametersFile
    Path to JSON file containing deployment parameters. If not provided, prompts for input.

.EXAMPLE
    .\deploy-infra.ps1
    .\deploy-infra.ps1 -ParametersFile ".\my-params.json"

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile
)

$ErrorActionPreference = "Stop"

# Import helper functions
. "$PSScriptRoot\modules\common.ps1"

#region Functions

function Get-DeploymentParameters {
    param([string]$ParametersFile)
    
    # If no file specified, check for default parameters.json in script directory
    if (-not $ParametersFile) {
        $defaultParamsFile = Join-Path $PSScriptRoot "parameters.json"
        if (Test-Path $defaultParamsFile) {
            $ParametersFile = $defaultParamsFile
            Write-InfoLog "Found parameters file: $ParametersFile"
        }
    }
    
    if ($ParametersFile -and (Test-Path $ParametersFile)) {
        Write-InfoLog "Loading parameters from file: $ParametersFile"
        $paramsJson = Get-Content $ParametersFile | ConvertFrom-Json
        
        # Convert PSCustomObject to Hashtable for tags
        $tagsHash = @{}
        if ($paramsJson.tags) {
            $paramsJson.tags.PSObject.Properties | ForEach-Object {
                $tagsHash[$_.Name] = $_.Value
            }
        }
        
        # Create proper hashtable with converted tags
        $params = @{
            subscriptionId = $paramsJson.subscriptionId
            location = $paramsJson.location
            resourceGroupName = $paramsJson.resourceGroupName
            resourcePrefix = $paramsJson.resourcePrefix
            environment = $paramsJson.environment
            enablePrivateEndpoints = $paramsJson.enablePrivateEndpoints
            enableMonitoring = $paramsJson.enableMonitoring
            tags = $tagsHash
        }
        
        # Add tenantId if present
        if ($paramsJson.tenantId) {
            $params.tenantId = $paramsJson.tenantId
        }
        
        return $params
    }
    
    Write-InfoLog "No parameters file found. Please provide deployment parameters interactively."
    
    $params = @{
        subscriptionId = Read-Host "Azure Subscription ID"
        tenantId = Read-Host "Azure Tenant ID (press Enter to skip if not needed)"
        location = Read-Host "Azure Region (e.g., eastus, westus2)"
        resourceGroupName = Read-Host "Resource Group Name"
        resourcePrefix = Read-Host "Resource Prefix (3-10 lowercase letters/numbers, used for unique naming)"
        environment = Read-Host "Environment (dev/staging/prod)"
        enablePrivateEndpoints = (Read-Host "Enable Private Endpoints? (y/n)") -eq 'y'
        enableMonitoring = $true
        tags = @{
            Environment = ""
            Project = "AgentsForITOps"
        }
    }
    
    # Remove tenantId if empty
    if ([string]::IsNullOrWhiteSpace($params.tenantId)) {
        $params.Remove('tenantId')
    }
    
    $params.tags.Environment = $params.environment
    
    # Add deployment metadata (logged automatically)
    Write-InfoLog "Deployment initiated by: $env:USERNAME at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    return $params
}

function Show-DeploymentSummary {
    param($params, $resources)
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Subscription:" -ForegroundColor Yellow -NoNewline
    Write-Host " $($params.subscriptionId)"
    
    Write-Host "Resource Group:" -ForegroundColor Yellow -NoNewline
    Write-Host " $($params.resourceGroupName)"
    
    Write-Host "Location:" -ForegroundColor Yellow -NoNewline
    Write-Host " $($params.location)"
    
    Write-Host "Environment:" -ForegroundColor Yellow -NoNewline
    Write-Host " $($params.environment)`n"
    
    Write-Host "Deployed Resources:" -ForegroundColor Green
    foreach ($resource in $resources.GetEnumerator()) {
        Write-Host "  $($resource.Key):" -ForegroundColor Yellow -NoNewline
        Write-Host " $($resource.Value)"
    }
    
    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

#endregion

#region Main Deployment

try {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   AI Agents for IT/Ops - Azure Infrastructure Deployment          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    # Step 1: Get deployment parameters
    $params = Get-DeploymentParameters -ParametersFile $ParametersFile
    
    # Validate resource prefix
    if ($params.resourcePrefix -notmatch '^[a-z0-9]{3,10}$') {
        throw "Resource prefix must be 3-10 lowercase letters or numbers"
    }
    
    # Step 2: Login and set subscription
    Write-SectionHeader "Azure Authentication"
    
    # Authenticate Azure PowerShell
    $currentContext = Get-AzContext
    if (-not $currentContext) {
        Write-InfoLog "No Azure PowerShell context found. Logging in..."
        if ($params.tenantId) {
            Write-InfoLog "Using tenant ID: $($params.tenantId)"
            Connect-AzAccount -TenantId $params.tenantId
        } else {
            Connect-AzAccount
        }
        
        # Verify authentication succeeded
        $currentContext = Get-AzContext
        if (-not $currentContext) {
            Write-ErrorLog "Azure PowerShell authentication failed."
            Write-Host "`nPlease authenticate manually by running:" -ForegroundColor Yellow
            if ($params.tenantId) {
                Write-Host "  Connect-AzAccount -TenantId $($params.tenantId)" -ForegroundColor Cyan
            } else {
                Write-Host "  Connect-AzAccount" -ForegroundColor Cyan
            }
            Write-Host "`nThen run this script again.`n" -ForegroundColor Yellow
            throw "Azure PowerShell authentication required"
        }
    }
    
    Write-InfoLog "Setting Azure PowerShell subscription: $($params.subscriptionId)"
    try {
        if ($params.tenantId) {
            Set-AzContext -SubscriptionId $params.subscriptionId -TenantId $params.tenantId -ErrorAction Stop | Out-Null
        } else {
            Set-AzContext -SubscriptionId $params.subscriptionId -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-WarningLog "Failed to set subscription context. Re-authenticating..."
        
        # Force re-authentication with subscription context
        if ($params.tenantId) {
            Write-InfoLog "Using tenant ID: $($params.tenantId)"
            Connect-AzAccount -TenantId $params.tenantId -Subscription $params.subscriptionId -Force
        } else {
            Connect-AzAccount -Subscription $params.subscriptionId -Force
        }
        
        # Retry setting context
        try {
            if ($params.tenantId) {
                Set-AzContext -SubscriptionId $params.subscriptionId -TenantId $params.tenantId -ErrorAction Stop | Out-Null
            } else {
                Set-AzContext -SubscriptionId $params.subscriptionId -ErrorAction Stop | Out-Null
            }
        } catch {
            Write-ErrorLog "Failed to set Azure PowerShell subscription context."
            Write-Host "`nPlease authenticate manually by running:" -ForegroundColor Yellow
            if ($params.tenantId) {
                Write-Host "  Connect-AzAccount -TenantId $($params.tenantId)" -ForegroundColor Cyan
                Write-Host "  Set-AzContext -SubscriptionId $($params.subscriptionId) -TenantId $($params.tenantId)" -ForegroundColor Cyan
            } else {
                Write-Host "  Connect-AzAccount" -ForegroundColor Cyan
                Write-Host "  Set-AzContext -SubscriptionId $($params.subscriptionId)" -ForegroundColor Cyan
            }
            Write-Host "`nThen run this script again.`n" -ForegroundColor Yellow
            throw "Azure PowerShell authentication required"
        }
    }
    
    Write-SuccessLog "Azure PowerShell authenticated successfully"
    
    # Authenticate Azure CLI
    Write-InfoLog "Checking Azure CLI authentication..."
    $cliAccount = az account show 2>$null | ConvertFrom-Json
    
    if (-not $cliAccount) {
        Write-InfoLog "No Azure CLI login found. Please log in..."
        if ($params.tenantId) {
            az login --tenant $params.tenantId | Out-Null
        } else {
            az login | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Azure CLI authentication failed."
            Write-Host "`nPlease authenticate manually by running:" -ForegroundColor Yellow
            if ($params.tenantId) {
                Write-Host "  az login --tenant $($params.tenantId)" -ForegroundColor Cyan
            } else {
                Write-Host "  az login" -ForegroundColor Cyan
            }
            Write-Host "`nThen run this script again.`n" -ForegroundColor Yellow
            throw "Azure CLI authentication required"
        }
        
        # Verify authentication succeeded
        $cliAccount = az account show 2>$null | ConvertFrom-Json
        if (-not $cliAccount) {
            Write-ErrorLog "Azure CLI authentication verification failed."
            Write-Host "`nPlease authenticate manually by running:" -ForegroundColor Yellow
            if ($params.tenantId) {
                Write-Host "  az login --tenant $($params.tenantId)" -ForegroundColor Cyan
            } else {
                Write-Host "  az login" -ForegroundColor Cyan
            }
            Write-Host "`nThen run this script again.`n" -ForegroundColor Yellow
            throw "Azure CLI authentication required"
        }
    }
    
    Write-InfoLog "Setting Azure CLI subscription: $($params.subscriptionId)"
    az account set --subscription $params.subscriptionId
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set Azure CLI subscription"
    }
    
    Write-SuccessLog "Azure CLI authenticated successfully"
    Write-SuccessLog "All authentication checks passed"
    
    # Step 3: Create Resource Group
    Write-SectionHeader "Resource Group"
    . "$PSScriptRoot\modules\resource-group.ps1"
    $rg = New-WorkshopResourceGroup -Name $params.resourceGroupName -Location $params.location -Tags $params.tags
    
    # Step 4: Create Storage Account
    Write-SectionHeader "Azure Storage Account"
    . "$PSScriptRoot\modules\storage.ps1"
    $storage = New-WorkshopStorageAccount `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -EnablePrivateEndpoint $params.enablePrivateEndpoints `
        -Tags $params.tags
    
    # Step 5: Create Azure AI Search
    Write-SectionHeader "Azure AI Search"
    . "$PSScriptRoot\modules\search.ps1"
    $search = New-WorkshopSearchService `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -StorageAccountName $storage.Name `
        -StorageContainerName $storage.ContainerName `
        -EnablePrivateEndpoint $params.enablePrivateEndpoints `
        -Tags $params.tags
    
    # Step 6: Create Container Registry
    Write-SectionHeader "Azure Container Registry"
    . "$PSScriptRoot\modules\acr.ps1"
    $acr = New-WorkshopContainerRegistry `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -EnablePrivateEndpoint $params.enablePrivateEndpoints `
        -Tags $params.tags
    
    # Step 7: Create Key Vault
    Write-SectionHeader "Azure Key Vault"
    . "$PSScriptRoot\modules\keyvault.ps1"
    $keyVault = New-WorkshopKeyVault `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -EnablePrivateEndpoint $params.enablePrivateEndpoints `
        -Tags $params.tags
    
    # Step 8: Create Application Insights
    if ($params.enableMonitoring) {
        Write-SectionHeader "Application Insights"
        . "$PSScriptRoot\modules\monitoring.ps1"
        $appInsights = New-WorkshopMonitoring `
            -ResourceGroupName $params.resourceGroupName `
            -Location $params.location `
            -Prefix $params.resourcePrefix `
            -Environment $params.environment `
            -Tags $params.tags
    }
    
    # Step 9: Create VNet (if private endpoints enabled)
    if ($params.enablePrivateEndpoints) {
        Write-SectionHeader "Virtual Network"
        . "$PSScriptRoot\modules\network.ps1"
        $vnet = New-WorkshopVirtualNetwork `
            -ResourceGroupName $params.resourceGroupName `
            -Location $params.location `
            -Prefix $params.resourcePrefix `
            -Environment $params.environment `
            -Tags $params.tags
    }
    
    # Step 10: Create AKS Cluster
    Write-SectionHeader "Azure Kubernetes Service"
    . "$PSScriptRoot\modules\aks.ps1"
    $aks = New-WorkshopAKSCluster `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -ContainerRegistryName $acr.Name `
        -VNetName $(if ($vnet) { $vnet.Name } else { $null }) `
        -Tags $params.tags
    
    # Enable AKS monitoring (if monitoring is enabled)
    if ($params.enableMonitoring -and $appInsights) {
        Write-InfoLog "Configuring AKS monitoring integration"
        Enable-AKSMonitoring `
            -ResourceGroupName $params.resourceGroupName `
            -AksName $aks.Name `
            -WorkspaceResourceId $appInsights.WorkspaceId
    }
    
    # Step 11: Create Azure OpenAI
    Write-SectionHeader "Azure OpenAI"
    . "$PSScriptRoot\modules\openai.ps1"
    $openai = New-WorkshopAzureOpenAI `
        -ResourceGroupName $params.resourceGroupName `
        -Location $params.location `
        -Prefix $params.resourcePrefix `
        -Environment $params.environment `
        -ModelName "gpt-4.1-mini" `
        -Tags $params.tags
    
    # Step 12: Configure RBAC
    Write-SectionHeader "RBAC Configuration"
    . "$PSScriptRoot\modules\rbac.ps1"
    Configure-WorkshopRBAC `
        -ResourceGroupName $params.resourceGroupName `
        -AKSName $aks.Name `
        -StorageAccountName $storage.Name `
        -SearchServiceName $search.Name `
        -ContainerRegistryName $acr.Name `
        -KeyVaultName $keyVault.Name `
        -AzureOpenAIName $openai.Name
    
    # Step 13: Store application secrets in Key Vault
    Write-SectionHeader "Storing Secrets in Key Vault"
    
    # Get Application Insights connection string
    $appInsightsConnString = ""
    if ($appInsights) {
        $appInsightsConnString = az monitor app-insights component show `
            --app $appInsights.Name `
            --resource-group $params.resourceGroupName `
            --query connectionString `
            -o tsv
    }
    
    # Prepare secrets for Key Vault
    $secrets = @{
        "AKS-ManagedIdentity-ClientId" = $aks.KubeletIdentityClientId
        "AzureOpenAI-Endpoint" = $openai.Endpoint
        "ApplicationInsights-ConnectionString" = $appInsightsConnString
        "AzureSearch-Endpoint" = "https://$($search.Name).search.windows.net"
    }
    
    Set-WorkshopSecrets `
        -KeyVaultName $keyVault.Name `
        -Secrets $secrets
    
    # Step 14: Upload conference documents to blob storage
    Write-SectionHeader "Uploading Conference Documents"
    $documentsPath = Join-Path $PSScriptRoot ".." ".." "Documents"
    if (Test-Path $documentsPath) {
        Upload-ConferenceDocuments `
            -StorageAccountName $storage.Name `
            -ContainerName $storage.ContainerName `
            -SourcePath $documentsPath
    } else {
        Write-WarningLog "Documents folder not found at: $documentsPath"
        Write-WarningLog "Conference documents will not be uploaded. The agent will have no data to search."
    }
    
    # Step 15: Create Search Index and Indexer
    Write-SectionHeader "Configuring Search Index"
    Initialize-SearchIndex `
        -ResourceGroupName $params.resourceGroupName `
        -SearchServiceName $search.Name `
        -StorageAccountName $storage.Name `
        -StorageContainerName $storage.ContainerName `
        -IndexName "conference-documents"
    
    # Step 16: Save configuration
    Write-SectionHeader "Saving Configuration"
    
    $outputConfig = @{
        subscriptionId = $params.subscriptionId
        resourceGroupName = $params.resourceGroupName
        location = $params.location
        environment = $params.environment
        resources = @{
            storageAccount = $storage.Name
            searchService = $search.Name
            containerRegistry = $acr.Name
            aksCluster = $aks.Name
            keyVault = $keyVault.Name
            appInsights = $(if ($appInsights) { $appInsights.Name } else { $null })
            azureOpenAI = $openai.Name
        }
        endpoints = @{
            storageAccount = "https://$($storage.Name).blob.core.windows.net"
            searchService = "https://$($search.Name).search.windows.net"
            containerRegistry = "$($acr.Name).azurecr.io"
            keyVault = "https://$($keyVault.Name).vault.azure.net"
            azureOpenAI = $openai.Endpoint
        }
        azureOpenAI = @{
            deploymentName = $openai.DeploymentName
            modelName = $openai.ModelName
        }
        managedIdentities = @{
            aksIdentity = $aks.IdentityClientId
        }
    }
    
    $configPath = Join-Path $PSScriptRoot "deployment-output.json"
    $outputConfig | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-SuccessLog "Configuration saved to: $configPath"
    
    # Show summary
    Show-DeploymentSummary -params $params -resources $outputConfig.resources
    
    # Next steps
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  NEXT STEP: Deploy Application" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To deploy the web application to AKS, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  .\deploy-app.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will:" -ForegroundColor Gray
    Write-Host "  1. Build and push container image using ACR Tasks" -ForegroundColor Gray
    Write-Host "  2. Configure kubectl with AKS credentials" -ForegroundColor Gray
    Write-Host "  3. Enable Key Vault CSI Driver addon" -ForegroundColor Gray
    Write-Host "  4. Generate Kubernetes manifests" -ForegroundColor Gray
    Write-Host "  5. Deploy application to AKS" -ForegroundColor Gray
    Write-Host "  6. Display the application endpoint" -ForegroundColor Gray
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    Write-SuccessLog "Infrastructure deployment completed successfully!"
    
} catch {
    Write-ErrorLog "Deployment failed: $_"
    Write-ErrorLog $_.ScriptStackTrace
    exit 1
}

#endregion
