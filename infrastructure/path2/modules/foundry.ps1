function New-WorkshopFoundry {
    <#
    .SYNOPSIS
        Creates a Microsoft Foundry resource, a Foundry project, and a model
        deployment used by the prompt agent.

    .DESCRIPTION
        Path 2 uses a Foundry-hosted prompt agent instead of a custom agent.
        This module provisions everything that CAN be created from the CLI:
          - A Foundry resource (Cognitive Services account, kind=AIServices)
            with project management enabled (--allow-project-management).
          - A custom subdomain (required so the resource has a stable AI endpoint).
          - A model deployment (e.g. gpt-4.1-mini) the agent will reason with.
          - A Foundry project (the container for agents, knowledge, evaluations).

        The prompt agent itself and the Knowledge Base are NOT created here -
        those are portal-only / SDK-only operations and are performed as guided
        manual steps later in the deployment.
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
        [string]$ModelName = "gpt-4.1-mini",
        
        [Parameter(Mandatory = $false)]
        [string]$ModelVersion = "",
        
        [Parameter(Mandatory = $false)]
        [int]$ModelCapacity = 10,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectName = "",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    $foundryName = "$Prefix-foundry-$Environment".ToLower()
    $deploymentName = $ModelName
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = "$Prefix-project-$Environment".ToLower()
    }
    
    Write-InfoLog "Creating Microsoft Foundry resource: $foundryName"
    
    # Check for soft-deleted Foundry resource and purge if found
    Write-InfoLog "Checking for soft-deleted Foundry resources..."
    $softDeleted = az cognitiveservices account list-deleted `
        --query "[?name=='$foundryName'].{name:name, location:location}" `
        -o json 2>$null | ConvertFrom-Json
    
    if ($softDeleted) {
        Write-WarningLog "Found soft-deleted Foundry resource. Purging..."
        az cognitiveservices account purge `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --location $Location `
            2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-InfoLog "Soft-deleted resource purged successfully"
            Start-Sleep -Seconds 5
        } else {
            Write-WarningLog "Could not purge soft-deleted resource. Attempting to continue..."
        }
    }
    
    # Check if Foundry resource already exists
    $existingFoundry = az cognitiveservices account show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingFoundry) {
        Write-WarningLog "Foundry resource '$foundryName' already exists"
        $foundry = $existingFoundry
    } else {
        Write-InfoLog "Creating Foundry resource (this may take a few minutes)..."
        
        $tagString = ($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
        
        # kind=AIServices + --allow-project-management is what makes this a
        # Foundry resource (vs. a plain Azure OpenAI / Cognitive Services account).
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
            throw "Failed to create Foundry resource"
        }
        
        Write-SuccessLog "Foundry resource created: $foundryName"
    }
    
    $endpoint = $foundry.properties.endpoint
    
    # Ensure system-assigned managed identity is enabled
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
    
    # Deploy the model the agent will use
    Write-InfoLog "Deploying model: $ModelName"
    
    $existingDeployment = az cognitiveservices account deployment show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        --deployment-name $deploymentName `
        2>$null | ConvertFrom-Json
    
    if ($existingDeployment) {
        Write-WarningLog "Model deployment '$deploymentName' already exists"
    } else {
        Write-InfoLog "Creating model deployment (this may take a few minutes)..."
        
        # Resolve latest available model version if not explicitly provided
        if ([string]::IsNullOrEmpty($ModelVersion)) {
            Write-InfoLog "Querying for latest available model version..."
            $latest = az cognitiveservices account list-models `
                --name $foundryName `
                --resource-group $ResourceGroupName `
                --query "[?name=='$ModelName'].version | sort(@) | [-1]" `
                -o tsv 2>$null
            
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($latest)) {
                $ModelVersion = $latest.Trim()
                Write-InfoLog "Using latest available version: $ModelVersion"
            } else {
                $ModelVersion = "2024-11-20"
                Write-WarningLog "Could not query model versions. Using fallback version: $ModelVersion"
            }
        } else {
            Write-InfoLog "Using specified model version: $ModelVersion"
        }
        
        az cognitiveservices account deployment create `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --deployment-name $deploymentName `
            --model-name $ModelName `
            --model-version $ModelVersion `
            --model-format OpenAI `
            --sku-name "GlobalStandard" `
            --sku-capacity $ModelCapacity `
            | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            # Some regions/models only support Standard - retry once with Standard
            Write-WarningLog "GlobalStandard deployment failed. Retrying with Standard SKU..."
            az cognitiveservices account deployment create `
                --name $foundryName `
                --resource-group $ResourceGroupName `
                --deployment-name $deploymentName `
                --model-name $ModelName `
                --model-version $ModelVersion `
                --model-format OpenAI `
                --sku-name "Standard" `
                --sku-capacity $ModelCapacity `
                | Out-Null
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to deploy model $ModelName"
            }
        }
        
        Write-SuccessLog "Model deployed: $deploymentName (version: $ModelVersion)"
    }
    
    # Create the Foundry project
    Write-InfoLog "Creating Foundry project: $ProjectName"
    
    $existingProject = az cognitiveservices account project show `
        --name $foundryName `
        --resource-group $ResourceGroupName `
        --project-name $ProjectName `
        2>$null | ConvertFrom-Json
    
    if ($existingProject) {
        Write-WarningLog "Foundry project '$ProjectName' already exists"
        $project = $existingProject
    } else {
        $project = az cognitiveservices account project create `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --project-name $ProjectName `
            --location $Location `
            | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Foundry project"
        }
        
        Write-SuccessLog "Foundry project created: $ProjectName"
    }
    
    # Build the project endpoint used by the SDK / UI / agents data plane.
    # The Foundry Agents data plane is served from the services.ai.azure.com host
    # (not cognitiveservices.azure.com), in the format:
    #   https://<resource>.services.ai.azure.com/api/projects/<project>
    # The resource custom subdomain equals $foundryName, so we construct it directly.
    $projectEndpoint = "https://$foundryName.services.ai.azure.com/api/projects/$ProjectName"
    
    # The Foundry project has its own system-assigned managed identity (distinct
    # from the account identity). The Knowledge Base runs under this identity, so
    # it needs data-plane access to the Search index at query time.
    $projectIdentityPrincipalId = $project.identity.principalId
    if ([string]::IsNullOrWhiteSpace($projectIdentityPrincipalId)) {
        $projectIdentityPrincipalId = az cognitiveservices account project show `
            --name $foundryName `
            --resource-group $ResourceGroupName `
            --project-name $ProjectName `
            --query identity.principalId `
            -o tsv 2>$null
    }
    
    return @{
        Name = $foundryName
        Id = $foundry.id
        Endpoint = $endpoint
        ProjectName = $ProjectName
        ProjectEndpoint = $projectEndpoint
        DeploymentName = $deploymentName
        ModelName = $ModelName
        IdentityPrincipalId = $foundry.identity.principalId
        ProjectIdentityPrincipalId = $projectIdentityPrincipalId
    }
}
