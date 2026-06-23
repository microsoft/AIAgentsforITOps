# Path 2: Foundry-Hosted Prompt Agent

## Overview

In this workshop path, you'll manage an **AI agent hosted in Microsoft Foundry**. Instead of writing and running agent code in your own containers (Path 1), you configure a **prompt agent** declaratively in the Foundry portal, ground it with a **Knowledge Base** over your documents, and host only a lightweight **chat UI** on Azure Kubernetes Service (AKS).

## Architecture

```markdown
┌─────────────┐
│   User      │
└──────┬──────┘
       │
       ▼
┌────────────────────────────────────────────┐
│  AKS Cluster                               │
│  ┌──────────────────────────────────────┐  │
│  │  Chat UI (.NET)                      │  │
│  │  - Calls the Foundry project         │  │
│  └───────────────────┬──────────────────┘  │
└──────────────────────┼─────────────────────┘
                       │ invoke agent
                       ▼
┌────────────────────────────────────────────┐
│  Microsoft Foundry                         │
│  ┌──────────────────────────────────────┐  │
│  │  Project                             │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │  Prompt    │──│  Knowledge     │──┼──┼──┐
│  │  │  Agent     │  │  Base          │  │  │  │
│  │  └─────┬──────┘  └────────────────┘  │  │  │
│  │        │ model                       │  │  │
│  │        ▼                             │  │  │
│  │  ┌────────────────┐                  │  │  │
│  │  │  Model         │                  │  │  │
│  │  │  Deployment    │                  │  │  │
│  │  └────────────────┘                  │  │  │
│  └──────────────────────────────────────┘  │  │
└────────────────────────────────────────────┘  │
                                                │ query
                                                ▼
                                          ┌──────────────┐
                                          │  Azure AI    │
                                          │   Search     │
                                          └──────┬───────┘
                                                 │
                                                 ▼
                                          ┌──────────────┐
                                          │   Storage    │
                                          │ (documents)  │
                                          └──────────────┘
```

## What You'll Learn

This workshop focuses on **infrastructure and platform management for Foundry-hosted agents**, not agent code development. You'll deploy the supporting Azure services, create a managed prompt agent, and learn to operate it.

### 1. **Infrastructure Deployment** (Lab 1)

- Deploy the Foundry resource, project, and model deployment
- Provision Azure AI Search and Storage for grounding data
- Create the Knowledge Base and the prompt agent
- Deploy the chat UI to AKS

### 2. **Managed Identity & RBAC** (Lab 2)

- Configure managed identities for Foundry, Search, and AKS
- Assign Foundry data-plane roles to the UI
- Grant Search and Storage access for the Knowledge Base
- Understand identity-based authentication across services

### 3. **Networking & Security** (Lab 3)

- Configure AKS networking for the UI
- Secure service-to-service communication to Foundry
- Understand VNet integration and private access patterns

### 4. **Secrets Management** (Lab 4)

- Configure Azure Key Vault Provider for CSI Driver
- Mount Foundry endpoints/secrets as read-only files in pods
- Manage application configuration securely

### 5. **Monitoring & Observability** (Lab 5)

- Use Foundry tracing to inspect agent runs
- Configure Application Insights for the UI and platform
- Analyze knowledge retrieval and model performance

### 6. **Cost Management** (Lab 6)

- Track Foundry model consumption and costs
- Monitor AKS and Search resource usage
- Implement cost alerts and budgets

### 7. **Foundry Control Plane** (Lab 7)

- **Assets** — inventory and govern models, deployments, connections, and knowledge
- **Compliance** — review content safety, policies, and data governance settings
- **Quota** — monitor and manage model capacity (TPM) and deployment limits
- **Admin** — manage project access, roles, and resource-level controls

## Key Differences from Path 1

| Aspect | Path 1 (Custom) | Path 2 (Foundry) |
|--------|-----------------|------------------|
| **Agent Location** | Runs in your AKS pods | Hosted in Foundry |
| **Code Control** | Full control over agent code | Declarative configuration |
| **LLM Integration** | Direct OpenAI SDK calls | Via Foundry models |
| **Grounding** | Search index + indexer (you build) | Knowledge Base (Foundry manages) |
| **Monitoring** | Application Insights in AKS | Foundry tracing + AKS |
| **AKS Role** | Hosts agent + UI | Hosts UI only |
| **Complexity** | Higher (more control) | Lower (managed service) |

## CLI-First, Portal Where Required

This path automates everything that the Azure CLI / Az PowerShell can create. Two
steps are **portal-only** because no CLI commands exist for them yet — the
**Knowledge Base** and the **prompt agent**. The prerequisites guide walks you
through those portal steps and explains *why* the portal is required.

## Prerequisites

Before starting this path, ensure you have:

- ✅ Completed [prerequisites](00-prerequisites.md)
- ✅ Access to the Microsoft Foundry portal (`https://ai.azure.com`)
- ✅ Basic understanding of Azure AI Search concepts
- ✅ Azure subscription with permissions to create:
  - Microsoft Foundry (Azure AI Services)
  - Azure AI Search
  - Azure Kubernetes Service
  - Managed Identities

## Workshop Labs

Follow these labs in order:

1. **[Deploy Infrastructure](01-deploy-infrastructure.md)** — Foundry, project, Knowledge Base, agent, and UI
2. **Managed Identity** — RBAC for Foundry, Search, and AKS *(in progress)*
3. **Networking** — AKS networking and secure access to Foundry *(in progress)*
4. **Secrets Management** — Key Vault CSI driver for the UI *(in progress)*
5. **Monitoring** — Foundry tracing and Application Insights *(in progress)*
6. **Cost Management** — Foundry, Search, and AKS cost control *(in progress)*
7. **Foundry Control Plane** — Assets, Compliance, Quota, and Admin *(in progress)*

> 📌 Labs 1–6 mirror Path 1 so you can compare the two approaches directly. Lab 7 is unique to Path 2 and covers the Foundry control plane for platform/infra management.
>
> 🚧 **Lab 1 is complete and deployable.** Labs 2–7 are still being written and will be linked here as they're published.

## Next Steps

👉 **[Start with Lab 0: Prerequisites](00-prerequisites.md)**

By the end of the prerequisites guide you'll have all infrastructure deployed **and a working prompt agent**, ready to begin the labs.

## Need Help?

- 📖 Review the lab instructions carefully
- 💬 Ask questions in GitHub Discussions
- 🐛 Report issues in GitHub Issues
