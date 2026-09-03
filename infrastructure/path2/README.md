# Path 2 Infrastructure — Microsoft Foundry Prompt Agent

This directory deploys the Azure infrastructure for **Path 2**, where the agent is a
**Microsoft Foundry hosted prompt agent** rather than a custom container running on AKS.

## What gets deployed

| Resource | Created by | Purpose |
|----------|-----------|---------|
| Resource Group | Az PowerShell | Container for all resources |
| Storage Account | Az PowerShell | Conference documents — the **Knowledge Source** |
| Azure AI Search | Azure CLI | Backing store for the Foundry **Knowledge Base** |
| Microsoft Foundry (AIServices) | Azure CLI | Hosts the project, model, and prompt agent |
| Foundry project | Azure CLI | Container for agents, knowledge, evaluations |
| Model deployment | Azure CLI | The LLM the agent reasons with (default `gpt-5.4-mini`) |
| Container Registry | Azure CLI | Stores the UI image |
| AKS cluster | Azure CLI | Hosts the **UI only** (not the agent) |
| Key Vault | Azure CLI | Stores endpoints/secrets for the UI |
| Application Insights | Azure CLI | Telemetry and monitoring |
| VNet + Private Endpoints | Az PowerShell | Optional private networking |
| RBAC assignments | Azure CLI | Managed-identity access between services |

## CLI-first, portal where required

Everything that **can** be created from the CLI is automated by `deploy-infra.ps1`.
Two steps are **portal-only** because no CLI/ARM commands exist for them yet:

1. **Knowledge Base** — connects the Search service and Storage container, and manages
   vectorization/ingestion. Created in the Foundry portal (`https://ai.azure.com`).
2. **Prompt agent** — the model + instructions + knowledge. Created in the Foundry
   portal (or via the `azure-ai-projects` Python SDK).

When the deployment finishes, the script prints clearly-marked **MANUAL PORTAL STEP**
blocks (Step A and Step B) with the exact resource names to use, and explains *why*
each step must be done in the portal.

## How the agent reaches the documents

```
Storage (conference-data)  --read-->  Azure AI Search  -->  Foundry Knowledge Base
                                                                   |
                                                                   v
                                                            Prompt Agent (Foundry)
                                                                   ^
                                                                   | invoke
                                                            UI pod on AKS
```

Unlike Path 1, **no index or indexer is created by the scripts** — the Foundry
Knowledge Base provisions and manages those when you connect the Search service in
the portal (Step A).

## Usage

```powershell
# 1. Copy and fill in parameters
Copy-Item .\parameters.json.example .\parameters.json
# edit parameters.json with your subscription, region, prefix, etc.

# 2. Deploy the infrastructure (CLI-creatable resources)
.\deploy-infra.ps1

# 3. Complete portal Step A (Knowledge Base) and Step B (prompt agent)
#    using the names printed at the end of the deployment.

# 4. Deploy the UI to AKS
.\deploy-app.ps1
```

## Structure

```
infrastructure/path2/
├── deploy-infra.ps1            # Main orchestrator (this folder)
├── parameters.json.example     # Configuration template
└── modules/
    ├── common.ps1              # Logging + portal-step helpers
    ├── resource-group.ps1      # Resource group
    ├── storage.ps1             # Storage + document upload
    ├── search.ps1              # Azure AI Search (no index/indexer)
    ├── foundry.ps1             # Foundry resource + project + model
    ├── acr.ps1                 # Container registry
    ├── aks.ps1                 # AKS (UI host)
    ├── keyvault.ps1            # Key Vault + secrets
    ├── monitoring.ps1          # Application Insights
    ├── network.ps1             # VNet (optional)
    └── rbac.ps1                # RBAC assignments
```
