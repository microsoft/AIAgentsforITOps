# Lab 4: Secrets Management with Key Vault

## Overview

Learn to securely manage secrets, certificates, and keys using Azure Key Vault integrated with your AI agent application.

**Time:** 20-25 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Store and retrieve secrets from Key Vault
- Integrate Key Vault with applications
- Implement secret rotation
- Monitor secret access
- Use Key Vault references in Kubernetes

## Step 1: Store Application Secrets

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$keyVault = $config.resources.keyVault
$resourceGroup = $config.resourceGroupName

# Store Foundry endpoint as secret
az keyvault secret set `
    --vault-name $keyVault `
    --name "FoundryProjectEndpoint" `
    --value $config.endpoints.foundryProject

# Store Application Insights connection string
$appInsightsConnectionString = az monitor app-insights component show `
    --app $config.resources.appInsights `
    --resource-group $resourceGroup `
    --query connectionString `
    -o tsv

az keyvault secret set `
    --vault-name $keyVault `
    --name "AppInsightsConnectionString" `
    --value $appInsightsConnectionString

# Store AKS managed identity client ID
$aksIdentity = az aks show `
    --name $config.resources.aksCluster `
    --resource-group $resourceGroup `
    --query identity.principalId `
    -o tsv

az keyvault secret set `
    --vault-name $keyVault `
    --name "AKSManagedIdentityClientId" `
    --value $aksIdentity

Write-Host "Secrets stored in Key Vault" -ForegroundColor Green
```

## Step 2: Retrieve Secrets Securely

```powershell
# Retrieve secret
$foundryEndpoint = az keyvault secret show `
    --vault-name $keyVault `
    --name "FoundryProjectEndpoint" `
    --query value `
    -o tsv

Write-Host "Retrieved secret (first 20 chars): $($foundryEndpoint.Substring(0, 20))..." -ForegroundColor Yellow

# Show secret versions
az keyvault secret list-versions `
    --vault-name $keyVault `
    --name "FoundryProjectEndpoint" `
    --query '[].{Enabled:attributes.enabled, Created:attributes.created, Version:id}' `
    --output table
```

## Step 3: Configure CSI Driver for AKS

```powershell
# Enable Key Vault provider for AKS
az aks enable-addons `
    --addons azure-keyvault-secrets-provider `
    --name $config.resources.aksCluster `
    --resource-group $resourceGroup

Write-Host "Azure Key Vault Secrets Provider enabled for AKS" -ForegroundColor Green

# Create SecretProviderClass
@"
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault-secrets
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "$aksIdentity"
    keyvaultName: "$keyVault"
    objects: |
      array:
        - |
          objectName: FoundryProjectEndpoint
          objectType: secret
          objectVersion: ""
        - |
          objectName: AppInsightsConnectionString
          objectType: secret
          objectVersion: ""
    tenantId: "$(az account show --query tenantId -o tsv)"
"@ | Out-File -FilePath "..\kubernetes\secretproviderclass.yaml" -Encoding UTF8

kubectl apply -f ..\kubernetes\secretproviderclass.yaml

Write-Host "SecretProviderClass created" -ForegroundColor Green
```

## Step 4: Enable Secret Rotation

```powershell
# Set expiration policy
az keyvault secret set-attributes `
    --vault-name $keyVault `
    --name "FoundryProjectEndpoint" `
    --expires "$(Get-Date).AddDays(90).ToString('yyyy-MM-ddTHH:mm:ss')"

# Enable soft-delete (should already be enabled)
az keyvault update `
    --name $keyVault `
    --resource-group $resourceGroup `
    --enable-soft-delete true `
    --enable-purge-protection true

Write-Host "Secret expiration and soft-delete configured" -ForegroundColor Green
```

## Step 5: Monitor Secret Access

```powershell
# Enable diagnostic settings
$workspaceId = az monitor log-analytics workspace show `
    --resource-group $resourceGroup `
    --workspace-name $config.resources.workspaceName `
    --query id `
    -o tsv

az monitor diagnostic-settings create `
    --name "kv-diagnostics" `
    --resource $(az keyvault show --name $keyVault --resource-group $resourceGroup --query id -o tsv) `
    --workspace $workspaceId `
    --logs '[{"category": "AuditEvent", "enabled": true}]' `
    --metrics '[{"category": "AllMetrics", "enabled": true}]'

Write-Host "Key Vault diagnostics enabled" -ForegroundColor Green

# Query audit logs
az monitor activity-log list `
    --resource-group $resourceGroup `
    --offset 1h `
    --query "[?contains(resourceId, 'vaults/$keyVault')].{Time:eventTimestamp, Operation:operationName.localizedValue, Status:status.localizedValue}" `
    --output table
```

## Key Learnings

✅ **Never hardcode secrets**  
✅ **Use managed identities for Key Vault access**  
✅ **Enable soft-delete and purge protection**  
✅ **Monitor all secret access**  
✅ **Rotate secrets regularly**

## Next Steps

- **[Lab 5: Monitoring & Observability](05-monitoring.md)**

## Resources

- [Key Vault Documentation](https://learn.microsoft.com/azure/key-vault/)
- [AKS Secrets Store CSI Driver](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver)
