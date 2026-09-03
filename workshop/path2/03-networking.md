# Lab 3: Networking for a Foundry-Hosted Agent

## Overview

Secure the inbound connection from the AKS chat UI to Microsoft Foundry and understand the separate outbound path from the Foundry-hosted agent to its knowledge source.

**Time:** 30-40 minutes  
**Difficulty:** Intermediate

## Learning Objectives

- Separate Foundry inbound isolation from agent outbound isolation
- Inspect the current public network path
- Add a private endpoint for the Foundry account
- Validate private DNS from an AKS pod
- Understand why full agent egress isolation must be designed at creation time

## Two Network Planes

```text
Inbound to Foundry
AKS UI ──HTTPS──> Foundry project endpoint

Outbound from the hosted agent
Foundry agent ──> Foundry IQ / Azure AI Search ──> Blob Storage
```

A private endpoint on the Foundry account secures the first path. It does **not** automatically inject the hosted agent into your VNet or privatize Search and Storage. Full outbound isolation requires a Foundry networking design created with BYO VNet or a managed VNet.

## Important Workshop Scope

Lab 1 deployed the fast public-network baseline. This lab adds **inbound private access** for the AKS caller while leaving agent egress public.

> **Do not disable public access on Search or Storage in this lab.** The indexed knowledge source created in Lab 1 uses a service-managed ingestion path. Indexed knowledge sources and their generated indexers don't currently support the private indexer execution environment required to traverse private endpoints. Locking those services down can leave the index empty or break refreshes.

## Step 1: Load the Deployment Context

```powershell
cd infrastructure/path2

$config = Get-Content .\deployment-output.json | ConvertFrom-Json
$resourceGroup = $config.resourceGroupName
$location = $config.location
$aksName = $config.resources.aksCluster
$foundryName = $config.resources.foundry
$projectEndpoint = $config.endpoints.foundryProject

$projectHost = ([Uri]$projectEndpoint).Host
Write-Host "Project endpoint: $projectEndpoint" -ForegroundColor Cyan
```

## Step 2: Inspect the AKS Network

The workshop can use either an explicitly created VNet or the AKS-managed VNet.

```powershell
$aksNodeResourceGroup = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query nodeResourceGroup -o tsv

$agentSubnetId = az aks show `
    --name $aksName `
    --resource-group $resourceGroup `
    --query agentPoolProfiles[0].vnetSubnetId -o tsv

if ([string]::IsNullOrWhiteSpace($agentSubnetId)) {
    $vnet = az network vnet list `
        --resource-group $aksNodeResourceGroup `
        --query "[0]" | ConvertFrom-Json
} else {
    $vnetId = ($agentSubnetId -split '/subnets/')[0]
    $vnet = az network vnet show --ids $vnetId | ConvertFrom-Json
}

Write-Host "AKS node resource group: $aksNodeResourceGroup" -ForegroundColor Cyan
Write-Host "VNet: $($vnet.name)" -ForegroundColor Cyan
$vnet.subnets | Select-Object name, addressPrefix, id | Format-Table -AutoSize
```

Record the VNet and choose a subnet for private endpoints. If the deployment created `private-endpoint-subnet`, use it. Otherwise, create a dedicated subnet or select an existing subnet that permits private endpoints.

## Step 3: Establish the Public Baseline

Resolve the Foundry endpoint from a temporary pod:

```powershell
# Remove an old test pod so this step is safe to rerun
kubectl delete pod dns-test `
    --namespace agent-demo `
    --ignore-not-found

kubectl run dns-test `
    --namespace agent-demo `
    --image=mcr.microsoft.com/cbl-mariner/base/core:2.0 `
    --restart=Never `
    --command -- sleep 86400

kubectl wait --namespace agent-demo `
    --for=condition=Ready pod/dns-test `
    --timeout=120s

kubectl exec -n agent-demo dns-test -- getent hosts $projectHost
```

The pod remains running for 24 hours so it can be reused after the private endpoint is created. Rerun this entire step if the pod is deleted or reaches the `Succeeded` phase.

The endpoint currently resolves through the public Foundry front door. Verify the application still works and ask:

> What were the stations for Cloud Platform Expert Meet-up at Build 2024?

## Step 4: Create the Foundry Private Endpoint

Use the Azure portal so Azure creates the correct private DNS integration for the current Foundry API version.

1. Open Azure portal and select the Foundry resource named in `deployment-output.json`.
2. Select **Resource Management** → **Networking**.
3. Open **Private endpoint connections** and select **+ Private endpoint**.
4. For the Instance details, use the following:
   - Name: `foundry-private-endpoint`
   - Network Interface Name: `foundry-private-endpoint-nic`
   - Region: same as the Foundry resource
5. Click **Next: Resource** and ensure the Target sub-resource is `account`. Click Next.
6. On Virtual Network, make sure the Virtual Network is the AKS VNet and the Subnet is the **aks-subnet**. Click Next until you reach the Review + create tab.
7. Click Create to create the endpoint.
8. Wait for the deployment to finalize, return to **Private endpoint connections** and confirm its state is **Approved**.

> If the connection remains `Pending`, an owner of the Foundry resource must approve it.

## Step 5: Validate Private DNS from AKS

Wait briefly for DNS propagation, then resolve the same public hostname again:

```powershell
kubectl exec -n agent-demo dns-test -- getent hosts $projectHost
```

If this command reports that the pod is `Succeeded`, recreate it before retrying:

```powershell
kubectl delete pod dns-test -n agent-demo --ignore-not-found

kubectl run dns-test `
    --namespace agent-demo `
    --image=mcr.microsoft.com/cbl-mariner/base/core:2.0 `
    --restart=Never `
    --command -- sleep 86400

kubectl wait --namespace agent-demo `
    --for=condition=Ready pod/dns-test `
    --timeout=120s

kubectl exec -n agent-demo dns-test -- getent hosts $projectHost
```

Expected result: the endpoint hostname resolves through its `privatelink` alias to an RFC 1918 private address such as `10.x.x.x`.

Inspect the created endpoint and DNS zone in Azure:

```powershell
az network private-endpoint list `
    --query "[?contains(privateLinkServiceConnections[0].privateLinkServiceId, '$foundryName')].{Name:name,ResourceGroup:resourceGroup,State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" `
    --output table

az network private-dns zone list `
    --query "[].{Name:name,ResourceGroup:resourceGroup}" `
    --output table
```

## Step 6: Disable Public Inbound Access

Only continue after private DNS resolves correctly from AKS.

1. In the Foundry resource, open **Networking** → **Firewalls and virtual networks**.
2. Change public network access from **All networks** to **Disabled**.
3. Save the change.

Your workstation might lose direct data-plane access to the Foundry project because it is outside the VNet. Keep the Azure portal open; management-plane operations remain available.

## Step 7: Verify the End-to-End Application

The chat UI is inside the AKS VNet, so it should continue to invoke the agent over Private Link.

```powershell
$externalIP = kubectl get service agent-webapp-service -n agent-demo `
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

Write-Host "Open http://$externalIP" -ForegroundColor Green
```

Ask the baseline question again. A successful response proves:

- Public inbound access to Foundry is disabled
- AKS resolves the unchanged Foundry hostname to the private endpoint
- Entra authentication and RBAC still apply over the private connection
- The agent can still use its public-egress knowledge path

## Step 8: Compare with Full Foundry Isolation

Open the Foundry portal or Microsoft Learn documentation and compare the workshop topology with the production options:

| Egress model | Inbound option | What it protects |
| --- | --- | --- |
| Public egress | Public or private endpoint | A private endpoint restricts callers only |
| BYO VNet | Private endpoint | Inbound plus agent/tool egress through your VNet |
| Managed VNet | Private endpoint | Inbound plus managed outbound isolation |

For BYO VNet, Foundry requires a dedicated subnet delegated to `Microsoft.App/environments`, with `/27` as the supported minimum. Prompt agents use a small static pool of addresses per project.

Network injection cannot be added to this existing Foundry account after deployment. To move this workshop to full isolation, redeploy the Foundry resource using the official private-network template, create private endpoints for each bring-your-own data resource, and reconnect the agent assets.

## Step 9: Clean Up the Test Pod

```powershell
kubectl delete pod dns-test -n agent-demo
```

Keep the private endpoint for the remaining labs. If portal access to project data is required from your workstation, use VPN/ExpressRoute/Bastion connectivity to the VNet, or temporarily restore **All networks** in the Foundry networking settings.

## Key Learnings

- Foundry networking has distinct inbound and outbound decisions
- Private DNS lets applications keep the same project endpoint
- Private Link doesn't replace Entra authentication or RBAC
- Full agent egress isolation is a design-time choice
- Foundry portal limitations and tool support must be evaluated before lockdown

## Next Steps

Continue to **[Lab 4: Secrets Management](04-secrets-management.md)**.

## Best Practices

### Do

- Decide inbound and outbound isolation separately
- Design VNet injection before creating the Foundry account
- Use a dedicated private-endpoint subnet and private DNS integration
- Validate DNS from the actual caller network
- Combine Private Link with managed identity and least-privilege RBAC
- Check tool support before committing to full isolation

### Avoid

- Assuming a Foundry private endpoint isolates agent egress
- Disabling public access before private DNS is working
- Locking down Search without validating the Knowledge Base ingestion model
- Using IP addresses in application configuration; continue using the endpoint FQDN

## Troubleshooting

### DNS still returns a public IP

- Confirm the private DNS zone is linked to the AKS VNet
- Confirm the A record exists in the zone
- With custom DNS, forward the private-link zone to Azure DNS at `168.63.129.16`

### UI receives a timeout

- Confirm the private endpoint is `Approved`
- Check outbound NSG and firewall access to the private IP on TCP 443
- Resolve the project hostname from the UI pod

### UI receives 403

The network path is likely working. Recheck the AKS identity's Foundry role from Lab 2.

## Resources

- [Configure network isolation for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [Networking options for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Azure Private Link](https://learn.microsoft.com/azure/private-link/private-link-overview)
