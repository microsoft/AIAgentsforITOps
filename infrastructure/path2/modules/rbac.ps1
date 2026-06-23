function Configure-WorkshopRBAC {
    <#
    .SYNOPSIS
        Configures RBAC role assignments for the Path 2 (Foundry-hosted agent)
        architecture.

    .DESCRIPTION
        Path 2 access relationships differ from Path 1:
          - Azure AI Search reads documents from Storage (the indexer pulls blobs).
          - The Foundry project's managed identity (which the Knowledge Base runs
            under) reads the Search index at query time to ground answers
            (Search Index Data Reader). The Foundry account identity is also
            granted the same read role. Foundry does NOT read Storage directly -
            it reaches documents via Search.
          - The AKS-hosted UI calls the Foundry project to invoke the agent
            (data-plane access to Cognitive Services / Foundry).
          - The UI pod also pulls images from ACR and reads secrets from Key Vault.
          - The deploying user is granted Azure AI Project Manager so they can
            build/manage agents and Knowledge Bases in the Foundry project from
            the portal (https://ai.azure.com).
    #>
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
        
        [Parameter(Mandatory = $true)]
        [string]$FoundryName,

        [Parameter(Mandatory = $false)]
        [string]$ProjectIdentityPrincipalId
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
    
    # Get Search Service resource ID and managed identity
    $searchId = az search service show `
        --name $SearchServiceName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
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
    
    # Get Foundry resource ID and managed identity
    $foundryId = az cognitiveservices account show `
        --name $FoundryName `
        --resource-group $ResourceGroupName `
        --query id `
        -o tsv
    
    $foundryIdentity = az cognitiveservices account show `
        --name $FoundryName `
        --resource-group $ResourceGroupName `
        --query identity.principalId `
        -o tsv
    
    #region Storage RBAC (only Search reads documents from Storage)
    
    Write-InfoLog "Assigning Storage Blob Data Reader to Search Service identity"
    az role assignment create `
        --role "Storage Blob Data Reader" `
        --assignee-object-id $searchIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $storageId `
        2>$null | Out-Null
    
    #endregion
    
    #region Search RBAC (Foundry Knowledge Base queries the Search index)
    
    Write-InfoLog "Assigning Search Index Data Reader to Foundry identity"
    az role assignment create `
        --role "Search Index Data Reader" `
        --assignee-object-id $foundryIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $searchId `
        2>$null | Out-Null
    
    if ([string]::IsNullOrWhiteSpace($ProjectIdentityPrincipalId)) {
        Write-WarningLog "Project managed identity not provided; skipping its Search Index Data Reader assignment. The Knowledge Base may fail to query the index."
    }
    else {
        Write-InfoLog "Assigning Search Index Data Reader to Foundry project identity"
        az role assignment create `
            --role "Search Index Data Reader" `
            --assignee-object-id $ProjectIdentityPrincipalId `
            --assignee-principal-type ServicePrincipal `
            --scope $searchId `
            2>$null | Out-Null
    }
    
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
    
    #region Foundry RBAC (AKS-hosted UI invokes the agent)
    
    Write-InfoLog "Assigning Cognitive Services User to AKS kubelet identity (call the Foundry agent)"
    az role assignment create `
        --role "Cognitive Services User" `
        --assignee-object-id $kubeletIdentity `
        --assignee-principal-type ServicePrincipal `
        --scope $foundryId `
        2>$null | Out-Null
    
    #endregion
    
    #region Foundry RBAC (deploying user builds agents in the portal)
    
    # The portal's Agents page requires the data-plane "Azure AI Project Manager"
    # role. Without it the user sees "You don't have permission to build agents in
    # this project". Grant it to the signed-in user on the Foundry resource.
    $currentUserId = az ad signed-in user show --query id -o tsv 2>$null
    
    if ([string]::IsNullOrWhiteSpace($currentUserId)) {
        Write-WarningLog "Could not determine the signed-in user; skipping Azure AI Project Manager assignment. Assign it manually to build agents in the portal."
    }
    else {
        Write-InfoLog "Assigning Azure AI Project Manager to current user (build agents in the Foundry project)"
        az role assignment create `
            --role "Azure AI Project Manager" `
            --assignee-object-id $currentUserId `
            --assignee-principal-type User `
            --scope $foundryId `
            2>$null | Out-Null
    }
    
    #endregion
    
    Write-SuccessLog "RBAC assignments completed"
    
    return @{
        AKSIdentity = $aksIdentity
        FoundryIdentity = $foundryIdentity
        SearchIdentity = $searchIdentity
        Assignments = @(
            "Search -> Storage: Storage Blob Data Reader"
            "Foundry -> Search: Search Index Data Reader"
            "Foundry Project -> Search: Search Index Data Reader"
            "AKS Cluster -> ACR: AcrPull"
            "AKS Kubelet -> Key Vault: Key Vault Secrets User"
            "AKS Kubelet -> Foundry: Cognitive Services User"
            "Current User -> Foundry: Azure AI Project Manager"
        )
    }
}
