# Path 2: Foundry-Hosted Agent with Knowledge Base

## Overview

In this workshop path, you'll learn to manage an **AI agent hosted in Microsoft Foundry**. The agent uses Foundry's knowledge base capabilities for intelligent grounding, while AKS hosts only the web UI for user interaction.

## Architecture

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│  AKS Cluster (UI Only)              │
│  ┌──────────────────────────────┐  │
│  │  Web UI (.NET)               │  │
│  │  ┌──────────┐  ┌───────────┐│  │
│  │  │ Chat UI  │  │ Foundry   ││  │
│  │  │          │  │ Client    ││  │
│  │  └──────────┘  └─────┬─────┘│  │
│  └──────────────────────┼───────┘  │
└───────────────────────────────────┘
                          │
                          ▼
         ┌────────────────────────────────┐
         │  Microsoft Foundry             │
         │  ┌──────────────────────────┐  │
         │  │  Agent                   │  │
         │  │  ┌────────────────────┐ │  │
         │  │  │  LLM (GPT-4o)      │ │  │
         │  │  └─────────┬──────────┘ │  │
         │  │            │             │  │
         │  │  ┌─────────▼──────────┐ │  │
         │  │  │  Knowledge Base    │ │  │
         │  │  └─────────┬──────────┘ │  │
         │  └────────────┼────────────┘  │
         └───────────────┼───────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Azure AI    │
                  │   Search     │
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Storage    │
                  │   Account    │
                  └──────────────┘
```

## What You'll Learn

### 1. **Foundry Project Management**
   - Create and configure Foundry projects
   - Deploy agents to Foundry
   - Manage agent lifecycle in portal
   - Configure agent settings

### 2. **Knowledge Base Configuration**
   - Set up knowledge sources (Azure Search)
   - Configure knowledge base indexing
   - Test knowledge grounding
   - Monitor knowledge base performance

### 3. **Agent Development in Foundry**
   - Create agents via portal or API
   - Configure agent behavior and prompts
   - Test agents in Foundry playground
   - Deploy agents for production

### 4. **Service Integration**
   - Connect Foundry to Azure AI Search
   - Configure managed identity for Foundry
   - Integrate AKS UI with Foundry agent
   - Secure Foundry-to-services communication

### 5. **Monitoring & Evaluation**
   - Use Foundry's built-in tracing
   - Configure agent evaluation metrics
   - Monitor agent performance
   - Track costs in Foundry

## Key Differences from Path 1

| Aspect | Path 1 (Custom) | Path 2 (Foundry) |
|--------|-----------------|------------------|
| **Agent Location** | Runs in your AKS pods | Hosted in Foundry |
| **Code Control** | Full control over agent code | Declarative configuration |
| **LLM Integration** | Direct OpenAI SDK calls | Via Foundry models |
| **RAG Pattern** | Custom implementation | Foundry knowledge base |
| **Monitoring** | Application Insights in AKS | Foundry tracing + AKS |
| **Deployment** | Docker + Kubernetes | Foundry deployment API |
| **Agent Visibility** | Logs and metrics only | Foundry portal UI |
| **Complexity** | Higher (more control) | Lower (managed service) |

## When to Choose This Path

✅ **Choose Path 2 if you:**
- Want managed agent hosting
- Prefer declarative agent configuration
- Need built-in evaluation and monitoring
- Want agent visibility in a portal
- Prefer lower operational overhead
- Are building standard agent scenarios

## Prerequisites

Before starting this path, ensure you have:

- ✅ Completed [common prerequisites](../00-prerequisites.md)
- ✅ Basic understanding of AI agents and LLMs
- ✅ Familiarity with Azure portal
- ✅ Azure subscription with permissions to create:
  - Microsoft Foundry projects
  - Azure AI Search
  - Azure Kubernetes Service
  - Managed Identities

## Workshop Labs

Follow these labs in order:

1. **[Deploy Infrastructure](01-deploy-infrastructure.md)** *(~45 minutes)*
   - Deploy Foundry project and AI hub
   - Deploy Azure AI Search and Storage
   - Configure AKS for UI hosting
   - Set up Key Vault and secrets

2. **[Foundry Agent Setup](02-foundry-agent-setup.md)** *(~40 minutes)*
   - Create agent in Foundry portal
   - Configure agent behavior and prompts
   - Test agent in Foundry playground
   - Deploy agent for production use

3. **[Knowledge Base Config](03-knowledge-base-config.md)** *(~45 minutes)*
   - Configure Azure Search as knowledge source
   - Set up knowledge base indexing
   - Test knowledge grounding
   - Optimize search relevance

4. **[Managed Identity](04-managed-identity.md)** *(~30 minutes)*
   - Configure Foundry managed identity
   - Set up RBAC for Search and Storage
   - Configure AKS UI authentication
   - Test service-to-service auth

5. **[Monitoring](05-monitoring-foundry.md)** *(~40 minutes)*
   - Use Foundry's built-in tracing
   - Configure agent evaluation
   - Set up custom metrics
   - Create dashboards

6. **[Cost Management](06-cost-management.md)** *(~30 minutes)*
   - Monitor Foundry usage costs
   - Track model token consumption
   - Optimize resource allocation
   - Set up cost alerts

7. **[Disaster Recovery](07-disaster-recovery.md)** *(~40 minutes)*
   - Backup agent configurations
   - Export knowledge base settings
   - Implement failover strategies
   - Test recovery procedures

**Total estimated time:** ~5-6 hours

## Quick Start

```powershell
# 1. Navigate to Path 2 infrastructure (from repository root)
cd infrastructure/path2

# 2. Deploy all infrastructure (including Foundry)
.\deploy-infra.ps1

# 3. Deploy the UI application
.\deploy-app.ps1

# 4. Create and configure agent in Foundry portal
# Follow the instructions displayed by the script

# 5. Access your agent
# The deployment script will display the endpoint URL
```

## Next Steps

👉 **[Start Lab 1: Deploy Infrastructure](01-deploy-infrastructure.md)**

## Need Help?

- 📖 Review the [troubleshooting guide](../troubleshooting.md)
- 💬 Ask questions in [GitHub Discussions](../../discussions)
- 🐛 Report issues in [GitHub Issues](../../issues)

## Additional Resources

- [Microsoft Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Knowledge Base Configuration Guide](https://learn.microsoft.com/azure/ai-foundry/how-to/knowledge-base)
- [Agent Deployment Best Practices](https://learn.microsoft.com/azure/ai-foundry/how-to/deploy-agents)
