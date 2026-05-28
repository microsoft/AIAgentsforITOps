# Lab 5: Monitoring AI Services & Agent Telemetry

## Overview

Configure monitoring for your AI services (Azure OpenAI and Azure AI Search) and observe real-time agent telemetry using Application Insights Live Metrics.

**Time:** 20-25 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Configure diagnostic settings for Azure OpenAI and Azure AI Search
- Query AI service metrics using Azure Monitor
- Observe real-time agent telemetry with Application Insights Live Metrics
- Understand what metrics are important for AI agent management

## Architecture: Monitoring Flow

```
AI Services (OpenAI, Search)
    └─ Diagnostic Settings enabled
         ↓ (logs & metrics)
    Log Analytics Workspace
         ↓ (queryable via Azure Monitor)
    Azure Portal Metrics Explorer

Agent Application (AKS)
    └─ Application Insights SDK
         ↓ (telemetry)
    Application Insights
         ↓ (real-time view)
    Live Metrics Dashboard
```

## Step 1: Configure Diagnostic Settings for Azure OpenAI

If not already there, navigate to the /infrastructure/path1/ directory:

```powershell
cd infrastructure/path1/
```

Let's enable comprehensive logging and metrics for Azure OpenAI:

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$openAiName = $config.resources.azureOpenAI

# Get resource IDs
$openAiId = az cognitiveservices account show `
    --name $openAiName `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

$logWorkspaceId = az monitor log-analytics workspace list `
    --resource-group $resourceGroup `
    --query '[0].id' `
    -o tsv

Write-Host "`nConfiguring diagnostics for Azure OpenAI: $openAiName" -ForegroundColor Cyan
Write-Host "Sending to Log Analytics: $logWorkspaceId" -ForegroundColor Yellow

# Enable all logs and metrics using category groups
az monitor diagnostic-settings create `
    --name "openai-diagnostics" `
    --resource $openAiId `
    --workspace $logWorkspaceId `
    --export-to-resource-specific true `
    --logs '[{"categoryGroup":"audit","enabled":true},{"categoryGroup":"allLogs","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]'

Write-Host "✓ Azure OpenAI diagnostics configured" -ForegroundColor Green
```

**What we're collecting:**

- **Audit category group**: Authentication and authorization events
- **AllLogs category group**: All available logs including:
  - Audit logs
  - RequestResponse logs (API requests/responses with prompts and completions)
  - Trace logs (detailed execution traces)
  - Azure OpenAI Request Usage (usage metrics per request)
- **AllMetrics**: Token usage, latency, throttling, errors

> **⚠️ Cost Consideration:** In this workshop, we're enabling **all logs** for comprehensive visibility. In production environments, be selective about which log categories you enable. The `RequestResponse` category, which includes full prompts and completions, can be very verbose and significantly increase Log Analytics costs. Consider enabling only essential categories (like `Audit` and `Azure OpenAI Request Usage`) and adding `RequestResponse` only when troubleshooting specific issues.

## Step 2: Configure Diagnostic Settings for Azure AI Search

Now enable monitoring for Azure AI Search:

```powershell
$searchName = $config.resources.searchService

$searchId = az search service show `
    --name $searchName `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

Write-Host "`nConfiguring diagnostics for Azure AI Search: $searchName" -ForegroundColor Cyan

# Enable all logs and metrics using category groups
az monitor diagnostic-settings create `
    --name "search-diagnostics" `
    --resource $searchId `
    --workspace $logWorkspaceId `
    --export-to-resource-specific true `
    --logs '[{"categoryGroup":"audit","enabled":true},{"categoryGroup":"allLogs","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]'

Write-Host "✓ Azure AI Search diagnostics configured" -ForegroundColor Green
```

**What we're collecting:**

- **AllLogs category group**: All available logs including OperationLogs (search queries, indexing operations, API calls)
- **AllMetrics**: Query latency, throttling, storage usage

## Step 3: Query Azure OpenAI Metrics in Azure Portal

Now let's view AI service metrics in the Azure Portal.

### 3.1 Navigate to Metrics Explorer

1. **Open Azure Portal** → Navigate to your Resource Group
2. **Find your Azure OpenAI resource** (e.g., `agntwrk-openai-dev`)
3. **Click "Metrics"** in the left menu (under Monitoring section)

### 3.2 View Token Usage

**Create a metric chart:**

1. **Metric Namespace**: `Cognitive Services standard metrics`
2. **Metric**: Select **"Processed Inference Tokens"**
3. **Aggregation**: `Sum`
4. **Time range**: Default is Last 24 hours, adjust as needed

You should see a chart showing how many tokens your agent has consumed! The chart shows a spike in token usage when you interact with the agent, which directly correlates to your Azure OpenAI costs. Each request to the agent that triggers an OpenAI API call will consume tokens based on the prompt and response size. At the bottom, you will see the (default) aggregation of `Sum`, which shows total tokens consumed in the selected time range. You can change the aggregation to `Average` to see average tokens per request, or `Count` to see number of requests.

### 3.3 View Request Latency

**Add another metric to the same chart:**

1. Click **"+ Add metric"**
2. **Metric**: Select **"Response Time"** (or **"Time To Response"**)
3. **Aggregation**: `Average`

This shows how long Azure OpenAI takes to respond to your agent's requests.

### 3.4 View Error Rate

**Add one more metric:**

1. Click **"+ Add metric"**
2. **Metric**: Select **"Total Errors"**
3. **Aggregation**: `Count`

> **💡 Tip:** You can save these charts to an Azure Dashboard for ongoing monitoring. Click "Save to dashboard" at the top of the metrics view.

## Step 4: Explore Application Insights Live Metrics

Now let's see real-time telemetry from your AI agent application.

### 4.1 Open Live Metrics Dashboard

1. **Open Azure Portal** and navigate to your Resource Group
2. **Find your Application Insights resource** (check `deployment-output.json` for the exact name under `config.resources.appInsights`)
3. In the left menu, expand **"Investigate"**
4. Click **"Live Metrics"**

The Live Metrics dashboard will open and start showing real-time telemetry from your agent application.

### 4.2 Interact with Your Agent

With the Live Metrics dashboard open, let's generate some activity to observe. If you don't have the agent UI open, follow these steps:

1. **Get your agent's URL:**
   - On a new browser tab, navigate to your **AKS cluster** in the Azure portal
   - In the left menu, click **"Services and ingresses"** (under Kubernetes resources)
   - Find the service named `agent-webapp-service`
   - Copy the **External IP** address

2. **Open the agent** in a new browser tab: `http://<EXTERNAL-IP>`

3. **Keep the Live Metrics dashboard visible** in another tab

4. **Ask questions to your agent** such as:
   - "Tell me about infrastructure Expert Meet-ups at Ignite"
   - "How many Expert Meet-up stations were there at Ignite 2025?"

5. **Watch the Live Metrics dashboard update in real-time!** You'll see requests flowing through as you interact with the agent.

### 4.3 What You'll See in Live Metrics

As you interact with the agent, the dashboard shows:

**Incoming Requests**

- Request rate (requests/second)
- Request duration (how long agent responses take)
- Failed requests (if any errors occur)

**Outgoing Requests (Dependencies)**

- Calls to Azure OpenAI
- Calls to Azure AI Search
- Response times for each dependency

**Sample Telemetry**

- **The actual questions users are asking!** (visible in the telemetry stream)
- Agent processing steps
- Search queries being executed
- OpenAI API calls with response times

**Server Performance**

- CPU usage
- Memory consumption
- Exception rate

> **💡 Key Insight:** The telemetry stream shows the questions being asked to your agent in real-time. This is invaluable for understanding usage patterns and identifying issues as they happen!

## Step 5: Query AI Service Logs with KQL

Let's write some queries to analyze AI service usage.

### 5.1 Azure OpenAI Request Analysis

In the Azure Portal:

1. Navigate to your **Log Analytics workspace**
2. Click **"Logs"** in the left menu
3. **Close the Queries hub** if it appears (the pop-up window with saved queries)
4. Ensure you're in **KQL mode**: Look at the top of the query editor - if you see "Simple mode", click the dropdown and select **"KQL mode"**
5. Paste this query:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where Category == "RequestResponse"
| where TimeGenerated > ago(1h)
| project TimeGenerated, OperationName, DurationMs, ResultType, properties_s
| order by TimeGenerated desc
| take 20
```

**What it shows:** Recent Azure OpenAI API calls with duration and results

> **💡 Note:** If you don't see any results, data may still be flowing from Azure OpenAI to Log Analytics. Diagnostic logs can take 5-15 minutes to appear after being enabled. Try interacting with your agent to generate some requests, then wait a few minutes and re-run the query.

### 5.2 Azure AI Search Query Performance

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SEARCH"
| where OperationName == "Query.Search"
| where TimeGenerated > ago(1h)
| project TimeGenerated, DurationMs, ResultCount = toint(resultSignature_d)
| summarize AvgDuration = avg(DurationMs), AvgResults = avg(ResultCount) by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**What it shows:** Search query latency and result counts

### 5.3 Error Analysis

```kql
AzureDiagnostics
| where ResourceProvider in ("MICROSOFT.COGNITIVESERVICES", "MICROSOFT.SEARCH")
| where ResultType != "Success" or Level == "Error"
| where TimeGenerated > ago(24h)
| summarize ErrorCount = count() by ResourceProvider, OperationName, ResultType
| order by ErrorCount desc
```

**What it shows:** All errors from AI services in the last 24 hours

## Best Practices for AI Agent Monitoring

### ✅ DO

- **Monitor token usage** - Track costs and identify expensive queries
- **Track latency** - Ensure agent response times meet user expectations
- **Watch for throttling** - Azure OpenAI has rate limits; monitor for 429 errors
- **Analyze user questions** - Understand what users are asking to improve the agent
- **Set up alerts** - Get notified when error rates spike or latency increases
- **Review logs regularly** - Identify patterns and optimization opportunities

### ❌ DON'T

- Store sensitive data in logs without proper controls
- Ignore error spikes (they often indicate configuration or quota issues)
- Forget about cost implications of logging (RequestResponse logs can be verbose)
- Overlook dependency failures (OpenAI/Search downtime affects your agent)

## Monitoring Checklist

✅ **Diagnostic settings enabled** for Azure OpenAI  
✅ **Diagnostic settings enabled** for Azure AI Search  
✅ **Metrics dashboard created** for token usage and latency  
✅ **Live Metrics tested** by interacting with the agent  
✅ **KQL queries saved** for ongoing analysis  
✅ **Alerts configured** for error thresholds (optional but recommended)

## Key Learnings

✅ **AI services generate rich telemetry** - Logs include prompts, completions, and token counts  
✅ **Live Metrics shows real-time agent behavior** - Including actual user questions  
✅ **Token usage is critical** - Directly impacts costs  
✅ **Latency matters** - Users expect fast responses from AI agents  
✅ **Dependencies are visible** - OpenAI and Search calls appear as outgoing requests  
✅ **KQL is powerful** - Can correlate events across multiple Azure services  

## Next Steps

- **[Lab 6: Cost Management](06-cost-management.md)** - Analyze and optimize AI service costs

## Resources

- [Azure OpenAI Monitoring](https://learn.microsoft.com/azure/ai-services/openai/how-to/monitoring)
- [Azure AI Search Monitoring](https://learn.microsoft.com/azure/search/monitor-azure-cognitive-search)
- [Application Insights Live Metrics](https://learn.microsoft.com/azure/azure-monitor/app/live-stream)
- [KQL Query Language](https://learn.microsoft.com/azure/data-explorer/kusto/query/)
- [Azure Monitor Metrics](https://learn.microsoft.com/azure/azure-monitor/essentials/metrics-getting-started)
