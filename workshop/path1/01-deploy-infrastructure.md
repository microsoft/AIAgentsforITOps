# Lab 1: Deploy Infrastructure

## Overview

In this lab, you'll deploy all the Azure resources needed for the Path 1 custom agent using the provided PowerShell deployment script, then deploy the application to AKS.

**Time:** 40-55 minutes (infrastructure: 30-45 min, application: 5-10 min)  
**Difficulty:** Beginner

## Objectives

- Deploy Azure infrastructure using PowerShell automation
- Configure deployment parameters
- Deploy the agent application to AKS
- Verify successful resource provisioning and application deployment
- Test the running agent application

## What Gets Deployed

This deployment creates a complete environment for running a custom AI agent on AKS:

| Resource | Purpose |
|----------|---------|
| **Resource Group** | Container for all resources |
| **Azure Storage** | Stores conference documents for search indexing |
| **Azure AI Search** | Indexes and searches conference content |
| **Azure OpenAI** | GPT-4.1-mini model for natural language generation |
| **Container Registry** | Stores container images for AKS |
| **Key Vault** | Securely stores secrets (endpoints, connection strings) |
| **Application Insights** | Monitoring and telemetry |
| **AKS Cluster** | Hosts the agent web application |
| **Managed Identities** | Enables secure service-to-service authentication |

**Estimated deployment time:** 30-45 minutes (automated)

---

## Step 1: Configure Parameters

Navigate to the Path 1 infrastructure folder:

```powershell
# From repository root
cd infrastructure/path1
```

Copy the example parameters file:

```powershell
Copy-Item .\parameters.json.example .\parameters.json
```

Edit the parameters:

```powershell
notepad parameters.json
```

On Notepad, update the parameters with your values:

```json
{
  "subscriptionId": "<your-azure-subscription-id>",
  "tenantId": "<your-azure-tenant-id>",
  "location": "<location>",
  "resourceGroupName": "<rg-name>",
  "resourcePrefix": "<prefixname>",
  "environment": "dev",
  "enablePrivateEndpoints": false,
  "enableMonitoring": true,
}
```

**Important parameters:**

- **subscriptionId**: Your Azure subscription ID (`az account show --query id -o tsv`)
- **location**: Azure region with OpenAI support (eastus, westus2, swedencentral)
- **resourcePrefix**: 3-10 lowercase letters/numbers (must be globally unique)
- **tenantId**: Your Azure AD tenant ID (`az account show --query tenantId -o tsv`)

**Save the file.**

---

## Step 2: Run Deployment

Execute the deployment script:

```powershell
.\deploy-infra.ps1
```

The script will:

1. ✅ Create Resource Group
2. ✅ Deploy Storage Account and upload conference documents
3. ✅ Create AI Search service and configure indexing
4. ✅ Deploy Azure OpenAI with GPT-4.1-mini model
5. ✅ Create Container Registry
6. ✅ Deploy Key Vault and store secrets
7. ✅ Set up Application Insights
8. ✅ Create AKS cluster with managed identity
9. ✅ Configure RBAC permissions

> 💡 **Tip:** You can open Azure Portal to watch resources being created in your resource group.

---

## Step 3: Verify Deployment

After deployment completes, verify the deployment output:

```powershell
# Check deployment output file
Get-Content .\deployment-output.json | ConvertFrom-Json | Format-List
```

**Expected output shows:**

- ✅ All resource names and endpoints
- ✅ Resource group name
- ✅ Subscription details

Quick verification:

```powershell
# List all deployed resources
az resource list --resource-group <your-resource-group> --output table
```

**You should see 10 resources** including AKS, OpenAI, Search, Storage, ACR, Key Vault, and App Insights.

---

## Step 4: Deploy the Application

Now that infrastructure is ready, deploy the agent application to AKS:

```powershell
# From the same directory (infrastructure/path1)
.\deploy-app.ps1
```

This script will:

1. ✅ Build the container image using **ACR Tasks** (no Docker Desktop needed)
2. ✅ Push the image to Azure Container Registry
3. ✅ Generate Kubernetes manifests with actual values
4. ✅ Deploy the application to AKS
5. ✅ Create a LoadBalancer service with external IP

**Expected timeline:** 5-10 minutes

### Test the Application

Once the application is deployed, the IP address of the LoadBalancer service will be displayed in the console output. You can open the application by using the provided URL.

Alternatively, you can retrieve the IP address and open the web application via:

```powershell
# Get the external IP
$externalIP = kubectl get service agent-webapp-service -n agent-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Write-Host "Application URL: http://$externalIP" -ForegroundColor Green

# Open in browser
Start-Process "http://$externalIP"
```

**You should see:**

- A chat interface
- Suggested questions about conferences
- Ability to ask questions and get AI-generated responses

**Try asking:** "What were the stations for Cloud Platform Expert Meet-up at Build 2024?"

---

## Next Steps

With the infrastructure deployed **and the application running**, you'll now explore how managed identities enable secure service-to-service authentication:

👉 **[Lab 2: Managed Identity](02-managed-identity.md)**

---

## Troubleshooting

### Issue: Resource name already exists

```powershell
# Edit parameters.json and use a different resourcePrefix
notepad parameters.json
# Then re-run: .\deploy-infra.ps1
```

### Issue: Key Vault soft-deleted

The deployment script automatically detects and purges soft-deleted Key Vaults (adds 30-60 seconds).

> **Workshop Configuration:** Key Vaults created by this workshop do NOT have purge protection enabled, allowing easy cleanup and redeployment. This is appropriate for dev/workshop environments but not for production.

If you see a purge error about "purge protection enabled":

```powershell
# This means a Key Vault with this name exists from outside this workshop
# Use a different resourcePrefix in parameters.json
notepad parameters.json
# Change: "resourcePrefix": "myprefix"  (use something unique)
# Then re-run
.\deploy-infra.ps1
```powershell
# This means a Key Vault with this name exists from outside this workshop
# Use a different resourcePrefix in parameters.json
notepad parameters.json
# Change: "resourcePrefix": "myprefix"  (use something unique)
# Then re-run
.\deploy-infra.ps1
```

### Issue: Insufficient quota for AKS

```powershell
# Check your VM quota
az vm list-usage --location eastus --query "[?localName=='Standard DSv3 Family vCPUs']" --output table

# If needed, request quota increase in Azure Portal
```

### Issue: Deployment fails partway through

```powershell
# Check deployment status in portal
az group show --name <your-resource-group> --query properties.provisioningState

# View activity log for errors
az monitor activity-log list --resource-group <your-resource-group> --max-events 20 --output table
```
