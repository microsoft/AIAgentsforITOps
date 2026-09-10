# Application Source Code

This directory contains the application code for both workshop paths.

## Structure

```
src/
├── path1/                    # Path 1: Custom Agent with Microsoft Foundry
│   └── agent-webapp/         # Full agent web application
│       ├── Controllers/      # API controllers
│       ├── Services/         # Agent and search services
│       ├── Models/           # Data models
│       ├── wwwroot/          # Static files (chat UI)
│       ├── Program.cs        # Application entry point
│       ├── Dockerfile        # Container image definition
│       └── AgentWebApp.csproj
│
└── path2/                    # Path 2: Foundry-Hosted Agent (Not yet implemented)
    └── (To be created)       # Lightweight UI-only application
```

## Path 1: Custom Agent Web Application

**Location**: `src/path1/agent-webapp/`

**Description**: Full-featured ASP.NET Core web application that:
- Runs the AI agent directly in the container
- Calls a Foundry `gpt-5.4-mini` deployment through the OpenAI-compatible Responses API
- Implements RAG pattern (Retrieval Augmented Generation)
- Queries Azure AI Search for context
- Serves chat UI via static files

**Key Components**:
- `Services/AgentService.cs` - Search grounding, citations, and Foundry model inference
- `Services/SearchService.cs` - Azure AI Search client
- `Controllers/ChatController.cs` - REST API for chat
- `wwwroot/index.html` - Chat interface

**Technologies**:
- .NET 8.0
- OpenAI .NET SDK (`OpenAI.Responses`)
- Azure.Search.Documents SDK
- Azure.Identity for managed identity authentication

## Path 2: UI-Only Application

**Location**: `src/path2/` (Not yet implemented)

**Description**: Lightweight web application that:
- Serves only the chat UI
- Proxies requests to Foundry-hosted agent
- Does NOT run agent logic locally
- Minimal container footprint

**Planned Structure**:
```
src/path2/
└── agent-ui/
    ├── wwwroot/              # Static UI files
    ├── Controllers/          # Minimal API proxy
    ├── Program.cs            # Simple web host
    ├── Dockerfile            # Lightweight container
    └── AgentUI.csproj
```

## Building and Deploying

### Path 1

Build is automated via ACR Tasks (no local Docker required):

```powershell
# From repository root
cd infrastructure/path1
.\deploy-app.ps1
```

This will:
1. Build `src/path1/agent-webapp/` using ACR Tasks
2. Push image to Azure Container Registry
3. Generate Kubernetes manifests
4. Deploy to AKS

### Path 2

(Not yet implemented)

## Local Development

### Path 1

Run locally with Azure services:

```powershell
cd src/path1/agent-webapp

# Set local configuration (appsettings.Development.json)
dotnet user-secrets set "Foundry:ModelEndpoint" "https://<foundry-account>.openai.azure.com/openai/v1"
dotnet user-secrets set "Foundry:ModelDeploymentName" "gpt-5.4-mini"
dotnet user-secrets set "AzureSearch:Endpoint" "<your-endpoint>"

# Run
dotnet run
```

Visit: http://localhost:5000

### Path 2

(Not yet implemented)

---

## Notes

- **Path 1** is self-contained: All agent logic runs in the container
- **Path 2** will be minimal: Agent logic runs in Foundry, container only hosts UI
- Both paths share the same workshop scenario (conference expert agent)
- Applications are deployed to separate AKS namespaces
