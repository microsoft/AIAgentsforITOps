# Lab 3: Private Networking for AI Services

## Overview

Secure Azure OpenAI and other AI services using private endpoints, eliminating public internet access while maintaining connectivity from your AKS-hosted agent.

**Time:** 20-25 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Understand private endpoints for Azure AI services
- Configure network access restrictions for Azure OpenAI
- Test network isolation impact on applications
- Configure private DNS for service discovery
- Implement Zero Trust networking for AI workloads

## Architecture: Before and After

**Before (Public Endpoints):**

```
Internet → Azure OpenAI (public endpoint)
         ↑
    AKS Agent Pod
```

**After (Private Endpoints):**

```
Internet ✗ Blocked
         
AKS VNet → Private Endpoint → Azure OpenAI (private IP)
    ↑
Agent Pod
```

## Why This Matters for AI Services

Azure OpenAI endpoints are **public by default**, meaning:

- ❌ Accessible from anywhere on the internet (with valid credentials)
- ❌ Susceptible to network-based attacks
- ❌ No network-layer access control

With private endpoints:

- ✅ Only accessible from your VNet
- ✅ Network-layer isolation (Zero Trust)
- ✅ Compliance with data residency requirements
- ✅ Reduced attack surface

## Step 1: Review Current Network Configuration

If not already there, navigate to the /infrastructure/path1/ directory.

```powershell
cd infrastructure/path1/
```

Load the information from your deployment into your environment:

```powershell
$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$location = $config.location
$aksName = $config.resources.aksCluster

# Verify variables are loaded
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Cyan
Write-Host "AKS Cluster: $aksName" -ForegroundColor Cyan
Write-Host "Subscription: $($config.subscriptionId)" -ForegroundColor Cyan
```

Find the AKS-managed VNet:

```powershell
# Get AKS node resource group (where VNet lives)
$aksNodeRG = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query nodeResourceGroup `
    -o tsv

Write-Host "`nAKS Node Resource Group: $aksNodeRG" -ForegroundColor Cyan

# Find the VNet
$aksVNet = az network vnet list `
    --resource-group $aksNodeRG `
    --query '[0]' `
    | ConvertFrom-Json

Write-Host "AKS VNet Name: $($aksVNet.name)" -ForegroundColor Cyan
Write-Host "AKS VNet ID: $($aksVNet.id)" -ForegroundColor Yellow
Write-Host "Address Space: $($aksVNet.addressSpace.addressPrefixes -join ', ')" -ForegroundColor Yellow

# List subnets
Write-Host "`nSubnets:" -ForegroundColor Cyan
$aksVNet.subnets | ForEach-Object {
    Write-Host "  - $($_.name): $($_.addressPrefix)" -ForegroundColor White
}
```

## Step 2: Test the Agent Application (Before Lockdown)

Open the agent web application to verify it's currently working:

```powershell
# Get the agent web app URL (LoadBalancer external IP)
$agentUrl = kubectl get service agent-webapp-service -n agent-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

if ($agentUrl) {
    Write-Host "`nAgent Web App URL: http://$agentUrl" -ForegroundColor Green
    Write-Host "Open this URL in your browser and test the agent (ask: 'How many Expert Meet-up stations were there at Ignite 2025?')" -ForegroundColor Yellow
    Write-Host "`n✓ Agent should respond successfully using Azure OpenAI" -ForegroundColor Green
} else {
    Write-Host "`nWaiting for LoadBalancer IP to be assigned..." -ForegroundColor Yellow
    Write-Host "Run: kubectl get services -n agent-demo" -ForegroundColor Cyan
    Write-Host "Wait until agent-webapp-service shows an EXTERNAL-IP (not <pending>)" -ForegroundColor Cyan
}
```

**Action:** Open the URL in your browser and verify the agent works.

## Step 3: Disable Public Access to Azure OpenAI and Search

Now let's lock down both AI services - **this will break the agent**:

```powershell
# Load service names from config
$openAiAccount = $config.resources.azureOpenAI
$searchService = $config.resources.searchService

Write-Host "Disabling public network access to Azure OpenAI and Search..." -ForegroundColor Cyan

# Disable Azure OpenAI
$subscriptionId = $config.subscriptionId
$openAiApiUri = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAiAccount`?api-version=2024-10-01"
$openAiJsonBody = '{\"properties\": {\"publicNetworkAccess\": \"Disabled\", \"networkAcls\": {\"bypass\": \"None\"}}}'  

az rest --method patch --uri $openAiApiUri --headers "Content-Type=application/json" --body $openAiJsonBody | Out-Null
Write-Host "✓ OpenAI public access disabled" -ForegroundColor Green

# Disable Azure Search (this can take several minutes)
Write-Host "Disabling Azure Search public access (this may take several minutes)..." -ForegroundColor Yellow
az search service update `
    --name $searchService `
    --resource-group $resourceGroup `
    --public-network-access disabled `
    | Out-Null

Write-Host "✓ Search public access disabled" -ForegroundColor Green
Write-Host "`n⚠️  The agent application will now FAIL completely" -ForegroundColor Red
```

## Step 4: Verify the Agent is Broken

Refresh the agent web app and try asking a question again:

```powershell
Write-Host "`n=== Testing Impact ===" -ForegroundColor Cyan
Write-Host "1. Refresh the agent web app in your browser" -ForegroundColor Yellow
Write-Host "2. Try asking: 'How many Expert Meet-up stations were there at Ignite 2025?'" -ForegroundColor Yellow
Write-Host "3. Expected result: 'Sorry, something went wrong. Please try again.'" -ForegroundColor Red
Write-Host "Press Enter after you've confirmed the agent is broken..." -ForegroundColor Yellow
Read-Host
```

**What's happening?**

Your agent uses a multi-service architecture:

1. **Azure AI Search**: Retrieves relevant documents from the index
2. **Azure OpenAI**: Reasons over the documents to generate intelligent responses

With both services blocked:

- ❌ Cannot retrieve documents from Search
- ❌ Cannot generate responses from OpenAI  
- ❌ Agent completely broken

> **🔍 Debugging Tip:** If you only block OpenAI but leave Search accessible, the agent might show degraded behavior (e.g., returning the same generic answer to every question). This indicates retrieval works but reasoning fails. For a clean break/fix demo, we block both services.

## Step 5: Create Private Endpoints in AKS VNet

Now let's fix it by adding private endpoints for **both services** directly in the AKS VNet:

```powershell
Write-Host "Creating private endpoints in AKS VNet..." -ForegroundColor Cyan

# Get the first available subnet in AKS VNet
$subnetName = $aksVNet.subnets[0].name
$subnetId = $aksVNet.subnets[0].id

Write-Host "Using subnet: $subnetName" -ForegroundColor Yellow

# Enable private endpoint support on the subnet if needed
az network vnet subnet update `
    --ids $subnetId `
    --disable-private-endpoint-network-policies true `
    2>&1 | Out-Null

# === Azure OpenAI Private Endpoint ===
Write-Host "Creating Azure OpenAI private endpoint..." -ForegroundColor Cyan

$openAiId = az cognitiveservices account show `
    --name $openAiAccount `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

$openAiPE = az network private-endpoint create `
    --name "$openAiAccount-pe" `
    --resource-group $aksNodeRG `
    --location $location `
    --subnet $subnetId `
    --private-connection-resource-id $openAiId `
    --group-id account `
    --connection-name "$openAiAccount-connection" `
    | ConvertFrom-Json

Write-Host "✓ OpenAI private endpoint created" -ForegroundColor Green
$openAiPrivateIP = $openAiPE.customDnsConfigs[0].ipAddresses[0]
Write-Host "  Private IP: $openAiPrivateIP" -ForegroundColor Cyan

# === Azure Search Private Endpoint ===
Write-Host "`nCreating Azure Search private endpoint..." -ForegroundColor Cyan

# Wait for Search service to finish provisioning after network change
Write-Host "Waiting for Search service to finish provisioning..." -ForegroundColor Yellow
$maxWaitSeconds = 300  # 5 minutes max
$elapsedSeconds = 0
$provisioningState = ""

do {
    Start-Sleep -Seconds 10
    $elapsedSeconds += 10
    
    $searchStatus = az search service show `
        --name $searchService `
        --resource-group $resourceGroup `
        | ConvertFrom-Json
    
    $provisioningState = $searchStatus.provisioningState
    
    if ($provisioningState -eq "Succeeded") {
        Write-Host "✓ Search service ready" -ForegroundColor Green
        break
    } elseif ($elapsedSeconds -ge $maxWaitSeconds) {
        Write-Host "⚠️  Timeout waiting for Search service. Continuing anyway..." -ForegroundColor Yellow
        break
    } else {
        Write-Host "  Still provisioning... ($elapsedSeconds seconds elapsed)" -ForegroundColor Gray
    }
} while ($provisioningState -ne "Succeeded")

$searchId = az search service show `
    --name $searchService `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

$searchPE = az network private-endpoint create `
    --name "$searchService-pe" `
    --resource-group $aksNodeRG `
    --location $location `
    --subnet $subnetId `
    --private-connection-resource-id $searchId `
    --group-id searchService `
    --connection-name "$searchService-connection" `
    2>&1 | ConvertFrom-Json

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Search private endpoint created" -ForegroundColor Green
    $searchPrivateIP = $searchPE.customDnsConfigs[0].ipAddresses[0]
    Write-Host "  Private IP: $searchPrivateIP" -ForegroundColor Cyan
} else {
    Write-Host "❌ Failed to create Search private endpoint. Service may still be provisioning." -ForegroundColor Red
    Write-Host "   Wait a few minutes and retry this step manually, or check the Azure Portal." -ForegroundColor Yellow
    return
}
```

## Step 6: Configure Private DNS Zones

```powershell
Write-Host "`nConfiguring Private DNS zones..." -ForegroundColor Cyan

# === Azure OpenAI DNS ===
$openAiDnsZone = "privatelink.openai.azure.com"

az network private-dns zone create `
    --name $openAiDnsZone `
    --resource-group $resourceGroup `
    2>$null | Out-Null

az network private-dns link vnet create `
    --name "aks-openai-link" `
    --resource-group $resourceGroup `
    --zone-name $openAiDnsZone `
    --virtual-network $aksVNet.id `
    --registration-enabled false `
    2>$null | Out-Null

az network private-dns record-set a add-record `
    --resource-group $resourceGroup `
    --zone-name $openAiDnsZone `
    --record-set-name $openAiAccount `
    --ipv4-address $openAiPrivateIP `
    2>$null | Out-Null

Write-Host "✓ OpenAI DNS configured: $openAiAccount.openai.azure.com → $openAiPrivateIP" -ForegroundColor Green

# === Azure Search DNS ===
$searchDnsZone = "privatelink.search.windows.net"

az network private-dns zone create `
    --name $searchDnsZone `
    --resource-group $resourceGroup `
    2>$null | Out-Null

az network private-dns link vnet create `
    --name "aks-search-link" `
    --resource-group $resourceGroup `
    --zone-name $searchDnsZone `
    --virtual-network $aksVNet.id `
    --registration-enabled false `
    2>$null | Out-Null

az network private-dns record-set a add-record `
    --resource-group $resourceGroup `
    --zone-name $searchDnsZone `
    --record-set-name $searchService `
    --ipv4-address $searchPrivateIP `
    2>$null | Out-Null

Write-Host "✓ Search DNS configured: $searchService.search.windows.net → $searchPrivateIP" -ForegroundColor Green
```

## Step 7: Verify the Agent is Fixed

```powershell
Write-Host "`n=== Testing Fix ===" -ForegroundColor Cyan
Write-Host "1. Wait ~30-60 seconds for DNS to propagate" -ForegroundColor Yellow
Write-Host "2. Refresh the agent web app in your browser" -ForegroundColor Yellow
Write-Host "3. Ask: 'How many Expert Meet-up stations were there at Ignite 2025?'" -ForegroundColor Yellow
Write-Host "4. Expected result: Agent works again! ✓" -ForegroundColor Green
Write-Host "`nPress Enter after you've confirmed the agent is working..." -ForegroundColor Yellow
Read-Host
```

**What changed?**

- ✅ AKS pods resolve `<openai>.openai.azure.com` to the private IP
- ✅ AKS pods resolve `<search>.search.windows.net` to the private IP
- ✅ Traffic stays within the VNet (no internet roundtrip)
- ✅ Both services accept connections from their private endpoints
- ✅ Agent retrieves documents (Search) and generates responses (OpenAI) successfully

## Step 8: View Network Configuration

```powershell
Write-Host "`n=== Network Topology Summary ===" -ForegroundColor Cyan

# List all private endpoints in AKS node resource group
az network private-endpoint list `
    --resource-group $aksNodeRG `
    --query '[].{Name:name, Service:privateLinkServiceConnections[0].privateLinkServiceId, State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, IP:customDnsConfigs[0].ipAddresses[0]}' `
    --output table

# Show DNS configuration
Write-Host "`n=== DNS Configuration ===" -ForegroundColor Cyan
Write-Host "`nOpenAI DNS Records:" -ForegroundColor Yellow
az network private-dns record-set a list `
    --zone-name "privatelink.openai.azure.com" `
    --resource-group $resourceGroup `
    --query '[].{Name:name, IPv4Address:aRecords[0].ipv4Address}' `
    --output table

Write-Host "`nSearch DNS Records:" -ForegroundColor Yellow
az network private-dns record-set a list `
    --zone-name "privatelink.search.windows.net" `
    --resource-group $resourceGroup `
    --query '[].{Name:name, IPv4Address:aRecords[0].ipv4Address}' `
    --output table
```

## Step 9: Clean Up (Return to Public Access)

If you want to revert to public endpoints (e.g., for development):

```powershell
Write-Host "`nReverting to public access (for development)..." -ForegroundColor Yellow

# Re-enable Azure OpenAI public access
$subscriptionId = $config.subscriptionId
$openAiApiUri = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAiAccount`?api-version=2024-10-01"
$openAiJsonBody = '{\"properties\": {\"publicNetworkAccess\": \"Enabled\", \"networkAcls\": {\"bypass\": \"AzureServices\"}}}'  

az rest --method patch --uri $openAiApiUri --headers "Content-Type=application/json" --body $openAiJsonBody | Out-Null
Write-Host "✓ OpenAI public access restored" -ForegroundColor Green

# Re-enable Azure Search public access
az search service update `
    --name $searchService `
    --resource-group $resourceGroup `
    --public-network-access enabled `
    | Out-Null

Write-Host "✓ Search public access restored" -ForegroundColor Green
Write-Host "Note: Private endpoints still exist but public access is now allowed too" -ForegroundColor Yellow
```

## Best Practices

### ✅ DO

- Use private endpoints for production AI workloads (and other Azure services)
- Disable public access once private endpoints are configured
- Link Private DNS zones to all VNets that need access
- Test the break/fix cycle to understand dependencies
- Document which services use private endpoints
- Monitor private endpoint connection health
- Use managed identities with private endpoints (no connection strings)

### ❌ DON'T

- Mix public and private access unless necessary (use one or the other)
- Forget DNS configuration (most common failure point)
- Assume private endpoints work immediately (DNS propagation takes time)
- Create private endpoints in the wrong VNet
- Skip testing after configuration changes

## Real-World Scenarios

### Multi-Region Deployments

```
[Region 1 VNet] → Private Endpoint → [OpenAI Region 1]
[Region 2 VNet] → Private Endpoint → [OpenAI Region 2]
        ↓ (VNet Peering or VPN)
   [Shared Services VNet]
```

### Hub-Spoke with Centralized AI Services

```
         [Hub VNet]
    ├── OpenAI Private Endpoint
    ├── Storage Private Endpoint
    └── Key Vault Private Endpoint
         ↓ (Peering)
[Spoke: AKS Prod] [Spoke: AKS Dev] [Spoke: AKS Test]
```

### Hybrid On-Premises + Azure

```
[On-Prem Network]
        ↓ (ExpressRoute/VPN)
    [Azure VNet]
    └── OpenAI Private Endpoint
```

On-premises applications can access Azure OpenAI via private connectivity!

## Next Steps

- **[Lab 4: Secrets Management](04-secrets-management.md)** - Secure secrets with Key Vault

## Resources

- [Azure Private Link Documentation](https://learn.microsoft.com/azure/private-link/)
- [Private Endpoints for Azure OpenAI](https://learn.microsoft.com/azure/ai-services/openai/how-to/managed-network)
- [Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-overview)
- [AKS Private Link Integration](https://learn.microsoft.com/azure/aks/private-clusters)

## Key Learnings

✅ **Private Endpoints Enable Zero Trust:** Network-layer isolation for AI services  
✅ **DNS is Critical:** Private DNS zones resolve FQDNs to private IPs  
✅ **Test the Impact:** Disable public access first, then fix with private endpoint  
✅ **Use Existing VNets:** No need for complex VNet peering if you deploy into the same VNet  
✅ **AI Services Support Private Link:** OpenAI, Cognitive Services, Search all work with private endpoints  
✅ **Break/Fix Teaches Best:** Seeing the failure helps understand the solution  
✅ **Every Customer is Different:** Some have hub-spoke, some have flat VNets - principle is the same

## Troubleshooting

### Agent Still Fails After Creating Private Endpoint

```powershell
# 1. Check private endpoint connection status
az network private-endpoint show `
    --name "$openAiAccount-pe" `
    --resource-group $aksNodeRG `
    --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState' `
    | ConvertFrom-Json

# Expected: status = "Approved"

# 2. Verify DNS resolution FROM an AKS pod
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup "$openAiAccount.openai.azure.com"

# Expected: Should return private IP (10.x.x.x), not public IP

# 3. Check DNS zone link
az network private-dns link vnet list `
    --zone-name "privatelink.openai.azure.com" `
    --resource-group $resourceGroup `
    --output table

# Expected: AKS VNet should be linked

# 4. Restart AKS pods to flush DNS cache
kubectl rollout restart deployment agent-webapp -n agent-demo
```

### DNS Resolves to Public IP Instead of Private IP

```powershell
# Check A record exists
az network private-dns record-set a list `
    --zone-name "privatelink.openai.azure.com" `
    --resource-group $resourceGroup `
    --output table

# Verify VNet link registration
az network private-dns link vnet show `
    --name "aks-vnet-link" `
    --zone-name "privatelink.openai.azure.com" `
    --resource-group $resourceGroup `
    | ConvertFrom-Json

# If missing, re-create the link
az network private-dns link vnet create `
    --name "aks-vnet-link" `
    --resource-group $resourceGroup `
    --zone-name "privatelink.openai.azure.com" `
    --virtual-network $aksVNet.id `
    --registration-enabled false
```

### "Public Network Access Disabled" Error from Local Machine

This is **expected** - your local machine cannot access AI services when public access is disabled. Options:

1. **Re-enable public access temporarily**:
   ```powershell
   # Re-enable Azure OpenAI
   $subscriptionId = $config.subscriptionId
   $openAiApiUri = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAiAccount`?api-version=2024-10-01"
   $openAiJsonBody = '{\"properties\": {\"publicNetworkAccess\": \"Enabled\", \"networkAcls\": {\"bypass\": \"AzureServices\"}}}'
   az rest --method patch --uri $openAiApiUri --headers "Content-Type=application/json" --body $openAiJsonBody
   
   # Re-enable Azure Search
   az search service update --name $searchService --resource-group $resourceGroup --public-network-access enabled
   ```

2. **Use a Bastion/Jump Box** in the AKS VNet for testing

3. **Use kubectl port-forward** to test from local machine:
   ```powershell
   kubectl port-forward deployment/agent-webapp 8080:80
   # Open http://localhost:8080
   ```

## Challenge Exercise

**Task:** Create private endpoints for the remaining services (Storage Account and Key Vault) and verify the agent still works.

<details>
<summary>Solution (click to expand)</summary>

**Storage Account:**

```powershell
$storageAccount = $config.resources.storageAccount

# Disable public access but allow Azure services (for Search indexer)
az storage account update `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --default-action Deny `
    --bypass AzureServices `
    | Out-Null

Write-Host "✓ Storage Account secured (accessible by Azure AI Search via trusted services)" -ForegroundColor Green
```

> **📝 Note:** Unlike OpenAI and Search, the Storage Account uses the **trusted services bypass** (`--bypass AzureServices`) instead of a private endpoint. This allows Azure AI Search to access the storage account for indexing, even when public access is denied. Azure AI Search is a PaaS service that doesn't support consuming storage via private endpoints in the same way AKS does. The agent application doesn't directly access Storage (it queries Search, which returns indexed results).

**Key Vault:**

```powershell
$keyVault = $config.resources.keyVault

# Disable public access
az keyvault update `
    --name $keyVault `
    --resource-group $resourceGroup `
    --public-network-access Disabled `
    | Out-Null

# Create private endpoint
$kvId = az keyvault show `
    --name $keyVault `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

az network private-endpoint create `
    --name "$keyVault-pe" `
    --resource-group $aksNodeRG `
    --location $location `
    --subnet $subnetId `
    --private-connection-resource-id $kvId `
    --group-id vault `
    --connection-name "$keyVault-connection" `
    | Out-Null

# Configure DNS
az network private-dns zone create `
    --name "privatelink.vaultcore.azure.net" `
    --resource-group $resourceGroup `
    2>$null | Out-Null

az network private-dns link vnet create `
    --name "aks-kv-link" `
    --resource-group $resourceGroup `
    --zone-name "privatelink.vaultcore.azure.net" `
    --virtual-network $aksVNet.id `
    --registration-enabled false `
    2>$null | Out-Null

Write-Host "✓ Key Vault secured with private endpoint" -ForegroundColor Green
```

</details>
