# Lab 6: Cost Management for a Foundry Agent

## Overview

Analyze the complete Path 2 cost profile, including model tokens managed through Foundry, Azure AI Search, AKS compute, telemetry ingestion, and supporting services. Add budgets and identify the highest-value optimizations.

**Time:** 30-35 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Map Foundry assets to Azure meters and resources
- Analyze fixed and consumption-based costs
- Inspect model deployment utilization and quota
- Create a resource-group budget and alert
- Right-size the AKS UI separately from the managed agent
- Control Search, logging, and token costs

## Path 2 Cost Model

| Layer | Main billing driver | Cost shape |
| --- | --- | --- |
| Foundry model deployment | Input/output tokens and selected model/SKU | Consumption |
| Foundry Agent Service | Features and backing resources used | Feature dependent |
| Azure AI Search | Tier, replicas, partitions, semantic/agentic features | Mostly provisioned |
| AKS UI | VM nodes, disks, load balancer, networking | Provisioned |
| Application Insights / Logs | Data ingestion, retention, queries | Consumption |
| Storage | Capacity, transactions, retrieval, egress | Consumption |
| Key Vault / ACR / Private Link | Operations, storage, endpoints, traffic | Low but nonzero |

The Foundry portal organizes the agent, model, knowledge, traces, and evaluations. Azure Cost Management remains the source of billed cost.

## Step 1: Load the Deployment Context

```powershell
cd infrastructure/path2

$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$subscriptionId = $config.subscriptionId
$resourceGroup = $config.resourceGroupName
$aksName = $config.resources.aksCluster
$foundryName = $config.resources.foundry
$searchName = $config.resources.searchService
$modelDeployment = $config.foundry.deploymentName

$aksNodeResourceGroup = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query nodeResourceGroup -o tsv

Write-Host "Application resource group: $resourceGroup" -ForegroundColor Cyan
Write-Host "AKS node resource group: $aksNodeResourceGroup" -ForegroundColor Cyan
```

## Step 2: Analyze Cost in Azure Portal

1. Open the Azure portal and navigate to **Cost Management + Billing** → **Cost Management** → **Reporting + analytics** → **Cost analysis**.
2. Set scope to the subscription of the workshop.
3. Click the All views tab and select the **Accumulated costs** view.
4. Set the date range to **Last 7 days** or a time range that includes the usage of the resources in this workshop.
5. Add a resource-group filter containing both:
   - The workshop resource group
   - The AKS `MC_` node resource group
6. Group by **Resource type**, then by **Resource**.

Look for:

- Azure Kubernetes Service node virtual machines and managed disks
- Azure AI Search
- Cognitive Services / Foundry model usage
- Log Analytics and Application Insights
- Load Balancer, Public IP, Private Endpoint, and bandwidth
- Container Registry, Key Vault, and Storage

> Cost data can lag usage by several hours. A newly deployed workshop may show little or no cost initially.

## Step 3: Inspect Foundry Assets and Model Utilization

In the Foundry portal:

1. Click Build on the top-right corner, and select **Deployments** on the menu.
2. Click the model deployed for the workshop **gpt-5.4-mini** and click **Monitor**.
3. Under **Model metrics**, review the data for token usage and estimated costs.

The cost of the Foundry resources is a limited view of the total Azure spend. The Foundry portal shows only the model deployment and agent service, not the supporting AKS, Search, or telemetry resources. In a production scenario, Foundry may be a small fraction of the total cost so you should always plan to review the complete Azure spend for the subscription and resource groups.

## Step 4: Compare Path 1 and Path 2 Cost Ownership

| Concern | Path 1 | Path 2 |
| --- | --- | --- |
| Agent compute | AKS pods/nodes | Foundry-managed agent execution |
| UI compute | Same AKS workload as agent | Lightweight AKS UI only |
| Model usage | Direct Azure OpenAI calls | Foundry model deployment calls |
| Retrieval | App calls Search | Foundry IQ / Knowledge Base calls Search |
| Quality operations | Custom implementation | Foundry evaluations and monitoring |

Path 2 reduces custom operational work, but AKS is still a significant fixed workshop cost because it hosts only one lightweight replica on a two-node cluster. In production, the UI could be consolidated onto shared compute or moved to a lower-cost hosting option.

## Step 5: Analyze AKS Utilization

```powershell
kubectl top nodes
kubectl top pods -n agent-demo

kubectl get deployment agent-webapp -n agent-demo `
    -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

Current workshop requests are intentionally small for the UI. Compare actual CPU and memory with the configured requests and limits.

Before right-sizing production workloads:

- Observe at least one representative business cycle
- Include startup and peak traffic
- Keep headroom for failures and rolling updates
- Use HPA for the UI and cluster autoscaler for nodes
- Consider whether a dedicated AKS cluster is justified for a thin UI

## Step 6: Review Search Capacity and Knowledge Design

```powershell
az search service show `
    --name $searchName `
    --resource-group $resourceGroup `
    --query "{Sku:sku.name,Replicas:replicaCount,Partitions:partitionCount,Status:status}" `
    --output table
```

Azure AI Search is typically a provisioned hourly cost. Review:

- Whether `Basic` is sufficient for workshop scale
- Index size and document count
- Query latency and throttling before adding replicas
- Storage capacity before adding partitions
- Whether duplicate knowledge sources or indexes can be removed
- Knowledge Base reasoning effort; Lab 1 uses **Minimal** to avoid redundant reasoning in Search

Don't reduce replicas or partitions solely from one quiet workshop hour. Production availability and query load matter.

## Step 7: Review Log Ingestion and Retention

```powershell
$workspace = az monitor log-analytics workspace list `
    --resource-group $resourceGroup `
    --query "[0]" | ConvertFrom-Json

[PSCustomObject]@{
    Workspace = $workspace.name
    Sku       = $workspace.sku.name
    Retention = $workspace.retentionInDays
} | Format-List
```

In Log Analytics, estimate ingestion by table:

```kql
Usage
| where TimeGenerated > ago(7d)
| where IsBillable == true
| summarize BillableGB=sum(Quantity) / 1000.0 by DataType
| order by BillableGB desc
```

Cost controls include:

- Collecting only required diagnostic categories
- Avoiding full prompt/response capture by default
- Setting appropriate retention
- Configuring a workspace daily cap as a safety net, not normal flow control
- Sampling high-volume application telemetry

## Step 8: Create a Budget

### Azure Portal

1. Open **Cost Management** → **Monitoring** → **Budgets**.
2. Select **+ Add**.
3. Add a `ResourceGroupName` filter for the workshop resource group and the AKS node resource group when the UI allows multiple filter values.
4. Name the budget `path2-workshop-budget`.
5. Set a monthly amount appropriate for your subscription and workshop duration.
6. Add alerts at 50%, 80%, and 100% of actual cost.
7. Add a forecast alert if supported.
8. Configure recipients or an action group and create the budget.

## Step 9: Apply Cost Allocation Tags

```powershell
$owner = az ad signed-in-user show --query userPrincipalName -o tsv

az group update --name $resourceGroup --tags `
    Environment=$($config.environment) `
    Project=AgentsForITOps `
    WorkshopPath=Path2 `
    Owner=$owner `
    --output none

az group update --name $aksNodeResourceGroup --tags `
    Environment=$($config.environment) `
    Project=AgentsForITOps `
    WorkshopPath=Path2 `
    Owner=$owner `
    --output none
```

Tag inheritance into billing records isn't retroactive, and some managed resources don't automatically inherit resource-group tags. Use Azure Policy tag inheritance for production governance.

## Step 10: Build an Optimization Backlog

Classify each recommendation by savings, engineering effort, and quality/reliability risk:

| Candidate | Expected effect | Validate first |
| --- | --- | --- |
| Delete workshop resources after training | Removes nearly all ongoing cost | Confirm no shared assets |
| Move thin UI from dedicated AKS | Reduces fixed compute overhead | Hosting/security requirements |
| Right-size AKS nodes and replica floor | Reduces VM cost | Peak usage and availability |
| Use a smaller model | Reduces token cost and latency | Foundry evaluation quality |
| Shorten prompts and responses | Reduces input/output tokens | Task adherence and user value |
| Cache repeated safe responses | Avoids repeated agent calls | Freshness and authorization |
| Tune Search replicas/partitions | Reduces provisioned Search cost | Latency, SLA, capacity |
| Reduce diagnostic volume/retention | Reduces Log Analytics cost | Audit and incident needs |
| Schedule nonproduction environments | Avoids idle cost | Startup time and dependencies |

Use Foundry evaluations before changing models or prompts. A cheaper agent that fails its task isn't an optimization.

## Key Learnings

- Path 2 shifts agent operations to Foundry but retains supporting Azure costs
- Model tokens, Search, and AKS have different cost behaviors
- Foundry provides model, quota, trace, and evaluation context; Cost Management shows billed spend
- The dedicated AKS cluster is intentionally oversized for a single workshop UI
- Quality evaluation is required for safe AI cost optimization

## Cost Governance Checklist

- [ ] Main and AKS node resource groups included in analysis
- [ ] Budget and forecast alerts configured
- [ ] Foundry model utilization and quota reviewed
- [ ] Token use correlated with agent traces
- [ ] Search capacity reviewed
- [ ] AKS UI compute right-sizing candidate documented
- [ ] Log ingestion and retention reviewed
- [ ] Resources tagged for allocation
- [ ] Workshop cleanup owner and date recorded

## Best Practices

### Do

- Treat cost, quality, security, and reliability as joint constraints
- Track cost per successful or quality-approved agent interaction
- Review model and Search choices with real telemetry
- Include managed AKS resources in budgets
- Delete short-lived workshop infrastructure promptly

### Avoid

- Assuming Foundry portal asset names map one-to-one to billing meters
- Optimizing only token cost while ignoring AKS and Search fixed costs
- Reducing model size without evaluation
- Using Log Analytics daily caps as the primary monitoring strategy
- Treating quota as equivalent to spend

## Resources

- [Azure Cost Management](https://learn.microsoft.com/azure/cost-management-billing/cost-management-billing-overview)
- [Plan and manage Azure AI Search costs](https://learn.microsoft.com/azure/search/search-sku-manage-costs)
- [Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/)
- [FinOps Framework](https://www.finops.org/framework/)

## Congratulations

You've completed the six Path 2 labs and operated a Foundry-hosted prompt agent across identity, networking, secrets, observability, and cost management.
