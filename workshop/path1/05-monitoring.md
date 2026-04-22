# Lab 5: Monitoring & Observability

## Overview

Implement comprehensive monitoring using Application Insights and Azure Monitor for the AI agent application.

**Time:** 25-30 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Configure Application Insights
- Set up custom metrics and alerts
- Query telemetry data
- Create dashboards
- Monitor AKS cluster health

## Step 1: View Application Insights Data

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$appInsights = $config.resources.appInsights
$resourceGroup = $config.resourceGroupName

# Get Application Insights app ID
$appId = az monitor app-insights component show `
    --app $appInsights `
    --resource-group $resourceGroup `
    --query appId `
    -o tsv

Write-Host "Application Insights App ID: $appId" -ForegroundColor Green

# Query recent requests
az monitor app-insights query `
    --app $appId `
    --analytics-query "requests | take 10" `
    --output table
```

## Step 2: Create Custom Metrics Alert

```powershell
# Create alert rule for failed requests
$appInsightsId = az monitor app-insights component show `
    --app $appInsights `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

az monitor metrics alert create `
    --name "HighFailureRate" `
    --resource-group $resourceGroup `
    --scopes $appInsightsId `
    --condition "avg requests/failed > 5" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --description "Alert when request failure rate exceeds 5 per minute"

Write-Host "Alert rule created" -ForegroundColor Green
```

## Step 3: Configure AKS Monitoring

```powershell
# View cluster metrics
kubectl top nodes
kubectl top pods --all-namespaces

# Get AKS insights
az aks show `
    --name $config.resources.aksCluster `
    --resource-group $resourceGroup `
    --query 'addonProfiles.omsagent' `
    | ConvertFrom-Json
```

## Step 4: Create Dashboard

```powershell
# Create custom dashboard (JSON template)
$dashboardPath = "..\monitoring-dashboard.json"

# Dashboard configuration
@{
    location = $config.location
    tags = @{ Environment = $config.environment }
    properties = @{
        lenses = @{
            "0" = @{
                order = 0
                parts = @{
                    "0" = @{
                        position = @{ x=0; y=0; colSpan=6; rowSpan=4 }
                        metadata = @{
                            type = "Extension/AppInsightsExtension/PartType/AppMapGalPt"
                            asset = @{
                                idInputName = "ComponentId"
                                type = "ApplicationInsights"
                            }
                        }
                    }
                }
            }
        }
    }
} | ConvertTo-Json -Depth 10 | Set-Content $dashboardPath

Write-Host "Dashboard template created" -ForegroundColor Green
```

## Step 5: Query Logs with KQL

```powershell
# Sample KQL queries
$queries = @(
    "requests | summarize count() by resultCode | order by count_ desc",
    "traces | where severityLevel >= 2 | top 10 by timestamp desc",
    "exceptions | summarize count() by type | order by count_ desc"
)

foreach ($query in $queries) {
    Write-Host "`nQuery: $query" -ForegroundColor Cyan
    az monitor app-insights query `
        --app $appId `
        --analytics-query $query `
        --output table
}
```

## Key Learnings

✅ **Instrument early:** Add telemetry from the start  
✅ **Use structured logging:** Makes querying easier  
✅ **Set up alerts:** Be proactive, not reactive  
✅ **Create dashboards:** Visibility for stakeholders  
✅ **Monitor costs:** Application Insights data ingestion costs

## Next Steps

- **[Lab 6: Cost Management](06-cost-management.md)**

## Resources

- [Application Insights Documentation](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [KQL Query Language](https://learn.microsoft.com/azure/data-explorer/kusto/query/)
