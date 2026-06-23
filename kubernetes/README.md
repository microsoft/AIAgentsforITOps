# Kubernetes Manifests

This directory contains Kubernetes manifest templates for deploying applications to AKS.

## Structure

```text
kubernetes/
├── path1/                           # Path 1: Custom Agent with Azure OpenAI
│   ├── namespace.yaml               # agent-demo namespace
│   ├── configmap.yaml               # Config template (search name, OpenAI deployment)
│   ├── secretproviderclass.yaml     # Key Vault CSI driver template
│   ├── serviceaccount.yaml          # Workload identity service account
│   ├── deployment.yaml              # Pod deployment template
│   ├── service.yaml                 # LoadBalancer service
│   ├── configmap.generated.yaml     # Generated with actual values
│   ├── secretproviderclass.generated.yaml
│   ├── deployment.generated.yaml
│   └── serviceaccount.generated.yaml
│
└── path2/                           # Path 2: Foundry-Hosted Agent (UI only)
    ├── namespace.yaml               # agent-demo namespace
    ├── secretproviderclass.yaml     # Key Vault CSI driver template
    ├── serviceaccount.yaml          # Workload identity service account
    ├── deployment.yaml              # Pod deployment template (UI)
    ├── service.yaml                 # LoadBalancer service
    ├── secretproviderclass.generated.yaml
    ├── deployment.generated.yaml
    └── serviceaccount.generated.yaml
```

## Path 1: Custom Agent Manifests

**Location**: `kubernetes/path1/`

### Path 1 Manifest Templates

Templates use placeholders like `${VARIABLE_NAME}` that are replaced during deployment by `infrastructure/path1/deploy-app.ps1`.

### Path 1 Key Vault CSI Driver

**Security Pattern:**

- Secrets mounted as **read-only files** at `/mnt/secrets-store/`
- Never synced as Kubernetes secrets (most secure approach)
- CSI driver authenticates via kubelet managed identity

**Secrets Retrieved:**

- `AKS-ManagedIdentity-ClientId` - For managed identity authentication
- `AzureOpenAI-Endpoint` - Azure OpenAI service endpoint
- `ApplicationInsights-ConnectionString` - For telemetry
- `AzureSearch-Endpoint` - Azure AI Search endpoint

### Path 1 Deployment

Manifests are generated and deployed automatically:

```powershell
cd infrastructure/path1
.\deploy-app.ps1
```

### Path 1 Verification

```powershell
# Check pod status
kubectl get pods -n agent-demo

# Check secrets mounted
kubectl exec -n agent-demo <pod-name> -- ls -la /mnt/secrets-store/

# Check service and external IP
kubectl get service agent-webapp-service -n agent-demo

# View pod logs
kubectl logs -n agent-demo -l app=agent-webapp --tail=50
```

## Path 2: Foundry-Hosted Agent Manifests

**Location**: `kubernetes/path2/`

Path 2 deploys a **UI-only** application to AKS. The agent itself runs in
Microsoft Foundry, so these manifests only run the chat web app, which calls the
Foundry-hosted prompt agent over the Responses API.

### Path 2 Manifest Templates

Templates use placeholders like `${VARIABLE_NAME}` that are replaced during deployment by `infrastructure/path2/deploy-app.ps1`.

> **No ConfigMap:** unlike Path 1, Path 2 needs no `configmap.yaml`. The UI reads
> everything it needs (project endpoint, agent name, telemetry) from Key Vault via
> the CSI driver.

### Path 2 Key Vault CSI Driver

**Security Pattern:**

- Secrets mounted as **read-only files** at `/mnt/secrets-store/`
- Never synced as Kubernetes secrets (most secure approach)
- CSI driver authenticates via kubelet managed identity

**Secrets Retrieved:**

- `AKS-ManagedIdentity-ClientId` - For managed identity authentication
- `Foundry-ProjectEndpoint` - Foundry project (data-plane) endpoint
- `Foundry-AgentName` - Name of the prompt agent to call (`conference-expert-agent`)
- `ApplicationInsights-ConnectionString` - For telemetry

### Path 2 Deployment

Manifests are generated and deployed automatically:

```powershell
cd infrastructure/path2
.\deploy-app.ps1
```

### Path 2 Verification

```powershell
# Check pod status
kubectl get pods -n agent-demo

# Check secrets mounted
kubectl exec -n agent-demo <pod-name> -- ls -la /mnt/secrets-store/

# Check service and external IP
kubectl get service agent-webapp-service -n agent-demo

# View pod logs
kubectl logs -n agent-demo -l app=agent-webapp --tail=50
```

---

**Note**: Legacy root-level manifests (`kubernetes/*.yaml`) are deprecated. Use path-specific manifests in `kubernetes/path1/` or `kubernetes/path2/` instead.

For detailed information about each manifest, see the [infrastructure README](../infrastructure/README.md).
