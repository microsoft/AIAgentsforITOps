# Lab 2: Managed Identity & RBAC

## Overview

Learn how to use Azure Managed Identities and Role-Based Access Control (RBAC) to secure access between Azure services without managing credentials.

**Time:** 25-30 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Understand managed identity types
- Configure RBAC permissions
- Test service-to-service authentication
- Troubleshoot identity issues
- Implement least-privilege access

## Managed Identity Types

### System-Assigned Managed Identity

- Tied to resource lifecycle
- Automatically deleted with resource
- One identity per resource

### User-Assigned Managed Identity

- Independent lifecycle
- Shared across multiple resources
- More flexible

**In this workshop, we use system-assigned identities for simplicity.**

## Step 1: Explore AKS Managed Identity

Load your environment:

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$aksName = $config.resources.aksCluster
```

Get AKS identity:

```powershell
# Get system-assigned managed identity
$aksIdentity = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query identity `
    | ConvertFrom-Json

Write-Host "Identity Type: $($aksIdentity.type)"
Write-Host "Principal ID: $($aksIdentity.principalId)"
Write-Host "Tenant ID: $($aksIdentity.tenantId)"
```

View the identity in Azure AD:

```powershell
# Get identity details
az ad sp show --id $aksIdentity.principalId | ConvertFrom-Json | Format-List
```

## Step 2: Audit Current RBAC Assignments

List all role assignments for the AKS identity:

```powershell
$aksIdentityId = $aksIdentity.principalId

# Get all role assignments
$roleAssignments = az role assignment list `
    --assignee $aksIdentityId `
    --all `
    --output json | ConvertFrom-Json

# Display organized view
$roleAssignments | ForEach-Object {
    [PSCustomObject]@{
        Role = $_.roleDefinitionName
        Scope = $_.scope
        Resource = ($_.scope -split '/')[-1]
    }
} | Format-Table -AutoSize
```

**Expected roles for AKS kubelet identity:**

- **Search Index Data Reader**  
  *Allows the agent application to query Azure AI Search indexes. The app retrieves relevant context from conference documents to answer user questions (traditional RAG pattern).*

- **AcrPull**  
  *Allows AKS to pull the agent container image from Azure Container Registry. Required for deploying and updating the application pods.*

- **Key Vault Secrets User**  
  *Allows the Secrets Store CSI Driver to read secrets from Key Vault and mount them as files in `/mnt/secrets-store/`. Provides access to Azure OpenAI endpoint, Application Insights connection string, and search endpoint.*

- **Cognitive Services OpenAI User**  
  *Allows the agent application to call the Azure OpenAI `gpt-4.1-mini` deployment. The app sends user questions with retrieved context to generate intelligent responses.*

> **Note:** The AKS identity does NOT have Storage access. Azure AI Search's managed identity has **Storage Blob Data Contributor** to read conference documents and build the search index. The pod only queries the already-built index.

## Step 3: View Storage Contents

View the conference data files that Azure AI Search indexed:

```powershell
$storageAccount = $config.resources.storageAccount

# Get storage account key (for comparison - we won't use this)
$storageKey = az storage account keys list `
    --account-name $storageAccount `
    --resource-group $resourceGroup `
    --query '[0].value' `
    -o tsv

Write-Host "Storage account has keys, but services use managed identity instead" -ForegroundColor Yellow

# List blobs using YOUR identity (requires you to have Storage Blob Data Reader or higher)
# This demonstrates the data that Search indexed
az storage blob list `
    --account-name $storageAccount `
    --container-name conference-data `
    --auth-mode login `
    --output table
```

**Key point:** Azure AI Search reads these files with its managed identity. The AKS pod never directly accesses storage - it only queries the search index!

## Step 4: Understand RBAC Scopes

RBAC assignments can be at different scopes:

```powershell
# Subscription scope
$subscriptionId = $config.subscriptionId
Write-Host "Subscription: /subscriptions/$subscriptionId"

# Resource group scope
$rgScope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup"
Write-Host "Resource Group: $rgScope"

# Resource scope (example: storage account)
$storageId = az storage account show `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --query id `
    -o tsv
Write-Host "Storage Account: $storageId"
```

**Best Practice:** Use the most restrictive scope possible (prefer resource > resource group > subscription).

## Step 5: Add Custom RBAC Assignment

Let's add a role assignment to demonstrate the process:

```powershell
# Create a user-assigned managed identity for testing
$testIdentityName = "test-managed-identity"

Write-Host "Creating test managed identity..." -ForegroundColor Cyan

$testIdentity = az identity create `
    --name $testIdentityName `
    --resource-group $resourceGroup `
    --location $config.location `
    | ConvertFrom-Json

$testIdentityId = $testIdentity.principalId

# Assign Storage Blob Data Reader role to test identity
Write-Host "Assigning Storage Blob Data Reader role..." -ForegroundColor Cyan

az role assignment create `
    --role "Storage Blob Data Reader" `
    --assignee-object-id $testIdentityId `
    --assignee-principal-type ServicePrincipal `
    --scope $storageId

# Verify assignment
az role assignment list `
    --assignee $testIdentityId `
    --scope $storageId `
    --output table
```

## Step 6: Test Least Privilege Access

Demonstrate what happens without proper permissions:

```powershell
# Try to delete a blob (should fail with current permissions)
try {
    az storage blob delete `
        --account-name $storageAccount `
        --container-name conference-data `
        --name "Build2024.docx" `
        --auth-mode login `
        --dry-run
    
    Write-Host "Dry run succeeded - checking actual permission..." -ForegroundColor Yellow
} catch {
    Write-Host "Access denied - this is expected! Identity only has READ permission." -ForegroundColor Green
}
```

**Key Learning:** Least privilege means granting only the minimum permissions needed.

## Step 7: Explore Search Service Identity

```powershell
$searchService = $config.resources.searchService

# Get Search service identity
$searchIdentity = az search service show `
    --name $searchService `
    --resource-group $resourceGroup `
    --query identity `
    | ConvertFrom-Json

Write-Host "Search Service Identity: $($searchIdentity.principalId)"

# List Search identity's role assignments
az role assignment list `
    --assignee $searchIdentity.principalId `
    --all `
    --output table
```

**Expected role for Search Service Identity:**

- **Storage Blob Data Contributor**  
  *Allows Azure AI Search to read conference data files (Build2024.docx, Build2025.docx, Ignite2024.docx, Ignite2025.docx) from the `conference-data` blob container and build the search index.*

**Why does Search need Storage access?**
- Search reads the .docx files and extracts text content
- Search builds and maintains the searchable index
- Uses managed identity instead of connection strings (more secure)
- The AKS pod queries this pre-built index - it never touches storage directly

## Step 8: Workload Identity for Kubernetes

Configure workload identity for AKS pods:

```powershell
# Get OIDC issuer URL
$oidcIssuer = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query oidcIssuerProfile.issuerUrl `
    -o tsv

Write-Host "OIDC Issuer: $oidcIssuer"

# Create federated credential for pod identity
$namespace = "default"
$serviceAccount = "agent-webapp-sa"

# This allows pods using this service account to get tokens
az identity federated-credential create `
    --name "$aksName-pod-identity" `
    --identity-name $(az aks show --name $aksName --resource-group $resourceGroup --query identity.userAssignedIdentities | ConvertFrom-Json | Get-Member -MemberType NoteProperty | Select-Object -First 1 -ExpandProperty Name | Split-Path -Leaf) `
    --resource-group $resourceGroup `
    --issuer $oidcIssuer `
    --subject "system:serviceaccount:${namespace}:${serviceAccount}" `
    --audiences "api://AzureADTokenExchange" `
    | Out-Null

Write-Host "Federated credential created for pod identity" -ForegroundColor Green
```

## Step 9: View RBAC Audit Logs

Monitor who accessed what:

```powershell
# Query Activity Log for role assignments
$endTime = Get-Date
$startTime = $endTime.AddHours(-24)

az monitor activity-log list `
    --resource-group $resourceGroup `
    --start-time $startTime.ToString("yyyy-MM-ddTHH:mm:ss") `
    --end-time $endTime.ToString("yyyy-MM-ddTHH:mm:ss") `
    --query "[?contains(operationName.localizedValue, 'role assignment')].{Time:eventTimestamp, Operation:operationName.localizedValue, Status:status.localizedValue, Caller:caller}" `
    --output table
```

## Step 10: Clean Up Test Resources

Remove the test identity created earlier:

```powershell
Write-Host "Cleaning up test identity..." -ForegroundColor Cyan

# Remove role assignment first
az role assignment delete `
    --assignee $testIdentityId `
    --scope $storageId

# Delete identity
az identity delete `
    --name $testIdentityName `
    --resource-group $resourceGroup

Write-Host "Test resources cleaned up" -ForegroundColor Green
```

## Best Practices Summary

### ✅ DO

- Use system-assigned identities for single-resource scenarios
- Use user-assigned identities when sharing across resources
- Assign roles at the most restrictive scope
- Regularly audit role assignments
- Use workload identity for Kubernetes pods
- Enable managed identity for all supported Azure services
- Document why each permission is needed

### ❌ DON'T

- Store connection strings or keys in code
- Grant excessive permissions
- Use subscription-level roles unnecessarily
- Share credentials between services
- Disable managed identity features

## Common RBAC Roles

| Role | Use Case | Permissions |
|------|----------|-------------|
| **Storage Blob Data Reader** | Read blobs | List, read |
| **Storage Blob Data Contributor** | Read/write blobs | List, read, write, delete |
| **Search Index Data Reader** | Query search indexes | Search |
| **AcrPull** | Pull container images | Registry read |
| **Key Vault Secrets User** | Read secrets | Get secret values |
| **Cognitive Services OpenAI User** | Call AI models | Inference |

## Troubleshooting

### Role Assignment Not Working

Wait for propagation (can take 5-10 minutes):

```powershell
# Check if assignment exists
az role assignment list --assignee <principal-id> --scope <resource-id>

# Force refresh (logout and login)
az logout
az login
```

### "Insufficient Permissions" Error

```powershell
# Verify the identity has the required role
az role assignment list --assignee <principal-id> --all

# Check the scope is correct
# Resource scope is more restrictive than resource group scope
```

### Managed Identity Not Found

```powershell
# Verify identity is enabled
az aks show --name <aks-name> --resource-group <rg> --query identity

# If null, enable it:
az aks update --name <aks-name> --resource-group <rg> --enable-managed-identity
```

## Key Learnings

✅ **No Secrets in Code:** Managed identities eliminate credential management  
✅ **Least Privilege:** Grant minimum permissions needed  
✅ **Auditable:** All access logged via Activity Log  
✅ **Automatic Rotation:** No manual key rotation needed  
✅ **RBAC Scopes:** Use most restrictive scope possible

## Challenge Exercise

**Task:** Create a new managed identity and grant it read-only access to Key Vault.

<details>
<summary>Solution (click to expand)</summary>

```powershell
# Create identity
$challengeIdentity = az identity create `
    --name "challenge-identity" `
    --resource-group $resourceGroup `
    --location $config.location `
    | ConvertFrom-Json

# Get Key Vault ID
$kvId = az keyvault show `
    --name $config.resources.keyVault `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Assign role
az role assignment create `
    --role "Key Vault Secrets User" `
    --assignee-object-id $challengeIdentity.principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $kvId

# Verify
az role assignment list `
    --assignee $challengeIdentity.principalId `
    --scope $kvId `
    --output table
```
</details>

## Next Steps

- **[Lab 3: Networking](03-networking.md)** - Configure virtual networks and private endpoints

## Resources

- [Managed Identities Documentation](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure RBAC Documentation](https://learn.microsoft.com/azure/role-based-access-control/)
- [AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)
