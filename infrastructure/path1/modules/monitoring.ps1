function New-WorkshopMonitoring {
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
        [hashtable]$Tags = @{}
    )
    
    $appInsightsName = "$Prefix-appinsights-$Environment"
    $logAnalyticsName = "$Prefix-logs-$Environment"
    
    Write-InfoLog "Creating Log Analytics Workspace: $logAnalyticsName"
    
    # Check if workspace exists
    $existingWorkspace = az monitor log-analytics workspace show `
        --resource-group $ResourceGroupName `
        --workspace-name $logAnalyticsName `
        2>$null | ConvertFrom-Json
    
    if ($existingWorkspace) {
        Write-WarningLog "Log Analytics workspace '$logAnalyticsName' already exists"
        $workspace = $existingWorkspace
    } else {
        # Create Log Analytics Workspace
        $workspace = az monitor log-analytics workspace create `
            --resource-group $ResourceGroupName `
            --workspace-name $logAnalyticsName `
            --location $Location `
            --retention-time 30 `
            | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Log Analytics workspace"
        }
        
        Write-SuccessLog "Log Analytics workspace created: $logAnalyticsName"
    }
    
    Write-InfoLog "Creating Application Insights: $appInsightsName"
    
    # Check if Application Insights exists
    $existingAppInsights = az monitor app-insights component show `
        --app $appInsightsName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingAppInsights) {
        Write-WarningLog "Application Insights '$appInsightsName' already exists"
        $appInsights = $existingAppInsights
    } else {
        # Create Application Insights
        # Note: Output may contain extension warnings, so we don't parse it directly
        az monitor app-insights component create `
            --app $appInsightsName `
            --location $Location `
            --resource-group $ResourceGroupName `
            --workspace $workspace.id `
            --kind web `
            --output none `
            2>$null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Application Insights"
        }
        
        # Query the created resource to get clean JSON
        $appInsights = az monitor app-insights component show `
            --app $appInsightsName `
            --resource-group $ResourceGroupName `
            | ConvertFrom-Json
        
        if (-not $appInsights) {
            throw "Application Insights was created but could not be queried"
        }
        
        Write-SuccessLog "Application Insights created: $appInsightsName"
    }
    
    # Get connection string
    $connectionString = az monitor app-insights component show `
        --app $appInsightsName `
        --resource-group $ResourceGroupName `
        --query connectionString `
        -o tsv
    
    return @{
        Name = $appInsightsName
        Id = $appInsights.id
        ConnectionString = $connectionString
        InstrumentationKey = $appInsights.instrumentationKey
        WorkspaceName = $logAnalyticsName
        WorkspaceId = $workspace.id
    }
}
