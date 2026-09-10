# Lab 4: Secrets Management with Azure Key Vault

## Overview

Understand how your deployed AI agent securely accesses secrets using Azure Key Vault, managed identities, and the Secrets Store CSI Driver. Then practice adding and mounting a new secret.

**Time:** 25-30 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Review existing Key Vault secrets for AI services
- Understand how secrets are mounted into AKS pods for your AI agent
- Learn about workload identity and the CSI Secrets Store Driver (AKS specific)
- Practice adding and mounting a new secret
- Understand secret rotation and monitoring

## Architecture: How Secrets Flow to Pods

```
Azure Key Vault
  └─ Configuration secrets (Foundry model endpoint, Search endpoint, etc.)
         ↓ (accessed via Managed Identity)
    SecretProviderClass (Kubernetes resource)
         ↓ (CSI Driver mounts as volume)
    Pod Volume (read-only file system)
         ↓ (app reads from files)
    Application Code
```

**Key Components:**

1. **Azure Key Vault**: Centralized secret storage
2. **Workload Identity**: Pod authenticates to Azure using managed identity
3. **Secrets Store CSI Driver**: Kubernetes driver that mounts Key Vault secrets as volumes
4. **SecretProviderClass**: Defines which secrets to mount from which vault

> **💡 Cross-Platform Note:** This pattern works similarly across Azure compute platforms:
> 
> - **AKS**: Secrets Store CSI Driver + workload identity (what we use)
> - **App Service**: Key Vault references in app settings (`@Microsoft.KeyVault(...)`)
> - **Container Apps**: Secret references with managed identity
> - **Azure Functions**: Same as App Service

## Step 1: Review Existing Key Vault Secrets

If not already there, navigate to the /infrastructure/path1/ directory:

```powershell
cd infrastructure/path1/
```

Let's examine what secrets are already stored for your AI agent:

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$keyVault = $config.resources.keyVault
$resourceGroup = $config.resourceGroupName

Write-Host "`nKey Vault: $keyVault" -ForegroundColor Cyan
Write-Host "Listing AI service secrets..." -ForegroundColor Yellow

# List all secrets
az keyvault secret list `
    --vault-name $keyVault `
    --query '[].{Name:name, Enabled:attributes.enabled, Created:attributes.created}' `
    --output table
```

**What each secret contains:**

| Secret Name | Purpose | Used By |
|------------|---------|---------|
| `Foundry-ModelEndpoint` | Foundry OpenAI-compatible Responses API base URL | Agent app (for direct `gpt-5.4-mini` inference) |
| `AzureSearch-Endpoint` | Azure AI Search service endpoint URL | Agent app (for RAG document retrieval) |
| `ApplicationInsights-ConnectionString` | Application Insights connection string | Agent app (for logging/monitoring) |
| `AKS-ManagedIdentity-ClientId` | Kubelet managed identity client ID | Agent app (for Azure authentication) |

> **💡 Note:** This deployment uses **managed identity** for authentication, so endpoints are stored instead of API keys. The app authenticates using the AKS kubelet identity with appropriate RBAC roles (configured in Lab 2).

Let's view one secret to see its details:

```powershell
# Show Foundry model endpoint metadata
az keyvault secret show `
    --vault-name $keyVault `
  --name "Foundry-ModelEndpoint" `
    --query '{Name:name, Enabled:attributes.enabled, Created:attributes.created, Updated:attributes.updated}' `
    --output table

# Retrieve the endpoint value
$foundryModelEndpoint = az keyvault secret show `
    --vault-name $keyVault `
  --name "Foundry-ModelEndpoint" `
    --query value `
    -o tsv

Write-Host "`nFoundry Responses Endpoint: $foundryModelEndpoint" -ForegroundColor Cyan
```

## Step 2: Understand How Secrets Are Mounted in AKS

The agent application running in AKS doesn't access Key Vault directly. Instead, secrets are mounted as **files** in the pod's file system using the **Secrets Store CSI Driver**.

### View the SecretProviderClass

This Kubernetes resource defines which secrets to mount:

```powershell
kubectl get secretproviderclass -n agent-demo

# View the full configuration
kubectl get secretproviderclass -n agent-demo -o yaml
```

**Key parts explained:**

```yaml
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"           # Not using legacy pod identity
    useVMManagedIdentity: "true"      # Using AKS kubelet identity
    keyvaultName: "<your-kv-name>"    # Your Key Vault name
    objects: |                         # Which secrets to mount
      array:
        - objectName: Foundry-ModelEndpoint
          objectType: secret
        - objectName: AzureSearch-Endpoint
          objectType: secret
        - objectName: ApplicationInsights-ConnectionString
          objectType: secret
        - objectName: AKS-ManagedIdentity-ClientId
          objectType: secret
```

### View the Pod Deployment

Check how the deployment references the SecretProviderClass:

```powershell
kubectl get deployment agent-webapp -n agent-demo -o yaml
```

Look for the **volume** and **volumeMount** sections:

```yaml
spec:
  template:
    spec:
      volumes:
      - name: keyvault-secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "azure-keyvault-secrets"  # References our SecretProviderClass
      
      containers:
      - name: agent-webapp
        volumeMounts:
        - name: keyvault-secrets
          mountPath: "/mnt/secrets-store"   # Secrets appear as files here
          readOnly: true
```

### Verify Secrets in a Running Pod

Let's connect to a running pod and see the mounted secrets:

```powershell
# Get pod name
$podName = kubectl get pods -n agent-demo -l app=agent-webapp -o jsonpath='{.items[0].metadata.name}'

Write-Host "`nVerifying secrets are mounted in pod: $podName" -ForegroundColor Cyan

# Show the Foundry Responses endpoint (to verify it's mounted)
kubectl exec -n agent-demo $podName -- cat /mnt/secrets-store/Foundry-ModelEndpoint
```

**What you'll see:**

- Each secret is a separate file (for example, `Foundry-ModelEndpoint` and `AzureSearch-Endpoint`)
- Files are read-only
- Content matches what's in Key Vault (endpoints use `https://` URLs)
- CSI driver keeps them synced (by default every 2 minutes)

## Step 3: Review Workload Identity Configuration

The pod authenticates to Key Vault using the **AKS kubelet managed identity** (configured during deployment).

Check the identity and its Key Vault permissions:

```powershell
# Get the AKS kubelet identity
$aksName = $config.resources.aksCluster
$kubeletIdentity = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query identityProfile.kubeletidentity.clientId `
    -o tsv

Write-Host "`nKubelet Managed Identity Client ID: $kubeletIdentity" -ForegroundColor Cyan

# Check Key Vault access policy for this identity
$kvId = az keyvault show `
    --name $keyVault `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

Write-Host "`nKey Vault RBAC role assignments for kubelet identity:" -ForegroundColor Yellow
az role assignment list `
    --assignee $kubeletIdentity `
    --scope $kvId `
    --query '[].{Role:roleDefinitionName, Scope:scope}' `
    --output table
```

You should see: **Key Vault Secrets User** role (allows reading secrets, not managing them).

## Step 4: Add a New Secret (Hands-On Exercise)

Now let's practice by adding a new secret and mounting it into the pod.

### 4.1 Create a New Secret in Key Vault

```powershell
# Add a sample external API endpoint (this won't be used by the app, just for practice)
$newSecretValue = "https://api.example.com/v1/endpoint-$(Get-Random -Minimum 1000 -Maximum 9999)"

az keyvault secret set `
    --vault-name $keyVault `
    --name "ExternalAPI-Endpoint" `
    --value $newSecretValue `
    --description "Demo secret for Lab 4 hands-on exercise"

Write-Host "`n✓ Created secret 'ExternalAPI-Endpoint' in Key Vault" -ForegroundColor Green
Write-Host "Secret value: $newSecretValue" -ForegroundColor Gray
```

### 4.2 Update SecretProviderClass to Include New Secret

We need to edit the SecretProviderClass to mount this new secret. The easiest way is to use `kubectl edit`:

```powershell
# First, save a backup
kubectl get secretproviderclass azure-keyvault-secrets -n agent-demo -o yaml > secretproviderclass-backup.yaml

Write-Host "`nBackup saved. Now opening editor to add the new secret..." -ForegroundColor Yellow

# Edit the SecretProviderClass
kubectl edit secretproviderclass azure-keyvault-secrets -n agent-demo
```

**In the editor that opens**, find the `objects:` section and add the new secret to the array:

```yaml
objects: |
  array:
    - |
      objectName: AKS-ManagedIdentity-ClientId
      objectType: secret
      objectVersion: ""
    - |
      objectName: Foundry-ModelEndpoint
      objectType: secret
      objectVersion: ""
    - |
      objectName: ApplicationInsights-ConnectionString
      objectType: secret
      objectVersion: ""
    - |
      objectName: AzureSearch-Endpoint
      objectType: secret
      objectVersion: ""
    - |                                        # <-- ADD THESE
      objectName: ExternalAPI-Endpoint         # <-- 4 LINES
      objectType: secret                       # <-- TO ADD
      objectVersion: ""                        # <-- THE NEW SECRET
```

Save and exit the editor.

You should see:
```
secretproviderclass.secrets-store.csi.x-k8s.io/azure-keyvault-secrets edited
```

### 4.3 Restart Pods to Mount the New Secret

The CSI driver only mounts secrets when pods start, so we need to restart:

```powershell
kubectl rollout restart deployment agent-webapp -n agent-demo

Write-Host "`nWaiting for pods to restart..." -ForegroundColor Yellow
kubectl rollout status deployment agent-webapp -n agent-demo

Write-Host "✓ Pods restarted" -ForegroundColor Green
```

### 4.4 Verify the New Secret is Mounted

```powershell
# Get the new pod name (after restart)
$podName = kubectl get pods -n agent-demo -l app=agent-webapp -o jsonpath='{.items[0].metadata.name}'

Write-Host "`nVerifying new secret in pod: $podName" -ForegroundColor Cyan

# Read the new secret file
Write-Host "`nContent of ExternalAPI-Endpoint:" -ForegroundColor Yellow
kubectl exec -n agent-demo $podName -- cat /mnt/secrets-store/ExternalAPI-Endpoint
```

**Success!** You've added a new secret to Key Vault and mounted it into the pod. 🎉

## Step 5: Secret Rotation and Monitoring

### Enable Secret Rotation

The CSI driver automatically syncs secrets every 2 minutes. Let's test it:

```powershell
# Update the secret value in Key Vault
$rotatedValue = "https://api.example.com/v2/endpoint-$(Get-Random -Minimum 1000 -Maximum 9999)"

az keyvault secret set `
    --vault-name $keyVault `
    --name "ExternalAPI-Endpoint" `
    --value $rotatedValue

Write-Host "`n✓ Secret rotated in Key Vault to: $rotatedValue" -ForegroundColor Green
Write-Host "Wait 2-3 minutes, then check the pod again..." -ForegroundColor Yellow

# After waiting 2-3 minutes:
Write-Host "`nVerifying secret rotation in pod:" -ForegroundColor Cyan
kubectl exec -n agent-demo $podName -- cat /mnt/secrets-store/ExternalAPI-Endpoint
```

The value should automatically update without restarting the pod!

### Monitor Secret Access

Enable Key Vault diagnostics to track who accessed what:

```powershell
# Get Key Vault resource ID
$kvResourceId = az keyvault show `
    --name $keyVault `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Find the Log Analytics workspace (created during infrastructure deployment)
$logWorkspaceId = az monitor log-analytics workspace list `
    --resource-group $resourceGroup `
    --query '[0].id' `
    -o tsv

Write-Host "`nLog Analytics Workspace: $logWorkspaceId" -ForegroundColor Cyan

# Enable audit logging (if not already enabled)
az monitor diagnostic-settings create `
    --name "keyvault-audit-logs" `
    --resource $kvResourceId `
    --workspace $logWorkspaceId `
    --logs '[{"category": "AuditEvent", "enabled": true}]' `
    --metrics '[{"category": "AllMetrics", "enabled": true}]' `
    2>$null

Write-Host "✓ Key Vault diagnostics enabled (logs sent to Log Analytics)" -ForegroundColor Green

# Query recent secret access (after a few minutes, logs appear in Log Analytics)
Write-Host "`nTo view Key Vault audit logs:" -ForegroundColor Yellow
Write-Host "1. Open Azure Portal and navigate to your Resource Group" -ForegroundColor White
Write-Host "2. Find the Log Analytics workspace resource" -ForegroundColor White
Write-Host "3. Click 'Logs' in the left menu" -ForegroundColor White
Write-Host "4. Switch to KQL mode (if needed)" -ForegroundColor White
Write-Host "5. Paste this query and click 'Run':" -ForegroundColor White
Write-Host @"

AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_appid_g, requestUri_s
| order by TimeGenerated desc
| take 20
"@ -ForegroundColor Cyan

Write-Host "`n⚠️  Note: Logs may take 5-10 minutes to appear after pods access secrets" -ForegroundColor Yellow
```

> **💡 Tip:** If you don't see results immediately, wait a few minutes. Logs only appear after:

> 1. A pod accesses Key Vault secrets (happens when pods start)
> 2. Key Vault sends audit logs to Log Analytics (typically 5-10 minutes)

## Step 6: Clean Up (Optional)

Remove the demo secret we created:

```powershell
# Remove from Key Vault
az keyvault secret delete `
    --vault-name $keyVault `
    --name "ExternalAPI-Endpoint"

Write-Host "✓ Demo secret deleted from Key Vault" -ForegroundColor Yellow

# Revert SecretProviderClass to original
kubectl apply -f secretproviderclass-backup.yaml

# Restart pods
kubectl rollout restart deployment agent-webapp -n agent-demo

Write-Host "✓ Configuration restored" -ForegroundColor Green
```

## Best Practices

### ✅ DO

- Use managed identities for Key Vault access (never store credentials)
- Enable soft-delete and purge protection on Key Vault
- Use separate Key Vaults for dev/test/prod
- Set secret expiration dates
- Monitor all secret access via diagnostic logs
- Rotate secrets regularly (especially API keys)
- Use RBAC roles (Key Vault Secrets User, not access policies)
- Mount secrets as volumes (not environment variables when possible)

### ❌ DON'T

- Hardcode secrets in application code
- Store secrets in container images
- Log secret values
- Share secrets across environments
- Use the same secret for multiple purposes
- Grant overly broad Key Vault permissions
- Disable soft-delete or purge protection

## Real-World Scenarios

### 1. Multi-Environment Setup

```
Key Vault (dev)    → Dev AKS Cluster
Key Vault (test)   → Test AKS Cluster  
Key Vault (prod)   → Prod AKS Cluster
```

Each environment has its own Key Vault with environment-specific secrets.

### 2. Secret Rotation Strategy

```
1. Generate new secret value
2. Add as new version in Key Vault (CSI driver auto-syncs)
3. App reads new value (restart if needed)
4. Verify app works with new secret
5. Deactivate old secret version
6. After grace period, delete old version
```

### 3. Cross-Service Secret Sharing

```
Azure Key Vault
    ├─ App Service (via @Microsoft.KeyVault reference)
    ├─ Azure Functions (via @Microsoft.KeyVault reference)
    ├─ AKS (via CSI Secrets Store Driver)
    └─ Container Apps (via secret reference)
```

All share the same Key Vault, each using different authentication methods but the same underlying secrets.

## Key Learnings

✅ **Secrets are files, not environment variables** - CSI driver mounts them as read-only files  
✅ **Managed identities eliminate credentials** - No passwords or keys to manage for Key Vault access  
✅ **Auto-rotation works** - Secrets update in pods without restart (every 2 minutes)  
✅ **Cross-platform pattern** - Same concepts work in App Service, Functions, Container Apps  
✅ **RBAC over access policies** - Use Azure RBAC (Key Vault Secrets User) for modern access control  
✅ **SecretProviderClass is the bridge** - Connects Kubernetes to Azure Key Vault  
✅ **Monitoring is essential** - Track all secret access via diagnostic logs  

## Next Steps

- **[Lab 5: Monitoring & Observability](05-monitoring.md)** - Track your agent's performance

## Resources

- [Azure Key Vault Documentation](https://learn.microsoft.com/azure/key-vault/)
- [AKS Secrets Store CSI Driver](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver)
- [Azure Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)
- [Key Vault RBAC Roles](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [App Service Key Vault References](https://learn.microsoft.com/azure/app-service/app-service-key-vault-references)

## Troubleshooting

### Secret Not Appearing in Pod

```powershell
# Check SecretProviderClass status
kubectl describe secretproviderclass azure-keyvault-secrets -n agent-demo

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=50

# Verify managed identity has Key Vault access
az role assignment list --assignee $kubeletIdentity --scope $kvId --output table

# Restart pod to force remount
kubectl rollout restart deployment agent-webapp -n agent-demo
```

### "Permission Denied" Errors

The kubelet identity needs the **Key Vault Secrets User** role:

```powershell
$kvId = az keyvault show --name $keyVault --resource-group $resourceGroup --query id -o tsv

az role assignment create `
    --assignee $kubeletIdentity `
    --role "Key Vault Secrets User" `
    --scope $kvId
```

### Secrets Not Rotating

Check the CSI driver rotation interval:

```powershell
# CSI driver syncs every 2 minutes by default
# Verify rotation is enabled
kubectl get secretproviderclass azure-keyvault-secrets -n agent-demo -o yaml | grep -i rotation

# Force immediate rotation by restarting the pod
kubectl rollout restart deployment agent-webapp -n agent-demo
```
