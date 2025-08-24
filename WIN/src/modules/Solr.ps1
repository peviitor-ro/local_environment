# Solr.ps1 - Apache Solr deployment and configuration
# This module handles Solr container deployment, core creation, schema configuration, and authentication

# ============================================================================
# SOLR CONFIGURATION
# ============================================================================

# Get configuration from global config
$script:SolrConfig = @{
    # Container configuration
    ContainerName = $Global:PeviitorConfig.Containers.Solr.Name
    ContainerImage = $Global:PeviitorConfig.Containers.Solr.Image
    ContainerIP = $Global:PeviitorConfig.Containers.Solr.IP
    ContainerPort = $Global:PeviitorConfig.Containers.Solr.Port
    NetworkName = $Global:PeviitorConfig.Network.Name
    
    # Solr configuration
    Cores = $Global:PeviitorConfig.Solr.Cores
    DefaultUser = $Global:PeviitorConfig.Solr.DefaultUser
    DefaultPassword = $Global:PeviitorConfig.Solr.DefaultPassword
    SecurityFile = $Global:PeviitorConfig.Solr.SecurityFile
    DefaultCredentialsHash = $Global:PeviitorConfig.Solr.DefaultCredentialsHash
    
    # Schema configuration
    JobsSchema = $Global:PeviitorConfig.SolrSchema.JobsCore
    LogoSchema = $Global:PeviitorConfig.SolrSchema.LogoCore
    FirmeSchema = $Global:PeviitorConfig.SolrSchema.FirmeCore
    
    # Path configuration
    SolrDataPath = $Global:PeviitorConfig.Paths.SolrData
    
    # Timeouts
    StartupTimeout = 60    # seconds to wait for Solr to start
    CoreTimeout = 30       # seconds to wait for core operations
    SchemaTimeout = 10     # seconds to wait for schema operations
    AuthTimeout = 15       # seconds to wait for auth operations
}

# ============================================================================
# SOLR DEPLOYMENT
# ============================================================================

function Deploy-SolrSearch {
    <#
    .SYNOPSIS
    Deploys the complete Apache Solr search engine with cores, schema, and authentication.
    
    .PARAMETER SolrUser
    Custom Solr username
    
    .PARAMETER SolrPassword
    Custom Solr password
    
    .PARAMETER Force
    Force redeployment even if already deployed
    
    .OUTPUTS
    Returns $true if Solr deployment was successful
    
    .EXAMPLE
    Deploy-SolrSearch -SolrUser "admin" -SolrPassword "SecurePassword123!" -Force
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SolrUser,
        
        [Parameter(Mandatory=$true)]
        [string]$SolrPassword,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-LogHeader -Title "APACHE SOLR DEPLOYMENT" -Level 2
    
    try {
        # Check if already deployed
        if (-not $Force) {
            $existingStatus = Test-SolrDeployment
            if ($existingStatus.IsDeployed -and $existingStatus.IsWorking) {
                Write-DetailedLog "Solr is already deployed and working" -Level "SUCCESS"
                return $true
            }
        }
        
        $deploySteps = @(
            @{ Name = "Deploy Solr Container"; Function = { Start-SolrContainer } }
            @{ Name = "Wait for Solr Startup"; Function = { Wait-ForSolrReady } }
            @{ Name = "Create Solr Cores"; Function = { New-SolrCores } }
            @{ Name = "Configure Jobs Schema"; Function = { Set-JobsCoreSchema } }
            @{ Name = "Configure Logo Schema"; Function = { Set-LogoCoreSchema } }
            @{ Name = "Configure Firme Schema"; Function = { Set-FirmeCoreSchema } }
            @{ Name = "Setup Suggest Component"; Function = { Set-SuggestComponent } }
            @{ Name = "Configure Authentication"; Function = { Set-SolrAuthentication -SolrUser $SolrUser -SolrPassword $SolrPassword } }
            @{ Name = "Verify Deployment"; Function = { Test-SolrDeployment } }
        )
        
        $stepNumber = 1
        $totalSteps = $deploySteps.Count
        
        foreach ($step in $deploySteps) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Solr Deployment"
            
            $result = & $step.Function
            
            if ($result -and (($result -is [bool] -and $result) -or ($result -is [hashtable] -and $result.Success))) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } else {
                Write-DetailedLog "❌ $($step.Name): FAILED" -Level "ERROR"
                Write-DetailedLog "Solr deployment failed at step: $($step.Name)" -Level "ERROR"
                
                # Attempt rollback
                Write-DetailedLog "Attempting Solr deployment rollback..." -Level "WARN"
                Invoke-SolrRollback
                
                return $false
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        Write-DetailedLog "🎉 Solr deployment completed successfully" -Level "SUCCESS"
        
        # Display access information
        Show-SolrAccessInfo -SolrUser $SolrUser
        
        return $true
        
    } catch {
        Write-InstallationError -ErrorMessage "Solr deployment failed" -Exception $_.Exception
        Invoke-SolrRollback
        return $false
    }
}

function Start-SolrContainer {
    <#
    .SYNOPSIS
    Starts the Apache Solr container.
    
    .OUTPUTS
    Returns $true if container was started successfully
    
    .EXAMPLE
    Start-SolrContainer
    #>
    
    Write-DetailedLog "Starting Apache Solr container" -Level "INFO"
    Show-Progress -Activity "Solr Container" -Status "Preparing container..." -PercentComplete 10
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $containerImage = $script:SolrConfig.ContainerImage
        $containerIP = $script:SolrConfig.ContainerIP
        $containerPort = $script:SolrConfig.ContainerPort
        $networkName = $script:SolrConfig.NetworkName
        $solrDataPath = $script:SolrConfig.SolrDataPath
        
        # Stop and remove existing container if it exists
        $existingContainer = docker ps -aq -f name=$containerName 2>$null
        if ($existingContainer) {
            Write-DetailedLog "Stopping existing container: $containerName" -Level "INFO"
            docker stop $containerName 2>$null | Out-Null
            docker rm $containerName 2>$null | Out-Null
        }
        
        # Ensure Solr data directory exists with proper permissions
        if (-not (Test-Path $solrDataPath)) {
            New-Item -Path $solrDataPath -ItemType Directory -Force | Out-Null
        }
        
        Show-Progress -Activity "Solr Container" -Status "Pulling container image..." -PercentComplete 20
        
        # Pull the latest Solr image
        Write-DetailedLog "Pulling Solr image: $containerImage" -Level "DEBUG"
        docker pull $containerImage 2>$null | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Warning: Failed to pull latest image, using cached version" -Level "WARN"
        }
        
        Show-Progress -Activity "Solr Container" -Status "Starting container..." -PercentComplete 40
        
        # Prepare Docker run arguments
        $dockerArgs = @(
            "run",
            "--name", $containerName,
            "--network", $networkName,
            "--ip", $containerIP,
            "--restart=always",
            "-d",
            "-p", $containerPort,
            "-v", "${solrDataPath}:/var/solr/data",
            $containerImage
        )
        
        Write-DetailedLog "Starting container with command: docker $($dockerArgs -join ' ')" -Level "DEBUG"
        
        # Start the container
        $containerID = docker @dockerArgs 2>$null
        
        if ($LASTEXITCODE -ne 0 -or -not $containerID) {
            Write-DetailedLog "Failed to start Solr container" -Level "ERROR"
            
            # Get more detailed error information
            $dockerError = docker @dockerArgs 2>&1
            Write-DetailedLog "Docker error: $dockerError" -Level "ERROR"
            
            return $false
        }
        
        Show-Progress -Activity "Solr Container" -Status "Waiting for container to be ready..." -PercentComplete 70
        
        # Wait for container to be running
        $containerReady = Wait-ForContainerRunning -ContainerName $containerName -TimeoutSeconds 30
        
        if (-not $containerReady) {
            Write-DetailedLog "Container failed to start within timeout" -Level "ERROR"
            return $false
        }
        
        # Set proper permissions on Solr data directory
        Set-SolrDataPermissions
        
        Show-Progress -Activity "Solr Container" -Status "Container started successfully" -PercentComplete 100
        Write-DetailedLog "Solr container started successfully" -Level "SUCCESS"
        Write-DetailedLog "Container ID: $($containerID.Substring(0,12))" -Level "DEBUG"
        Write-DetailedLog "Container URL: http://localhost:$($containerPort.Split(':')[0])/solr/" -Level "INFO"
        
        return $true
        
    } catch {
        Write-DetailedLog "Solr container deployment failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Wait-ForContainerRunning {
    <#
    .SYNOPSIS
    Waits for a Docker container to be in running state.
    
    .PARAMETER ContainerName
    Name of the container to wait for
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    
    .OUTPUTS
    Returns $true if container is running within timeout
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter()]
        [int]$TimeoutSeconds = 60
    )
    
    $startTime = Get-Date
    
    while ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            # Check if container is running
            $containerStatus = docker ps -f name=$ContainerName --format "{{.Status}}" 2>$null
            
            if ($containerStatus -and $containerStatus -like "*Up*") {
                Write-DetailedLog "Container is running: $ContainerName" -Level "DEBUG"
                return $true
            }
            
            Start-Sleep -Seconds 2
            
        } catch {
            # Continue waiting
        }
    }
    
    Write-DetailedLog "Container did not start within $TimeoutSeconds seconds" -Level "ERROR"
    return $false
}

function Wait-ForSolrReady {
    <#
    .SYNOPSIS
    Waits for Solr to be fully ready and accepting requests.
    
    .OUTPUTS
    Returns $true if Solr is ready within timeout
    
    .EXAMPLE
    Wait-ForSolrReady
    #>
    
    Write-DetailedLog "Waiting for Solr to be ready" -Level "INFO"
    Show-Progress -Activity "Solr Startup" -Status "Checking Solr availability..." -PercentComplete 10
    
    $containerName = $script:SolrConfig.ContainerName
    $timeout = $script:SolrConfig.StartupTimeout
    $startTime = Get-Date
    
    try {
        while ((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            try {
                # Test Solr admin API
                $testResult = docker exec $containerName curl -s "http://localhost:8983/solr/admin/info/system" 2>$null
                
                if ($LASTEXITCODE -eq 0 -and $testResult -like "*solr-impl*") {
                    Write-DetailedLog "Solr is ready and responding" -Level "SUCCESS"
                    Show-Progress -Activity "Solr Startup" -Status "Solr is ready" -PercentComplete 100
                    return $true
                }
                
                # Update progress
                $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
                $progressPercent = [math]::Min(90, ($elapsedSeconds / $timeout) * 90)
                Show-Progress -Activity "Solr Startup" -Status "Waiting for Solr... ($([math]::Round($elapsedSeconds))s)" -PercentComplete $progressPercent
                
                Start-Sleep -Seconds 5
                
            } catch {
                # Continue waiting
                Start-Sleep -Seconds 2
            }
        }
        
        Write-DetailedLog "Solr did not become ready within $timeout seconds" -Level "ERROR"
        return $false
        
    } catch {
        Write-DetailedLog "Error waiting for Solr: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Set-SolrDataPermissions {
    <#
    .SYNOPSIS
    Sets proper permissions on the Solr data directory.
    
    .EXAMPLE
    Set-SolrDataPermissions
    #>
    
    try {
        $solrDataPath = $script:SolrConfig.SolrDataPath
        $containerName = $script:SolrConfig.ContainerName
        
        Write-DetailedLog "Setting Solr data permissions" -Level "DEBUG"
        
        # Set ownership to Solr user (UID 8983) inside container
        docker exec $containerName chown -R solr:solr /var/solr/data 2>$null | Out-Null
        
        # Set permissions on host (for Windows)
        if (Test-Path $solrDataPath) {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            
            # Use icacls to set full control for current user
            $icaclsArgs = @(
                "`"$solrDataPath`"",
                "/grant",
                "`"$currentUser`":(OI)(CI)F",
                "/T",
                "/Q"
            )
            
            Start-Process -FilePath "icacls" -ArgumentList $icaclsArgs -Wait -NoNewWindow -WindowStyle Hidden | Out-Null
        }
        
    } catch {
        Write-DetailedLog "Warning: Could not set Solr data permissions: $($_.Exception.Message)" -Level "WARN"
    }
}

# ============================================================================
# SOLR CORES MANAGEMENT
# ============================================================================

function New-SolrCores {
    <#
    .SYNOPSIS
    Creates all required Solr cores.
    
    .OUTPUTS
    Returns $true if all cores were created successfully
    
    .EXAMPLE
    New-SolrCores
    #>
    
    Write-DetailedLog "Creating Solr cores" -Level "INFO"
    Show-Progress -Activity "Solr Cores" -Status "Creating cores..." -PercentComplete 10
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $cores = $script:SolrConfig.Cores
        
        $coreNumber = 1
        $totalCores = $cores.Count
        
        foreach ($coreName in $cores) {
            $progressPercent = ($coreNumber / $totalCores) * 80 + 10
            Show-Progress -Activity "Solr Cores" -Status "Creating core: $coreName" -PercentComplete $progressPercent
            
            Write-DetailedLog "Creating Solr core: $coreName" -Level "DEBUG"
            
            # Create the core using Solr admin API
            $createResult = docker exec -it $containerName bin/solr create_core -c $coreName 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-DetailedLog "Core created successfully: $coreName" -Level "SUCCESS"
            } else {
                # Check if core already exists
                $coreStatus = docker exec $containerName curl -s "http://localhost:8983/solr/admin/cores?action=STATUS&core=$coreName" 2>$null
                
                if ($coreStatus -and $coreStatus -like "*$coreName*") {
                    Write-DetailedLog "Core already exists: $coreName" -Level "INFO"
                } else {
                    Write-DetailedLog "Failed to create core: $coreName" -Level "ERROR"
                    return $false
                }
            }
            
            $coreNumber++
        }
        
        Show-Progress -Activity "Solr Cores" -Status "All cores created successfully" -PercentComplete 100
        Write-DetailedLog "All Solr cores created successfully" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error creating Solr cores: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

# ============================================================================
# SCHEMA CONFIGURATION
# ============================================================================

function Set-JobsCoreSchema {
    <#
    .SYNOPSIS
    Configures the schema for the Jobs core with all required fields and copy fields.
    
    .OUTPUTS
    Returns $true if schema was configured successfully
    
    .EXAMPLE
    Set-JobsCoreSchema
    #>
    
    Write-DetailedLog "Configuring Jobs core schema" -Level "INFO"
    Show-Progress -Activity "Jobs Schema" -Status "Adding fields..." -PercentComplete 10
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $jobsSchema = $script:SolrConfig.JobsSchema
        
        # Add all fields
        $fieldNumber = 1
        $totalFields = $jobsSchema.Fields.Count
        
        foreach ($field in $jobsSchema.Fields) {
            $progressPercent = ($fieldNumber / $totalFields) * 60 + 10
            Show-Progress -Activity "Jobs Schema" -Status "Adding field: $($field.name)" -PercentComplete $progressPercent
            
            $success = Add-SolrField -ContainerName $containerName -CoreName "jobs" -Field $field
            
            if (-not $success) {
                Write-DetailedLog "Failed to add field: $($field.name)" -Level "ERROR"
                return $false
            }
            
            $fieldNumber++
        }
        
        Show-Progress -Activity "Jobs Schema" -Status "Adding copy fields..." -PercentComplete 70
        
        # Add copy fields
        $copyFieldNumber = 1
        $totalCopyFields = $jobsSchema.CopyFields.Count
        
        foreach ($copyField in $jobsSchema.CopyFields) {
            $progressPercent = ($copyFieldNumber / $totalCopyFields) * 20 + 70
            Show-Progress -Activity "Jobs Schema" -Status "Adding copy field: $($copyField.source)" -PercentComplete $progressPercent
            
            $success = Add-SolrCopyField -ContainerName $containerName -CoreName "jobs" -CopyField $copyField
            
            if (-not $success) {
                Write-DetailedLog "Failed to add copy field: $($copyField.source) -> $($copyField.dest)" -Level "ERROR"
                return $false
            }
            
            $copyFieldNumber++
        }
        
        Show-Progress -Activity "Jobs Schema" -Status "Jobs schema configured successfully" -PercentComplete 100
        Write-DetailedLog "Jobs core schema configured successfully" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error configuring Jobs schema: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Set-LogoCoreSchema {
    <#
    .SYNOPSIS
    Configures the schema for the Logo core.
    
    .OUTPUTS
    Returns $true if schema was configured successfully
    
    .EXAMPLE
    Set-LogoCoreSchema
    #>
    
    Write-DetailedLog "Configuring Logo core schema" -Level "INFO"
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $logoSchema = $script:SolrConfig.LogoSchema
        
        # Add fields for Logo core
        foreach ($field in $logoSchema.Fields) {
            $success = Add-SolrField -ContainerName $containerName -CoreName "logo" -Field $field
            
            if (-not $success) {
                Write-DetailedLog "Failed to add Logo field: $($field.name)" -Level "ERROR"
                return $false
            }
        }
        
        Write-DetailedLog "Logo core schema configured successfully" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Error configuring Logo schema: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Set-FirmeCoreSchema {
    <#
    .SYNOPSIS
    Configures the schema for the Firme core with all required fields and copy fields.
    
    .OUTPUTS
    Returns $true if schema was configured successfully
    
    .EXAMPLE
    Set-FirmeCoreSchema
    #>
    
    Write-DetailedLog "Configuring Firme core schema" -Level "INFO"
    Show-Progress -Activity "Firme Schema" -Status "Adding fields..." -PercentComplete 10
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $firmeSchema = $script:SolrConfig.FirmeSchema
        
        # Add all fields
        $fieldNumber = 1
        $totalFields = $firmeSchema.Fields.Count
        
        foreach ($field in $firmeSchema.Fields) {
            $progressPercent = ($fieldNumber / $totalFields) * 70 + 10
            Show-Progress -Activity "Firme Schema" -Status "Adding field: $($field.name)" -PercentComplete $progressPercent
            
            $success = Add-SolrField -ContainerName $containerName -CoreName "firme" -Field $field
            
            if (-not $success) {
                Write-DetailedLog "Failed to add field: $($field.name)" -Level "ERROR"
                return $false
            }
            
            $fieldNumber++
        }
        
        Show-Progress -Activity "Firme Schema" -Status "Adding copy fields..." -PercentComplete 80
        
        # Add copy fields
        foreach ($copyField in $firmeSchema.CopyFields) {
            $success = Add-SolrCopyField -ContainerName $containerName -CoreName "firme" -CopyField $copyField
            
            if (-not $success) {
                Write-DetailedLog "Failed to add copy field: $($copyField.source) -> $($copyField.dest)" -Level "ERROR"
                return $false
            }
        }
        
        Show-Progress -Activity "Firme Schema" -Status "Firme schema configured successfully" -PercentComplete 100
        Write-DetailedLog "Firme core schema configured successfully" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error configuring Firme schema: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Add-SolrField {
    <#
    .SYNOPSIS
    Adds a field to a Solr core schema.
    
    .PARAMETER ContainerName
    Name of the Solr container
    
    .PARAMETER CoreName
    Name of the Solr core
    
    .PARAMETER Field
    Field definition hashtable
    
    .OUTPUTS
    Returns $true if field was added successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$true)]
        [string]$CoreName,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Field
    )
    
    try {
        # Build field definition JSON
        $fieldDef = @{
            name = $Field.name
            type = $Field.type
            stored = $Field.stored
            indexed = $Field.indexed
        }
        
        # Add optional properties
        if ($Field.multiValued) { $fieldDef.multiValued = $Field.multiValued }
        if ($Field.docValues) { $fieldDef.docValues = $Field.docValues }
        if ($Field.uninvertible) { $fieldDef.uninvertible = $Field.uninvertible }
        if ($Field.omitNorms) { $fieldDef.omitNorms = $Field.omitNorms }
        if ($Field.omitTermFreqAndPositions) { $fieldDef.omitTermFreqAndPositions = $Field.omitTermFreqAndPositions }
        if ($Field.sortMissingLast) { $fieldDef.sortMissingLast = $Field.sortMissingLast }
        
        # Convert to JSON
        $fieldJson = $fieldDef | ConvertTo-Json -Compress
        $addFieldJson = @{ "add-field" = @($fieldDef) } | ConvertTo-Json -Compress
        
        Write-DetailedLog "Adding field to $CoreName core: $($Field.name)" -Level "DEBUG"
        
        # Execute curl command inside container
        $curlCmd = "curl -X POST -H 'Content-Type: application/json' --data '$addFieldJson' http://localhost:8983/solr/$CoreName/schema"
        
        $result = docker exec -it $ContainerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "Field added successfully: $($Field.name)" -Level "DEBUG"
            return $true
        } else {
            # Check if field already exists (which is acceptable)
            if ($result -and $result -like "*already exists*") {
                Write-DetailedLog "Field already exists: $($Field.name)" -Level "DEBUG"
                return $true
            } else {
                Write-DetailedLog "Failed to add field: $($Field.name), Result: $result" -Level "ERROR"
                return $false
            }
        }
        
    } catch {
        Write-DetailedLog "Error adding Solr field $($Field.name): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Add-SolrCopyField {
    <#
    .SYNOPSIS
    Adds a copy field to a Solr core schema.
    
    .PARAMETER ContainerName
    Name of the Solr container
    
    .PARAMETER CoreName
    Name of the Solr core
    
    .PARAMETER CopyField
    Copy field definition hashtable
    
    .OUTPUTS
    Returns $true if copy field was added successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$true)]
        [string]$CoreName,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$CopyField
    )
    
    try {
        # Build copy field definition JSON
        $copyFieldDef = @{
            source = $CopyField.source
            dest = $CopyField.dest
        }
        
        $addCopyFieldJson = @{ "add-copy-field" = $copyFieldDef } | ConvertTo-Json -Compress
        
        Write-DetailedLog "Adding copy field to $CoreName core: $($CopyField.source) -> $($CopyField.dest)" -Level "DEBUG"
        
        # Execute curl command inside container
        $curlCmd = "curl -X POST -H 'Content-Type: application/json' --data '$addCopyFieldJson' http://localhost:8983/solr/$CoreName/schema"
        
        $result = docker exec -it $ContainerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "Copy field added successfully: $($CopyField.source) -> $($CopyField.dest)" -Level "DEBUG"
            return $true
        } else {
            # Check if copy field already exists (which is acceptable)
            if ($result -and $result -like "*already exists*") {
                Write-DetailedLog "Copy field already exists: $($CopyField.source) -> $($CopyField.dest)" -Level "DEBUG"
                return $true
            } else {
                Write-DetailedLog "Failed to add copy field: $($CopyField.source) -> $($CopyField.dest), Result: $result" -Level "ERROR"
                return $false
            }
        }
        
    } catch {
        Write-DetailedLog "Error adding copy field $($CopyField.source) -> $($CopyField.dest): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# SUGGEST COMPONENT CONFIGURATION
# ============================================================================

function Set-SuggestComponent {
    <#
    .SYNOPSIS
    Configures the suggest component for job title auto-completion.
    
    .OUTPUTS
    Returns $true if suggest component was configured successfully
    
    .EXAMPLE
    Set-SuggestComponent
    #>
    
    Write-DetailedLog "Configuring suggest component for jobs core" -Level "INFO"
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $suggestConfig = $script:SolrConfig.JobsSchema.SuggestComponent
        
        # Add suggest component
        $suggestComponentDef = @{
            "add-searchcomponent" = @{
                name = "suggest"
                class = "solr.SuggestComponent"
                suggester = @{
                    name = $suggestConfig.name
                    lookupImpl = $suggestConfig.lookupImpl
                    dictionaryImpl = $suggestConfig.dictionaryImpl
                    field = $suggestConfig.field
                    suggestAnalyzerFieldType = "text_general"
                    buildOnCommit = "true"
                    buildOnStartup = "false"
                }
            }
        }
        
        $suggestComponentJson = $suggestComponentDef | ConvertTo-Json -Compress -Depth 5
        
        Write-DetailedLog "Adding suggest component to jobs core" -Level "DEBUG"
        
        # Execute curl command to add suggest component
        $curlCmd = "curl -X POST -H 'Content-Type: application/json' --data '$suggestComponentJson' http://localhost:8983/solr/jobs/config"
        
        $result = docker exec -it $containerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to add suggest component: $result" -Level "WARN"
            # Continue anyway as this is not critical for basic functionality
        }
        
        # Add suggest request handler
        $suggestHandlerDef = @{
            "add-requesthandler" = @{
                name = "/suggest"
                class = "solr.SearchHandler"
                startup = "lazy"
                defaults = @{
                    suggest = "true"
                    "suggest.dictionary" = $suggestConfig.name
                    "suggest.count" = "10"
                }
                components = @("suggest")
            }
        }
        
        $suggestHandlerJson = $suggestHandlerDef | ConvertTo-Json -Compress -Depth 5
        
        Write-DetailedLog "Adding suggest request handler to jobs core" -Level "DEBUG"
        
        # Execute curl command to add suggest request handler
        $curlCmd = "curl -X POST -H 'Content-Type: application/json' --data '$suggestHandlerJson' http://localhost:8983/solr/jobs/config"
        
        $result = docker exec -it $containerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "Suggest component configured successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Failed to add suggest request handler: $result" -Level "WARN"
            # Continue anyway as this is not critical for basic functionality
            return $true
        }
        
    } catch {
        Write-DetailedLog "Error configuring suggest component: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# AUTHENTICATION CONFIGURATION
# ============================================================================

function Set-SolrAuthentication {
    <#
    .SYNOPSIS
    Configures Solr authentication with custom user credentials.
    
    .PARAMETER SolrUser
    Custom Solr username
    
    .PARAMETER SolrPassword
    Custom Solr password
    
    .OUTPUTS
    Returns $true if authentication was configured successfully
    
    .EXAMPLE
    Set-SolrAuthentication -SolrUser "admin" -SolrPassword "SecurePassword123!"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SolrUser,
        
        [Parameter(Mandatory=$true)]
        [string]$SolrPassword
    )
    
    Write-DetailedLog "Configuring Solr authentication" -Level "INFO"
    Show-Progress -Activity "Solr Authentication" -Status "Creating security configuration..." -PercentComplete 10
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $defaultUser = $script:SolrConfig.DefaultUser
        $defaultPassword = $script:SolrConfig.DefaultPassword
        $defaultCredHash = $script:SolrConfig.DefaultCredentialsHash
        
        # Create security.json content
        $securityConfig = @{
            authentication = @{
                blockUnknown = $true
                class = "solr.BasicAuthPlugin"
                credentials = @{
                    solr = $defaultCredHash
                }
                realm = "My Solr users"
                forwardCredentials = $false
            }
            authorization = @{
                class = "solr.RuleBasedAuthorizationPlugin"
                permissions = @(
                    @{
                        name = "security-edit"
                        role = "admin"
                    }
                )
                "user-role" = @{
                    solr = "admin"
                }
            }
        }
        
        $securityJson = $securityConfig | ConvertTo-Json -Depth 10
        
        Show-Progress -Activity "Solr Authentication" -Status "Installing security configuration..." -PercentComplete 30
        
        # Create security.json file on host
        $securityFile = Join-Path (Get-Location) $script:SolrConfig.SecurityFile
        $securityJson | Set-Content -Path $securityFile -Encoding UTF8
        
        Write-DetailedLog "Security configuration file created: $securityFile" -Level "DEBUG"
        
        # Copy security.json to container
        $copyResult = docker cp $securityFile "${containerName}:/var/solr/data/security.json" 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to copy security.json to container" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "Solr Authentication" -Status "Restarting Solr container..." -PercentComplete 50
        
        # Restart container to apply authentication
        Write-DetailedLog "Restarting Solr container to apply authentication" -Level "DEBUG"
        docker restart $containerName 2>$null | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to restart Solr container" -Level "ERROR"
            return $false
        }
        
        # Wait for Solr to be ready again
        Show-Progress -Activity "Solr Authentication" -Status "Waiting for Solr to be ready..." -PercentComplete 60
        
        $solrReady = Wait-ForSolrReady
        if (-not $solrReady) {
            Write-DetailedLog "Solr failed to restart after authentication setup" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "Solr Authentication" -Status "Creating custom user..." -PercentComplete 70
        
        # Create new user
        $success = New-SolrUser -ContainerName $containerName -DefaultUser $defaultUser -DefaultPassword $defaultPassword -NewUser $SolrUser -NewPassword $SolrPassword
        
        if (-not $success) {
            Write-DetailedLog "Failed to create new Solr user" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "Solr Authentication" -Status "Removing default user..." -PercentComplete 90
        
        # Remove default user
        $success = Remove-SolrUser -ContainerName $containerName -AuthUser $SolrUser -AuthPassword $SolrPassword -UserToRemove $defaultUser
        
        if (-not $success) {
            Write-DetailedLog "Warning: Failed to remove default Solr user" -Level "WARN"
            # Continue anyway
        }
        
        # Set proper permissions on security.json
        docker exec $containerName chmod 600 /var/solr/data/security.json 2>$null | Out-Null
        
        # Final restart to ensure everything is working
        docker restart $containerName 2>$null | Out-Null
        Wait-ForSolrReady | Out-Null
        
        # Cleanup temporary security file
        Remove-Item $securityFile -Force -ErrorAction SilentlyContinue
        
        Show-Progress -Activity "Solr Authentication" -Status "Authentication configured successfully" -PercentComplete 100
        Write-DetailedLog "Solr authentication configured successfully" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error configuring Solr authentication: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function New-SolrUser {
    <#
    .SYNOPSIS
    Creates a new Solr user with admin role.
    
    .PARAMETER ContainerName
    Name of the Solr container
    
    .PARAMETER DefaultUser
    Default Solr username
    
    .PARAMETER DefaultPassword
    Default Solr password
    
    .PARAMETER NewUser
    New username to create
    
    .PARAMETER NewPassword
    New password
    
    .OUTPUTS
    Returns $true if user was created successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$true)]
        [string]$DefaultUser,
        
        [Parameter(Mandatory=$true)]
        [string]$DefaultPassword,
        
        [Parameter(Mandatory=$true)]
        [string]$NewUser,
        
        [Parameter(Mandatory=$true)]
        [string]$NewPassword
    )
    
    try {
        Write-DetailedLog "Creating new Solr user: $NewUser" -Level "DEBUG"
        
        # Create new user
        $createUserData = @{ "set-user" = @{ $NewUser = $NewPassword } } | ConvertTo-Json -Compress
        
        $curlCmd = "curl --user '$DefaultUser:$DefaultPassword' http://localhost:8983/solr/admin/authentication -H 'Content-type:application/json' -d '$createUserData'"
        
        $result = docker exec -it $ContainerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to create new user: $result" -Level "ERROR"
            return $false
        }
        
        # Assign admin role to new user
        $assignRoleData = @{ "set-user-role" = @{ $NewUser = @("admin") } } | ConvertTo-Json -Compress
        
        $curlCmd = "curl --user '$DefaultUser:$DefaultPassword' http://localhost:8983/solr/admin/authorization -H 'Content-type:application/json' -d '$assignRoleData'"
        
        $result = docker exec -it $ContainerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "New Solr user created successfully: $NewUser" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Failed to assign admin role to new user: $result" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error creating Solr user: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-SolrUser {
    <#
    .SYNOPSIS
    Removes a Solr user.
    
    .PARAMETER ContainerName
    Name of the Solr container
    
    .PARAMETER AuthUser
    Username for authentication
    
    .PARAMETER AuthPassword
    Password for authentication
    
    .PARAMETER UserToRemove
    Username to remove
    
    .OUTPUTS
    Returns $true if user was removed successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerName,
        
        [Parameter(Mandatory=$true)]
        [string]$AuthUser,
        
        [Parameter(Mandatory=$true)]
        [string]$AuthPassword,
        
        [Parameter(Mandatory=$true)]
        [string]$UserToRemove
    )
    
    try {
        Write-DetailedLog "Removing Solr user: $UserToRemove" -Level "DEBUG"
        
        # Delete user
        $deleteUserData = @{ "delete-user" = @($UserToRemove) } | ConvertTo-Json -Compress
        
        $curlCmd = "curl --user '$AuthUser:$AuthPassword' http://localhost:8983/solr/admin/authentication -H 'Content-type:application/json' -d '$deleteUserData'"
        
        $result = docker exec -it $ContainerName bash -c $curlCmd 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "Solr user removed successfully: $UserToRemove" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Failed to remove Solr user: $result" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error removing Solr user: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# SOLR DEPLOYMENT VERIFICATION
# ============================================================================

function Test-SolrDeployment {
    <#
    .SYNOPSIS
    Tests the Solr deployment to ensure it's working correctly.
    
    .OUTPUTS
    Returns hashtable with deployment status information
    
    .EXAMPLE
    $status = Test-SolrDeployment
    #>
    
    Write-DetailedLog "Testing Solr deployment" -Level "INFO"
    
    $result = @{
        IsDeployed = $false
        IsWorking = $false
        ContainerRunning = $false
        SolrResponding = $false
        CoresCreated = $false
        AuthenticationWorking = $false
        Issues = @()
        CoreStatus = @{}
    }
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $containerPort = ($script:SolrConfig.ContainerPort -split ':')[0]
        $cores = $script:SolrConfig.Cores
        
        # Test 1: Check if container is running
        $containerStatus = docker ps -f name=$containerName --format "{{.Status}}" 2>$null
        
        if ($containerStatus -and $containerStatus -like "*Up*") {
            $result.ContainerRunning = $true
            Write-DetailedLog "✅ Container is running: $containerName" -Level "DEBUG"
        } else {
            $result.Issues += "Container is not running"
            Write-DetailedLog "❌ Container is not running: $containerName" -Level "ERROR"
        }
        
        if ($result.ContainerRunning) {
            $result.IsDeployed = $true
            
            # Test 2: Check Solr responsiveness
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$containerPort/solr/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 401) {
                    # 401 is acceptable if authentication is enabled
                    $result.SolrResponding = $true
                    Write-DetailedLog "✅ Solr is responding" -Level "DEBUG"
                } else {
                    $result.Issues += "Solr returned status code: $($response.StatusCode)"
                }
            } catch {
                $result.Issues += "Solr is not responding: $($_.Exception.Message)"
                Write-DetailedLog "❌ Solr responsiveness test failed: $($_.Exception.Message)" -Level "ERROR"
            }
            
            # Test 3: Check cores
            foreach ($coreName in $cores) {
                try {
                    $coreResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/solr/admin/cores?action=STATUS&core=$coreName" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                    
                    if ($coreResponse.StatusCode -eq 200 -and $coreResponse.Content -like "*$coreName*") {
                        $result.CoreStatus[$coreName] = $true
                        Write-DetailedLog "✅ Core is available: $coreName" -Level "DEBUG"
                    } else {
                        $result.CoreStatus[$coreName] = $false
                        $result.Issues += "Core is not available: $coreName"
                    }
                } catch {
                    $result.CoreStatus[$coreName] = $false
                    $result.Issues += "Core test failed: $coreName - $($_.Exception.Message)"
                    Write-DetailedLog "❌ Core test failed: $coreName - $($_.Exception.Message)" -Level "ERROR"
                }
            }
            
            $result.CoresCreated = ($result.CoreStatus.Values | Where-Object { $_ -eq $true }).Count -eq $cores.Count
            
            # Test 4: Test authentication (if enabled)
            try {
                $adminResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/solr/admin/info/system" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($adminResponse.StatusCode -eq 401) {
                    # Authentication is working (returns 401 without credentials)
                    $result.AuthenticationWorking = $true
                    Write-DetailedLog "✅ Authentication is enabled" -Level "DEBUG"
                } elseif ($adminResponse.StatusCode -eq 200) {
                    # Authentication might not be enabled yet, but Solr is working
                    Write-DetailedLog "⚠️ Solr is responding but authentication may not be enabled" -Level "WARN"
                }
            } catch {
                # Could be due to authentication, which is expected
                if ($_.Exception.Message -like "*401*") {
                    $result.AuthenticationWorking = $true
                    Write-DetailedLog "✅ Authentication is working" -Level "DEBUG"
                }
            }
            
            # Determine if deployment is working
            $result.IsWorking = $result.SolrResponding -and $result.CoresCreated
        }
        
        # Log results
        if ($result.IsWorking) {
            Write-DetailedLog "Solr deployment verification: PASSED" -Level "SUCCESS"
        } else {
            Write-DetailedLog "Solr deployment verification: FAILED" -Level "ERROR"
            foreach ($issue in $result.Issues) {
                Write-DetailedLog "  - $issue" -Level "ERROR"
            }
        }
        
    } catch {
        $result.Issues += "Deployment test failed: $($_.Exception.Message)"
        Write-DetailedLog "Solr deployment test error: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $result
}

# ============================================================================
# SOLR STATUS AND REPORTING
# ============================================================================

function Show-SolrAccessInfo {
    <#
    .SYNOPSIS
    Displays access information for the deployed Solr instance.
    
    .PARAMETER SolrUser
    Solr username for access
    
    .EXAMPLE
    Show-SolrAccessInfo -SolrUser "admin"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SolrUser
    )
    
    $containerPort = ($script:SolrConfig.ContainerPort -split ':')[0]
    
    Write-LogHeader -Title "SOLR ACCESS INFORMATION" -Level 3
    
    Write-DetailedLog "Apache Solr is now accessible:" -Level "SUCCESS"
    Write-DetailedLog "🔍 Solr Admin UI: http://localhost:$containerPort/solr/" -Level "INFO"
    Write-DetailedLog "👤 Username: $SolrUser" -Level "INFO"
    Write-DetailedLog "🔑 Password: [As configured]" -Level "INFO"
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "Available Cores:" -Level "INFO"
    
    foreach ($coreName in $script:SolrConfig.Cores) {
        Write-DetailedLog "  📊 $coreName: http://localhost:$containerPort/solr/#/~cores/$coreName" -Level "INFO"
    }
    
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "🎉 Solr deployment completed successfully!" -Level "SUCCESS"
}

function Get-SolrStatus {
    <#
    .SYNOPSIS
    Gets comprehensive status of the Solr deployment.
    
    .OUTPUTS
    Returns hashtable with detailed status information
    
    .EXAMPLE
    $status = Get-SolrStatus
    #>
    
    $status = @{
        Container = @{}
        Cores = @{}
        Authentication = @{}
        Performance = @{}
        IsHealthy = $false
    }
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        $containerPort = ($script:SolrConfig.ContainerPort -split ':')[0]
        $cores = $script:SolrConfig.Cores
        
        # Container status
        $containerExists = docker ps -aq -f name=$containerName 2>$null
        $containerRunning = docker ps -q -f name=$containerName 2>$null
        
        $status.Container = @{
            Name = $containerName
            Exists = [bool]$containerExists
            Running = [bool]$containerRunning
            Status = if ($containerRunning) { "Running" } elseif ($containerExists) { "Stopped" } else { "Not Found" }
        }
        
        if ($containerRunning) {
            try {
                $containerInfo = docker inspect $containerName 2>$null | ConvertFrom-Json
                if ($containerInfo) {
                    $status.Container.StartedAt = $containerInfo[0].State.StartedAt
                    $status.Container.IPAddress = $containerInfo[0].NetworkSettings.Networks.($script:SolrConfig.NetworkName).IPAddress
                }
            } catch {
                # Could not get additional container info
            }
        }
        
        # Core status
        foreach ($coreName in $cores) {
            try {
                $coreResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/solr/admin/cores?action=STATUS&core=$coreName" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                
                $status.Cores[$coreName] = @{
                    Exists = ($coreResponse.StatusCode -eq 200 -and $coreResponse.Content -like "*$coreName*")
                    Accessible = $true
                    Error = $null
                }
            } catch {
                $status.Cores[$coreName] = @{
                    Exists = $false
                    Accessible = $false
                    Error = $_.Exception.Message
                }
            }
        }
        
        # Authentication status
        try {
            $authResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/solr/admin/info/system" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            
            $status.Authentication = @{
                Enabled = ($authResponse.StatusCode -eq 401)
                Working = $true
            }
        } catch {
            $status.Authentication = @{
                Enabled = ($_.Exception.Message -like "*401*")
                Working = ($_.Exception.Message -like "*401*")
            }
        }
        
        # Overall health assessment
        $coresHealthy = ($status.Cores.Values | Where-Object { $_.Exists }).Count -eq $cores.Count
        $status.IsHealthy = $status.Container.Running -and $coresHealthy
        
    } catch {
        Write-DetailedLog "Error getting Solr status: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $status
}

function Write-SolrReport {
    <#
    .SYNOPSIS
    Displays a comprehensive Solr status report.
    
    .EXAMPLE
    Write-SolrReport
    #>
    
    $status = Get-SolrStatus
    
    Write-LogHeader -Title "SOLR STATUS REPORT" -Level 3
    
    # Container status
    $containerIcon = switch ($status.Container.Status) {
        "Running" { "🟢" }
        "Stopped" { "🟡" }
        "Not Found" { "🔴" }
        default { "❓" }
    }
    
    Write-DetailedLog "Container Status:" -Level "INFO"
    Write-DetailedLog "  $containerIcon $($status.Container.Name): $($status.Container.Status)" -Level "INFO"
    
    if ($status.Container.IPAddress) {
        Write-DetailedLog "    IP Address: $($status.Container.IPAddress)" -Level "INFO"
    }
    
    if ($status.Container.StartedAt) {
        $startTime = [DateTime]::Parse($status.Container.StartedAt).ToString("yyyy-MM-dd HH:mm:ss")
        Write-DetailedLog "    Started: $startTime" -Level "INFO"
    }
    
    # Core status
    Write-DetailedLog "Core Status:" -Level "INFO"
    foreach ($coreName in $script:SolrConfig.Cores) {
        $coreStatus = $status.Cores[$coreName]
        $coreIcon = if ($coreStatus.Exists) { "✅" } else { "❌" }
        
        Write-DetailedLog "  $coreIcon $coreName: $(if ($coreStatus.Exists) { 'Available' } else { 'Missing' })" -Level "INFO"
        
        if (-not $coreStatus.Accessible -and $coreStatus.Error) {
            Write-DetailedLog "    Error: $($coreStatus.Error)" -Level "ERROR"
        }
    }
    
    # Authentication status
    $authIcon = if ($status.Authentication.Enabled -and $status.Authentication.Working) { "🔐" } else { "🔓" }
    $authStatus = if ($status.Authentication.Enabled) { "Enabled" } else { "Disabled" }
    
    Write-DetailedLog "Authentication Status:" -Level "INFO"
    Write-DetailedLog "  $authIcon Authentication: $authStatus" -Level "INFO"
    
    # Overall health
    $healthIcon = if ($status.IsHealthy) { "💚" } else { "❤️" }
    $healthStatus = if ($status.IsHealthy) { "HEALTHY" } else { "UNHEALTHY" }
    
    Write-DetailedLog "$healthIcon Solr Overall Status: $healthStatus" -Level $(if ($status.IsHealthy) { "SUCCESS" } else { "ERROR" })
}

# ============================================================================
# SOLR ROLLBACK AND CLEANUP
# ============================================================================

function Invoke-SolrRollback {
    <#
    .SYNOPSIS
    Performs rollback of Solr deployment in case of failure.
    
    .OUTPUTS
    Returns $true if rollback was successful
    
    .EXAMPLE
    Invoke-SolrRollback
    #>
    
    Write-DetailedLog "Performing Solr deployment rollback" -Level "WARN"
    
    try {
        $containerName = $script:SolrConfig.ContainerName
        
        # Stop and remove container
        $containerExists = docker ps -aq -f name=$containerName 2>$null
        if ($containerExists) {
            Write-DetailedLog "Stopping and removing container: $containerName" -Level "INFO"
            docker stop $containerName 2>$null | Out-Null
            docker rm $containerName 2>$null | Out-Null
        }
        
        # Clean up Solr data directory (but preserve structure)
        $solrDataPath = $script:SolrConfig.SolrDataPath
        if (Test-Path $solrDataPath) {
            Write-DetailedLog "Cleaning Solr data directory: $solrDataPath" -Level "INFO"
            Get-ChildItem -Path $solrDataPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove temporary security file
        $securityFile = Join-Path (Get-Location) $script:SolrConfig.SecurityFile
        if (Test-Path $securityFile) {
            Remove-Item $securityFile -Force -ErrorAction SilentlyContinue
        }
        
        Write-DetailedLog "Solr rollback completed" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Solr rollback failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Solr deployment module loaded" -Level "DEBUG"

# Validate configuration on module load
if (-not $Global:PeviitorConfig) {
    Write-DetailedLog "Global Peviitor configuration not found - some functions may not work correctly" -Level "WARN"
}