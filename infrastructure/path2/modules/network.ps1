function New-WorkshopVirtualNetwork {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    $vnetName = "$Prefix-vnet-$Environment"
    $aksSubnetName = "aks-subnet"
    $privateEndpointSubnetName = "private-endpoint-subnet"
    
    Write-InfoLog "Creating Virtual Network: $vnetName"
    
    # Check if VNet exists
    $existingVnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName -ErrorAction SilentlyContinue
    
    if ($existingVnet) {
        Write-WarningLog "Virtual Network '$vnetName' already exists"
        return @{
            Name = $vnetName
            Id = $existingVnet.Id
            AKSSubnetId = ($existingVnet.Subnets | Where-Object { $_.Name -eq $aksSubnetName }).Id
            PrivateEndpointSubnetId = ($existingVnet.Subnets | Where-Object { $_.Name -eq $privateEndpointSubnetName }).Id
        }
    }
    
    # Create AKS subnet configuration
    $aksSubnet = New-AzVirtualNetworkSubnetConfig `
        -Name $aksSubnetName `
        -AddressPrefix "10.0.0.0/22"
    
    # Create Private Endpoint subnet configuration
    $privateEndpointSubnet = New-AzVirtualNetworkSubnetConfig `
        -Name $privateEndpointSubnetName `
        -AddressPrefix "10.0.4.0/24" `
        -PrivateEndpointNetworkPoliciesFlag Disabled
    
    # Create VNet
    $vnet = New-AzVirtualNetwork `
        -Name $vnetName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -AddressPrefix "10.0.0.0/16" `
        -Subnet $aksSubnet, $privateEndpointSubnet `
        -Tag $Tags
    
    Write-SuccessLog "Virtual Network created: $vnetName"
    
    # Get subnet IDs
    $aksSubnetId = ($vnet.Subnets | Where-Object { $_.Name -eq $aksSubnetName }).Id
    $privateEndpointSubnetId = ($vnet.Subnets | Where-Object { $_.Name -eq $privateEndpointSubnetName }).Id
    
    Write-InfoLog "  AKS Subnet: $aksSubnetName (10.0.0.0/22)"
    Write-InfoLog "  Private Endpoint Subnet: $privateEndpointSubnetName (10.0.4.0/24)"
    
    return @{
        Name = $vnetName
        Id = $vnet.Id
        AKSSubnetId = $aksSubnetId
        PrivateEndpointSubnetId = $privateEndpointSubnetId
    }
}
