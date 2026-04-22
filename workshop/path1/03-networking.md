# Lab 3: Private Networking & VNets

## Overview

Configure virtual networks and private endpoints to isolate Azure resources from the public internet.

**Time:** 30-35 minutes  
**Difficulty:** Intermediate-Advanced

## Learning Objectives

- Create and configure virtual networks
- Deploy private endpoints
- Configure DNS for private endpoints
- Test network isolation
- Implement network security groups

## Architecture: Before and After

**Before (Public Endpoints):**
```
Internet → Storage/Search/KeyVault (public IPs)
```

**After (Private Endpoints):**
```
VNet → Private Endpoint → Storage/Search/KeyVault (private IPs)
Internet ✗ Blocked
```

## Step 1: Review Current Network Configuration

Load environment:

```powershell
$config = Get-Content ..\infrastructure\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$location = $config.location
```

Check if VNet was created:

```powershell
$vnetName = "$($config.resources.storageAccount -replace 'stor.*', '')-vnet-$($config.environment)"

$vnet = az network vnet show `
    --name $vnetName `
    --resource-group $resourceGroup `
    2>$null | ConvertFrom-Json

if ($vnet) {
    Write-Host "VNet already exists: $vnetName" -ForegroundColor Green
    $vnet | Format-List name, addressSpace, subnets
} else {
    Write-Host "No VNet found. Will create one." -ForegroundColor Yellow
}
```

## Step 2: Create Virtual Network (If Not Exists)

```powershell
if (-not $vnet) {
    Write-Host "Creating Virtual Network..." -ForegroundColor Cyan
    
    $vnet = az network vnet create `
        --name $vnetName `
        --resource-group $resourceGroup `
        --location $location `
        --address-prefix 10.0.0.0/16 `
        | ConvertFrom-Json
    
    Write-Host "VNet created: $vnetName" -ForegroundColor Green
}

# Create subnets
$aksSubnet = "aks-subnet"
$privateEndpointSubnet = "private-endpoint-subnet"

# AKS subnet
az network vnet subnet create `
    --name $aksSubnet `
    --vnet-name $vnetName `
    --resource-group $resourceGroup `
    --address-prefix 10.0.0.0/22 `
    | Out-Null

# Private endpoint subnet
az network vnet subnet create `
    --name $privateEndpointSubnet `
    --vnet-name $vnetName `
    --resource-group $resourceGroup `
    --address-prefix 10.0.4.0/24 `
    --disable-private-endpoint-network-policies true `
    | Out-Null

Write-Host "Subnets created" -ForegroundColor Green
```

## Step 3: Create Private Endpoint for Storage

```powershell
$storageAccount = $config.resources.storageAccount

Write-Host "Creating private endpoint for Storage Account..." -ForegroundColor Cyan

# Get subnet ID
$subnetId = az network vnet subnet show `
    --name $privateEndpointSubnet `
    --vnet-name $vnetName `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Get storage account ID
$storageId = az storage account show `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Create private endpoint
$storagePE = az network private-endpoint create `
    --name "$storageAccount-pe" `
    --resource-group $resourceGroup `
    --location $location `
    --vnet-name $vnetName `
    --subnet $privateEndpointSubnet `
    --private-connection-resource-id $storageId `
    --group-id blob `
    --connection-name "$storageAccount-connection" `
    | ConvertFrom-Json

Write-Host "Private endpoint created: $($storagePE.name)" -ForegroundColor Green

# Get private IP
$privateIP = $storagePE.customDnsConfigs[0].ipAddresses[0]
Write-Host "Private IP: $privateIP" -ForegroundColor Yellow
```

## Step 4: Configure Private DNS Zone

```powershell
Write-Host "Creating Private DNS Zone..." -ForegroundColor Cyan

$dnsZoneName = "privatelink.blob.core.windows.net"

# Create private DNS zone
$dnsZone = az network private-dns zone create `
    --name $dnsZoneName `
    --resource-group $resourceGroup `
    2>$null | ConvertFrom-Json

if (-not $dnsZone) {
    $dnsZone = az network private-dns zone show `
        --name $dnsZoneName `
        --resource-group $resourceGroup `
        | ConvertFrom-Json
    Write-Host "DNS Zone already exists" -ForegroundColor Yellow
} else {
    Write-Host "DNS Zone created" -ForegroundColor Green
}

# Link DNS zone to VNet
az network private-dns link vnet create `
    --name "$vnetName-link" `
    --resource-group $resourceGroup `
    --zone-name $dnsZoneName `
    --virtual-network $vnetName `
    --registration-enabled false `
    2>$null | Out-Null

Write-Host "DNS Zone linked to VNet" -ForegroundColor Green

# Create DNS A record
az network private-dns record-set a add-record `
    --resource-group $resourceGroup `
    --zone-name $dnsZoneName `
    --record-set-name $storageAccount `
    --ipv4-address $privateIP `
    2>$null | Out-Null

Write-Host "DNS A record created" -ForegroundColor Green
```

## Step 5: Disable Public Access to Storage

```powershell
Write-Host "Disabling public access to Storage Account..." -ForegroundColor Cyan

az storage account update `
    --name $storageAccount `
    --resource-group $resourceGroup `
    --default-action Deny `
    --bypass AzureServices `
    | Out-Null

Write-Host "Public access disabled. Storage only accessible via private endpoint." -ForegroundColor Green
```

## Step 6: Test Network Isolation

From your local machine (public internet):

```powershell
Write-Host "`nTesting network isolation..." -ForegroundColor Cyan

# This should fail (timeout or access denied)
try {
    az storage blob list `
        --account-name $storageAccount `
        --container-name conference-data `
        --auth-mode login `
        --timeout 10
    
    Write-Host "⚠️ Unexpected: Public access still allowed!" -ForegroundColor Red
} catch {
    Write-Host "✅ Expected: Public access blocked" -ForegroundColor Green
    Write-Host "Error (as expected): $_" -ForegroundColor DarkGray
}
```

## Step 7: Create Private Endpoint for Key Vault

```powershell
$keyVault = $config.resources.keyVault

Write-Host "`nCreating private endpoint for Key Vault..." -ForegroundColor Cyan

# Get Key Vault ID
$kvId = az keyvault show `
    --name $keyVault `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Create private endpoint
$kvPE = az network private-endpoint create `
    --name "$keyVault-pe" `
    --resource-group $resourceGroup `
    --location $location `
    --vnet-name $vnetName `
    --subnet $privateEndpointSubnet `
    --private-connection-resource-id $kvId `
    --group-id vault `
    --connection-name "$keyVault-connection" `
    | ConvertFrom-Json

Write-Host "Private endpoint created: $($kvPE.name)" -ForegroundColor Green

# Configure DNS for Key Vault
$kvDnsZone = "privatelink.vaultcore.azure.net"

az network private-dns zone create `
    --name $kvDnsZone `
    --resource-group $resourceGroup `
    2>$null | Out-Null

az network private-dns link vnet create `
    --name "$vnetName-kv-link" `
    --resource-group $resourceGroup `
    --zone-name $kvDnsZone `
    --virtual-network $vnetName `
    --registration-enabled false `
    2>$null | Out-Null

$kvPrivateIP = $kvPE.customDnsConfigs[0].ipAddresses[0]

az network private-dns record-set a add-record `
    --resource-group $resourceGroup `
    --zone-name $kvDnsZone `
    --record-set-name $keyVault `
    --ipv4-address $kvPrivateIP `
    2>$null | Out-Null

Write-Host "Key Vault DNS configured" -ForegroundColor Green

# Disable public access
az keyvault update `
    --name $keyVault `
    --resource-group $resourceGroup `
    --public-network-access Disabled `
    | Out-Null

Write-Host "Key Vault public access disabled" -ForegroundColor Green
```

## Step 8: Create Network Security Group

```powershell
Write-Host "`nCreating Network Security Group..." -ForegroundColor Cyan

$nsgName = "$($config.environment)-nsg"

# Create NSG
$nsg = az network nsg create `
    --name $nsgName `
    --resource-group $resourceGroup `
    --location $location `
    | ConvertFrom-Json

# Add rule: Allow HTTPS from VNet
az network nsg rule create `
    --name "AllowHTTPSFromVNet" `
    --nsg-name $nsgName `
    --resource-group $resourceGroup `
    --priority 100 `
    --source-address-prefixes VirtualNetwork `
    --destination-port-ranges 443 `
    --access Allow `
    --protocol Tcp `
    --direction Inbound `
    | Out-Null

# Add rule: Deny all inbound from Internet
az network nsg rule create `
    --name "DenyAllInboundFromInternet" `
    --nsg-name $nsgName `
    --resource-group $resourceGroup `
    --priority 200 `
    --source-address-prefixes Internet `
    --destination-port-ranges '*' `
    --access Deny `
    --protocol '*' `
    --direction Inbound `
    | Out-Null

Write-Host "NSG created with security rules" -ForegroundColor Green

# Associate NSG with private endpoint subnet
az network vnet subnet update `
    --name $privateEndpointSubnet `
    --vnet-name $vnetName `
    --resource-group $resourceGroup `
    --network-security-group $nsgName `
    | Out-Null

Write-Host "NSG associated with subnet" -ForegroundColor Green
```

## Step 9: View Network Topology

```powershell
Write-Host "`nNetwork Topology:" -ForegroundColor Cyan

# List all private endpoints
az network private-endpoint list `
    --resource-group $resourceGroup `
    --query '[].{Name:name, State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, IP:customDnsConfigs[0].ipAddresses[0]}' `
    --output table

# List subnets and their assignments
az network vnet subnet list `
    --vnet-name $vnetName `
    --resource-group $resourceGroup `
    --query '[].{Name:name, AddressPrefix:addressPrefix, NSG:networkSecurityGroup.id}' `
    --output table
```

## Step 10: Create Test VM (Optional)

To truly test private connectivity:

```powershell
Write-Host "`nCreating test VM in VNet (optional)..." -ForegroundColor Cyan

$vmName = "test-vm"
$adminUsername = "azureuser"
$adminPassword = Read-Host "Enter VM admin password" -AsSecureString

# Convert secure string to plain text for Azure CLI
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword)
)

az vm create `
    --name $vmName `
    --resource-group $resourceGroup `
    --location $location `
    --vnet-name $vnetName `
    --subnet $privateEndpointSubnet `
    --image Win2022Datacenter `
    --size Standard_B2s `
    --admin-username $adminUsername `
    --admin-password $plainPassword `
    --public-ip-address "" `
    --nsg "" `
    | Out-Null

Write-Host "Test VM created (no public IP)" -ForegroundColor Green
Write-Host "Connect via Bastion or VPN to test private endpoints" -ForegroundColor Yellow
```

## Best Practices

### ✅ DO

- Use private endpoints for production workloads
- Configure private DNS zones correctly
- Apply Network Security Groups (NSGs)
- Document network topology
- Use Azure Bastion or VPN for management access
- Regular audit of network rules
- Implement least-privilege network access

### ❌ DON'T

- Mix public and private endpoints unnecessarily
- Leave default "Allow all" network rules
- Forget DNS configuration
- Expose management interfaces publicly
- Skip network monitoring

## Network Topologies

### Hub-Spoke Topology
```
[Hub VNet]
    ├── [Firewall]
    ├── [VPN Gateway]
    └── [Shared Services]
         ↓
    [Spoke VNet 1]    [Spoke VNet 2]
    (Workload A)      (Workload B)
```

### Peered VNets
```
[VNet-Dev] ←→ [VNet-Prod]
     ↓              ↓
[Test Resources] [Prod Resources]
```

## Troubleshooting

### Cannot Access Storage After Private Endpoint

```powershell
# Check private endpoint status
az network private-endpoint show `
    --name "$storageAccount-pe" `
    --resource-group $resourceGroup `
    --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState' `
    | ConvertFrom-Json

# Verify DNS resolution
nslookup "$storageAccount.blob.core.windows.net"
# Should return private IP (10.0.x.x)
```

### DNS Not Resolving Correctly

```powershell
# Check DNS zone links
az network private-dns link vnet list `
    --zone-name "privatelink.blob.core.windows.net" `
    --resource-group $resourceGroup `
    --output table

# Verify A record exists
az network private-dns record-set a list `
    --zone-name "privatelink.blob.core.windows.net" `
    --resource-group $resourceGroup `
    --output table
```

### NSG Blocking Traffic

```powershell
# List NSG rules
az network nsg show `
    --name $nsgName `
    --resource-group $resourceGroup `
    --query 'securityRules[].{Name:name, Priority:priority, Access:access, Direction:direction}' `
    --output table

# View NSG flow logs (if enabled)
az network watcher flow-log list `
    --location $location `
    --resource-group $resourceGroup `
    --output table
```

## Key Learnings

✅ **Network Isolation:** Private endpoints eliminate public internet exposure  
✅ **DNS Critical:** Correct DNS configuration is essential  
✅ **Defense in Depth:** Use NSGs, private endpoints, and RBAC together  
✅ **Zero Trust:** Never trust network location alone  
✅ **Monitoring:** Always enable network monitoring

## Challenge Exercise

**Task:** Create a private endpoint for the Azure AI Search service and verify it's not accessible from the internet.

<details>
<summary>Solution (click to expand)</summary>

```powershell
$searchService = $config.resources.searchService

# Get Search service ID
$searchId = az search service show `
    --name $searchService `
    --resource-group $resourceGroup `
    --query id `
    -o tsv

# Create private endpoint
az network private-endpoint create `
    --name "$searchService-pe" `
    --resource-group $resourceGroup `
    --location $location `
    --vnet-name $vnetName `
    --subnet $privateEndpointSubnet `
    --private-connection-resource-id $searchId `
    --group-id searchService `
    --connection-name "$searchService-connection" `
    | Out-Null

# Configure DNS
$searchDnsZone = "privatelink.search.windows.net"

az network private-dns zone create `
    --name $searchDnsZone `
    --resource-group $resourceGroup `
    2>$null | Out-Null

az network private-dns link vnet create `
    --name "$vnetName-search-link" `
    --resource-group $resourceGroup `
    --zone-name $searchDnsZone `
    --virtual-network $vnetName `
    --registration-enabled false `
    2>$null | Out-Null

# Disable public access
az search service update `
    --name $searchService `
    --resource-group $resourceGroup `
    --public-network-access disabled `
    | Out-Null

Write-Host "Search service now private!" -ForegroundColor Green
```
</details>

## Next Steps

- **[Lab 4: Secrets Management](04-secrets-management.md)** - Secure secrets with Key Vault

## Resources

- [Azure Private Link Documentation](https://learn.microsoft.com/azure/private-link/)
- [Virtual Network Documentation](https://learn.microsoft.com/azure/virtual-network/)
- [Network Security Groups](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview)
- [Private Endpoints for Storage](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints)
