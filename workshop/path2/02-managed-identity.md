# Lab 2: Managed Identity & RBAC for a Foundry Agent

## Overview

Explore how managed identities and Azure RBAC secure every hop in the Path 2 architecture. Unlike Path 1, the agent is hosted by Microsoft Foundry; AKS hosts only the chat UI.

**Time:** 30-35 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Distinguish the AKS, Search, Foundry account, and Foundry project identities
- Map each identity to the operation it performs
- Audit Azure and Foundry role assignments
- Verify the identity used by the chat UI
- Apply least privilege at resource scope

## Identity Flow

```text
AKS chat UI (kubelet identity)
    ├── reads configuration → Key Vault
    └── invokes agent → Foundry project

Foundry prompt agent (project identity)
    └── queries knowledge → Azure AI Search

Azure AI Search (system-assigned identity)
    └── reads source documents → Blob Storage
```

Path 1 gives the AKS workload direct roles on OpenAI and Search. Path 2 does not: the UI invokes Foundry, and Foundry owns the model and knowledge orchestration.

## Step 1: Load the Deployment Context

From the repository root:

```powershell
cd infrastructure/path2

$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$aksName = $config.resources.aksCluster
$foundryName = $config.resources.foundry
$projectName = $config.resources.foundryProject
$searchName = $config.resources.searchService
$storageName = $config.resources.storageAccount
$keyVaultName = $config.resources.keyVault

Write-Host "Resource group: $resourceGroup" -ForegroundColor Cyan
Write-Host "Foundry project: $projectName" -ForegroundColor Cyan
```

## Step 2: Discover the Managed Identities

```powershell
# AKS control-plane and kubelet identities
$aks = az aks show --name $aksName --resource-group $resourceGroup | ConvertFrom-Json
$aksControlPlaneId = $aks.identity.principalId
$kubeletId = $aks.identityProfile.kubeletidentity.objectId
$kubeletClientId = $aks.identityProfile.kubeletidentity.clientId

# Search identity
$searchId = az search service show `
    --name $searchName `
    --resource-group $resourceGroup `
    --query identity.principalId -o tsv

# Foundry account identity
$foundryId = az cognitiveservices account show `
    --name $foundryName `
    --resource-group $resourceGroup `
    --query identity.principalId -o tsv

# Foundry project identity
$projectId = az cognitiveservices account project show `
    --name $foundryName `
    --resource-group $resourceGroup `
    --project-name $projectName `
    --query identity.principalId -o tsv

# Signed-in workshop user
$currentUser = az ad signed-in-user show `
    --query "{ObjectId:id, UserPrincipalName:userPrincipalName}" `
    | ConvertFrom-Json
$currentUserId = $currentUser.ObjectId

[PSCustomObject]@{
    AksControlPlane = $aksControlPlaneId
    AksKubelet      = $kubeletId
    Search          = $searchId
    FoundryAccount  = $foundryId
    FoundryProject  = $projectId
    WorkshopUser    = "$($currentUser.UserPrincipalName) ($currentUserId)"
} | Format-List
```

> **Key distinction:** The Foundry account and project identities are separate principals. The Knowledge Base connection created in exercise 01 uses **Project Managed Identity**, so the project identity is the important data-plane identity for retrieval.

## Step 3: Audit the Expected Role Assignments

```powershell
function Show-Roles([string]$Name, [string]$PrincipalId) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    az role assignment list `
        --assignee $PrincipalId `
        --all `
        --query "[].{Role:roleDefinitionName, Scope:scope}" `
        --output table
}

Show-Roles "AKS control plane" $aksControlPlaneId
Show-Roles "AKS kubelet / chat UI" $kubeletId
Show-Roles "Azure AI Search" $searchId
Show-Roles "Foundry account" $foundryId
Show-Roles "Foundry project" $projectId
Show-Roles "Workshop user" $currentUserId
```

Compare the results with the intended access graph:

| Principal | Role | Scope | Why |
| --- | --- | --- | --- |
| AKS control plane | `AcrPull` | Container Registry | Pull the UI image |
| AKS control plane | `Contributor` | MC_* (managed cluster) | Access to managed cluster resource group |
| AKS kubelet | `Key Vault Secrets User` | Key Vault | Let the CSI provider mount UI configuration |
| AKS kubelet | `Cognitive Services User` | Foundry account | Acquire a token and invoke the prompt agent |
| Azure AI Search | `Storage Blob Data Reader` | Storage account | Ingest conference documents |
| Foundry account | `Search Index Data Reader` | Search service | Account-level fallback used by some Foundry operations |
| Foundry project | `Search Index Data Reader` | Search service | Query the Knowledge Base index |
| Workshop user | `Azure AI Project Manager` | Foundry account | Build and manage agents in the portal |

> **Note:** The workshop user might have additional roles in the output. Role assignments depend on the subscription's existing configuration, and the subscription, resource group, or resources might also be used for other purposes. Roles assigned at a parent scope, such as the subscription or resource group, are inherited by resources beneath that scope. For this workshop, verify that the required `Azure AI Project Manager` assignment is present; don't treat unrelated pre-existing or inherited roles as workshop requirements.

All data roles should be scoped to the individual resource, not the subscription.

## Step 4: Inspect Access in the Foundry Portal

1. Open the Foundry portal at `https://ai.azure.com` and select your project.
2. Make sure the **New Foundry** toggle is on.
3. Click **Build** → **Knowledge** and click the Manage link next to the active Search connection.
4. Confirm the Auth method is **Project Managed Identity** for both the CognitiveSearch and RemoteTool connections.

This portal view adds the Foundry data-plane perspective that is absent from Path 1. Azure portal RBAC controls who may access the resource; the Foundry project view shows how that access is used by project assets and connections.

## Step 5: Verify the UI Uses Entra ID, Not an API Key

Inspect the mounted files without printing their values:

```powershell
$podName = kubectl get pods -n agent-demo -l app=agent-webapp `
    -o jsonpath='{.items[0].metadata.name}'

kubectl exec -n agent-demo $podName -- ls -l /mnt/secrets-store
```

Expected files include:

- `AKS-ManagedIdentity-ClientId`
- `Foundry-ProjectEndpoint`
- `Foundry-AgentName`
- `ApplicationInsights-ConnectionString`

There is no Foundry API key. The .NET UI uses `DefaultAzureCredential`, requests an Entra token for `https://ai.azure.com/.default`, and calls the Foundry Responses endpoint.

Confirm the client ID matches the deployed kubelet identity:

```powershell
$mountedClientId = kubectl exec -n agent-demo $podName -- `
    cat /mnt/secrets-store/AKS-ManagedIdentity-ClientId

[PSCustomObject]@{
    MountedClientId = $mountedClientId.Trim()
    AksClientId     = $kubeletClientId
    Match           = ($mountedClientId.Trim() -eq $kubeletClientId)
} | Format-List
```

## Step 6: Test Least Privilege

The AKS identity should invoke the agent but should not manage Foundry resources or read source blobs directly.

```powershell
$storageResourceId = az storage account show `
    --name $storageName `
    --resource-group $resourceGroup `
    --query id -o tsv

$directStorageRoles = az role assignment list `
    --assignee $kubeletId `
    --scope $storageResourceId `
    --query "[].roleDefinitionName" -o tsv

if ([string]::IsNullOrWhiteSpace($directStorageRoles)) {
    Write-Host "PASS: The UI identity has no direct Storage role." -ForegroundColor Green
} else {
    Write-Host "Review unexpected Storage roles: $directStorageRoles" -ForegroundColor Yellow
}
```

Now send a question through the UI. A successful answer proves that the UI can invoke Foundry and that Foundry can retrieve knowledge, without granting the UI direct access to Search or Storage.

## Step 7: Review RBAC Activity

```powershell
$startTime = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")

az monitor activity-log list `
    --resource-group $resourceGroup `
    --start-time $startTime `
    --query "[?contains(operationName.localizedValue, 'role assignment')].{Time:eventTimestamp,Operation:operationName.localizedValue,Status:status.localizedValue,Caller:caller}" `
    --output table
```

Activity Log records control-plane changes such as role assignments. Agent invocations and knowledge queries are data-plane operations and are explored in Lab 5.

## Key Learnings

- Path 2 separates UI identity, agent identity, and data-source identity
- The AKS UI invokes Foundry but does not implement retrieval itself
- The Foundry project identity queries Search
- Search reads Blob Storage with its own identity
- RBAC and network controls are complementary and are both required

## Next Steps

Continue to **[Lab 3: Networking](03-networking.md)**.

## Best Practices

### Do

- Use project managed identity for Foundry connections
- Grant data roles at the individual resource scope
- Give the UI only agent invocation and configuration-read permissions
- Audit both the Foundry account and project identities
- Use groups for human access to Foundry projects

### Avoid

- Giving the AKS UI direct Search or Storage access when Foundry performs retrieval
- Assigning `Owner` or `Contributor` merely to invoke an agent
- Using API keys when Entra authentication is supported
- Assuming the Foundry account and project identities are interchangeable

## Troubleshooting

### UI receives 401 or 403 from Foundry

```powershell
az role assignment list --assignee $kubeletId --scope `
    (az cognitiveservices account show --name $foundryName --resource-group $resourceGroup --query id -o tsv) `
    --output table
```

Confirm `Cognitive Services User` exists, then allow several minutes for RBAC propagation.

### Knowledge connection is inactive or retrieval fails

Verify `Search Index Data Reader` on the project identity and confirm **Project Managed Identity** is selected on the Foundry knowledge connection.

### Principal ID is empty

Re-open the resource in Azure portal and confirm its system-assigned identity is enabled. Project identity is queried separately from the parent Foundry resource.

## Resources

- [Microsoft Foundry RBAC](https://learn.microsoft.com/azure/ai-foundry/concepts/rbac-ai-foundry)
- [Managed identities for Azure resources](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview)
- [Azure RBAC best practices](https://learn.microsoft.com/azure/role-based-access-control/best-practices)
