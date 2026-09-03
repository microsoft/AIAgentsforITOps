# Lab 4: Secrets and Configuration for a Foundry Agent UI

## Overview

Review how the Path 2 chat UI reads configuration from Azure Key Vault through the Secrets Store CSI Driver. The Foundry agent's model, instructions, and knowledge connection remain managed as project assets in Foundry rather than copied into Kubernetes.

**Time:** 25-30 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Distinguish secrets from nonsecret configuration
- Inspect the Key Vault CSI mount used by the UI
- Compare Key Vault configuration with Foundry-managed agent configuration
- Add, mount, rotate, and remove a test secret
- Avoid exposing values in Kubernetes or logs

## Configuration Boundaries

```text
Azure Key Vault                         Microsoft Foundry project
├── Foundry project endpoint            ├── Prompt agent instructions
├── Foundry agent name                  ├── Model deployment selection
├── App Insights connection string      └── Knowledge Base connection
└── Managed identity client ID
          │
          ▼ CSI read-only files
       AKS chat UI
```

Endpoints, names, and client IDs aren't credentials, but Key Vault provides a consistent, auditable configuration channel. Authentication to Foundry uses an Entra token, not an API key.

## Step 1: Load the Deployment Context

```powershell
cd infrastructure/path2

$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$keyVaultName = $config.resources.keyVault
$aksName = $config.resources.aksCluster
```

## Step 2: Inventory Key Vault Without Revealing Values

```powershell
az keyvault secret list `
    --vault-name $keyVaultName `
    --query "[].{Name:name,Enabled:attributes.enabled,Updated:attributes.updated,Expires:attributes.expires}" `
    --output table
```

Expected Path 2 entries:

| Name | Purpose |
| --- | --- |
| `AKS-ManagedIdentity-ClientId` | Selects the managed identity used by the UI and CSI provider |
| `ApplicationInsights-ConnectionString` | Sends UI telemetry to Application Insights |
| `AzureSearch-Endpoint` | Deployment metadata; not mounted into the UI |
| `Foundry-AgentName` | Name of the prompt agent invoked by the UI |
| `Foundry-Endpoint` | Account endpoint; the UI uses the project endpoint instead |
| `Foundry-ProjectEndpoint` | Foundry project data-plane endpoint |

> Never print secret values in shared terminals, screenshots, or workshop recordings.

## Step 3: Inspect the CSI Configuration

```powershell
kubectl get secretproviderclass azure-keyvault-secrets `
    -n agent-demo -o yaml

kubectl get deployment agent-webapp -n agent-demo -o yaml
```

Find these relationships:

- The `SecretProviderClass` uses the Azure provider and managed identity
- Its object list names the four files to mount
- The deployment creates a `secrets-store.csi.k8s.io` volume
- The volume is mounted read-only at `/mnt/secrets-store`
- No `secretObjects` block synchronizes values to a Kubernetes Secret

Confirm there are no application secrets stored as Kubernetes Secrets:

```powershell
kubectl get secrets -n agent-demo
```

The default service-account token objects, if shown, aren't copies of the Key Vault values.

## Step 4: Inspect the Mounted Files Safely

```powershell
$podName = kubectl get pods -n agent-demo -l app=agent-webapp `
    -o jsonpath='{.items[0].metadata.name}'

kubectl exec -n agent-demo $podName -- `
    sh -c 'for f in /mnt/secrets-store/*; do printf "%s (%s bytes)\n" "$(basename "$f")" "$(wc -c < "$f")"; done'
```

This verifies the mount without displaying contents.

The application reads each file at startup. It then uses `DefaultAzureCredential` to acquire an Entra token and invokes:

```text
{projectEndpoint}/agents/{agentName}/endpoint/protocols/openai/responses
```

## Step 5: Inspect Agent Configuration in the Foundry Portal

1. Open `https://ai.azure.com` and select the workshop project.
2. Open **Build** → **Agents** → `conference-expert-agent`.
3. Review the selected model, instructions, and attached knowledge.
4. Open **Build** → **Knowledge** and review the active Search connection.

These settings are project assets, not Key Vault secrets. Changes are governed and versioned in Foundry, while Key Vault contains only what the external UI needs to locate and observe the agent.

## Step 6: Add and Mount a Test Secret

Create a harmless test configuration value:

```powershell
$testValue = "workshop-$([Guid]::NewGuid().ToString('N').Substring(0,8))"

az keyvault secret set `
    --vault-name $keyVaultName `
    --name "Workshop-Configuration" `
    --value $testValue `
    --description "Temporary Path 2 Lab 4 value" `
    --output none

Write-Host "Created Workshop-Configuration" -ForegroundColor Green
```

Back up and edit the `SecretProviderClass`:

```powershell
kubectl get secretproviderclass azure-keyvault-secrets -n agent-demo -o yaml `
    | Set-Content .\secretproviderclass-path2-backup.yaml

kubectl edit secretproviderclass azure-keyvault-secrets -n agent-demo
```

Add this object under the existing `objects` array:

```yaml
        - |
          objectName: Workshop-Configuration
          objectType: secret
          objectVersion: ""
```

Restart the UI so a fresh volume mount is created:

```powershell
kubectl rollout restart deployment agent-webapp -n agent-demo
kubectl rollout status deployment agent-webapp -n agent-demo --timeout=180s

$podName = kubectl get pods -n agent-demo -l app=agent-webapp `
    -o jsonpath='{.items[0].metadata.name}'

kubectl exec -n agent-demo $podName -- `
    test -f /mnt/secrets-store/Workshop-Configuration

if ($LASTEXITCODE -eq 0) {
    $mountedValue = kubectl exec -n agent-demo $podName -- `
        cat /mnt/secrets-store/Workshop-Configuration

    Write-Host "PASS: Test configuration is mounted: $mountedValue" -ForegroundColor Green
}
```

Printing the value here is safe only because it is randomly generated, harmless workshop data. Never use this approach with credentials or production secrets.

## Step 7: Rotate the Test Secret

```powershell
$rotatedValue = "rotated-$([Guid]::NewGuid().ToString('N').Substring(0,8))"

az keyvault secret set `
    --vault-name $keyVaultName `
    --name "Workshop-Configuration" `
    --value $rotatedValue `
    --output none

az keyvault secret list-versions `
    --vault-name $keyVaultName `
    --name "Workshop-Configuration" `
    --query "[].{Version:id,Enabled:attributes.enabled,Updated:attributes.updated}" `
    --output table
```

The CSI provider periodically refreshes mounted content when rotation is enabled. Check the AKS add-on settings:

```powershell
az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query addonProfiles.azureKeyvaultSecretsProvider.config `
    --output json
```

If automatic rotation isn't enabled in this cluster, restart the deployment to consume the new version. Also remember that this UI reads its effective settings at process startup, so restart the application even if the mounted file changes.

## Step 8: Enable Key Vault Audit Logs

```powershell
$keyVaultId = az keyvault show `
    --name $keyVaultName `
    --resource-group $resourceGroup `
    --query id -o tsv

$workspace = az monitor log-analytics workspace list `
    --resource-group $resourceGroup `
    --query "[0].{Id:id,Name:name}" `
    --output json | ConvertFrom-Json

$workspaceId = $workspace.Id
$workspaceName = $workspace.Name

az monitor diagnostic-settings create `
    --name keyvault-audit `
    --resource $keyVaultId `
    --workspace $workspaceId `
    --logs '[{"categoryGroup":"audit","enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none
```

After telemetry arrives, run the query in the Azure portal:

1. Open the [Azure portal](https://portal.azure.com).
2. Search for and select **Log Analytics workspaces**.
3. Open the workspace whose name matches the value in `$workspaceName`.
4. Select **Logs** from the workspace menu.
5. Close the **Queries hub** if it opens, change to KQL mode in the drop-down menu on the right, and paste the query below into the editor.
6. Select **Run**. Audit records can take several minutes to appear after diagnostic settings are enabled.

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| project TimeGenerated, OperationName, ResultType, CallerIPAddress, identity_claim_appid_g
| order by TimeGenerated desc
```

Audit who accessed a secret, but never ingest secret values into logs.

## Step 9: Clean Up

```powershell
kubectl apply -f .\secretproviderclass-path2-backup.yaml
kubectl rollout restart deployment agent-webapp -n agent-demo
kubectl rollout status deployment agent-webapp -n agent-demo --timeout=180s

az keyvault secret delete `
    --vault-name $keyVaultName `
    --name "Workshop-Configuration" `
    --output none

Remove-Item .\secretproviderclass-path2-backup.yaml
```

## Key Learnings

- Path 2 has no Foundry API key in the chat UI
- The CSI volume provides a read-only, auditable configuration channel
- Foundry owns agent configuration; Key Vault owns external app configuration
- Rotation has two layers: refreshing the mounted file and reloading the app
- Key Vault access still depends on managed identity and RBAC

## Next Steps

Continue to **[Lab 5: Monitoring & Observability](05-monitoring.md)**.

## Best Practices

### Do

- Prefer managed identity over service credentials
- Keep Key Vault values out of Kubernetes Secrets when file mounts are sufficient
- Separate external application configuration from Foundry agent assets
- Set expiration and ownership metadata for actual credentials
- Audit reads and review stale secret versions
- Restart applications that cache configuration at startup

### Avoid

- Treating an endpoint or agent name as an authentication secret
- Storing model instructions or knowledge content in Key Vault
- Printing mounted values during diagnostics
- Assuming a changed file is automatically reloaded by application code
- Granting `Key Vault Administrator` to runtime identities

## Resources

- [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/overview)
- [Secrets Store CSI Driver for AKS](https://learn.microsoft.com/azure/aks/csi-secrets-store-driver)
- [Key Vault RBAC](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
