# Lab 5: Monitoring a Foundry Agent and Its Chat UI

## Overview

Observe both halves of Path 2: the AKS-hosted chat UI in Azure Monitor and the managed prompt agent in the Foundry portal. Then correlate invocation latency, failures, model use, and knowledge retrieval.

**Time:** 35-45 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Connect the existing Application Insights resource to Foundry
- Inspect agent traces in the Foundry portal
- Query UI requests and Foundry dependencies in Application Insights
- Monitor Search and Foundry platform metrics
- Create a basic operational alert
- Understand privacy and cost implications of GenAI telemetry

## Observability Layers

```text
User
  └── AKS chat UI ── Application Insights requests/dependencies/exceptions
          └── Foundry Responses API ── Foundry traces and model usage
                  └── Knowledge Base ── Azure AI Search logs and metrics
```

Path 1 traces code that performs retrieval and model calls inside AKS. Path 2 shows the UI call in AKS telemetry and the managed agent execution in Foundry telemetry.

## Step 1: Load the Deployment Context

```powershell
cd infrastructure/path2

$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$foundryName = $config.resources.foundry
$projectName = $config.resources.foundryProject
$searchName = $config.resources.searchService
$appInsightsName = $config.resources.appInsights

$workspaceId = az monitor log-analytics workspace list `
    --resource-group $resourceGroup `
    --query "[0].id" -o tsv
```

## Step 2: Connect Application Insights to Foundry

Lab 1 created Application Insights for the UI, but a Foundry project must also be associated with an Application Insights data source before its trace and monitoring views can use it.

Before opening the portal, grant the Foundry project's managed identity permission to read Application Insights telemetry:

```powershell
$projectPrincipalId = az cognitiveservices account project show `
    --name $foundryName `
    --resource-group $resourceGroup `
    --project-name $projectName `
    --query identity.principalId `
    --output tsv

$appInsightsId = az monitor app-insights component show `
    --app $appInsightsName `
    --resource-group $resourceGroup `
    --query id `
    --output tsv

$monitoringReaderAssignment = az role assignment list `
    --assignee $projectPrincipalId `
    --role "Monitoring Reader" `
    --scope $appInsightsId `
    --query "[0].id" `
    --output tsv

if ([string]::IsNullOrWhiteSpace($monitoringReaderAssignment)) {
    az role assignment create `
        --assignee-object-id $projectPrincipalId `
        --assignee-principal-type ServicePrincipal `
        --role "Monitoring Reader" `
        --scope $appInsightsId `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assign Monitoring Reader to the Foundry project identity."
    }

    Write-Host "Assigned Monitoring Reader to the Foundry project identity." -ForegroundColor Green
} else {
    Write-Host "Monitoring Reader is already assigned to the Foundry project identity." -ForegroundColor Green
}
```

Creating the role assignment requires permission to manage access, such as **Role Based Access Control Administrator**, **User Access Administrator**, or **Owner**, at the applicable scope. Allow several minutes for a new assignment to propagate before connecting or opening traces.

1. Open `https://ai.azure.com` and select the workshop project.
2. Click Build on the top-right corner to open the Foundry project in the new portal.
3. On the Agents page, click the agent name to open its details page.
4. Open **Monitoring** in the agent navigation.
5. On the warning message to connect an App Insights, click Connect and choose the existing Application Insights resource from `deployment-output.json`.
6. Change the Auth type to Project's Managed Identity and select **Connect**.
7. Confirm the project now shows the Application Insights resource as its observability data source.

You need contributor-level permission to make the connection. Users viewing logs need at least `Log Analytics Reader` on the workspace or equivalent access through resource-context mode.

Explore the metrics presented about the agent. You might need to refresh the page to see the first few invocations. The metrics are based on Foundry traces, so they will not appear until the agent has been invoked.

Use **Open in Azure Monitor** to open the same metrics in the Azure portal. The Foundry portal shows only the agent's own traces, while the Azure portal can show all telemetry from the project and its dependencies.

## Step 3: Generate a Trace Set

Open the chat UI and send these questions one at a time:

1. `What were the stations for Cloud Platform Expert Meet-up at Build 2024?`
2. `How many Expert Meet-up stations were there at Ignite 2025?`
3. `What happened at Build 2035?`

The third prompt tests the instruction that the agent must not invent facts when its Knowledge Base lacks the requested year.

Also create one controlled failure by temporarily using an invalid continuation:

1. Open a new browser tab or clear the current conversation.
2. Send another valid question.
3. Do not change production configuration merely to manufacture a failure.

The successful set is enough to explore traces; existing transient errors can be reviewed if present.

## Step 4: Inspect Foundry Traces

1. In the Foundry project, open **Traces**.
2. Set the time range to the last day.
3. Select a recent invocation for `conference-expert-agent`.
4. Review the trace timeline and expand available spans.
5. Record:
   - Total duration
   - Agent/model operation duration
   - Input and output token counts, when available
   - Knowledge or tool operations
   - Status and error details
6. Compare the grounded answer with the 2035 answer.

Depending on the portal rollout and agent API version, managed agent spans can take several minutes to appear and span names may differ. The important concepts are the execution hierarchy, timings, token attributes, retrieval operations, and errors.

Click the Graph view to see the span hierarchy and relationships.

> **Privacy:** Input/output capture can expose user prompts, model responses, and retrieved content. Enable content capture only with an approved retention, access, and redaction policy.

## Step 5: Review Foundry operational metrics

Click **Operate** on the top-right corner of the Foundry project to open the monitoring workbook.

1. Select Last Day for the time range.
2. Make sure the project is the project used for the workshop.
3. Review Agent run volume, success rate, and token usage.

If the new portal doesn't yet expose this view in your region, continue in Application Insights. Foundry experiences evolve, but the linked Application Insights workspace remains the source of the telemetry.

## Step 6: Query the AKS Chat UI

Open the Application Insights Logs query editor in the Azure portal:

1. Open the [Azure portal](https://portal.azure.com).
2. In the top search box, search for and select **Application Insights**.
3. Select the Application Insights resource whose name matches `$appInsightsName` from Step 1.
4. Under **Monitoring** in the resource menu, select **Logs**.
5. Close the **Queries hub** window if it opens and change the drop-down menu onm the right to KQL mode.
6. Paste the following query into a new query tab and select **Run**. Set the portal time range to **Last hour** if needed; the query also limits results to the last hour.

```kql
requests
| where timestamp > ago(1h)
| summarize Requests=count(), Failures=countif(success == false),
            P50=percentile(duration, 50), P95=percentile(duration, 95)
    by bin(timestamp, 5m), name
| order by timestamp desc
```

Review outbound calls from the UI:

```kql
dependencies
| where timestamp > ago(1h)
| where target contains "services.ai.azure.com"
| summarize Calls=count(), Failures=countif(success == false),
            AvgDuration=avg(duration), P95=percentile(duration, 95)
    by target, resultCode
| order by Calls desc
```

Review exceptions:

```kql
exceptions
| where timestamp > ago(24h)
| summarize Count=count(), LastSeen=max(timestamp) by type, outerMessage
| order by Count desc
```

The UI dependency duration includes network time plus the managed agent execution. Compare it with the selected Foundry trace duration to identify whether delay is mostly inside or outside the agent.

## Step 7: Enable Platform Diagnostics

Discover supported categories before creating settings:

```powershell
$foundryResourceId = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $resourceGroup `
    --query id -o tsv

$searchResourceId = az search service show `
    --name $searchName `
    --resource-group $resourceGroup `
    --query id -o tsv

az monitor diagnostic-settings categories list `
    --resource $foundryResourceId --output table

az monitor diagnostic-settings categories list `
    --resource $searchResourceId --output table
```

Enable available logs and metrics using category groups:

```powershell
az monitor diagnostic-settings create `
    --name foundry-diagnostics `
    --resource $foundryResourceId `
    --workspace $workspaceId `
    --export-to-resource-specific true `
    --logs '[{"categoryGroup":"audit","enabled":true},{"categoryGroup":"allLogs","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none

az monitor diagnostic-settings create `
    --name search-diagnostics `
    --resource $searchResourceId `
    --workspace $workspaceId `
    --export-to-resource-specific true `
    --logs '[{"categoryGroup":"audit","enabled":true},{"categoryGroup":"allLogs","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none
```

> For production, select only required categories. Full request/response logging can expose content and increase ingestion cost.

## Step 8: Inspect Resource Metrics

In Azure portal:

1. Open the Foundry resource, expand Monitoring and click **Metrics**.
2. In the chart view, make sure the scope is set to the Foundry resource and the time range is **Last 24 hours**.
3. On the Metric selection in the chart, inspect the data of different metrics, such as `Azure OpenAI Requests`, `Time to Response`, and `Latency`.
4. Return to the Azure portal home and navigate to the Azure AI Search → **Metrics**.
5. Review the AI Search associated metrics, such as `Document processed count`, `Indexed processed files`, `Query volume`, and `Storage usage`.

Metrics available in the picker are authoritative for the selected resource and region; names can change as releases evolve.

## Step 9: Create an Operational Alert

Create a simple alert for failed UI requests:

1. In the [Azure portal](https://portal.azure.com), search for and select **Application Insights**.
2. Open the resource whose name matches `$appInsightsName` from Step 1.
3. Under **Monitoring**, select **Alerts**, then select **Create** → **Alert rule**.

### Scope

The **Scope** tab should already contain the workshop Application Insights resource. Confirm that the resource name matches `$appInsightsName`; don't add the Log Analytics workspace or Foundry resource to this alert.

### Condition

1. Open the **Condition** tab.
2. For **Signal name**, select **Failed requests**.
3. Under **Alert logic**, enter these values exactly:

    | Setting | Value |
    | --- | --- |
    | Threshold type | **Static** |
    | Aggregation type | **Count** |
    | Operator | **Greater than** |
    | Unit | **Count** |
    | Threshold | `2` |

4. Leave **Split by dimensions** empty. This creates one alert across all failed requests rather than a separate alert for each request name or result code.
5. Under **When to evaluate**, set:

    | Setting | Value |
    | --- | --- |
    | Check every | **1 minute** |
    | Lookback period | **5 minutes** |

This condition fires when Application Insights records more than two failed requests during a five-minute window. The preview chart is historical guidance only; it doesn't need to show failures before the rule can be created.

### Actions

1. Select **Next: Actions**.
2. If an action group already exists for the workshop, choose **Use action groups**, select it, and then choose **Select**.
3. Otherwise, on the **Use quick actions** pane, enter:
    - **Action group name:** `path2-workshop-alerts`
    - **Display name:** `Path2Alerts`
4. On the actions, choose **Email** as the notification type, enter an address you can access, and click Save.
5. Click Next and on the Details tab, on the **Alert rule name** field, enter `path2-ui-failed-requests`.
6. Select **Review + create** and then **Create**. Back in the alert-rule wizard, confirm that `path2-workshop-alerts` appears under **Action group name**.

> Creating an action group can send real notifications and may incur notification charges. For a classroom demonstration where notifications aren't needed, you can continue without an action group and create only the alert rule.

Return to **Application Insights** → **Alerts** → **Alert rules** and confirm that `path2-ui-failed-requests` is listed and enabled. The rule may take several minutes to become active.

For production, also consider alerts for:

- Foundry 429 throttling
- P95 agent latency
- Model deployment utilization near quota
- Search throttling or indexer failures
- AKS pod restarts and unavailable replicas
- Evaluation quality or safety score regression

## Key Learnings

- Path 2 observability spans two execution boundaries
- Foundry traces explain managed agent operations
- Application Insights explains the external UI and API dependency
- Metrics, traces, logs, and evaluations answer different questions
- Token telemetry supports both performance and cost management

## Next Steps

## Best Practices

### Do

- Correlate UI requests, Foundry traces, model metrics, and Search telemetry
- Track P95 latency, failures, throttling, and token consumption
- Add quality and safety evaluation to operational monitoring
- Restrict access to prompt and response content
- Set retention and daily ingestion limits intentionally
- Alert on symptoms users experience, not every low-level metric

### Avoid

- Logging sensitive prompts by default
- Assuming HTTP success means a correct answer
- Enabling every diagnostic category indefinitely
- Monitoring only AKS when the agent runs in Foundry
- Treating delayed trace ingestion as request failure

Continue to **[Lab 6: Cost Management](06-cost-management.md)**.

## Resources

- [View traces in Microsoft Foundry](https://learn.microsoft.com/azure/ai-foundry/how-to/develop/trace-application)
- [Monitor generative AI applications](https://learn.microsoft.com/azure/ai-foundry/how-to/monitor-applications)
- [Application Insights overview](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [Azure AI Search monitoring](https://learn.microsoft.com/azure/search/search-monitor-usage)
