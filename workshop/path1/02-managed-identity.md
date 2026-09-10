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

### AKS-Specific: Two Identities

> Note: In this workshop, we use AKS for hosting our application and agent. The below details are exclusive for AKS. If your company hosts your app and agents on other services (like Azure App Service, Azure Container Apps, etc.) then this specific detail about AKS having two identities does not apply to you.

By default, AKS clusters use **two distinct managed identities**:

1. **Control Plane Identity**
   - Manages the AKS cluster infrastructure
   - Has Contributor access to the MC_* (managed cluster) resource group, and AcrPull role on the Container Registry (if using ACR)
   - Creates/manages VMs, load balancers, NSGs, etc.

2. **Kubelet Identity**
   - Used by worker nodes and **all pods running on AKS**
   - This is what your application uses to access Azure resources
    - Granted permissions to ACR, Key Vault, Search, Foundry, etc.

> **Key Point:** When configuring RBAC for your application, you assign roles to the **kubelet identity**, not the control plane identity!

## Step 1: Explore AKS Managed Identities

If not already there, navigate to the /infrastructure/path1/ directory.

```powershell
cd infrastructure/path1/
```

Load the information from your deployment into your environment:

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$aksName = $config.resources.aksCluster
```

**Important:** AKS uses **two different managed identities**:

1. **Control Plane Identity** - Manages cluster infrastructure (MC_ resource group)
2. **Kubelet Identity** - Used by nodes and pods to access Azure resources

Get both identities:

```powershell
# Get AKS control plane identity
$aksControlPlaneIdentity = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query identity.principalId `
    -o tsv

Write-Host "`n=== AKS Control Plane Identity ===`nPrincipal ID: $aksControlPlaneIdentity" -ForegroundColor Cyan

# Get kubelet identity (this is what pods use!)
$kubeletIdentity = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query identityProfile.kubeletidentity `
    | ConvertFrom-Json

Write-Host "`n=== Kubelet Identity (Used by Pods) ===`nPrincipal ID: $($kubeletIdentity.objectId)`nClient ID: $($kubeletIdentity.clientId)`nResource ID: $($kubeletIdentity.resourceId)" -ForegroundColor Cyan
```

## Step 2: Audit Control Plane Identity RBAC

List role assignments for the **AKS control plane identity**:

```powershell
# Get control plane role assignments
$controlPlaneRoles = az role assignment list `
    --assignee $aksControlPlaneIdentity `
    --all `
    --output json | ConvertFrom-Json

Write-Host "`n=== Control Plane Identity Roles ===" -ForegroundColor Cyan
$controlPlaneRoles | ForEach-Object {
    [PSCustomObject]@{
        Role = $_.roleDefinitionName
        Scope = $_.scope
        Resource = ($_.scope -split '/')[-1]
    }
} | Format-Table -AutoSize
```

**Expected roles for Control Plane Identity:**

- **Contributor** on MC_* resource group  
  *Manages the AKS-managed infrastructure (VMs, load balancers, etc.)*

- **AcrPull** on Container Registry  
  *Allows AKS to pull container images for deployments*

## Step 3: Audit Kubelet Identity RBAC

List role assignments for the **kubelet identity** (this is what your pods use):

```powershell
# Get kubelet role assignments
$kubeletRoles = az role assignment list `
    --assignee $kubeletIdentity.objectId `
    --all `
    --output json | ConvertFrom-Json

Write-Host "`n=== Kubelet Identity Roles (Used by Pods) ===" -ForegroundColor Cyan
$kubeletRoles | ForEach-Object {
    [PSCustomObject]@{
        Role = $_.roleDefinitionName
        Scope = $_.scope
        Resource = ($_.scope -split '/')[-1]
    }
} | Format-Table -AutoSize
```

**Expected roles for Kubelet Identity:**

- **Search Index Data Reader**  
  *Allows the agent application to query Azure AI Search indexes. The app retrieves relevant context from conference documents to answer user questions (traditional RAG pattern).*

- **Key Vault Secrets User**  
    *Allows the Secrets Store CSI Driver to read secrets from Key Vault and mount them as files in `/mnt/secrets-store/`. These secrets provide the Foundry Responses endpoint, Application Insights connection string, and Search endpoint.*

- **Cognitive Services OpenAI User**  
    *Allows the agent application to call the `gpt-5.4-mini` deployment on the Microsoft Foundry account. The built-in role retains “OpenAI” in its name because Foundry exposes the model through an OpenAI-compatible inference API.*

> **Note:** The kubelet identity does NOT have Storage access. Azure AI Search's managed identity has **Storage Blob Data Contributor** to read conference documents and build the search index. The pod only queries the already-built index.

## Step 4: View Storage Contents

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

# Get your current user's object ID
$currentUserId = az ad signed-in-user show --query id -o tsv

# Get storage account resource ID
$storageAccountId = az storage account show `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Grant yourself Storage Blob Data Reader to view the blobs
az role assignment create `
    --role "Storage Blob Data Reader" `
    --assignee-object-id $currentUserId `
    --assignee-principal-type User `
    --scope $storageAccountId `
    2>&1 | Out-Null

Write-Host "`nGranted Storage Blob Data Reader permission to your user account" -ForegroundColor Green

# List blobs using YOUR identity
# This demonstrates the data that Search indexed
az storage blob list `
    --account-name $storageAccount `
    --container-name conference-data `
    --auth-mode login `
    --output table
```

> Note: It might take a few moments for the role assignment to propagate.

**Key point:** Azure AI Search reads these files with its managed identity. The AKS kubelet identity never directly accesses storage - pods only query the search index!

## Step 5: Understand RBAC Scopes

RBAC assignments can be at different scopes:

```powershell
# Subscription scope
$subscriptionId = $config.subscriptionId

# Resource group scope
$rgScope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup"

# Resource scope (example: storage account)
$storageId = az storage account show `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

Write-Host "`nSubscription: /subscriptions/$subscriptionId`nResource Group: $rgScope`nStorage Account: $storageId" -ForegroundColor Cyan
```

**Best Practice:** Use the most restrictive scope possible (prefer resource > resource group > subscription).

## Step 6: Add Custom RBAC Assignment

Let's add a role assignment to demonstrate the process:

```powershell
# Create a user-assigned managed identity for testing
$testIdentityName = "test-managed-identity"

$testIdentity = az identity create `
    --name $testIdentityName `
    --resource-group $resourceGroup `
    --location $config.location `
    | ConvertFrom-Json

$testIdentityId = $testIdentity.principalId

# Assign Storage Blob Data Reader role to test identity
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

## Step 7: Test Least Privilege Access

Demonstrate what happens without proper permissions:

```powershell
# Try to delete a blob (should fail - we only have READ permission)
Write-Host "`nAttempting to delete a blob with Storage Blob Data Reader permission..." -ForegroundColor Cyan

$deleteResult = az storage blob delete `
    --account-name $storageAccount `
    --container-name conference-data `
    --name "Build2024.docx" `
    --auth-mode login `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "✓ Access denied as expected! You only have READ permission, not DELETE." -ForegroundColor Green
    Write-Host "  Error: $deleteResult" -ForegroundColor DarkGray
} else {
    Write-Host "✗ Unexpected: Delete succeeded (you may have higher permissions than expected)" -ForegroundColor Yellow
}
```

**Key Learning:** Least privilege means granting only the minimum permissions needed.

## Step 8: Explore Search Service Identity

```powershell
$searchService = $config.resources.searchService

# Get Search service identity
$searchIdentity = az search service show `
    --name $searchService `
    --resource-group $resourceGroup `
    --query identity `
    | ConvertFrom-Json

Write-Host "`nSearch Service Identity: $($searchIdentity.principalId)" -ForegroundColor Cyan

# List Search identity's role assignments
az role assignment list `
    --assignee $searchIdentity.principalId `
    --all `
    --output table
```

**Expected role for Search Service Identity:**

- **Storage Blob Data Contributor**  
  *Allows Azure AI Search to read conference data files (Build2024.docx, Build2025.docx, Ignite2024.docx, Ignite2025.docx) from the `conference-data` blob container and build the search index.*

> **Note:** For this workshop's read-only indexing scenario, **Storage Blob Data Reader** would be sufficient. We granted **Contributor** to demonstrate a common pattern and to support potential future scenarios like automated index rebuilds or document cleanup workflows. In production, always start with the minimum role needed (Reader) and elevate only if required.

**Why does Search need Storage access?**

- Search reads the .docx files and extracts text content
- Search builds and maintains the searchable index
- Uses managed identity instead of connection strings (more secure)
- The AKS pod queries this pre-built index - it never touches storage directly

## Step 9: Workload Identity for Kubernetes

**Workload Identity** enables Kubernetes pods to authenticate as Azure managed identities without storing credentials. It works by establishing a trust relationship between your AKS cluster's OIDC issuer and Microsoft Entra ID. When a pod needs to access resources such as Key Vault, Search, or Foundry, it requests a token from its service account, which Entra ID validates against a federated credential. This token exchange allows the pod to assume the managed identity's permissions securely. Think of it as "pod-to-Azure SSO": application code uses `DefaultAzureCredential`, and Azure handles authentication.

Configure workload identity for AKS pods:

```powershell
# Get OIDC issuer URL
$oidcIssuer = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query oidcIssuerProfile.issuerUrl `
    -o tsv

Write-Host "`nOIDC Issuer: $oidcIssuer" -ForegroundColor Cyan

# Create federated credential for pod identity
$namespace = "default"
$serviceAccount = "agent-webapp-sa"

# Get the kubelet identity name from the resource ID
$kubeletIdentityName = ($kubeletIdentity.resourceId -split '/')[-1]

# This allows pods using this service account to get tokens as the kubelet identity
az identity federated-credential create `
    --name "$aksName-pod-identity" `
    --identity-name $kubeletIdentityName `
    --resource-group $resourceGroup `
    --issuer $oidcIssuer `
    --subject "system:serviceaccount:${namespace}:${serviceAccount}" `
    --audiences "api://AzureADTokenExchange" `
    2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Federated credential created for pod identity" -ForegroundColor Green
} else {
    Write-Host "Federated credential may already exist (this is normal)" -ForegroundColor Yellow
}
```

**Why did we do this?**

The infrastructure deployment scripts already configured workload identity for the agent webapp - that's why the app was working before this step. This exercise demonstrates **how** workload identity is configured so you can:

1. **Add New Service Accounts:** Create additional Kubernetes service accounts for different apps or microservices
2. **Multi-Tenant Scenarios:** Grant different pods different Azure permissions by using separate managed identities and federated credentials
3. **Troubleshoot:** Understand the OIDC trust relationship when authentication issues arise
4. **Manual Setup:** Configure workload identity when deploying to existing AKS clusters or when automation isn't available

**Real-world scenarios where you'll configure this manually:**

- **Adding a background job pod** that needs different permissions than your web app (e.g., write access to storage)
- **Deploying third-party applications** that need Azure resource access without sharing your main app's identity
- **Development environments** where you want to quickly test a pod with specific RBAC roles
- **Migration projects** where you're moving containerized apps to AKS and need to replace connection strings with managed identities

The key takeaway: One managed identity can have multiple federated credentials, allowing multiple service accounts (and thus multiple pods/deployments) to use the same Azure identity, or you can create separate identities for tighter security boundaries.

## Step 10: View RBAC Audit Logs

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

## Step 11: Clean Up Test Resources

Remove the test identity created earlier:

```powershell
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
| **Cognitive Services OpenAI User** | Call models deployed on the Foundry account | Inference |

## Next Steps

- **[Lab 3: Networking](03-networking.md)** - Configure virtual networks and private endpoints

## Resources

- [Managed Identities Documentation](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure RBAC Documentation](https://learn.microsoft.com/azure/role-based-access-control/)
- [AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)

## Key Learnings

✅ **AKS Has Two Identities:** Control plane (manages infrastructure) and kubelet (used by pods)  
✅ **Assign Roles to Kubelet Identity:** For pod access to Azure resources  
✅ **No Secrets in Code:** Managed identities eliminate credential management  
✅ **Least Privilege:** Grant minimum permissions needed  
✅ **Auditable:** All access logged via Activity Log  
✅ **Automatic Rotation:** No manual key rotation needed  
✅ **RBAC Scopes:** Use most restrictive scope possible

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
