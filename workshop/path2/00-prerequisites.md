# Lab 0: Prerequisites (Path 2)

## Overview

Before starting the **Path 2: Foundry-Hosted Prompt Agent** workshop, ensure you have all the necessary tools and accounts configured.

> **Note:** This prerequisites guide is specific to Path 2. Path 1 (Custom Agent on AKS) has different requirements.

## Required Accounts

### Azure Subscription

- Active Azure subscription with Owner or Contributor access
- Sufficient quota for:
  - Virtual Machines (for AKS nodes)
  - Azure AI Services (Microsoft Foundry)
  - Azure AI Search
  - A model deployment (default `gpt-5.4-mini`)
- No policy restrictions that would block resource creation
- Access to the **Microsoft Foundry portal**: `https://ai.azure.com`

**To verify:**

```powershell
az account show
az account list-locations -o table
```

### Model Quota

Path 2 deploys a model (default `gpt-5.4-mini`) into your Foundry resource. Confirm you have quota for it in your chosen region (for example `eastus`, `westus2`, or `swedencentral`).

```powershell
# After login, list Cognitive Services usage/quota in a region
az cognitiveservices usage list --location eastus -o table
```

## Required Tools

### PowerShell 7.0 or Later

**Windows:**

```powershell
# Check version
$PSVersionTable.PSVersion

# Install if needed
winget install Microsoft.PowerShell
```

**Verify:**

```powershell
pwsh --version
```

### Azure CLI 2.50.0+

**Installation:**

```powershell
# Windows
winget install Microsoft.AzureCLI

# Verify
az --version
```

**Login:**

```powershell
az login
az account set --subscription <your-subscription-id>
```

### Register Azure Resource Providers

The deployment scripts assume the required Azure resource providers are already registered in the target subscription. Register the providers used by Path 2, including the additional providers required by Foundry Agent Service:

```powershell
$providers = @(
    "Microsoft.Resources"
    "Microsoft.Authorization"
    "Microsoft.Storage"
    "Microsoft.Search"
    "Microsoft.CognitiveServices"
    "Microsoft.ContainerRegistry"
    "Microsoft.ContainerService"
    "Microsoft.Compute"
    "Microsoft.Network"
    "Microsoft.ManagedIdentity"
    "Microsoft.KeyVault"
    "Microsoft.OperationalInsights"
    "Microsoft.Insights"
    "Microsoft.OperationsManagement"
    "Microsoft.MachineLearningServices"
    "Microsoft.App"
)

foreach ($provider in $providers) {
    az provider register --namespace $provider --wait
}
```

Your account must have permission to register providers in the subscription. Registration can take several minutes.

**Verify:**

```powershell
$providers | ForEach-Object {
    $registration = az provider show --namespace $_ | ConvertFrom-Json
    [pscustomobject]@{
        Provider = $registration.namespace
        State = $registration.registrationState
    }
} | Format-Table
```

Confirm that every provider reports `Registered` before continuing.

Register these additional providers only when you use the corresponding optional Foundry feature:

```powershell
# Standard agent setup with your own Azure Cosmos DB for agent state
az provider register --namespace Microsoft.DocumentDB --wait

# Grounding with Bing Search
az provider register --namespace Microsoft.Bing --wait
```

> **Note:** The workshop scripts do not deploy Azure Cosmos DB. `Microsoft.DocumentDB` is required only if you configure a standard Foundry agent setup with your own Cosmos DB resource. The basic agent setup uses platform-managed agent state.

### kubectl (Kubernetes CLI)

**Installation:**

```powershell
az aks install-cli
```

**Verify:**

```powershell
kubectl version --client
```

> **Note:** Path 2 uses **ACR Tasks** to build the UI container image directly in Azure. You do NOT need Docker Desktop installed locally. This simplifies the workshop setup and eliminates Docker Desktop licensing requirements.

### .NET 10.0 SDK (Optional - for local development only)

**Installation:**

```powershell
winget install Microsoft.DotNet.SDK.10
```

**Verify:**

```powershell
dotnet --version
```

### Git

**Verify:**

```powershell
git --version
```

## Azure PowerShell Modules

```powershell
# Install required modules
Install-Module -Name Az -AllowClobber -Scope CurrentUser
Install-Module -Name Az.Search -Scope CurrentUser
Install-Module -Name Az.CognitiveServices -Scope CurrentUser

# Import modules
Import-Module Az
Import-Module Az.Search
Import-Module Az.CognitiveServices
```

## Azure CLI Extensions

```powershell
# Install required extensions
az extension add --name aks-preview
az extension update --name aks-preview
```

## Environment Setup

### Clone Repository

```powershell
git clone https://github.com/your-org/AgentsforITOps.git
cd AgentsforITOps
```

### Verify Project Structure

```powershell
Get-ChildItem -Recurse -Depth 2
```

You should see:

- `Documents/` - Conference data files
- `src/path2/` - Chat UI application code
- `infrastructure/path2/` - Deployment scripts
- `kubernetes/path2/` - K8s manifests
- `workshop/path2/` - Lab guides

## Service Principal (Optional)

If deploying via CI/CD, create a service principal:

```powershell
az ad sp create-for-rbac --name "agents-workshop-sp" --role Contributor --scopes /subscriptions/<subscription-id>
```

Save the output (appId, password, tenant) securely.

## Network Requirements

Ensure your network allows:

- Azure portal and Microsoft Foundry portal (`https://ai.azure.com`) access
- Azure CLI authentication
- Container registry push/pull
- AKS API server access

## Estimated Costs

**Path 2 workshop infrastructure monthly cost:**

- Azure AI Search (Basic): ~$75
- AKS (2-node cluster, D2s_v3): ~$140
- Microsoft Foundry (S0): Base ~$0 + model usage based on GPT-5.4-mini token consumption
- Azure Storage (Standard LRS): ~$5
- Container Registry (Standard): ~$5
- Key Vault: ~$0.03
- Application Insights: ~$2.30 + data ingestion
- **Total: ~$230-245/month + usage**

> **Important:** Delete all resources after completing the workshop to avoid ongoing charges.

## Pre-Workshop Checklist

- [ ] Azure subscription with appropriate permissions and model quota
- [ ] Access to the Microsoft Foundry portal (`https://ai.azure.com`)
- [ ] PowerShell 7.0+ installed and working
- [ ] Azure CLI 2.50.0+ installed and authenticated
- [ ] Required Azure resource providers registered
- [ ] kubectl installed
- [ ] Git installed
- [ ] Repository cloned locally
- [ ] Azure PowerShell modules installed
- [ ] Azure CLI extensions (aks-preview) installed
- [ ] Network connectivity verified
- [ ] Aware of estimated costs
- [ ] (Optional) .NET 10.0 SDK for local development

## Troubleshooting

### PowerShell Execution Policy

If scripts won't run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Azure CLI Authentication Issues

```powershell
az logout
az login --use-device-code
```

## Next Steps

Once all prerequisites are met, proceed to [Lab 1: Deploy Infrastructure](01-deploy-infrastructure.md).

## Support

For issues during setup:

1. Check error messages carefully
2. Verify versions of all tools
3. Ensure Azure subscription has necessary quotas
4. Review Azure service health status

## Additional Resources

- [Microsoft Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure PowerShell Documentation](https://learn.microsoft.com/powershell/azure/)
- [Azure CLI Documentation](https://learn.microsoft.com/cli/azure/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
