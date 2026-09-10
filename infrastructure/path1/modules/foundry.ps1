function New-WorkshopFoundry {
    <#
    .SYNOPSIS
        Creates a Microsoft Foundry resource, project, and model deployment for
        the custom Path 1 agent.

    .DESCRIPTION
        Path 1 keeps retrieval and orchestration in the AKS application. The
        application calls the model deployment directly through the Foundry
        resource's OpenAI-compatible Responses API; it does not invoke a
        Foundry-hosted prompt agent.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{},

        [Parameter(Mandatory = $false)]
        [string]$ModelName = "gpt-5.4-mini",

        [Parameter(Mandatory = $false)]
        [string]$ModelVersion = "2026-03-17",

        [Parameter(Mandatory = $false)]
        [int]$ModelCapacity = 10,

        [Parameter(Mandatory = $false)]
        [string]$ProjectName = ""
    )

    $foundryName = "$Prefix-foundry-$Environment".ToLower()
    $deploymentName = $ModelName
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = "$Prefix-custom-agent-$Environment".ToLower()
    }

    Write-InfoLog "Creating Microsoft Foundry resource: $foundryName"

    $softDeleted = az cognitiveservices account list-deleted `
        --query "[?name=='$foundryName'].{name:name, location:location}" `
        --output json 2>$null | ConvertFrom-Json

    if ($softDeleted) {
        Write-WarningLog "Found soft-deleted Foundry resource. Purging..."
        az cognitiveservices account purge `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --location $Location `
            2>$null | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-WarningLog "Could not purge soft-deleted resource. Attempting to continue..."
        }
    }

    $foundry = az cognitiveservices account show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json

    if ($foundry) {
        if ($foundry.kind -ne "AIServices") {
            throw "Resource '$foundryName' exists but is kind '$($foundry.kind)', not 'AIServices'. Choose another prefix or remove the incompatible resource."
        }
        Write-WarningLog "Foundry resource '$foundryName' already exists"
    } else {
        Write-InfoLog "Creating Foundry resource (this may take a few minutes)..."
        $tagString = ($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "

        $foundry = az cognitiveservices account create `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --kind AIServices `
            --sku S0 `
            --custom-domain $foundryName `
            --allow-project-management true `
            --assign-identity `
            --tags $tagString `
            --yes `
            | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Microsoft Foundry resource"
        }

        Write-SuccessLog "Foundry resource created: $foundryName"
    }

    if (-not $foundry.identity -or $foundry.identity.type -notlike "*SystemAssigned*") {
        Write-InfoLog "Enabling system-assigned managed identity"
        az cognitiveservices account identity assign `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            | Out-Null

        $foundry = az cognitiveservices account show `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            | ConvertFrom-Json
    }

    $modelEndpoint = $foundry.properties.endpoints.'Azure OpenAI Legacy API - Latest moniker'
    if ([string]::IsNullOrWhiteSpace($modelEndpoint)) {
        $modelEndpoint = "https://$foundryName.openai.azure.com/"
    }
    $responsesEndpoint = "$($modelEndpoint.TrimEnd('/'))/openai/v1"

    Write-InfoLog "Deploying model: $ModelName"
    $existingDeployment = az cognitiveservices account deployment show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        --deployment-name $deploymentName `
        2>$null | ConvertFrom-Json

    if ($existingDeployment) {
        $deployedVersion = $existingDeployment.properties.model.version
        if ($deployedVersion -ne $ModelVersion) {
            throw "Model deployment '$deploymentName' uses version '$deployedVersion', but this workshop requires '$ModelVersion'. Remove or update the existing deployment, then run the script again."
        }
        Write-WarningLog "Model deployment '$deploymentName' already exists with required version '$ModelVersion'"
    } else {
        if ([string]::IsNullOrWhiteSpace($ModelVersion)) {
            Write-InfoLog "Querying for latest available model version..."
            $ModelVersion = az cognitiveservices account list-models `
                --name $foundryName `
                --resource-group $ResourceGroupName `
                --query "[?name=='$ModelName'].version | sort(@) | [-1]" `
                --output tsv 2>$null

            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ModelVersion)) {
                throw "Could not resolve an available version for model '$ModelName' in '$Location'. Verify model availability and quota in the target region."
            }
            $ModelVersion = $ModelVersion.Trim()
        }

        Write-InfoLog "Using model version: $ModelVersion"
        az cognitiveservices account deployment create `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --deployment-name $deploymentName `
            --model-name $ModelName `
            --model-version $ModelVersion `
            --model-format OpenAI `
            --sku-name GlobalStandard `
            --sku-capacity $ModelCapacity `
            | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to deploy model '$ModelName'. Confirm that GlobalStandard is supported and quota is available in '$Location'."
        }

        Write-SuccessLog "Model deployed: $deploymentName (version: $ModelVersion)"
    }

    Write-InfoLog "Creating Foundry project: $ProjectName"
    $project = az cognitiveservices account project show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        --project-name $ProjectName `
        2>$null | ConvertFrom-Json

    if ($project) {
        Write-WarningLog "Foundry project '$ProjectName' already exists"
    } else {
        $project = az cognitiveservices account project create `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --project-name $ProjectName `
            --location $Location `
            | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Foundry project '$ProjectName'"
        }
        Write-SuccessLog "Foundry project created: $ProjectName"
    }

    return @{
        Name = $foundryName
        Id = $foundry.id
        Endpoint = $foundry.properties.endpoint
        ModelEndpoint = $modelEndpoint
        ResponsesEndpoint = $responsesEndpoint
        ProjectName = $ProjectName
        ProjectEndpoint = "https://$foundryName.services.ai.azure.com/api/projects/$ProjectName"
        DeploymentName = $deploymentName
        ModelName = $ModelName
        ModelVersion = $ModelVersion
        IdentityPrincipalId = $foundry.identity.principalId
    }
}
