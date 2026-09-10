# Path 1: Custom Agent on AKS with Microsoft Foundry

## Overview

In this workshop path, you'll learn to manage a **custom AI agent running on Azure Kubernetes Service (AKS)**. Retrieval and orchestration remain in the .NET application: it searches Azure AI Search, assembles grounded context and citations, and calls a `gpt-5.4-mini` model deployment in Microsoft Foundry through its OpenAI-compatible Responses API. It does not invoke a Foundry-hosted prompt agent.

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
│  │  Agent Web App (.NET)                │  │
│  │  ┌────────────┐  ┌────────────────┐  │  │
│  │  │  Chat UI   │  │  Agent Service │  │  │
│  │  └────────────┘  └────┬───────────┘  │  │
│  │                       │              │  │
│  └───────────────────────┼──────────────┘  │
└────────────────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
         ▼                ▼                ▼
  ┌──────────┐    ┌──────────────┐  ┌──────────┐
   │ Microsoft│    │  Azure AI    │  │   Key    │
   │ Foundry  │    │   Search     │  │  Vault   │
  └──────────┘    └──────────────┘  └──────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Storage    │
                  │   Account    │
                  └──────────────┘
```

## What You'll Learn

This workshop focuses on **infrastructure management for AI agents**, not agent development. You'll learn to deploy and manage the Azure infrastructure that supports custom agents running on AKS.

### 1. **Infrastructure Deployment** (Lab 1)

- Deploy AKS cluster for agent hosting
- Provision a Microsoft Foundry account, project, `gpt-5.4-mini` deployment, and Azure AI Search
- Set up Azure Container Registry for image management
- Configure Storage Account for document indexing
- Deploy Key Vault for secrets management
- Set up Application Insights for monitoring

### 2. **Managed Identity & RBAC** (Lab 2)

- Configure AKS kubelet managed identity
- Assign RBAC roles for Foundry model inference
- Set up permissions for Azure AI Search
- Grant Key Vault Secrets User access
- Understand identity-based authentication

### 3. **Networking & Security** (Lab 3)

- Configure AKS networking and service endpoints
- Implement network security groups
- Set up secure service-to-service communication
- Understand VNet integration patterns
- Review network traffic flow

### 4. **Secrets Management** (Lab 4)

- Configure Azure Key Vault Provider for CSI Driver
- Mount secrets as read-only files in pods
- Manage application secrets securely
- Understand CSI driver architecture
- Avoid storing secrets in Kubernetes

### 5. **Monitoring & Observability** (Lab 5)

- Configure Application Insights for AKS pods
- Set up distributed tracing
- Monitor Foundry model token usage
- Create custom dashboards
- Analyze application performance

### 6. **Cost Management** (Lab 6)

- Monitor and optimize AKS resource usage
- Track Foundry model consumption and costs
- Implement cost alerts and budgets
- Understand pricing models
- Optimize resource allocation

## Key Differences from Path 2

| Aspect | Path 1 (Custom) | Path 2 (Foundry) |
|--------|-----------------|------------------|
| **Agent Location** | Runs in your AKS pods | Hosted in Foundry |
| **Code Control** | Full control over agent code | Declarative configuration |
| **LLM Integration** | Direct Responses API call to a Foundry model deployment | Foundry-hosted prompt agent invokes a model |
| **Monitoring** | Application Insights in AKS | Foundry tracing + AKS |
| **Deployment** | Docker + Kubernetes | Foundry deployment API |
| **Scaling** | Pod autoscaling | Foundry managed |
| **Complexity** | Higher (more control) | Lower (managed service) |

## Prerequisites

Before starting this path, ensure you have:

- ✅ Completed [prerequisites](00-prerequisites.md)
- ✅ Familiarity with Docker and Kubernetes concepts
- ✅ Basic understanding of .NET applications
- ✅ Azure subscription with permissions to create:
  - Azure Kubernetes Service
   - Microsoft Foundry
  - Azure AI Search
  - Managed Identities

## Workshop Labs

Follow these labs in order:

1. **[Deploy Infrastructure](01-deploy-infrastructure.md)** *(~45 minutes)*
   - Deploy AKS, Foundry, Search, and supporting services
   - Configure networking and managed identities
   - Set up Key Vault and secrets

2. **[Managed Identity](02-managed-identity.md)** *(~30 minutes)*
   - Configure kubelet identity
   - Set up RBAC for Foundry, Search, and Key Vault
   - Test managed identity authentication

3. **[Networking](03-networking.md)** *(~45 minutes)*
   - Configure AKS networking
   - Set up network security groups
   - Implement service mesh concepts

4. **[Secrets Management](04-secrets-management.md)** *(~30 minutes)*
   - Configure Key Vault CSI driver
   - Mount secrets as files
   - Secure credential management

5. **[Monitoring](05-monitoring.md)** *(~40 minutes)*
   - Configure Application Insights
   - Set up custom metrics
   - Create dashboards

6. **[Cost Management](06-cost-management.md)** *(~30 minutes)*
   - Monitor Foundry model token usage
   - Optimize AKS resources
   - Set up cost alerts

**Total estimated time:** ~4-5 hours

## Next Steps

👉 **[Start Lab 1: Deploy Infrastructure](01-deploy-infrastructure.md)**

## Need Help?

- 📖 Review the lab instructions carefully
- 💬 Ask questions in GitHub Discussions
- 🐛 Report issues in GitHub Issues
