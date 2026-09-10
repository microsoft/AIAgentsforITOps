# Infrastructure Deployment Scripts

This directory contains PowerShell scripts for deploying Azure infrastructure for both workshop paths.

## Structure

```markdown
infrastructure/
├── common/                          # Shared helper modules
│   ├── common.ps1                   # Logging and utility functions
│   └── validation.ps1               # Parameter validation
│
├── path1/                           # Path 1: Custom Agent with Microsoft Foundry
│   ├── deploy-infra.ps1             # Main deployment orchestrator
│   ├── deploy-app.ps1               # Application deployment to AKS
│   ├── parameters.json.example      # Configuration template
│   └── modules/                     # Infrastructure modules
│       ├── foundry.ps1               # Foundry account, project, and model deployment
│       ├── aks.ps1                  # AKS cluster
│       ├── search.ps1               # Azure AI Search
│       ├── storage.ps1              # Storage account
│       ├── acr.ps1                  # Container registry
│       ├── keyvault.ps1             # Key Vault
│       ├── rbac.ps1                 # RBAC assignments
│       ├── monitoring.ps1           # Application Insights
│       ├── network.ps1              # VNet and networking
│       └── resource-group.ps1       # Resource group creation
│
└── path2/                           # Path 2: Foundry-Hosted Agent
    └── modules/                     # (Not yet implemented)
```

