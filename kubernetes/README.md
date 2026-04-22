# Kubernetes Manifests

This directory contains Kubernetes manifest templates for deploying applications to AKS.

## Structure

```
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
└── path2/                           # Path 2: Foundry-Hosted Agent
    └── (Not yet implemented)
```

## Path 1: Custom Agent Manifests

**Location**: `kubernetes/path1/`

### Manifest Templates

Templates use placeholders like `${VARIABLE_NAME}` that are replaced during deployment by `infrastructure/path1/deploy-app.ps1`.

### Key Vault CSI Driver

**Security Pattern:**
- Secrets mounted as **read-only files** at `/mnt/secrets-store/`
- Never synced as Kubernetes secrets (most secure approach)
- CSI driver authenticates via kubelet managed identity

**Secrets Retrieved:**
- `AKS-ManagedIdentity-ClientId` - For managed identity authentication
- `AzureOpenAI-Endpoint` - Azure OpenAI service endpoint
- `ApplicationInsights-ConnectionString` - For telemetry
- `AzureSearch-Endpoint` - Azure AI Search endpoint

### Deployment

Manifests are generated and deployed automatically:

```powershell
cd infrastructure/path1
.\deploy-app.ps1
```

### Verification

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

**Location**: `kubernetes/path2/` (Not yet implemented)

Will contain manifests for UI-only deployment that calls Foundry-hosted agent.

---

**Note**: Legacy root-level manifests (`kubernetes/*.yaml`) are deprecated. Use path-specific manifests in `kubernetes/path1/` instead.

For detailed information about each manifest, see the [infrastructure README](../infrastructure/README.md).
# Kubernetes Manifests

This directory contains Kubernetes manifests for deploying the AI Agents workshop application.

## Files

### Template Files (committed to Git)
- **deployment.yaml** - Deployment template with placeholders like `${AZURE_CONTAINER_REGISTRY}`
- **secretproviderclass.yaml** - SecretProviderClass template for Key Vault CSI driver
- **configmap.yaml** - ConfigMap with Azure resource endpoints
- **service.yaml** - LoadBalancer service configuration
- **serviceaccount.yaml** - Service account for workload identity

### Generated Files (NOT committed to Git)
These files are automatically generated during deployment and contain your environment-specific values:
- **deployment.generated.yaml** - Deployment with actual ACR and image values
- **secretproviderclass.generated.yaml** - SecretProviderClass with actual Key Vault name and tenant ID

## Secret Management - Azure Key Vault CSI Driver

**This workshop demonstrates the recommended pattern for secrets in AKS:**

✅ **Azure Key Vault Provider for Secrets Store CSI Driver**
- Secrets stored in Azure Key Vault (not Kubernetes secrets)
- Mounted into pods as volumes using the CSI driver
- Authentication via AKS managed identity (no credentials needed)
- Automatic secret rotation support
- No secrets stored in etcd

### How it works:

1. **Infrastructure deployment** stores secrets in Key Vault:
   - `AKS-ManagedIdentity-ClientId`
   - `Foundry-Project-Endpoint`
   - `ApplicationInsights-ConnectionString`
   - `AzureSearch-Endpoint`
   - `AzureStorage-BlobEndpoint`

2. **SecretProviderClass** defines which secrets to mount and how

3. **Deployment** references the SecretProviderClass via volume mount:
   ```yaml
   volumes:
   - name: keyvault-secrets
     csi:
       driver: secrets-store.csi.k8s.io
       volumeAttributes:
         secretProviderClass: "azure-keyvault-secrets"
   ```

4. **Secrets are mounted** at `/mnt/secrets-store` as files in the pod

5. **Application reads secrets** from mounted files or environment variables

## Usage

Enable the CSI driver add-on on your AKS cluster:

```powershell
az aks enable-addons --addons azure-keyvault-secrets-provider --resource-group <rg> --name <aks-cluster>
```

Then apply the generated manifests:

```powershell
kubectl apply -f kubernetes/configmap.yaml
kubectl apply -f kubernetes/serviceaccount.yaml
kubectl apply -f kubernetes/secretproviderclass.generated.yaml
kubectl apply -f kubernetes/deployment.generated.yaml
kubectl apply -f kubernetes/service.yaml
```

## Security Note

Never commit the `*.generated.yaml` files to version control. They contain environment-specific values that should remain private to your deployment.
