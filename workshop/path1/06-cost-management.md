# Lab 6: Cost Management & Optimization

## Overview

Analyze, optimize, and control costs for the AI agent on Azure infrastructure.

**Time:** 20-25 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Analyze current costs
- Implement cost controls
- Set up budgets and alerts
- Optimize resource sizing
- Implement auto-scaling

## Step 1: View Current Costs

### 1.1 View Costs in Azure Portal

1. **Open Azure Portal**, navigate to **Cost Management + Billing**, and select **Cost Management**
2. In the left menu, click **Cost analysis** under Reporting + analytics
3. Set the scope to your **Resource Group** (from `deployment-output.json`)
4. Select the **Accumulated costs** report
5. Change the time range to **Last 7 days**
6. Change Group by to **Resource type** and the Granularity to **None** to see cost breakdown
7. Review the chart and table showing actual costs

You should see costs broken down by:

- Azure AI Search
- Azure OpenAI (base + token usage)
- Storage Account
- Container Registry
- Key Vault
- Application Insights

> **💡 Note:** You won't see AKS compute node costs in this view because they're in the managed cluster (MC_) resource group, not your main resource group. To see full AKS costs, change the scope to your **Subscription** level and filter by resource group name, or navigate directly to the MC_ resource group.

### 1.2 View AKS Compute Costs

To see the actual compute costs for your AKS cluster:

1. In the **Cost analysis** view, change the scope to **Subscription** level
2. Keep **Accumulated costs** selected
3. Set **Group by** to **Resource group**
4. Look for the **MC_** resource group
5. This shows the compute node costs (Virtual Machines, Disks, Load Balancers)

> **💡 Why is this?** Azure Kubernetes Service creates a separate managed resource group (prefixed with MC_) for all cluster infrastructure. This keeps the cluster resources isolated from your application resources.

## Step 2: Create Budget and Alert

Creating a budget helps you track spending and get notified before costs exceed your threshold.

### 2.1 Create Budget in Azure Portal

1. **Open Azure Portal** → Navigate to **Cost Management + Billing**
2. Select **Cost Management** → Click **Budgets** under Monitoring in the left menu
3. Click **+ Add** to create a new budget
4. **Budget details:**
   - **Filters**: Add a filter **ResourceGroupName** and select your resource group
   - **Name**: `workshop-budget`
   - **Reset period**: Monthly
   - **Creation date**: First day of current month
   - **Expiration date**: One year from now
   - **Amount**: `$300`
   - Click Next
5. **Alert conditions:**
   - **Type**: Actual cost
   - **% of budget**: `80`
   - **Action group**: Skip (or create if you want)
   - **Alert recipients (email)**: Enter your email address
6. Click **Create**

You'll now receive an email alert when your monthly spending reaches 80% of $300 ($240).

### 2.2 (Optional) Create Budget via CLI

If you prefer to use the Azure CLI:

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName

# Simple budget without email notifications
az consumption budget create `
    --resource-group $resourceGroup `
    --budget-name "workshop-budget-cli" `
    --category cost `
    --amount 300 `
    --time-grain Monthly `
    --start-date (Get-Date -Day 1 -Format "yyyy-MM-dd") `
    --end-date ((Get-Date).AddYears(1).ToString("yyyy-MM-dd"))

Write-Host "Budget created: `$300/month" -ForegroundColor Green
Write-Host "Configure email alerts in the Azure Portal under Budgets" -ForegroundColor Yellow
```

## Step 3: Analyze Resource Utilization

```powershell
# Check AKS node utilization
Write-Host "`nAKS Resource Utilization:" -ForegroundColor Cyan
kubectl top nodes

# Check pod utilization
kubectl top pods --all-namespaces --sort-by=cpu

# Recommendation: If CPU < 30% consistently, consider smaller node sizes
```

## Step 4: Tag Resources for Cost Allocation

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName

# Tag all resources for cost tracking
$tags = @{
    Environment = $config.environment
    Project = "AgentsForITOps"
    CostCenter = "IT-Training"
    Owner = $env:USERNAME
}

az group update `
    --name $resourceGroup `
    --tags Environment=$($tags.Environment) Project=$($tags.Project) CostCenter=$($tags.CostCenter) Owner=$($tags.Owner)

Write-Host "Tags applied to resource group" -ForegroundColor Green

# Apply tags to individual resources
$resourceIds = az resource list `
    --resource-group $resourceGroup `
    --query '[].id' `
    -o tsv

foreach ($resourceId in $resourceIds) {
    az resource tag --ids $resourceId --tags Environment=$($tags.Environment) Project=$($tags.Project) 2>$null
}

Write-Host "Tags applied to all resources" -ForegroundColor Green
```

## Cost Optimization Best Practices

Beyond monitoring and budgets, consider these strategies to optimize Azure costs:

### Compute Optimization

- **Azure Reservations**: Save up to 72% on AKS compute by committing to 1 or 3-year reserved instances
- **Right-size VMs**: Monitor resource utilization for 2+ weeks and adjust VM sizes accordingly
- **Azure Spot VMs**: Use spot instances for non-critical workloads (up to 90% savings)
- **Auto-shutdown**: Enable scheduled shutdown for dev/test environments during non-business hours
- **Azure Hybrid Benefit**: Apply existing Windows Server licenses to save on VM costs

### AI Services Optimization

- **Token usage monitoring**: Track Azure OpenAI token consumption to identify expensive queries
- **Model selection**: Use smaller models (GPT-4.1-mini vs GPT-4) where appropriate
- **Caching**: Implement response caching to reduce redundant API calls
- **Batch processing**: Group similar requests together to optimize throughput

### Organizational Practices

- **Tagging**: Apply consistent tags for cost allocation and chargeback
- **Regular reviews**: Schedule monthly cost reviews to identify trends and anomalies
- **FinOps culture**: Involve engineering teams in cost optimization decisions

## Key Learnings

✅ **Monitor continuously:** Costs can spiral quickly  
✅ **Set budgets:** Get alerts before overspending  
✅ **Right-size resources:** Don't overprovision  
✅ **Use auto-scaling:** Pay only for what you need  
✅ **Tag everything:** Enable cost allocation and chargeback

## Cost Saving Checklist

- [ ] Budget alerts configured
- [ ] Auto-scaling enabled (HPA + Cluster Autoscaler)
- [ ] Lifecycle policies on storage
- [ ] Reserved instances for predictable workloads
- [ ] Dev/test resources scheduled for shutdown
- [ ] Tags applied for cost allocation
- [ ] Regular cost reviews scheduled
- [ ] Unused resources identified and deleted

## Congratulations!

You've completed the AI Agents for IT/Ops Workshop (Path 1)! You now have hands-on experience managing Azure infrastructure for AI agents, including deployment, security, monitoring, and cost optimization.

## Resources

- [Azure Cost Management Documentation](https://learn.microsoft.com/azure/cost-management-billing/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [FinOps Framework](https://www.finops.org/)
