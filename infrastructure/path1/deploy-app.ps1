<#
.SYNOPSIS
    Deploys the AI Agent web application to Azure Kubernetes Service
    
.DESCRIPTION
    This script:
    1. Builds and pushes the container image using ACR Tasks
    2. Gets AKS credentials
    3. Enables the Azure Key Vault CSI Driver addon
    4. Generates Kubernetes manifests with environment-specific values
    5. Deploys the application to AKS
    6. Validates the deployment
    
.PARAMETER DeploymentOutputFile
    Path to the deployment-output.json file from deploy-infra.ps1
    Default: .\deployment-output.json
    
.PARAMETER ImageTag
    Tag for the container image
    Default: v1
    
.EXAMPLE
    .\deploy-app.ps1
    
.EXAMPLE
    .\deploy-app.ps1 -ImageTag "v2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DeploymentOutputFile = "$PSScriptRoot\deployment-output.json",
    
    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "v1"
)

# Import common functions (logging, etc.)
. "$PSScriptRoot\modules\common.ps1"

# Print header
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   AI Agents for IT/Ops - Application Deployment                   ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verify deployment output file exists
if (-not (Test-Path $DeploymentOutputFile)) {
    Write-ErrorLog "Deployment output file not found: $DeploymentOutputFile"
    Write-Host "Please run .\infrastructure\deploy-infra.ps1 first" -ForegroundColor Red
    exit 1
}

# Load deployment output
Write-InfoLog "Loading deployment configuration from: $DeploymentOutputFile"
$deployment = Get-Content $DeploymentOutputFile | ConvertFrom-Json

# Extract resource names
$resourceGroup = $deployment.resourceGroupName
$acrName = $deployment.resources.containerRegistry
$aksName = $deployment.resources.aksCluster
$kvName = $deployment.resources.keyVault

Write-Host ""
Write-Host "Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
Write-Host "  ACR: $acrName" -ForegroundColor Gray
Write-Host "  AKS: $aksName" -ForegroundColor Gray
Write-Host "  Key Vault: $kvName" -ForegroundColor Gray
Write-Host "  Image Tag: $ImageTag" -ForegroundColor Gray
Write-Host ""

# Step 1: Build and push container image
Write-SectionHeader "Building Container Image"
Write-InfoLog "Building container image using ACR Tasks (no Docker Desktop required)"

$appPath = Join-Path $PSScriptRoot "..\..\src\path1\agent-webapp"
if (-not (Test-Path $appPath)) {
    Write-ErrorLog "Application path not found: $appPath"
    exit 1
}

Push-Location $appPath
try {
    Write-InfoLog "Building image: agent-webapp:$ImageTag"
    az acr build --registry $acrName --image "agent-webapp:$ImageTag" . --output table
    
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog "Failed to build container image"
        exit 1
    }
    
    Write-SuccessLog "Container image built successfully"
} finally {
    Pop-Location
}

# Step 2: Get AKS credentials
Write-SectionHeader "Configuring Kubernetes Access"
Write-InfoLog "Getting AKS credentials"

az aks get-credentials --resource-group $resourceGroup --name $aksName --overwrite-existing

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Failed to get AKS credentials"
    exit 1
}

Write-SuccessLog "AKS credentials configured"

# Step 3: Enable Key Vault CSI Driver
Write-SectionHeader "Enabling Key Vault CSI Driver"
Write-InfoLog "Enabling azure-keyvault-secrets-provider addon"

az aks enable-addons --addons azure-keyvault-secrets-provider --resource-group $resourceGroup --name $aksName --output none

if ($LASTEXITCODE -ne 0) {
    Write-WarningLog "CSI Driver may already be enabled (this is OK)"
} else {
    Write-SuccessLog "Key Vault CSI Driver enabled"
}

# Step 4: Generate Kubernetes manifests
Write-SectionHeader "Generating Kubernetes Manifests"

# Get tenant ID
$tenantId = az account show --query tenantId -o tsv
Write-InfoLog "Tenant ID: $tenantId"

# Get AKS kubelet identity
$aksIdentity = az aks show --resource-group $resourceGroup --name $aksName --query identityProfile.kubeletidentity.clientId -o tsv
Write-InfoLog "AKS Kubelet Identity: $aksIdentity"

# Generate SecretProviderClass
Write-InfoLog "Generating SecretProviderClass manifest"
$kubernetesPath = Join-Path $PSScriptRoot "..\..\kubernetes\path1"
$spcTemplate = Join-Path $kubernetesPath "secretproviderclass.yaml"
$spcOutput = Join-Path $kubernetesPath "secretproviderclass.generated.yaml"

if (-not (Test-Path $spcTemplate)) {
    Write-ErrorLog "SecretProviderClass template not found: $spcTemplate"
    exit 1
}

$spcYaml = Get-Content $spcTemplate -Raw
$spcYaml = $spcYaml -replace '\$\{KEY_VAULT_NAME\}', $kvName
$spcYaml = $spcYaml -replace '\$\{AZURE_TENANT_ID\}', $tenantId
$spcYaml = $spcYaml -replace '\$\{AKS_IDENTITY_CLIENT_ID\}', $aksIdentity
$spcYaml | Set-Content $spcOutput -NoNewline

Write-SuccessLog "Generated: secretproviderclass.generated.yaml"

# Generate Deployment manifest
Write-InfoLog "Generating Deployment manifest"
$deploymentTemplate = Join-Path $kubernetesPath "deployment.yaml"
$deploymentOutput = Join-Path $kubernetesPath "deployment.generated.yaml"

if (-not (Test-Path $deploymentTemplate)) {
    Write-ErrorLog "Deployment template not found: $deploymentTemplate"
    exit 1
}

$deployYaml = Get-Content $deploymentTemplate -Raw
$deployYaml = $deployYaml -replace '\$\{AZURE_CONTAINER_REGISTRY\}', "$acrName.azurecr.io"
$deployYaml = $deployYaml -replace '\$\{IMAGE_TAG\}', $ImageTag
$deployYaml | Set-Content $deploymentOutput -NoNewline

Write-SuccessLog "Generated: deployment.generated.yaml"

# Generate ConfigMap manifest
Write-InfoLog "Generating ConfigMap manifest"
$configMapTemplate = Join-Path $kubernetesPath "configmap.yaml"
$configMapOutput = Join-Path $kubernetesPath "configmap.generated.yaml"

if (-not (Test-Path $configMapTemplate)) {
    Write-ErrorLog "ConfigMap template not found: $configMapTemplate"
    exit 1
}

$configMapYaml = Get-Content $configMapTemplate -Raw
$configMapYaml = $configMapYaml -replace '\$\{AZURE_SEARCH_NAME\}', $deployment.resources.searchService
$configMapYaml | Set-Content $configMapOutput -NoNewline

Write-SuccessLog "Generated: configmap.generated.yaml"

# Generate ServiceAccount manifest
Write-InfoLog "Generating ServiceAccount manifest"
$serviceAccountTemplate = Join-Path $kubernetesPath "serviceaccount.yaml"
$serviceAccountOutput = Join-Path $kubernetesPath "serviceaccount.generated.yaml"

if (-not (Test-Path $serviceAccountTemplate)) {
    Write-ErrorLog "ServiceAccount template not found: $serviceAccountTemplate"
    exit 1
}

$serviceAccountYaml = Get-Content $serviceAccountTemplate -Raw
$serviceAccountYaml = $serviceAccountYaml -replace '\$\{MANAGED_IDENTITY_CLIENT_ID\}', $aksIdentity
$serviceAccountYaml | Set-Content $serviceAccountOutput -NoNewline

Write-SuccessLog "Generated: serviceaccount.generated.yaml"

# Step 5: Deploy to Kubernetes
Write-SectionHeader "Deploying to Kubernetes"

$manifests = @(
    @{ Name = "Namespace"; Path = "namespace.yaml" }
    @{ Name = "ConfigMap"; Path = "configmap.generated.yaml" }
    @{ Name = "ServiceAccount"; Path = "serviceaccount.generated.yaml" }
    @{ Name = "SecretProviderClass"; Path = "secretproviderclass.generated.yaml" }
    @{ Name = "Deployment"; Path = "deployment.generated.yaml" }
    @{ Name = "Service"; Path = "service.yaml" }
)

foreach ($manifest in $manifests) {
    $manifestPath = Join-Path $kubernetesPath $manifest.Path
    
    if (-not (Test-Path $manifestPath)) {
        Write-WarningLog "Manifest not found, skipping: $($manifest.Path)"
        continue
    }
    
    Write-InfoLog "Applying $($manifest.Name)..."
    kubectl apply -f $manifestPath
    
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog "Failed to apply $($manifest.Name)"
        exit 1
    }
}

Write-SuccessLog "All manifests deployed successfully"
Write-Host ""
Write-InfoLog "Secrets are mounted from Key Vault via CSI driver (no Kubernetes secrets)"

# Step 6: Validate deployment
Write-SectionHeader "Validating Deployment"

Write-InfoLog "Checking pod status..."
kubectl get pods -l app=agent-webapp -n agent-demo

Write-Host ""
Write-InfoLog "Checking service status..."
kubectl get services agent-webapp-service -n agent-demo

# Wait for external IP assignment
Write-Host ""
Write-InfoLog "Waiting for external IP assignment (this may take a few minutes)..."
$maxWait = 180  # 3 minutes
$waited = 0
$externalIP = ""

while ($waited -lt $maxWait) {
    $externalIP = kubectl get service agent-webapp-service -n agent-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    
    if (-not [string]::IsNullOrWhiteSpace($externalIP)) {
        break
    }
    
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 5
    $waited += 5
}

Write-Host ""

if ([string]::IsNullOrWhiteSpace($externalIP)) {
    Write-WarningLog "External IP not yet assigned. Check status with: kubectl get services -n agent-demo"
} else {
    Write-SuccessLog "External IP assigned: $externalIP"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  APPLICATION ENDPOINT" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  http://$externalIP" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
}

Write-Host ""
Write-Host "[SUCCESS]" -ForegroundColor Green
Write-Host "Application deployment completed successfully!" -ForegroundColor Green
Write-Host ""
