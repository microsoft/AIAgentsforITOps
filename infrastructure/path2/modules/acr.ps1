function New-WorkshopContainerRegistry {
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
        [bool]$EnablePrivateEndpoint = $false,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    # ACR name must be globally unique and 5-50 alphanumeric characters
    $acrName = "$($Prefix)acr$Environment".ToLower() -replace '[^a-z0-9]', ''
    
    Write-InfoLog "Creating Azure Container Registry: $acrName"
    
    # Check if ACR exists
    $existingAcr = az acr show --name $acrName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    
    if ($existingAcr) {
        Write-WarningLog "Container registry '$acrName' already exists"
        $acr = $existingAcr
    } else {
        Write-InfoLog "Creating container registry..."
        
        $acr = az acr create `
            --name $acrName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku Standard `
            --admin-enabled false `
            --public-network-enabled $(if ($EnablePrivateEndpoint) { "false" } else { "true" }) `
            | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create container registry"
        }
        
        Write-SuccessLog "Container registry created: $acrName"
    }
    
    # Enable system-assigned managed identity (if not already enabled)
    if (-not $acr.identity -or $acr.identity.type -ne "SystemAssigned") {
        Write-InfoLog "Enabling system-assigned managed identity"
        $acr = az acr identity assign `
            --name $acrName `
            --identities [system] `
            | ConvertFrom-Json
    } else {
        Write-InfoLog "Managed identity already enabled"
    }
    
    # Note: Content trust and vulnerability scanning require Premium SKU
    # For workshop purposes, using Standard SKU is sufficient
    
    return @{
        Name = $acrName
        Id = $acr.id
        LoginServer = $acr.loginServer
        IdentityPrincipalId = $acr.identity.principalId
    }
}
