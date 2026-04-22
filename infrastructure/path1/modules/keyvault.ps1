function New-WorkshopKeyVault {
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
    
    $keyVaultName = "$Prefix-kv-$Environment".ToLower()
    
    Write-InfoLog "Creating Azure Key Vault: $keyVaultName"
    
    # Get current user object ID for Key Vault access
    $currentUser = az ad signed-in-user show | ConvertFrom-Json
    $currentUserObjectId = $currentUser.id
    
    # Check if Key Vault exists in soft-delete state
    Write-InfoLog "Checking for soft-deleted Key Vault with name: $keyVaultName"
    $deletedVaults = az keyvault list-deleted --query "[?name=='$keyVaultName']" 2>$null | ConvertFrom-Json
    
    if ($deletedVaults -and $deletedVaults.Count -gt 0) {
        Write-WarningLog "Found soft-deleted Key Vault '$keyVaultName' - purging it first..."
        Write-InfoLog "This may take a few moments..."
        
        az keyvault purge --name $keyVaultName --no-wait 2>$null
        
        # Wait for purge to complete (up to 60 seconds)
        $maxWaitSeconds = 60
        $waitSeconds = 0
        $purged = $false
        
        while ($waitSeconds -lt $maxWaitSeconds) {
            Start-Sleep -Seconds 5
            $waitSeconds += 5
            
            $stillDeleted = az keyvault list-deleted --query "[?name=='$keyVaultName']" 2>$null | ConvertFrom-Json
            if (-not $stillDeleted -or $stillDeleted.Count -eq 0) {
                $purged = $true
                break
            }
            
            Write-InfoLog "  Waiting for purge to complete... ($waitSeconds seconds)"
        }
        
        if ($purged) {
            Write-SuccessLog "Soft-deleted Key Vault purged successfully"
        } else {
            Write-WarningLog "Purge initiated but not yet complete. Continuing with deployment..."
        }
    }
    
    # Check if Key Vault exists
    $existingKv = az keyvault show --name $keyVaultName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    
    if ($existingKv) {
        Write-WarningLog "Key Vault '$keyVaultName' already exists"
        $keyVault = $existingKv
    } else {
        Write-InfoLog "Creating Key Vault..."
        
        # Note: Soft delete is enabled by default in Azure Key Vault (90-day retention)
        # Purge protection is NOT enabled for workshop environments to allow easy cleanup
        $keyVault = az keyvault create `
            --name $keyVaultName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --enable-rbac-authorization true `
            --public-network-access $(if ($EnablePrivateEndpoint) { "disabled" } else { "enabled" }) `
            | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Key Vault"
        }
        
        Write-SuccessLog "Key Vault created: $keyVaultName"
    }
    
    # Assign Key Vault Administrator role to current user
    Write-InfoLog "Assigning Key Vault Administrator role to current user"
    
    $roleAssignment = az role assignment create `
        --role "Key Vault Administrator" `
        --assignee-object-id $currentUserObjectId `
        --assignee-principal-type User `
        --scope $keyVault.id `
        2>$null | ConvertFrom-Json
    
    if ($LASTEXITCODE -eq 0) {
        Write-SuccessLog "Role assigned successfully"
    } else {
        Write-WarningLog "Role assignment may already exist"
    }
    
    return @{
        Name = $keyVaultName
        Id = $keyVault.id
        Uri = $keyVault.properties.vaultUri
    }
}

function Set-WorkshopSecrets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Secrets
    )
    
    Write-InfoLog "Storing secrets in Key Vault: $KeyVaultName"
    
    foreach ($secretName in $Secrets.Keys) {
        $secretValue = $Secrets[$secretName]
        
        if ([string]::IsNullOrEmpty($secretValue)) {
            Write-WarningLog "Skipping empty secret: $secretName"
            continue
        }
        
        Write-InfoLog "  Setting secret: $secretName"
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name $secretName `
            --value $secretValue `
            --output none
        
        if ($LASTEXITCODE -ne 0) {
            Write-WarningLog "Failed to set secret: $secretName"
        }
    }
    
    Write-SuccessLog "Secrets stored in Key Vault"
}
