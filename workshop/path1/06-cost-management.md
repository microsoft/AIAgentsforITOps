# Lab 6: Cost Management & Optimization

## Overview

Analyze, optimize, and control costs for the AI agent Azure infrastructure.

**Time:** 20-25 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Analyze current costs
- Implement cost controls
- Set up budgets and alerts
- Optimize resource sizing
- Implement auto-scaling

## Step 1: View Current Costs

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$subscriptionId = $config.subscriptionId

# Get current month costs
$endDate = Get-Date -Format "yyyy-MM-dd"
$startDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")

# Query cost management
az costmanagement query `
    --type ActualCost `
    --dataset-filter "{\"and\":[{\"dimensions\":{\"name\":\"ResourceGroup\",\"operator\":\"In\",\"values\":[\"$resourceGroup\"]}}]}" `
    --timeframe Custom `
    --time-period from=$startDate to=$endDate `
    --dataset-aggregation "{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}}" `
    --dataset-grouping name="ResourceType" type="Dimension" `
    --query "rows" `
    --output table

Write-Host "`nEstimated monthly cost breakdown:" -ForegroundColor Cyan
Write-Host "- AKS (2 nodes): ~`$150/month" -ForegroundColor Yellow
Write-Host "- AI Search (Basic): ~`$75/month" -ForegroundColor Yellow
Write-Host "- Storage (Standard LRS): ~`$5/month" -ForegroundColor Yellow
Write-Host "- Container Registry (Basic): ~`$5/month" -ForegroundColor Yellow
Write-Host "- Key Vault: ~`$0.03/month" -ForegroundColor Yellow
Write-Host "- Application Insights: ~`$2.30/month + data ingestion" -ForegroundColor Yellow
Write-Host "Total: ~`$240-260/month" -ForegroundColor Green
```

## Step 2: Create Budget and Alert

```powershell
# Create budget
$budgetName = "workshop-budget"
$budgetAmount = 300

az consumption budget create `
    --resource-group $resourceGroup `
    --budget-name $budgetName `
    --amount $budgetAmount `
    --time-grain Monthly `
    --start-date (Get-Date -Day 1 -Format "yyyy-MM-dd") `
    --end-date ((Get-Date).AddYears(1).ToString("yyyy-MM-dd")) `
    --notifications "{\"Actual_GreaterThan_80_Percent\":{\"enabled\":true,\"operator\":\"GreaterThan\",\"threshold\":80,\"contactEmails\":[\"your@email.com\"]}}"

Write-Host "Budget created: `$$budgetAmount/month" -ForegroundColor Green
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

## Step 4: Implement Auto-Scaling

```powershell
# Configure Horizontal Pod Autoscaler
@"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: agent-webapp-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-webapp
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
"@ | Out-File -FilePath "..\kubernetes\hpa.yaml" -Encoding UTF8

kubectl apply -f ..\kubernetes\hpa.yaml

Write-Host "Horizontal Pod Autoscaler configured" -ForegroundColor Green
```

## Step 5: Optimize Storage Costs

```powershell
$storageAccount = $config.resources.storageAccount

# Enable lifecycle management
az storage account management-policy create `
    --account-name $storageAccount `
    --policy @"
{
  \"rules\": [
    {
      \"enabled\": true,
      \"name\": \"MoveToCool\",
      \"type\": \"Lifecycle\",
      \"definition\": {
        \"filters\": {
          \"blobTypes\": [\"blockBlob\"],
          \"prefixMatch\": [\"conference-data/\"]
        },
        \"actions\": {
          \"baseBlob\": {
            \"tierToCool\": {\"daysAfterModificationGreaterThan\": 30}
          }
        }
      }
    }
  ]
}
"@

Write-Host "Storage lifecycle policy created" -ForegroundColor Green
```

## Step 6: Cost Optimization Recommendations

```powershell
Write-Host "`nCost Optimization Recommendations:" -ForegroundColor Cyan

$recommendations = @(
    "✅ Use Azure Reservations for AKS compute (up to 72% savings)",
    "✅ Enable auto-shutdown for dev/test resources",
    "✅ Right-size VMs based on actual usage (monitor for 2 weeks)",
    "✅ Use Azure Hybrid Benefit if you have licenses",
    "✅ Move infrequently accessed data to Cool or Archive tier",
    "✅ Delete unused snapshots and old container images",
    "✅ Use Azure Spot VMs for non-critical workloads",
    "✅ Review and remove orphaned resources (disks, IPs, etc.)"
)

$recommendations | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
```

## Step 7: Tag Resources for Cost Allocation

```powershell
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

## Next Steps

- **[Lab 7: Disaster Recovery & HA](07-disaster-recovery.md)**

## Resources

- [Azure Cost Management Documentation](https://learn.microsoft.com/azure/cost-management-billing/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [FinOps Framework](https://www.finops.org/)
