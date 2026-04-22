# Lab 7: Disaster Recovery & High Availability

## Overview

Implement disaster recovery and high availability patterns for the AI agent infrastructure.

**Time:** 30-35 minutes  
**Difficulty:** Advanced

## Learning Objectives

- Configure backup and restore
- Implement geo-redundancy
- Set up health checks
- Create disaster recovery runbook
- Test failover procedures

## Step 1: Configure AKS Backup

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$aksName = $config.resources.aksCluster

# Install Velero for Kubernetes backups
kubectl create namespace velero

# Create storage account for backups
$backupStorageAccount = "$($config.resources.storageAccount)backup".ToLower()

az storage account create `
    --name $backupStorageAccount `
    --resource-group $resourceGroup `
    --location $config.location `
    --sku Standard_GRS `
    --kind StorageV2

az storage container create `
    --name velero `
    --account-name $backupStorageAccount

Write-Host "Backup storage configured" -ForegroundColor Green
```

## Step 2: Configure Storage Geo-Redundancy

```powershell
$storageAccount = $config.resources.storageAccount

# Upgrade to GRS (Geo-Redundant Storage)
az storage account update `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --sku Standard_GRS

Write-Host "Storage upgraded to GRS (replicates to secondary region)" -ForegroundColor Green

# View replication status
az storage account show `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --query '{Name:name, SKU:sku.name, PrimaryLocation:primaryLocation, SecondaryLocation:secondaryLocation}' `
    | ConvertFrom-Json | Format-List
```

## Step 3: Enable Key Vault Backup

```powershell
$keyVault = $config.resources.keyVault

# Backup all secrets
$secrets = az keyvault secret list `
    --vault-name $keyVault `
    --query '[].name' `
    -o tsv

$backupFolder = "..\keyvault-backup"
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null

foreach ($secret in $secrets) {
    Write-Host "Backing up secret: $secret" -ForegroundColor Cyan
    
    az keyvault secret backup `
        --vault-name $keyVault `
        --name $secret `
        --file "$backupFolder\$secret.backup"
}

Write-Host "Key Vault secrets backed up to: $backupFolder" -ForegroundColor Green
```

## Step 4: Configure Multi-Region Deployment (Conceptual)

```powershell
Write-Host "`nMulti-Region Architecture:" -ForegroundColor Cyan

@"
Primary Region (Active):
- AKS Cluster #1
- Storage Account (GRS primary)
- AI Search #1
- Key Vault #1

Secondary Region (Standby):
- AKS Cluster #2 (ready for failover)
- Storage Account (GRS replica - read-only)
- AI Search #2 (replica)
- Key Vault #2 (replica)

Traffic Manager / Front Door:
- Health probes on both regions
- Automatic failover to secondary
- Geographic routing
"@ | Write-Host -ForegroundColor Yellow

Write-Host "`nFor production, deploy to secondary region using:" -ForegroundColor Green
Write-Host ".\deploy-infra.ps1 -ParametersFile .\parameters-secondary.json" -ForegroundColor White
```

## Step 5: Implement Health Checks

```powershell
# Update deployment with health checks (already in deployment.yaml)
Write-Host "`nHealth check configuration:" -ForegroundColor Cyan

@"
Liveness Probe:
- Endpoint: /health
- Initial Delay: 30s
- Period: 10s
- Failure Threshold: 3

Readiness Probe:
- Endpoint: /health
- Initial Delay: 10s
- Period: 5s
- Failure Threshold: 3
"@ | Write-Host -ForegroundColor Yellow

# Test health endpoint
kubectl get pods -l app=agent-webapp -o wide
```

## Step 6: Create Disaster Recovery Runbook

```powershell
$runbook = @"
# Disaster Recovery Runbook - AI Agent Infrastructure

## Recovery Time Objective (RTO): 4 hours
## Recovery Point Objective (RPO): 1 hour

## Scenario 1: AKS Cluster Failure

1. Verify primary cluster is down:
   kubectl cluster-info

2. Switch to secondary cluster:
   az aks get-credentials --name <secondary-aks> --resource-group <secondary-rg>

3. Verify pods are running:
   kubectl get pods --all-namespaces

4. Update DNS/Traffic Manager to point to secondary:
   az network traffic-manager endpoint update ...

## Scenario 2: Storage Account Failure

1. Initiate failover to secondary region:
   az storage account failover --name $storageAccount --resource-group $resourceGroup

2. Update application configuration with new endpoint

3. Verify data accessibility

## Scenario 3: Complete Region Outage

1. Activate secondary region resources
2. Restore Key Vault secrets from backup
3. Update DNS to secondary region
4. Validate all services operational
5. Monitor and adjust capacity

## Post-Recovery Tasks

- [ ] Document incident
- [ ] Review logs
- [ ] Update runbook
- [ ] Conduct postmortem
- [ ] Test restore procedures

## Contact Information

Primary: Operations Team - ops@company.com
Escalation: CTO - cto@company.com
Azure Support: 1-800-xxx-xxxx
"@

$runbook | Out-File -FilePath "..\DR-Runbook.md" -Encoding UTF8
Write-Host "Disaster Recovery Runbook created: DR-Runbook.md" -ForegroundColor Green
```

## Step 7: Test Backup Restore

```powershell
# Simulate restore of a secret
$testSecret = "AppInsightsConnectionString"

Write-Host "`nTesting restore procedure for: $testSecret" -ForegroundColor Cyan

# Backup secret
az keyvault secret backup `
    --vault-name $keyVault `
    --name $testSecret `
    --file ".\test-backup.backup"

Write-Host "Secret backed up" -ForegroundColor Green

# Simulate restoration (to same or different vault)
Write-Host "To restore, run:" -ForegroundColor Yellow
Write-Host "az keyvault secret restore --vault-name $keyVault --file .\test-backup.backup" -ForegroundColor White

# Clean up test
Remove-Item ".\test-backup.backup" -Force
```

## Step 8: Configure Alerts for Availability

```powershell
$aksId = az aks show --name $aksName --resource-group $resourceGroup --query id -o tsv

# Create availability alert
az monitor metrics alert create `
    --name "AKS-Availability-Alert" `
    --resource-group $resourceGroup `
    --scopes $aksId `
    --condition "avg kube_node_status_condition < 1" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --description "Alert when AKS nodes become unhealthy"

Write-Host "Availability alerts configured" -ForegroundColor Green
```

## Step 9: Document Recovery Procedures

```powershell
$procedures = @"
# Recovery Procedures

## Backup Schedule
- Full backup: Weekly (Sunday 00:00 UTC)
- Incremental: Daily (00:00 UTC)
- Retention: 30 days

## Restore Time Estimates
- Single secret: < 5 minutes
- Key Vault: < 15 minutes
- AKS configuration: < 30 minutes
- Full infrastructure: < 4 hours

## Validation Checklist
- [ ] All pods running (kubectl get pods)
- [ ] Health endpoints responding
- [ ] Storage accessible
- [ ] Secrets retrievable
- [ ] External connectivity verified
- [ ] Monitoring operational
- [ ] Logs flowing to Application Insights
"@

$procedures | Out-File -FilePath "..\Recovery-Procedures.md" -Encoding UTF8
Write-Host "Recovery procedures documented" -ForegroundColor Green
```

## Step 10: High Availability Checklist

```powershell
Write-Host "`nHigh Availability Checklist:" -ForegroundColor Cyan

$haChecklist = @(
    "✅ Multiple AKS nodes (min 3 for production)",
    "✅ Pod replicas (min 2 per deployment)",
    "✅ Geo-redundant storage (GRS or GZRS)",
    "✅ Health checks configured",
    "✅ Auto-scaling enabled",
    "✅ Backup and restore tested",
    "✅ Multi-region deployment plan",
    "✅ DR runbook created and tested",
    "✅ Monitoring and alerting active",
    "✅ Incident response team trained"
)

$haChecklist | ForEach-Object { Write-Host $_ -ForegroundColor Green }
```

## Key Learnings

✅ **Plan for failure:** Everything fails eventually  
✅ **Test DR procedures:** Untested backups are useless  
✅ **Document everything:** Clear runbooks save hours during incidents  
✅ **Automate recovery:** Manual processes lead to errors  
✅ **Monitor continuously:** Early detection reduces impact

## RTO/RPO Targets by Tier

| Tier | RTO | RPO | Cost |
|------|-----|-----|------|
| **Bronze** | 24 hours | 24 hours | $ |
| **Silver** | 4 hours | 1 hour | $$ |
| **Gold** | 1 hour | 15 minutes | $$$ |
| **Platinum** | < 1 minute | Near-zero | $$$$ |

**This workshop implements Silver tier (RTO: 4h, RPO: 1h)**

## Disaster Recovery Testing

Schedule regular DR tests:

```powershell
# Quarterly DR test schedule
$drTests = @(
    @{ Quarter="Q1"; Scenario="AKS cluster failure"; Date="January 15" },
    @{ Quarter="Q2"; Scenario="Storage account corruption"; Date="April 15" },
    @{ Quarter="Q3"; Scenario="Complete region outage"; Date="July 15" },
    @{ Quarter="Q4"; Scenario="Full restore from backup"; Date="October 15" }
)

$drTests | Format-Table -AutoSize
```

## Workshop Completion

Congratulations! You've completed all workshop labs:

✅ Lab 0: Prerequisites  
✅ Lab 1: Deploy Infrastructure  
✅ Lab 2: Managed Identity & RBAC  
✅ Lab 3: Private Networking  
✅ Lab 4: Secrets Management  
✅ Lab 5: Monitoring & Observability  
✅ Lab 6: Cost Management  
✅ Lab 7: Disaster Recovery & HA

## Final Cleanup

**Only run when completely done with the workshop:**

```powershell
# ⚠️ WARNING: This deletes all workshop resources

Write-Host "Are you sure you want to delete all workshop resources?" -ForegroundColor Red
$confirmation = Read-Host "Type 'DELETE' to confirm"

if ($confirmation -eq 'DELETE') {
    az group delete --name $resourceGroup --yes --no-wait
    Write-Host "Resource group deletion initiated" -ForegroundColor Yellow
    Write-Host "Resources will be deleted in the background (20-30 minutes)" -ForegroundColor Yellow
} else {
    Write-Host "Deletion cancelled" -ForegroundColor Green
}
```

## Resources

- [Azure Site Recovery](https://learn.microsoft.com/azure/site-recovery/)
- [AKS Business Continuity](https://learn.microsoft.com/azure/aks/operator-best-practices-multi-region)
- [Azure Backup](https://learn.microsoft.com/azure/backup/)
- [Disaster Recovery Planning Guide](https://learn.microsoft.com/azure/architecture/framework/resiliency/backup-and-recovery)
