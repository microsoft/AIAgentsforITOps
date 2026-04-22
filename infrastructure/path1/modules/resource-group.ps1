function New-WorkshopResourceGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    Write-InfoLog "Creating resource group: $Name in $Location"
    
    $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
    
    if ($rg) {
        Write-WarningLog "Resource group '$Name' already exists"
        return $rg
    }
    
    $rg = New-AzResourceGroup -Name $Name -Location $Location -Tag $Tags
    
    Write-SuccessLog "Resource group created: $($rg.ResourceGroupName)"
    
    return $rg
}
