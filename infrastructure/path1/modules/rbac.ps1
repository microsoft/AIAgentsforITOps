function Configure-WorkshopRBAC {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$AKSName,
        
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$SearchServiceName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerRegistryName,
        
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory = $false)]
        [string]$AzureOpenAIName
    )
    
    Write-InfoLog "Configuring RBAC assignments"
    
    # Get AKS system-assigned managed identity (for cluster operations)
    $aksIdentity = az aks show `
        --name $AKSName `
        --resource-group $ResourceGroupName `
        --query identity.principalId `
        -o tsv
    
    # Get AKS kubelet managed identity (for CSI driver and pod operations)
    $kubeletIdentity = az aks show `
        --name $AKSName `
        --resource-group $ResourceGroupName `
        --query identityProfile.kubeletidentity.objectId `
        -o tsv
    
    # Get Storage Account resource ID
    $storageId = az storage account show `
        --name $StorageAccountName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
    # Get Search Service resource ID  
    $searchId = az search service show `
        --name $SearchServiceName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
    # Get Search Service managed identity
    $searchIdentity = az search service show `
        --name $SearchServiceName `
        --resource-group $ResourceGroupName `
        --query identity.principalId `
        -o tsv
    
    # Get ACR resource ID
    $acrId = az acr show `
        --name $ContainerRegistryName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
    # Get Key Vault resource ID
    $kvId = az keyvault show `
        --name $KeyVaultName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
    #region Storage RBAC
    
    # Only Search Service needs Storage access to read and index documents
    Write-InfoLog "Assigning Storage Blob Data Contributor to Search Service identity"
    az role assignment create `
        --role "Storage Blob Data Contributor" `
        --assignee-object-id $searchIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $storageId `
        2>$null | Out-Null
    
    #endregion
    
    #region Search RBAC
    
    Write-InfoLog "Assigning Search Index Data Reader to AKS kubelet identity"
    az role assignment create `
        --role "Search Index Data Reader" `
        --assignee-object-id $kubeletIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $searchId `
        2>$null | Out-Null
    
    #endregion
    
    #region ACR RBAC
    
    Write-InfoLog "Assigning AcrPull role to AKS identity"
    az role assignment create `
        --role "AcrPull" `
        --assignee-object-id $aksIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $acrId `
        2>$null | Out-Null
    
    #endregion
    
    #region Key Vault RBAC
    
    Write-InfoLog "Assigning Key Vault Secrets User to AKS kubelet identity"
    az role assignment create `
        --role "Key Vault Secrets User" `
        --assignee-object-id $kubeletIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $kvId `
        2>$null | Out-Null
    
    #endregion
    
    #region Azure OpenAI RBAC
    
    if ($AzureOpenAIName) {
        Write-InfoLog "Assigning Cognitive Services OpenAI User to AKS kubelet identity"
        
        # Get OpenAI resource ID
        $openAIId = az cognitiveservices account show `
            --name $AzureOpenAIName `
            --resource-group $ResourceGroupName `
            --query id `
            -o tsv
        
        az role assignment create `
            --role "Cognitive Services OpenAI User" `
            --assignee-object-id $kubeletIdentity `
            --assignee-principal-type ServicePrincipal `
            --scope $openAIId `
            2>$null | Out-Null
        
        Write-SuccessLog "Azure OpenAI RBAC configured"
    } else {
        Write-WarningLog "Azure OpenAI name not provided, skipping OpenAI RBAC"
    }
    
    #endregion
    
    Write-SuccessLog "RBAC assignments completed"
    
    # Return summary
    return @{
        AKSIdentity = $aksIdentity
        Assignments = @(
            "Search -> Storage: Storage Blob Data Contributor"
            "AKS Kubelet -> Search: Search Index Data Reader"
            "AKS Cluster -> ACR: AcrPull"
            "AKS Kubelet -> Key Vault: Key Vault Secrets User"
            "AKS Kubelet -> Azure OpenAI: Cognitive Services OpenAI User"
        )
    }
}
