# Lab 0: Prerequisites (Path 1)

## Overview

Before starting the **Path 1: Custom Agent on AKS** workshop, ensure you have all the necessary tools and accounts configured.

> **Note:** This prerequisites guide is specific to Path 1. Path 2 (Foundry-Hosted Agent) has different requirements.

## Required Accounts

### Azure Subscription

- Active Azure subscription with Owner or Contributor access
- Sufficient quota for:
  - Virtual Machines (for AKS nodes)
  - Azure AI Services
  - Azure Cognitive Search
- No policy restrictions that would block resource creation

**To verify:**

```powershell
az account show
az account list-locations -o table
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

### kubectl (Kubernetes CLI)

**Installation:**

```powershell
az aks install-cli
```

**Verify:**

```powershell
kubectl version --client
```

> **Note:** Path 1 uses **ACR Tasks** to build container images directly in Azure. You do NOT need Docker Desktop installed locally. This simplifies the workshop setup and eliminates Docker Desktop licensing requirements.

### .NET 8.0 SDK (Optional - for local development only)

**Installation:**

```powershell
winget install Microsoft.DotNet.SDK.8
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
- `src/path1/agent-webapp/` - Web application code
- `infrastructure/path1/` - Deployment scripts
- `kubernetes/path1/` - K8s manifests
- `workshop/path1/` - Lab guides

## Service Principal (Optional)

If deploying via CI/CD, create a service principal:

```powershell
az ad sp create-for-rbac --name "agents-workshop-sp" --role Contributor --scopes /subscriptions/<subscription-id>
```

Save the output (appId, password, tenant) securely.

## Network Requirements

Ensure your network allows:

- Azure portal access
- Azure CLI authentication
- Container registry push/pull
- AKS API server access

## Estimated Costs

**Path 1 workshop infrastructure monthly cost:**

- Azure AI Search (Basic): ~$75
- AKS (1-node cluster, D2s_v3): ~$75
- Azure OpenAI (S0): Base ~$0 + usage ~$5-15/month (GPT-4.1-mini)
- Azure Storage (Standard LRS): ~$5
- Container Registry (Standard): ~$5
- Key Vault: ~$0.03
- Application Insights: ~$2.30 + data ingestion
- **Total: ~$167-177/month + usage**

> **Important:** Delete all resources after completing the workshop to avoid ongoing charges.

## Pre-Workshop Checklist

- [ ] Azure subscription with appropriate permissions
- [ ] PowerShell 7.0+ installed and working
- [ ] Azure CLI 2.50.0+ installed and authenticated
- [ ] kubectl installed
- [ ] Git installed
- [ ] Repository cloned locally
- [ ] Azure PowerShell modules installed
- [ ] Azure CLI extensions (aks-preview) installed
- [ ] Network connectivity verified
- [ ] Aware of estimated costs
- [ ] (Optional) .NET 8.0 SDK for local development

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

- [Azure PowerShell Documentation](https://learn.microsoft.com/powershell/azure/)
- [Azure CLI Documentation](https://learn.microsoft.com/cli/azure/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [.NET Documentation](https://learn.microsoft.com/dotnet/)
