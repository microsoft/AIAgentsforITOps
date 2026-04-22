# Common helper functions for deployment scripts

function Write-SectionHeader {
    param([string]$Title)
    
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Write-InfoLog {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-SuccessLog {
    param([string]$Message)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Test-AzureCLI {
    try {
        $null = az version 2>$null
        return $true
    } catch {
        return $false
    }
}

function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5
    )
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            $attempt++
            if ($attempt -ge $MaxRetries) {
                throw
            }
            Write-WarningLog "Attempt $attempt failed. Retrying in $RetryDelaySeconds seconds..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Get-UniqueResourceName {
    param(
        [string]$Prefix,
        [string]$ResourceType,
        [string]$Environment
    )
    
    $hash = (Get-Date).ToString("yyyyMMddHHmmss").Substring(6)
    return "$Prefix$ResourceType$Environment$hash".ToLower()
}

function Wait-ForResourceProvisioning {
    param(
        [string]$ResourceId,
        [int]$TimeoutSeconds = 600
    )
    
    Write-InfoLog "Waiting for resource to be fully provisioned..."
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $resource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        if ($resource -and $resource.Properties.provisioningState -eq "Succeeded") {
            Write-SuccessLog "Resource provisioned successfully"
            return $true
        }
        Start-Sleep -Seconds 10
    }
    
    throw "Resource provisioning timed out after $TimeoutSeconds seconds"
}
