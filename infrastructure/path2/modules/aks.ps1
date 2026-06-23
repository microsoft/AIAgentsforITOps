function New-WorkshopAKSCluster {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$Prefix,
        
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerRegistryName,
        
        [Parameter(Mandatory = $false)]
        [string]$VNetName = $null,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    $aksName = "$Prefix-aks-$Environment"
    
    Write-InfoLog "Creating Azure Kubernetes Service cluster: $aksName"
    Write-InfoLog "This may take 10-15 minutes..."
    
    # Build AKS create command
    $aksCreateArgs = @(
        "--resource-group", $ResourceGroupName,
        "--name", $aksName,
        "--location", $Location,
        "--node-count", "2",
        "--node-vm-size", "Standard_D2s_v3",
        "--enable-managed-identity",
        "--no-ssh-key",
        "--network-plugin", "azure",
        "--network-policy", "azure",
        "--enable-cluster-autoscaler",
        "--min-count", "2",
        "--max-count", "5"
    )
    
    # Add VNet integration if VNet name provided
    if ($VNetName) {
        Write-InfoLog "Configuring VNet integration"
        
        $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName
        $aksSubnet = $vnet.Subnets | Where-Object { $_.Name -eq "aks-subnet" }
        
        if ($aksSubnet) {
            $aksCreateArgs += "--vnet-subnet-id", $aksSubnet.Id
        }
    }
    
    # Check if AKS cluster exists
    $existingAks = az aks show --name $aksName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    
    if ($existingAks) {
        Write-WarningLog "AKS cluster '$aksName' already exists. Skipping creation and configuration."
        
        # Get existing cluster information
        $aksIdentity = az aks show `
            --name $aksName `
            --resource-group $ResourceGroupName `
            --query identity.principalId `
            -o tsv
        
        $kubeletIdentityClientId = az aks show `
            --name $aksName `
            --resource-group $ResourceGroupName `
            --query identityProfile.kubeletidentity.clientId `
            -o tsv
        
        $oidcIssuer = az aks show `
            --name $aksName `
            --resource-group $ResourceGroupName `
            --query oidcIssuerProfile.issuerUrl `
            -o tsv
        
        Write-InfoLog "Using existing AKS cluster configuration"
        
        return @{
            Name = $aksName
            Id = $existingAks.id
            IdentityPrincipalId = $aksIdentity
            KubeletIdentityClientId = $kubeletIdentityClientId
            OidcIssuer = $oidcIssuer
            Fqdn = $existingAks.fqdn
        }
    }
    
    # Create AKS cluster
    Write-InfoLog "Creating new AKS cluster..."
    $aks = az aks create @aksCreateArgs | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create AKS cluster"
    }
    
    Write-SuccessLog "AKS cluster created: $aksName"
    
    # Attach ACR to AKS
    Write-InfoLog "Attaching ACR to AKS cluster"
    
    # Get ACR resource ID
    $acrId = az acr show --name $ContainerRegistryName --resource-group $ResourceGroupName --query id -o tsv
    
    if ($acrId) {
        $attachOutput = az aks update `
            --name $aksName `
            --resource-group $ResourceGroupName `
            --attach-acr $acrId `
            2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-SuccessLog "ACR attached successfully"
        } else {
            # Check if already attached
            if ($attachOutput -match "already attached" -or $attachOutput -match "RoleAssignmentExists") {
                Write-InfoLog "ACR already attached to AKS"
            } else {
                Write-WarningLog "ACR attachment issue: $attachOutput"
            }
        }
    } else {
        Write-WarningLog "Could not find ACR: $ContainerRegistryName"
    }
    
    # Enable workload identity (for managed identity pod access)
    Write-InfoLog "Enabling workload identity"
    
    az aks update `
        --name $aksName `
        --resource-group $ResourceGroupName `
        --enable-oidc-issuer `
        --enable-workload-identity `
        | Out-Null
    
    # Get AKS managed identity
    $aksIdentity = az aks show `
        --name $aksName `
        --resource-group $ResourceGroupName `
        --query identity.principalId `
        -o tsv
    
    # Get kubelet managed identity client ID (needed for CSI driver)
    $kubeletIdentityClientId = az aks show `
        --name $aksName `
        --resource-group $ResourceGroupName `
        --query identityProfile.kubeletidentity.clientId `
        -o tsv
    
    # Get OIDC issuer URL
    $oidcIssuer = az aks show `
        --name $aksName `
        --resource-group $ResourceGroupName `
        --query oidcIssuerProfile.issuerUrl `
        -o tsv
    
    Write-SuccessLog "AKS cluster configured with workload identity"
    
    return @{
        Name = $aksName
        Id = $aks.id
        IdentityPrincipalId = $aksIdentity
        KubeletIdentityClientId = $kubeletIdentityClientId
        OidcIssuer = $oidcIssuer
        Fqdn = $aks.fqdn
    }
}

function Enable-AKSMonitoring {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$AksName,
        
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceResourceId
    )
    
    Write-InfoLog "Enabling monitoring on AKS cluster: $AksName"
    
    try {
        az aks enable-addons `
            --resource-group $ResourceGroupName `
            --name $AksName `
            --addons monitoring `
            --workspace-resource-id $WorkspaceResourceId `
            2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-SuccessLog "AKS monitoring enabled successfully"
            return $true
        } else {
            Write-WarningLog "Could not enable AKS monitoring. This can be configured later in the Azure portal."
            return $false
        }
    }
    catch {
        Write-WarningLog "Error enabling AKS monitoring: $($_.Exception.Message)"
        Write-InfoLog "Monitoring can be enabled later via: az aks enable-addons --addons monitoring"
        return $false
    }
}
