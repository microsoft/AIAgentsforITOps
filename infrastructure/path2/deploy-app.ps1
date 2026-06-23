<#
.SYNOPSIS
    Deploys the Path 2 chat UI to Azure Kubernetes Service.

.DESCRIPTION
    Unlike Path 1, the agent lives in Microsoft Foundry. This script:
    1. Verifies the Foundry prompt agent exists (created in the portal) and is
       reachable via the Foundry data plane, addressed by name.
    2. Stores the agent name in Key Vault (Foundry-AgentName) so the UI can read it.
    3. Builds and pushes the container image using ACR Tasks.
    4. Gets AKS credentials and enables the Key Vault CSI Driver addon.
    5. Generates Kubernetes manifests with environment-specific values.
    6. Deploys the application to AKS and waits for the public endpoint.

    The UI calls the prompt agent over the OpenAI Responses API:
      {projectEndpoint}/agents/{agentName}/endpoint/protocols/openai/responses

.PARAMETER DeploymentOutputFile
    Path to the deployment-output.json file from deploy-infra.ps1.
    Default: .\deployment-output.json

.PARAMETER AgentName
    Name of the Foundry prompt agent created in the portal (Lab Step 5).
    Default: conference-expert-agent

.PARAMETER ImageTag
    Tag for the container image. Default: v1

.EXAMPLE
    .\deploy-app.ps1

.EXAMPLE
    .\deploy-app.ps1 -AgentName "conference-expert-agent" -ImageTag "v2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DeploymentOutputFile = "$PSScriptRoot\deployment-output.json",

    [Parameter(Mandatory = $false)]
    [string]$AgentName = "conference-expert-agent",

    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "v1"
)

# Import common functions (logging, etc.)
. "$PSScriptRoot\modules\common.ps1"

# Print header
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   AI Agents for IT/Ops - Application Deployment (Path 2 / Foundry) ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verify deployment output file exists
if (-not (Test-Path $DeploymentOutputFile)) {
    Write-ErrorLog "Deployment output file not found: $DeploymentOutputFile"
    Write-Host "Please run .\deploy-infra.ps1 first" -ForegroundColor Red
    exit 1
}

# Load deployment output
Write-InfoLog "Loading deployment configuration from: $DeploymentOutputFile"
$deployment = Get-Content $DeploymentOutputFile | ConvertFrom-Json

# Extract resource names
$resourceGroup   = $deployment.resourceGroupName
$acrName         = $deployment.resources.containerRegistry
$aksName         = $deployment.resources.aksCluster
$kvName          = $deployment.resources.keyVault
$projectEndpoint = $deployment.foundry.projectEndpoint
$projectName     = $deployment.foundry.projectName

# The Foundry Agents data plane is served from the *.services.ai.azure.com host,
# NOT the control-plane *.cognitiveservices.azure.com host. Older deployment
# output files may still carry the cognitiveservices host, so normalize it here.
if ($projectEndpoint -match 'cognitiveservices\.azure\.com') {
    $projectEndpoint = $projectEndpoint -replace 'cognitiveservices\.azure\.com', 'services.ai.azure.com'
    Write-WarningLog "Normalized project endpoint to the Foundry data-plane host (services.ai.azure.com)."
}

Write-Host ""
Write-Host "Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group:   $resourceGroup" -ForegroundColor Gray
Write-Host "  ACR:              $acrName" -ForegroundColor Gray
Write-Host "  AKS:              $aksName" -ForegroundColor Gray
Write-Host "  Key Vault:        $kvName" -ForegroundColor Gray
Write-Host "  Foundry Project:  $projectName" -ForegroundColor Gray
Write-Host "  Project Endpoint: $projectEndpoint" -ForegroundColor Gray
Write-Host "  Agent Name:       $AgentName" -ForegroundColor Gray
Write-Host "  Image Tag:        $ImageTag" -ForegroundColor Gray
Write-Host ""

# Step 1: Resolve the Foundry Agent ID by name
Write-SectionHeader "Verifying Foundry Agent"
Write-InfoLog "Checking the Foundry project for prompt agent: $AgentName"

if ([string]::IsNullOrWhiteSpace($projectEndpoint)) {
    Write-ErrorLog "Foundry project endpoint is missing from deployment-output.json."
    exit 1
}

# Acquire an Entra ID token for the Foundry data plane
$agentToken = az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($agentToken)) {
    Write-ErrorLog "Failed to acquire an access token for https://ai.azure.com. Run 'az login' and retry."
    exit 1
}

# New Foundry prompt agents are addressed by NAME (not a generated Agent ID) and
# invoked over the OpenAI Responses API. We only need to confirm the agent exists.
$apiVersion = "2025-11-15-preview"
$agentUri = "$($projectEndpoint.TrimEnd('/'))/agents/$AgentName`?api-version=$apiVersion"

try {
    $headers = @{ Authorization = "Bearer $agentToken" }
    $agent = Invoke-RestMethod -Uri $agentUri -Headers $headers -Method Get -ErrorAction Stop
    Write-SuccessLog "Found agent '$AgentName'."
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-ErrorLog "No Foundry prompt agent named '$AgentName' was found in project '$projectName'."
        Write-Host "Create the prompt agent in the Foundry portal (Lab Step 5) first," -ForegroundColor Red
        Write-Host "or pass the correct name with: .\deploy-app.ps1 -AgentName '<your-agent-name>'" -ForegroundColor Red
    }
    else {
        Write-ErrorLog "Failed to verify Foundry agent (HTTP $statusCode): $($_.Exception.Message)"
        Write-Host "Verify you have the 'Azure AI Project Manager' (Foundry Project Manager) role on the project," -ForegroundColor Red
        Write-Host "and that the project endpoint is correct: $projectEndpoint" -ForegroundColor Red
    }
    exit 1
}

# Step 2: Store the agent name in Key Vault
Write-SectionHeader "Storing Agent Name in Key Vault"
Write-InfoLog "Setting secret: Foundry-AgentName"
az keyvault secret set --vault-name $kvName --name "Foundry-AgentName" --value $AgentName --output none

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Failed to store Foundry-AgentName in Key Vault: $kvName"
    exit 1
}
Write-SuccessLog "Agent name stored in Key Vault"

# Ensure the UI reads the data-plane endpoint host. deploy-infra.ps1 may have
# stored the cognitiveservices host; refresh it with the normalized value.
Write-InfoLog "Refreshing secret: Foundry-ProjectEndpoint"
az keyvault secret set --vault-name $kvName --name "Foundry-ProjectEndpoint" --value $projectEndpoint --output none

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Failed to store Foundry-ProjectEndpoint in Key Vault: $kvName"
    exit 1
}
Write-SuccessLog "Project endpoint stored in Key Vault"

# Step 3: Build and push container image
Write-SectionHeader "Building Container Image"
Write-InfoLog "Building container image using ACR Tasks (no Docker Desktop required)"

$appPath = Join-Path $PSScriptRoot "..\..\src\path2\agent-webapp"
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

# Step 4: Get AKS credentials
Write-SectionHeader "Configuring Kubernetes Access"
Write-InfoLog "Getting AKS credentials"

az aks get-credentials --resource-group $resourceGroup --name $aksName --overwrite-existing

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog "Failed to get AKS credentials"
    exit 1
}

Write-SuccessLog "AKS credentials configured"

# Step 5: Enable Key Vault CSI Driver
Write-SectionHeader "Enabling Key Vault CSI Driver"
Write-InfoLog "Enabling azure-keyvault-secrets-provider addon"

az aks enable-addons --addons azure-keyvault-secrets-provider --resource-group $resourceGroup --name $aksName --output none

if ($LASTEXITCODE -ne 0) {
    Write-WarningLog "CSI Driver may already be enabled (this is OK)"
} else {
    Write-SuccessLog "Key Vault CSI Driver enabled"
}

# Step 6: Generate Kubernetes manifests
Write-SectionHeader "Generating Kubernetes Manifests"

# Get tenant ID
$tenantId = az account show --query tenantId -o tsv
Write-InfoLog "Tenant ID: $tenantId"

# Get AKS kubelet identity
$aksIdentity = az aks show --resource-group $resourceGroup --name $aksName --query identityProfile.kubeletidentity.clientId -o tsv
Write-InfoLog "AKS Kubelet Identity: $aksIdentity"

$kubernetesPath = Join-Path $PSScriptRoot "..\..\kubernetes\path2"

# Generate SecretProviderClass
Write-InfoLog "Generating SecretProviderClass manifest"
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

# Step 7: Deploy to Kubernetes
Write-SectionHeader "Deploying to Kubernetes"

$manifests = @(
    @{ Name = "Namespace"; Path = "namespace.yaml" }
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

# Step 8: Validate deployment
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
