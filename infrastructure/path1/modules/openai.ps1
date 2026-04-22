function New-WorkshopAzureOpenAI {
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
        [string]$ModelName = "gpt-4.1-mini",
        
        [Parameter(Mandatory = $false)]
        [string]$ModelVersion = ""
    )
    
    $openAIName = "$Prefix-openai-$Environment"
    $deploymentName = "gpt-4.1-mini"
    
    Write-InfoLog "Creating Azure OpenAI resource: $openAIName"
    
    # Check for existing soft-deleted OpenAI resource and purge if found
    Write-InfoLog "Checking for soft-deleted OpenAI resources..."
    $softDeletedAccounts = az cognitiveservices account list-deleted `
        --query "[?name=='$openAIName'].{name:name, location:location}" `
        -o json 2>$null | ConvertFrom-Json
    
    if ($softDeletedAccounts) {
        Write-WarningLog "Found soft-deleted Azure OpenAI resource. Purging..."
        
        az cognitiveservices account purge `
            --name $openAIName `
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
    
    # Check if Azure OpenAI resource already exists
    $existingOpenAI = az cognitiveservices account show `
        --name $openAIName `
        --resource-group $ResourceGroupName `
        2>$null | ConvertFrom-Json
    
    if ($existingOpenAI) {
        Write-WarningLog "Azure OpenAI resource '$openAIName' already exists"
        $openAI = $existingOpenAI
    } else {
        # Create Azure OpenAI resource
        Write-InfoLog "Creating Azure OpenAI resource (this may take a few minutes)..."
        
        $tagString = ($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
        
        $openAI = az cognitiveservices account create `
            --name $openAIName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --kind OpenAI `
            --sku S0 `
            --custom-domain $openAIName `
            --tags $tagString `
            --yes `
            | ConvertFrom-Json
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create Azure OpenAI resource"
        }
        
        Write-SuccessLog "Azure OpenAI resource created: $openAIName"
    }
    
    # Get the endpoint
    $endpoint = $openAI.properties.endpoint
    
    # Deploy the model
    Write-InfoLog "Deploying model: $ModelName"
    
    # Check if deployment already exists
    $existingDeployment = az cognitiveservices account deployment show `
        --name $openAIName `
        --resource-group $ResourceGroupName `
        --deployment-name $deploymentName `
        2>$null | ConvertFrom-Json
    
    if ($existingDeployment) {
        Write-WarningLog "Model deployment '$deploymentName' already exists"
    } else {
        # Create model deployment
        Write-InfoLog "Creating model deployment (this may take a few minutes)..."
        
        # If no model version specified, query for latest available version
        if ([string]::IsNullOrEmpty($ModelVersion)) {
            Write-InfoLog "Querying for latest available model version..."
            
            $availableModels = az cognitiveservices account list-models `
                --name $openAIName `
                --resource-group $ResourceGroupName `
                --query "[?name=='$ModelName'].version | sort(@) | [-1]" `
                -o tsv 2>$null
            
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($availableModels)) {
                $ModelVersion = $availableModels.Trim()
                Write-InfoLog "Using latest available version: $ModelVersion"
            } else {
                # Fallback to a known stable version for gpt-4.1-mini
                $ModelVersion = "2024-11-20"
                Write-WarningLog "Could not query model versions. Using fallback version: $ModelVersion"
            }
        } else {
            Write-InfoLog "Using specified model version: $ModelVersion"
        }
        
        # Create deployment with model version
        az cognitiveservices account deployment create `
            --name $openAIName `
            --resource-group $ResourceGroupName `
            --deployment-name $deploymentName `
            --model-name $ModelName `
            --model-version $ModelVersion `
            --model-format OpenAI `
            --sku-name "Standard" `
            --sku-capacity 10 `
            | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to deploy model $ModelName"
        }
        
        Write-SuccessLog "Model deployed: $deploymentName (version: $ModelVersion)"
    }
    
    # Enable managed identity if not already enabled
    if (-not $openAI.identity -or $openAI.identity.type -ne "SystemAssigned") {
        Write-InfoLog "Enabling system-assigned managed identity"
        az cognitiveservices account identity assign `
            --name $openAIName `
            --resource-group $ResourceGroupName `
            | Out-Null
        
        # Refresh OpenAI details
        $openAI = az cognitiveservices account show `
            --name $openAIName `
            --resource-group $ResourceGroupName `
            | ConvertFrom-Json
    } else {
        Write-InfoLog "Managed identity already enabled"
    }
    
    return @{
        Name = $openAIName
        Id = $openAI.id
        Endpoint = $endpoint
        DeploymentName = $deploymentName
        ModelName = $ModelName
        IdentityPrincipalId = $openAI.identity.principalId
    }
}
