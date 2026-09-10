# AI Agents for IT/Ops Workshop

## Workshop Overview

This workshop teaches developers and IT/Ops professionals how to manage AI agents on Azure infrastructure. The focus is on **infrastructure management**, not agent development.

### Learning Objectives

Participants will learn to manage:

- **Managed Identity & RBAC**: Secure access between Azure services
- **Private Networking & VNets**: Network isolation and security
- **Secrets Management**: Azure Key Vault integration
- **Monitoring & Observability**: Application Insights and logging
- **Cost Management**: Resource optimization and budgeting

---

## 🎯 Choose Your Workshop Path

This workshop offers **two distinct paths** for managing AI agents on Azure. Both paths use the same conference expert agent scenario but differ in where and how the agent is hosted and managed.

### Path 1: Custom Agent on AKS with Microsoft Foundry

**Best for:** Teams managing their own agent infrastructure, containerized deployments

**Architecture:**

- ✅ **Agent runs entirely on AKS** - Full control over hosting and scaling
- ✅ **Direct Foundry model integration** - Agent calls a `gpt-5.4-mini` deployment through the OpenAI-compatible Responses API
- ✅ **RAG pattern in code** - Custom implementation of retrieval + generation
- ✅ **AKS-centric monitoring** - Application Insights integrated in pods

**Infrastructure you'll manage:**

- AKS cluster configuration and scaling
- Microsoft Foundry account, project, and model deployment
- Container registry and image management
- Direct service-to-service authentication and networking
- Custom agent code deployment

**When to choose this path:**

- You want full control over agent hosting
- You're building custom agents with specific requirements
- You need to manage agents as part of Kubernetes workloads
- You want to understand RAG implementation details

👉 **[Start Path 1: Custom Agent Workshop](workshop/path1/README.md)**

---

### Path 2: Foundry-Hosted Agent with Knowledge Base

**Best for:** Teams using Microsoft Foundry for managed agent hosting

**Architecture:**

- ✅ **Agent hosted in Microsoft Foundry** - Managed scaling and hosting
- ✅ **Foundry Knowledge Base** - Declarative knowledge configuration
- ✅ **AKS hosts UI only** - Lightweight web frontend
- ✅ **Foundry-centric monitoring** - Agent tracing and evaluation in Foundry

**Infrastructure you'll manage:**

- Foundry project and agent deployments
- Knowledge base configuration and indexing
- AKS cluster for web UI hosting (For workshop purposes. Could be deployed on different Azure service)
- Foundry-to-services authentication and networking
- Agent lifecycle in Foundry portal

**When to choose this path:**

- You want managed agent hosting and lifecycle
- You prefer declarative agent configuration
- You need built-in evaluation and monitoring
- You want visibility in the Foundry portal

👉 **[Start Path 2: Foundry-Hosted Agent Workshop](workshop/path2/README.md)**

---

## 🚀 Common Prerequisites

**Both paths require:**

- Azure subscription with Owner or Contributor access
- PowerShell 7.0 or later
- Azure CLI 2.50.0 or later
- kubectl CLI
- .NET 8.0 SDK (optional, for local development)

---

## Sample Agent: Conference Expert

Both paths implement the same agent experience - answering questions about Microsoft Ignite and Build Expert Meet-up.

**User Experience (identical for both paths):**

- Web-based chat interface
- Natural language Q&A about conference sessions
- Intelligent responses using data not available in the model's training set
- Real-time interaction

**Sample Questions:**

- "What is the Cloud Platform Expert Meet-up at Build?"
- "Tell me about Infrastructure Expert Meet-ups at Ignite"
- "How many Expert Meet-up stations were there at Ignite 2025?"

---

## Repository Structure

> **Note:** Each workshop path is **fully self-contained** with its own infrastructure scripts, application code, Kubernetes manifests, and workshop guides. **Both paths are implemented and deployable.**

```markdown
AgentsforITOps/
├── Documents/                      # Conference data files (shared)
│   ├── Build2024.docx
│   ├── Build2025.docx
│   ├── Ignite2024.docx
│   └── Ignite2025.docx
│
├── infrastructure/
│   ├── path1/                      # Path 1: Custom Agent infrastructure
│   │   ├── deploy-infra.ps1       # Main deployment for custom agent
│   │   ├── deploy-app.ps1         # App deployment to AKS
│   │   ├── modules/
│   │   │   ├── storage.ps1
│   │   │   ├── search.ps1
│   │   │   ├── foundry.ps1        # Foundry account, project, and model deployment
│   │   │   ├── aks.ps1
│   │   │   ├── acr.ps1
│   │   │   ├── keyvault.ps1
│   │   │   └── monitoring.ps1
│   │   └── parameters.json.example
│   │
│   ├── path2/                      # Path 2: Foundry Agent infrastructure
│   │   ├── deploy-infra.ps1       # Provisions Foundry, project, model, Search, AKS
│   │   ├── deploy-app.ps1         # Verifies the agent and deploys the UI to AKS
│   │   ├── modules/
│   │   │   ├── foundry.ps1        # Foundry resource, project, model deployment
│   │   │   ├── search.ps1
│   │   │   ├── storage.ps1
│   │   │   ├── aks.ps1
│   │   │   ├── acr.ps1
│   │   │   ├── keyvault.ps1
│   │   │   ├── monitoring.ps1
│   │   │   ├── network.ps1
│   │   │   └── rbac.ps1
│   │   └── parameters.json.example
│   │
│   └── common/                     # Shared infrastructure modules
│       ├── common.ps1             # Common functions
│       └── validation.ps1         # Validation helpers
│
├── src/
│   ├── path1/                      # Path 1: Custom Agent application
│   │   └── agent-webapp/           # Full .NET custom RAG app using a Foundry model
│   │       ├── Controllers/
│   │       ├── Models/
│   │       ├── Services/
│   │       │   ├── AgentService.cs        # Search grounding + Foundry Responses API
│   │       │   └── SearchService.cs       # Azure AI Search client
│   │       ├── Program.cs
│   │       └── Dockerfile
│   │
│   └── path2/                      # Path 2: Foundry Agent application
│       └── agent-webapp/           # Lightweight .NET chat UI (calls Foundry agent)
│           ├── Controllers/
│           ├── Models/
│           ├── Services/
│           │   └── FoundryAgentService.cs # Calls the Foundry agent (Responses API)
│           ├── wwwroot/            # Chat UI front-end
│           ├── Program.cs
│           └── Dockerfile
│
├── kubernetes/
│   ├── path1/                     # Path 1: Custom agent manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── secretproviderclass.yaml
│   │   └── configmap.yaml
│   │
│   └── path2/                     # Path 2: Foundry agent manifests (UI only)
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── secretproviderclass.yaml
│       └── serviceaccount.yaml
│
└── workshop/                      # Workshop guides
    ├── 00-prerequisites.md        # Common prerequisites
    │
    ├── path1/                     # Path 1: Custom Agent Workshop
    │   ├── README.md              # Path 1 overview
    │   ├── 01-deploy-infrastructure.md
    │   ├── 02-managed-identity.md
    │   ├── 03-networking.md
    │   ├── 04-secrets-management.md
    │   ├── 05-monitoring.md
    │   └── 06-cost-management.md
    │
    └── path2/                     # Path 2: Foundry Agent Workshop
        ├── README.md              # Path 2 overview
        ├── 00-prerequisites.md
        └── 01-deploy-infrastructure.md  # (Labs 02–07 in progress)
```

---

## Cost Estimates

**Estimated monthly cost for the workshop environment:**

### Path 1: Custom Agent on AKS + Microsoft Foundry

- Azure AI Search (Basic): ~$75/month
- AKS (1-node cluster, D2s_v3): ~$75/month
- Microsoft Foundry model inference: usage-based `gpt-5.4-mini` token charges
- Azure Storage (Standard LRS): ~$5/month
- Container Registry (Basic): ~$5/month
- Key Vault: ~$0.03/month
- Application Insights: ~$2.30/month + data ingestion
- **Total**: ~$167-177/month + usage

### Path 2: Foundry-Hosted Agent

- Azure AI Search (Basic): ~$75/month
- AKS (1-node cluster, D2s_v3): ~$75/month
- Microsoft Foundry model (GPT-5.4-mini): Base ~$0 + usage based on token consumption
- Azure Storage (Standard LRS): ~$5/month
- Container Registry (Basic): ~$5/month
- Key Vault: ~$0.03/month
- Application Insights: ~$2.30/month + data ingestion
- **Total**: ~$167-177/month + usage

> **Note:** AKS hosts only the chat UI in Path 2 (the agent runs in Foundry), so it
> can be sized smaller or swapped for a lighter compute service to reduce cost.

> **💡 Tip**: Delete resources after completing the workshop to avoid ongoing charges.

> **Note**: Actual costs may vary based on usage patterns, data transfer, and regional pricing.

---

## Contributing

Contributions are welcome! Please submit issues and pull requests.

## License

This project is licensed under the MIT License.

## Support

For questions or issues, please open a GitHub issue or contact the maintainers.
