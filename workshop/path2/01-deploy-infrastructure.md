# Lab 1: Deploy Infrastructure, Agent & Application

## Overview

In this lab, you'll deploy all the Azure resources needed for the Path 2 Foundry-hosted agent, create the prompt agent in the Foundry portal, and deploy the chat UI to AKS. By the end you'll have a **fully functional agent** answering questions about your documents.

**Time:** 50-65 minutes (infrastructure: 30-45 min, agent setup: 10-15 min, application: 5-10 min)  
**Difficulty:** Beginner

## Objectives

- Deploy Azure infrastructure using PowerShell automation
- Configure deployment parameters
- Create the Foundry Knowledge Base and prompt agent (portal)
- Deploy the chat UI to AKS
- Verify successful provisioning and test the agent

## What Gets Deployed

This deployment creates a complete environment for running a Foundry-hosted prompt agent:

| Resource | Purpose |
|----------|---------|
| **Resource Group** | Container for all resources |
| **Azure Storage** | Stores conference documents (the Knowledge Source) |
| **Azure AI Search** | Backing store for the Foundry Knowledge Base |
| **Microsoft Foundry** | Hosts the project, model, and prompt agent |
| **Foundry Project** | Container for agents, knowledge, and evaluations |
| **Model Deployment** | The LLM the agent reasons with (default GPT-4.1-mini) |
| **Container Registry** | Stores the UI container image |
| **Key Vault** | Securely stores endpoints and connection strings |
| **Application Insights** | Monitoring and telemetry |
| **AKS Cluster** | Hosts the chat UI (the agent runs in Foundry) |
| **Managed Identities** | Enables secure service-to-service authentication |

**Estimated deployment time:** 30-45 minutes (automated)

> **CLI-first, portal where required:** The deployment script creates everything that
> can be made from the CLI. Two steps — the **Knowledge Base** and the **prompt agent** —
> have no CLI commands yet and are done in the Foundry portal (Steps 4 and 5 below),
> with an explanation of why.

---

## Step 1: Configure Parameters

Navigate to the Path 2 infrastructure folder:

```powershell
# From repository root
cd infrastructure/path2
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
  "modelName": "gpt-4.1-mini"
}
```

**Important parameters:**

- **subscriptionId**: Your Azure subscription ID (`az account show --query id -o tsv`)
- **location**: Azure region with Foundry + model support (eastus, westus2, swedencentral)
- **resourcePrefix**: 3-10 lowercase letters/numbers (must be globally unique)
- **tenantId**: Your Azure AD tenant ID (`az account show --query tenantId -o tsv`)
- **modelName**: Model to deploy for the agent (default `gpt-4.1-mini`)

**Save the file.**

---

## Step 2: Run Deployment

Execute the deployment script:

```powershell
.\deploy-infra.ps1
```

The script will:

1. ✅ Create Resource Group
2. ✅ Deploy Storage Account and upload conference documents (the Knowledge Source)
3. ✅ Create AI Search service (Knowledge Base backing store — no index/indexer yet)
4. ✅ Deploy Microsoft Foundry resource, project, and the model deployment
5. ✅ Create Container Registry
6. ✅ Deploy Key Vault and store secrets
7. ✅ Set up Application Insights
8. ✅ Create AKS cluster with managed identity
9. ✅ Configure RBAC permissions
10. ✅ Print the two portal-only steps (Knowledge Base + prompt agent)

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
- ✅ Foundry resource, project name, and project endpoint
- ✅ Resource group name

Quick verification:

```powershell
# List all deployed resources
az resource list --resource-group <your-resource-group> --output table
```

Note these values from `deployment-output.json` — you'll use them in the portal steps:

- `resources.foundry` — the Foundry resource name
- `resources.foundryProject` — the project name
- `resources.searchService` — the Search service name
- `resources.storageAccount` — the Storage account name
- `foundry.deploymentName` — the deployed model name
- `endpoints.foundryProject` — the project endpoint (for the UI)

---

## Step 4: Create the Knowledge Base (Portal)

> **Why the portal?** Azure Search **Knowledge Bases** and **Knowledge Sources** have no
> Azure CLI commands today. They must be created in the Azure portal, which
> wires together the Search service, document vectorization, and the ingestion
> pipeline for you. This is the first place the workshop switches from CLI to portal.

### Step 4.1: Create the Knowledge Base in Azure AI Search

1. Open the Azure portal at `https://portal.azure.com` and sign in.
2. Navigate to the Resource Group created in this workshop, and open the Azure AI Search resource (the `searchService` name from `deployment-output.json`).
3. On the Search service page, expand **Agentic retrieval** and click **Knowledge sources** in the left menu.
4. Click **+ Add knowledge source**.
5. Select **Azure Blob (Indexed)** as the source type.
6. Fill out the information for the Azure blob (Indexed) knowledge source:

   - **Name:** `conference-knowledge-source`
   - **Subscription:** your Azure subscription
   - **Storage account:** the `storageAccount` from `deployment-output.json`
   - **Blob container:** `conference-data`
   - **Blob folder:** leave blank (all blobs in the container)
   - **Content extraction:** leave default (Mode should be set to Minimal and set to use Managed Identity)
   - **Vectorization/embedding settings:** leave default
  
7. Click **Create** to create the knowledge source.
8. Once the knowledge source is created, click **Create a knowledge base**. (If you accidentally close the page, you can also click **Knowledge bases** in the left menu and then click **+ Add knowledge base**.)
9. Fill out the information needed:
    - **Name:** `conference-knowledge-base`
    - **Knowledge source:** Make sure the knowledge source listed is the one you just created (`conference-knowledge-source`)
    - **Retrieval:** Change **Reasoning effort** to **Minimal** (All reasoning will be done in Foundry, so we don't need the reasoning to happen in Search.)
10. Click **Create knowledge base** to create the knowledge base.
11. Close the AI Search playground and return to the Azure AI Search resource.
12. Expand **Search management** and click **Indexers** in the left menu. You should see the status **Success** for an index named `conference-knowledge-source-indexer` created by the knowledge base with the **Docs succeeded** count of 4 (the four conference documents).

With the Knowledge source and base created, you can close the Azure AI Search page.

## Step 4.2: Connect Microsoft Foundry to Azure AI Search Knowledge Base

1. If not there already, open the Azure portal at `https://portal.azure.com` and sign in.
2. Navigate to the Resource Group created in this workshop, and open the Foundry resource (the `foundry` name from `deployment-output.json`).
3. On the Foundry resource page, click the "Go to Foundry portal" button.
4. On the Foundry portal, select your project (the `foundryProject` name from `deployment-output.json`).
5. On the Foundry resource page, click **Go to Foundry portal** to open the Foundry portal in a new tab.
6. On the Microsoft Foundry page, click **Tools** on the top-right menu, then click **Connect a tool** in the main menu.
7. On the Select a tool page, select **Azure AI Search** and click **Add tool**.
8. On the Create a new connection page, select the following:

   - **Azure AI Search:** the `searchService` from `deployment-output.json`
   - **Authentication method:** Project Managed Identity

9. Click **Connect** to create the connection.
10. On the left-hand menu, click **Knowledge**. Note that the Knowledge Base you created in Step 4.1 (`conference-knowledge-base`) is listed as **Active**. This Knowledge Base is now connected to your Foundry project and can be used by the prompt agent.

---

## Step 5: Create the Prompt Agent (Portal)

> **Why the portal?** **Prompt agents cannot be created with the Azure CLI.** You
> create them in the Foundry portal (or with the `azure-ai-projects` Python SDK). The
> portal is the guided experience used in this workshop.

1. If not there already, open the Foundry portal at `https://ai.azure.com`.
2. On the top-right menu, click **Build** and open the **Agents** menu on the right-hand side menu.
3. Select **+ New agent**, and then **Build an agent**.
4. On the Create an agent page, set the **Agent name** to exactly `conference-expert-agent` and click **Create**.

   > **Important:** Keep the name `conference-expert-agent`. The `deploy-app.ps1`
   > script verifies the agent **by this name** and stores it for the UI to call, so the
   > name must match (or you must pass `-AgentName` later).

5. With the agent open, configure it as the following:
   - **Deployment / Model:** select the deployed model `gpt-4.1-mini`.
   - **Instructions:** paste the persona below.

   ```text
   You are a helpful Expert Meet-up conference assistant specializing in Microsoft Ignite
   and Build conferences. Your role is to answer questions about the Expert Meet-up
   at these conferences.

   When answering:
   - Pay CLOSE ATTENTION to years/dates in the question (e.g., 2024 vs 2025).
   - Only use information from the CORRECT year mentioned in the question.
   - Be concise and direct (3-4 sentences when possible).
   - Use the connected knowledge base to ground every response.
   - If the knowledge base doesn't contain information for the specific year
     requested, say so clearly.
   - Focus on helping users understand expert areas.
   - Don't make up information - only use what's in the knowledge base.
   - Always mention which conference and year you're answering about.
   ```

6. Under **Knowledge**, click **Add** and select the **Connect to Foundry IQ**. On the Connect to Foundry IQ pop-up window, select the connection with the AI Search and attach the Knowledge Base you connected in Step 4 (`conference-knowledge-base`). This is what lets the agent ground its answers in the conference documents.
7. On the **Playground** chat area, test the agent:
   *"What were the stations for Cloud Platform Expert Meet-up at Build 2024?"*
   Confirm the answer is grounded (it should reference the conference documents).
8. Click **Save** on the top-right to save the agent configuration.

## Step 6: Deploy the Application

Now that the agent is working, deploy the chat UI to AKS:

```powershell
# From the same directory (infrastructure/path2)
.\deploy-app.ps1
```

New Foundry prompt agents are addressed by **name**, so the script **verifies the agent exists** (`conference-expert-agent`) through the Foundry data plane, then stores that name in Key Vault as the
`Foundry-AgentName` secret. If you named the agent differently, pass it explicitly:

```powershell
.\deploy-app.ps1 -AgentName "<your-agent-name>"
```

This script will:

1. ✅ Verify the Foundry **prompt agent** by name and store it in Key Vault (`Foundry-AgentName`)
2. ✅ Build the container image using **ACR Tasks** (no Docker Desktop needed)
3. ✅ Push the image to Azure Container Registry
4. ✅ Generate Kubernetes manifests with actual values
5. ✅ Deploy the application to AKS
6. ✅ Create a LoadBalancer service with external IP

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
- Ability to ask questions and get answers from the Foundry-hosted agent

**Try asking:** "What were the stations for Cloud Platform Expert Meet-up at Build 2024?"

---

## Next Steps

With the infrastructure deployed, the agent running in Foundry, **and the UI working**, you'll now explore how managed identities enable secure service-to-service authentication:

👉 **[Lab 2: Managed Identity](02-managed-identity.md)**

---

## Troubleshooting

### Issue: Resource name already exists

```powershell
# Edit parameters.json and use a different resourcePrefix
notepad parameters.json
# Then re-run: .\deploy-infra.ps1
```

### Issue: Model deployment failed (quota or SKU)

```powershell
# Check Cognitive Services usage/quota in your region
az cognitiveservices usage list --location eastus -o table
```

If `GlobalStandard` capacity is unavailable, the deployment script automatically retries with the `Standard` SKU. If both fail, request a quota increase or choose a different region in `parameters.json`.

### Issue: Key Vault soft-deleted

The deployment script automatically detects and purges soft-deleted Key Vaults (adds 30-60 seconds).

> **Workshop Configuration:** Key Vaults created by this workshop do NOT have purge protection enabled, allowing easy cleanup and redeployment. This is appropriate for dev/workshop environments but not for production.

### Issue: Agent returns "no information"

- Confirm the Knowledge Base ingestion run finished (Step 4).
- Confirm the documents are present in the `conference-data` container:

  ```powershell
  az storage blob list --account-name <storageAccount> --container-name conference-data --auth-mode login -o table
  ```

### Issue: Foundry project not visible in the portal

- Confirm you're signed in to the same tenant/subscription used for deployment.
- Verify the project exists:

  ```powershell
  az cognitiveservices account project show --name <foundry> --resource-group <rg> --project-name <project>
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
