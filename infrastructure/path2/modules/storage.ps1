function New-WorkshopStorageAccount {
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
    
    # Storage account name must be globally unique and 3-24 lowercase letters/numbers
    $storageAccountName = "$($Prefix)stor$Environment".ToLower() -replace '[^a-z0-9]', ''
    if ($storageAccountName.Length -gt 24) {
        $storageAccountName = $storageAccountName.Substring(0, 24)
    }
    
    Write-InfoLog "Creating storage account: $storageAccountName"
    
    # Check if storage account exists
    $existingStorage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
    
    if ($existingStorage) {
        Write-WarningLog "Storage account '$storageAccountName' already exists"
        $storageAccount = $existingStorage
    } else {
        # Create storage account
        $storageAccount = New-AzStorageAccount `
            -ResourceGroupName $ResourceGroupName `
            -Name $storageAccountName `
            -Location $Location `
            -SkuName Standard_LRS `
            -Kind StorageV2 `
            -AccessTier Hot `
            -EnableHttpsTrafficOnly $true `
            -MinimumTlsVersion TLS1_2 `
            -AllowBlobPublicAccess $false `
            -Tag $Tags `
            -WarningAction SilentlyContinue
        
        Write-SuccessLog "Storage account created: $storageAccountName"
    }
    
    # Get storage context
    $ctx = $storageAccount.Context
    
    # Create container for conference documents
    $containerName = "conference-data"
    
    $existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
    if (-not $existingContainer) {
        Write-InfoLog "Creating blob container: $containerName"
        New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off | Out-Null
        Write-SuccessLog "Container created: $containerName"
    } else {
        Write-WarningLog "Container '$containerName' already exists"
    }
    
    # Enable system-assigned managed identity (if not already enabled)
    if (-not $storageAccount.Identity -or $storageAccount.Identity.Type -ne "SystemAssigned") {
        Write-InfoLog "Enabling system-assigned managed identity"
        $storageAccount = Set-AzStorageAccount `
            -ResourceGroupName $ResourceGroupName `
            -Name $storageAccountName `
            -AssignIdentity
        Write-SuccessLog "Managed identity enabled"
    } else {
        Write-InfoLog "Managed identity already enabled"
    }
    
    # Configure network rules (disable public access if private endpoints enabled)
    if ($EnablePrivateEndpoint) {
        Write-InfoLog "Configuring network rules for private access"
        Update-AzStorageAccountNetworkRuleSet `
            -ResourceGroupName $ResourceGroupName `
            -Name $storageAccountName `
            -DefaultAction Deny `
            -Bypass AzureServices
        Write-SuccessLog "Network rules configured"
    }
    
    return @{
        Name = $storageAccountName
        Id = $storageAccount.Id
        ContainerName = $containerName
        Endpoint = $storageAccount.PrimaryEndpoints.Blob
        Context = $ctx
    }
}

function Upload-ConferenceDocuments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )
    
    Write-InfoLog "Uploading conference documents from: $SourcePath"
    
    # Get storage account
    $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }
    if (-not $storageAccount) {
        throw "Storage account not found: $StorageAccountName"
    }
    
    $ctx = $storageAccount.Context
    
    # Get all .docx files
    $files = Get-ChildItem -Path $SourcePath -Filter "*.docx" -File
    
    if ($files.Count -eq 0) {
        Write-WarningLog "No .docx files found in $SourcePath"
        return
    }
    
    foreach ($file in $files) {
        Write-InfoLog "  Uploading: $($file.Name)"
        
        Set-AzStorageBlobContent `
            -File $file.FullName `
            -Container $ContainerName `
            -Blob $file.Name `
            -Context $ctx `
            -Force `
            -ErrorAction Stop | Out-Null
    }
    
    Write-SuccessLog "Uploaded $($files.Count) document(s)"
}
