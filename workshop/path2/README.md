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

## Key Differences from Path 1

| Aspect | Path 1 (Custom) | Path 2 (Foundry) |
| --- | --- | --- |
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
2. **[Managed Identity](02-managed-identity.md)** — RBAC for Foundry, Search, Storage, and the AKS UI
3. **[Networking](03-networking.md)** — Private inbound access to Foundry and outbound isolation concepts
4. **[Secrets Management](04-secrets-management.md)** — Key Vault CSI configuration for the UI and Foundry asset boundaries
5. **[Monitoring](05-monitoring.md)** — Foundry traces, evaluations, Application Insights, and platform telemetry
6. **[Cost Management](06-cost-management.md)** — Foundry model, Search, AKS, and observability cost controls

## Next Steps

👉 **[Start with Lab 0: Prerequisites](00-prerequisites.md)**

By the end of the prerequisites guide you'll have all infrastructure deployed **and a working prompt agent**, ready to begin the labs.

## Need Help?

- 📖 Review the lab instructions carefully
- 💬 Ask questions in GitHub Discussions
- 🐛 Report issues in GitHub Issues
