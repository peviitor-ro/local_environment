# Frontend.ps1 - Frontend deployment and configuration
# This module handles Peviitor frontend build download, API setup, and Apache container deployment

# ============================================================================
# FRONTEND CONFIGURATION
# ============================================================================

# Get configuration from global config
$script:FrontendConfig = @{
    # GitHub repository configuration
    GitHubOwner = $Global:PeviitorConfig.Repositories.SearchEngine.Owner
    GitHubRepo = $Global:PeviitorConfig.Repositories.SearchEngine.Repo
    GitHubAsset = $Global:PeviitorConfig.Repositories.SearchEngine.AssetName
    APIGitHubOwner = $Global:PeviitorConfig.Repositories.API.Owner
    APIGitHubRepo = $Global:PeviitorConfig.Repositories.API.Repo
    APIBranch = $Global:PeviitorConfig.Repositories.API.Branch
    APIRepoURL = $Global:PeviitorConfig.Repositories.API.URL
    
    # Container configuration
    ContainerName = $Global:PeviitorConfig.Containers.Apache.Name
    ContainerImage = $Global:PeviitorConfig.Containers.Apache.Image
    ContainerIP = $Global:PeviitorConfig.Containers.Apache.IP
    ContainerPort = $Global:PeviitorConfig.Containers.Apache.Port
    NetworkName = $Global:PeviitorConfig.Network.Name
    
    # Path configuration
    BuildPath = $Global:PeviitorConfig.Paths.Build
    APIPath = $Global:PeviitorConfig.Paths.API
    
    # API configuration
    APIEnvFile = $Global:PeviitorConfig.API.EnvFile
    APIConfig = $Global:PeviitorConfig.API.Configuration
    
    # URLs and endpoints
    SwaggerPort = $Global:PeviitorConfig.Servers.SwaggerUIPort
    
    # Download configuration
    DownloadTimeout = 300  # 5 minutes
    ExtractionTimeout = 120  # 2 minutes
}

# ============================================================================
# FRONTEND BUILD MANAGEMENT
# ============================================================================

function Deploy-PeviitorFrontend {
    <#
    .SYNOPSIS
    Deploys the complete Peviitor frontend including build download, API setup, and container deployment.
    
    .PARAMETER Force
    Force redeployment even if already deployed
    
    .PARAMETER SolrUser
    Solr username for API configuration
    
    .PARAMETER SolrPassword
    Solr password for API configuration
    
    .OUTPUTS
    Returns $true if frontend deployment was successful
    
    .EXAMPLE
    Deploy-PeviitorFrontend -SolrUser "admin" -SolrPassword "password123" -Force
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter(Mandatory=$true)]
        [string]$SolrUser,
        
        [Parameter(Mandatory=$true)]
        [string]$SolrPassword
    )
    
    Write-LogHeader -Title "PEVIITOR FRONTEND DEPLOYMENT" -Level 2
    
    try {
        # Check if already deployed
        if (-not $Force) {
            $existingStatus = Test-FrontendDeployment
            if ($existingStatus.IsDeployed -and $existingStatus.IsWorking) {
                Write-DetailedLog "Frontend is already deployed and working" -Level "SUCCESS"
                return $true
            }
        }
        
        $deploySteps = @(
            @{ Name = "Download Frontend Build"; Function = { Get-FrontendBuild } }
            @{ Name = "Extract Build Files"; Function = { Expand-FrontendBuild } }
            @{ Name = "Setup API Repository"; Function = { Install-APIRepository } }
            @{ Name = "Configure API Environment"; Function = { Set-APIConfiguration -SolrUser $SolrUser -SolrPassword $SolrPassword } }
            @{ Name = "Deploy Apache Container"; Function = { Start-ApacheContainer } }
            @{ Name = "Configure Swagger UI"; Function = { Set-SwaggerConfiguration } }
            @{ Name = "Verify Deployment"; Function = { Test-FrontendDeployment } }
        )
        
        $stepNumber = 1
        $totalSteps = $deploySteps.Count
        
        foreach ($step in $deploySteps) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Frontend Deployment"
            
            $result = & $step.Function
            
            if ($result -and $result -is [bool] -and $result) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } elseif ($result -and $result -is [hashtable] -and $result.Success) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } else {
                Write-DetailedLog "❌ $($step.Name): FAILED" -Level "ERROR"
                Write-DetailedLog "Frontend deployment failed at step: $($step.Name)" -Level "ERROR"
                
                # Attempt rollback
                Write-DetailedLog "Attempting frontend deployment rollback..." -Level "WARN"
                Invoke-FrontendRollback
                
                return $false
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        Write-DetailedLog "🎉 Frontend deployment completed successfully" -Level "SUCCESS"
        
        # Display access URLs
        Show-FrontendAccessInfo
        
        return $true
        
    } catch {
        Write-InstallationError -ErrorMessage "Frontend deployment failed" -Exception $_.Exception
        Invoke-FrontendRollback
        return $false
    }
}

function Get-FrontendBuild {
    <#
    .SYNOPSIS
    Downloads the latest frontend build from GitHub releases.
    
    .OUTPUTS
    Returns hashtable with download results
    
    .EXAMPLE
    $result = Get-FrontendBuild
    #>
    
    Write-DetailedLog "Downloading frontend build from GitHub" -Level "INFO"
    Show-Progress -Activity "Frontend Download" -Status "Fetching release information..." -PercentComplete 10
    
    try {
        # Get latest release information
        $releaseInfo = Get-GitHubLatestRelease -Owner $script:FrontendConfig.GitHubOwner -Repo $script:FrontendConfig.GitHubRepo
        
        if (-not $releaseInfo.Success) {
            Write-DetailedLog "Failed to get release information: $($releaseInfo.Error)" -Level "ERROR"
            return @{ Success = $false; Error = $releaseInfo.Error }
        }
        
        Show-Progress -Activity "Frontend Download" -Status "Finding build asset..." -PercentComplete 20
        
        # Find the build asset
        $buildAsset = $releaseInfo.Assets | Where-Object { $_.name -eq $script:FrontendConfig.GitHubAsset }
        
        if (-not $buildAsset) {
            $error = "Build asset '$($script:FrontendConfig.GitHubAsset)' not found in release $($releaseInfo.Version)"
            Write-DetailedLog $error -Level "ERROR"
            return @{ Success = $false; Error = $error }
        }
        
        Write-DetailedLog "Found build asset: $($buildAsset.name) ($([math]::Round($buildAsset.size / 1MB, 1))MB)" -Level "INFO"
        
        Show-Progress -Activity "Frontend Download" -Status "Downloading build..." -PercentComplete 30
        
        # Download the build
        $downloadResult = Download-GitHubAsset -Asset $buildAsset -TargetPath $script:FrontendConfig.BuildPath
        
        if (-not $downloadResult.Success) {
            Write-DetailedLog "Failed to download build: $($downloadResult.Error)" -Level "ERROR"
            return $downloadResult
        }
        
        Show-Progress -Activity "Frontend Download" -Status "Download completed" -PercentComplete 100
        Write-DetailedLog "Frontend build downloaded successfully" -Level "SUCCESS"
        
        return @{
            Success = $true
            DownloadPath = $downloadResult.FilePath
            Version = $releaseInfo.Version
            Size = $buildAsset.size
        }
        
    } catch {
        $error = "Frontend build download failed: $($_.Exception.Message)"
        Write-DetailedLog $error -Level "ERROR"
        return @{ Success = $false; Error = $error }
    } finally {
        Hide-Progress
    }
}

function Expand-FrontendBuild {
    <#
    .SYNOPSIS
    Extracts the frontend build ZIP file to the build directory.
    
    .OUTPUTS
    Returns $true if extraction was successful
    
    .EXAMPLE
    Expand-FrontendBuild
    #>
    
    Write-DetailedLog "Extracting frontend build" -Level "INFO"
    Show-Progress -Activity "Frontend Extraction" -Status "Preparing extraction..." -PercentComplete 10
    
    try {
        $buildPath = $script:FrontendConfig.BuildPath
        $zipPath = Join-Path $buildPath "build.zip"
        
        # Check if ZIP file exists
        if (-not (Test-Path $zipPath)) {
            Write-DetailedLog "Build ZIP file not found: $zipPath" -Level "ERROR"
            return $false
        }
        
        Write-DetailedLog "Extracting build ZIP: $zipPath" -Level "DEBUG"
        
        Show-Progress -Activity "Frontend Extraction" -Status "Extracting files..." -PercentComplete 30
        
        # Remove existing build files (except the ZIP)
        $existingFiles = Get-ChildItem -Path $buildPath -Exclude "*.zip" -ErrorAction SilentlyContinue
        if ($existingFiles) {
            Write-DetailedLog "Removing existing build files" -Level "DEBUG"
            $existingFiles | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Extract ZIP file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $buildPath)
        
        Show-Progress -Activity "Frontend Extraction" -Status "Verifying extraction..." -PercentComplete 80
        
        # Verify extraction
        $extractedFiles = Get-ChildItem -Path $buildPath -Exclude "*.zip" | Measure-Object
        
        if ($extractedFiles.Count -eq 0) {
            Write-DetailedLog "No files were extracted from the build ZIP" -Level "ERROR"
            return $false
        }
        
        # Remove the ZIP file after successful extraction
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        
        # Remove .htaccess if it exists (as per original script)
        $htaccessPath = Join-Path $buildPath ".htaccess"
        if (Test-Path $htaccessPath) {
            Remove-Item $htaccessPath -Force -ErrorAction SilentlyContinue
            Write-DetailedLog "Removed .htaccess file" -Level "DEBUG"
        }
        
        Show-Progress -Activity "Frontend Extraction" -Status "Extraction completed" -PercentComplete 100
        Write-DetailedLog "Frontend build extracted successfully ($($extractedFiles.Count) items)" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Frontend build extraction failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Install-APIRepository {
    <#
    .SYNOPSIS
    Clones the API repository into the build directory.
    
    .OUTPUTS
    Returns $true if API repository was installed successfully
    
    .EXAMPLE
    Install-APIRepository
    #>
    
    Write-DetailedLog "Installing API repository" -Level "INFO"
    Show-Progress -Activity "API Setup" -Status "Preparing API installation..." -PercentComplete 10
    
    try {
        $apiPath = $script:FrontendConfig.APIPath
        $apiRepoURL = $script:FrontendConfig.APIRepoURL
        $apiBranch = $script:FrontendConfig.APIBranch
        
        # Remove existing API directory
        if (Test-Path $apiPath) {
            Write-DetailedLog "Removing existing API directory: $apiPath" -Level "DEBUG"
            Remove-Item $apiPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Show-Progress -Activity "API Setup" -Status "Cloning API repository..." -PercentComplete 30
        
        # Clone API repository
        Write-DetailedLog "Cloning API repository from: $apiRepoURL" -Level "DEBUG"
        Write-DetailedLog "Branch: $apiBranch, Target: $apiPath" -Level "DEBUG"
        
        $gitArgs = @("clone", "--depth", "1", "--branch", $apiBranch, "--single-branch", $apiRepoURL, $apiPath)
        
        $process = Start-Process -FilePath "git" -ArgumentList $gitArgs -Wait -PassThru -NoNewWindow -WindowStyle Hidden
        
        if ($process.ExitCode -ne 0) {
            Write-DetailedLog "Git clone failed with exit code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "API Setup" -Status "Verifying API installation..." -PercentComplete 80
        
        # Verify the clone was successful
        if (-not (Test-Path $apiPath)) {
            Write-DetailedLog "API directory was not created: $apiPath" -Level "ERROR"
            return $false
        }
        
        $apiFiles = Get-ChildItem -Path $apiPath -Recurse | Measure-Object
        
        if ($apiFiles.Count -eq 0) {
            Write-DetailedLog "API directory is empty after clone" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "API Setup" -Status "API installation completed" -PercentComplete 100
        Write-DetailedLog "API repository installed successfully ($($apiFiles.Count) files)" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "API repository installation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Set-APIConfiguration {
    <#
    .SYNOPSIS
    Creates the API configuration file with Solr credentials.
    
    .PARAMETER SolrUser
    Solr username
    
    .PARAMETER SolrPassword
    Solr password
    
    .OUTPUTS
    Returns $true if API configuration was created successfully
    
    .EXAMPLE
    Set-APIConfiguration -SolrUser "admin" -SolrPassword "password123"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SolrUser,
        
        [Parameter(Mandatory=$true)]
        [string]$SolrPassword
    )
    
    Write-DetailedLog "Creating API configuration" -Level "INFO"
    
    try {
        $apiPath = $script:FrontendConfig.APIPath
        $envFilePath = Join-Path $apiPath $script:FrontendConfig.APIEnvFile
        
        # Prepare API configuration
        $apiConfig = $script:FrontendConfig.APIConfig.Clone()
        $apiConfig.SOLR_USER = $SolrUser
        $apiConfig.SOLR_PASS = $SolrPassword
        
        Write-DetailedLog "Creating API environment file: $envFilePath" -Level "DEBUG"
        
        # Create the API environment file content
        $envContent = @()
        foreach ($key in $apiConfig.Keys) {
            $value = $apiConfig[$key]
            $envContent += "$key = $value"
        }
        
        # Write the environment file
        $envContent | Set-Content -Path $envFilePath -Encoding UTF8
        
        if (Test-Path $envFilePath) {
            Write-DetailedLog "API configuration created successfully" -Level "SUCCESS"
            Write-DetailedLog "Configuration file: $envFilePath" -Level "DEBUG"
            
            # Log configuration (without password)
            foreach ($line in $envContent) {
                if ($line -like "*SOLR_PASS*") {
                    Write-DetailedLog "  SOLR_PASS = [REDACTED]" -Level "DEBUG"
                } else {
                    Write-DetailedLog "  $line" -Level "DEBUG"
                }
            }
            
            return $true
        } else {
            Write-DetailedLog "Failed to create API configuration file" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "API configuration creation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# APACHE CONTAINER DEPLOYMENT
# ============================================================================

function Start-ApacheContainer {
    <#
    .SYNOPSIS
    Starts the Apache container for the frontend.
    
    .OUTPUTS
    Returns $true if container was started successfully
    
    .EXAMPLE
    Start-ApacheContainer
    #>
    
    Write-DetailedLog "Starting Apache container" -Level "INFO"
    Show-Progress -Activity "Container Deployment" -Status "Preparing container..." -PercentComplete 10
    
    try {
        $containerName = $script:FrontendConfig.ContainerName
        $containerImage = $script:FrontendConfig.ContainerImage
        $containerIP = $script:FrontendConfig.ContainerIP
        $containerPort = $script:FrontendConfig.ContainerPort
        $networkName = $script:FrontendConfig.NetworkName
        $buildPath = $script:FrontendConfig.BuildPath
        
        # Stop and remove existing container if it exists
        $existingContainer = docker ps -aq -f name=$containerName 2>$null
        if ($existingContainer) {
            Write-DetailedLog "Stopping existing container: $containerName" -Level "INFO"
            docker stop $containerName 2>$null | Out-Null
            docker rm $containerName 2>$null | Out-Null
        }
        
        Show-Progress -Activity "Container Deployment" -Status "Pulling container image..." -PercentComplete 30
        
        # Pull the latest image
        Write-DetailedLog "Pulling container image: $containerImage" -Level "DEBUG"
        docker pull $containerImage 2>$null | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Warning: Failed to pull latest image, using cached version" -Level "WARN"
        }
        
        Show-Progress -Activity "Container Deployment" -Status "Starting container..." -PercentComplete 50
        
        # Prepare Docker run arguments
        $dockerArgs = @(
            "run",
            "--name", $containerName,
            "--network", $networkName,
            "--ip", $containerIP,
            "--restart=always",
            "-d",
            "-p", $containerPort,
            "-v", "${buildPath}:/var/www/html",
            $containerImage
        )
        
        Write-DetailedLog "Starting container with command: docker $($dockerArgs -join ' ')" -Level "DEBUG"
        
        # Start the container
        $containerID = docker @dockerArgs 2>$null
        
        if ($LASTEXITCODE -ne 0 -or -not $containerID) {
            Write-DetailedLog "Failed to start Apache container" -Level "ERROR"
            
            # Get more detailed error information
            $dockerError = docker @dockerArgs 2>&1
            Write-DetailedLog "Docker error: $dockerError" -Level "ERROR"
            
            return $false
        }
        
        Show-Progress -Activity "Container Deployment" -Status "Waiting for container to be ready..." -PercentComplete 70
        
        # Wait for container to be running
        $containerReady = Wait-ForContainerReady -ContainerName $containerName -TimeoutSeconds 30
        
        if (-not $containerReady) {
            Write-DetailedLog "Container failed to start within timeout" -Level "ERROR"
            return $false
        }
        
        Show-Progress -Activity "Container Deployment" -Status "Container deployed successfully" -PercentComplete 100
        Write-DetailedLog "Apache container started successfully" -Level "SUCCESS"
        Write-DetailedLog "Container ID: $($containerID.Substring(0,12))" -Level "DEBUG"
        Write-DetailedLog "Container URL: http://localhost:$($containerPort.Split(':')[0])/" -Level "INFO"
        
        return $true
        
    } catch {
        Write-DetailedLog "Apache container deployment failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Wait-ForContainerReady {
    <#
    .SYNOPSIS
    Waits for a Docker container to be ready and healthy.
    
    .PARAMETER ContainerName
    Name of the container to wait for
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    
    .OUTPUTS
    Returns $true if container is ready within timeout
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
                # Container is running, test if it's responding
                $containerPort = ($script:FrontendConfig.ContainerPort -split ':')[0]
                
                try {
                    $response = Invoke-WebRequest -Uri "http://localhost:$containerPort/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                    if ($response.StatusCode -eq 200) {
                        Write-DetailedLog "Container is ready and responding" -Level "SUCCESS"
                        return $true
                    }
                } catch {
                    # Container not ready yet
                }
            }
            
            Start-Sleep -Seconds 2
            
        } catch {
            # Continue waiting
        }
    }
    
    Write-DetailedLog "Container did not become ready within $TimeoutSeconds seconds" -Level "ERROR"
    return $false
}

# ============================================================================
# SWAGGER UI CONFIGURATION
# ============================================================================

function Set-SwaggerConfiguration {
    <#
    .SYNOPSIS
    Configures Swagger UI to use the correct local URL.
    
    .OUTPUTS
    Returns $true if Swagger configuration was updated successfully
    
    .EXAMPLE
    Set-SwaggerConfiguration
    #>
    
    Write-DetailedLog "Configuring Swagger UI" -Level "INFO"
    
    try {
        $containerName = $script:FrontendConfig.ContainerName
        $swaggerPort = $script:FrontendConfig.SwaggerPort
        
        # Wait a moment for container to settle
        Start-Sleep -Seconds 2
        
        # Update Swagger UI configuration inside the container
        $sedCommand = "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:$swaggerPort/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js"
        
        Write-DetailedLog "Updating Swagger UI configuration in container" -Level "DEBUG"
        
        $execResult = docker exec $containerName bash -c $sedCommand 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to update Swagger UI configuration" -Level "WARN"
            # Don't fail deployment for Swagger config issues
            return $true
        }
        
        # Restart the container to apply changes
        Write-DetailedLog "Restarting container to apply Swagger configuration" -Level "DEBUG"
        docker restart $containerName 2>$null | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            # Wait for container to be ready again
            $containerReady = Wait-ForContainerReady -ContainerName $containerName -TimeoutSeconds 30
            
            if ($containerReady) {
                Write-DetailedLog "Swagger UI configured successfully" -Level "SUCCESS"
            } else {
                Write-DetailedLog "Container restart failed after Swagger configuration" -Level "WARN"
            }
        } else {
            Write-DetailedLog "Failed to restart container after Swagger configuration" -Level "WARN"
        }
        
        return $true
        
    } catch {
        Write-DetailedLog "Swagger configuration failed: $($_.Exception.Message)" -Level "WARN"
        # Don't fail deployment for Swagger config issues
        return $true
    }
}

# ============================================================================
# DEPLOYMENT VERIFICATION
# ============================================================================

function Test-FrontendDeployment {
    <#
    .SYNOPSIS
    Tests the frontend deployment to ensure it's working correctly.
    
    .OUTPUTS
    Returns hashtable with deployment status information
    
    .EXAMPLE
    $status = Test-FrontendDeployment
    #>
    
    Write-DetailedLog "Testing frontend deployment" -Level "INFO"
    
    $result = @{
        IsDeployed = $false
        IsWorking = $false
        ContainerRunning = $false
        WebsiteAccessible = $false
        APIAccessible = $false
        SwaggerAccessible = $false
        Issues = @()
    }
    
    try {
        $containerName = $script:FrontendConfig.ContainerName
        $containerPort = ($script:FrontendConfig.ContainerPort -split ':')[0]
        
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
            
            # Test 2: Check main website accessibility
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$containerPort/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($response.StatusCode -eq 200) {
                    $result.WebsiteAccessible = $true
                    Write-DetailedLog "✅ Main website is accessible" -Level "DEBUG"
                } else {
                    $result.Issues += "Website returned status code: $($response.StatusCode)"
                }
            } catch {
                $result.Issues += "Website is not accessible: $($_.Exception.Message)"
                Write-DetailedLog "❌ Website accessibility test failed: $($_.Exception.Message)" -Level "ERROR"
            }
            
            # Test 3: Check API accessibility
            try {
                $apiResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/api/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($apiResponse.StatusCode -eq 200 -or $apiResponse.StatusCode -eq 404) {
                    # 404 is acceptable for API root, means API is reachable
                    $result.APIAccessible = $true
                    Write-DetailedLog "✅ API is accessible" -Level "DEBUG"
                } else {
                    $result.Issues += "API returned unexpected status code: $($apiResponse.StatusCode)"
                }
            } catch {
                $result.Issues += "API is not accessible: $($_.Exception.Message)"
                Write-DetailedLog "❌ API accessibility test failed: $($_.Exception.Message)" -Level "ERROR"
            }
            
            # Test 4: Check Swagger UI accessibility
            try {
                $swaggerResponse = Invoke-WebRequest -Uri "http://localhost:$containerPort/swagger-ui/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                
                if ($swaggerResponse.StatusCode -eq 200) {
                    $result.SwaggerAccessible = $true
                    Write-DetailedLog "✅ Swagger UI is accessible" -Level "DEBUG"
                } else {
                    $result.Issues += "Swagger UI returned status code: $($swaggerResponse.StatusCode)"
                }
            } catch {
                $result.Issues += "Swagger UI is not accessible: $($_.Exception.Message)"
                Write-DetailedLog "❌ Swagger UI accessibility test failed: $($_.Exception.Message)" -Level "ERROR"
            }
            
            # Determine if deployment is working
            $result.IsWorking = $result.WebsiteAccessible -and $result.APIAccessible
        }
        
        # Log results
        if ($result.IsWorking) {
            Write-DetailedLog "Frontend deployment verification: PASSED" -Level "SUCCESS"
        } else {
            Write-DetailedLog "Frontend deployment verification: FAILED" -Level "ERROR"
            foreach ($issue in $result.Issues) {
                Write-DetailedLog "  - $issue" -Level "ERROR"
            }
        }
        
    } catch {
        $result.Issues += "Deployment test failed: $($_.Exception.Message)"
        Write-DetailedLog "Frontend deployment test error: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $result
}

# ============================================================================
# FRONTEND ROLLBACK AND CLEANUP
# ============================================================================

function Invoke-FrontendRollback {
    <#
    .SYNOPSIS
    Performs rollback of frontend deployment in case of failure.
    
    .OUTPUTS
    Returns $true if rollback was successful
    
    .EXAMPLE
    Invoke-FrontendRollback
    #>
    
    Write-DetailedLog "Performing frontend deployment rollback" -Level "WARN"
    
    try {
        $containerName = $script:FrontendConfig.ContainerName
        
        # Stop and remove container
        $containerExists = docker ps -aq -f name=$containerName 2>$null
        if ($containerExists) {
            Write-DetailedLog "Stopping and removing container: $containerName" -Level "INFO"
            docker stop $containerName 2>$null | Out-Null
            docker rm $containerName 2>$null | Out-Null
        }
        
        # Clean up build directory (but preserve structure)
        $buildPath = $script:FrontendConfig.BuildPath
        if (Test-Path $buildPath) {
            Write-DetailedLog "Cleaning build directory: $buildPath" -Level "INFO"
            Get-ChildItem -Path $buildPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-DetailedLog "Frontend rollback completed" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Frontend rollback failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-GitHubLatestRelease {
    <#
    .SYNOPSIS
    Gets information about the latest GitHub release.
    
    .PARAMETER Owner
    GitHub repository owner
    
    .PARAMETER Repo
    GitHub repository name
    
    .OUTPUTS
    Returns hashtable with release information
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Owner,
        
        [Parameter(Mandatory=$true)]
        [string]$Repo
    )
    
    try {
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
        $headers = @{
            'User-Agent' = 'Peviitor-Installer/1.0'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        Write-DetailedLog "Fetching release info from: $apiUrl" -Level "DEBUG"
        
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        
        return @{
            Success = $true
            Version = $response.tag_name
            Assets = $response.assets
            PublishedAt = $response.published_at
            Body = $response.body
        }
        
    } catch {
        $error = "Failed to get GitHub release information: $($_.Exception.Message)"
        Write-DetailedLog $error -Level "ERROR"
        
        return @{
            Success = $false
            Error = $error
        }
    }
}

function Download-GitHubAsset {
    <#
    .SYNOPSIS
    Downloads a GitHub release asset.
    
    .PARAMETER Asset
    Asset object from GitHub API
    
    .PARAMETER TargetPath
    Directory where to save the file
    
    .OUTPUTS
    Returns hashtable with download results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [object]$Asset,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetPath
    )
    
    try {
        $downloadUrl = $Asset.browser_download_url
        $fileName = $Asset.name
        $filePath = Join-Path $TargetPath $fileName
        
        # Ensure target directory exists
        if (-not (Test-Path $TargetPath)) {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        }
        
        # Remove existing file
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
        }
        
        Write-DetailedLog "Downloading: $downloadUrl" -Level "DEBUG"
        Write-DetailedLog "Target: $filePath" -Level "DEBUG"
        
        # Create WebClient with progress tracking
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent', 'Peviitor-Installer/1.0')
        
        # Register progress event
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            $received = $Event.SourceEventArgs.BytesReceived
            $total = $Event.SourceEventArgs.TotalBytesToReceive
            
            $status = if ($total -gt 0) {
                $receivedMB = [math]::Round($received / 1MB, 1)
                $totalMB = [math]::Round($total / 1MB, 1)
                "Downloading $fileName... $receivedMB MB / $totalMB MB ($percent%)"
            } else {
                "Downloading $fileName... $([math]::Round($received / 1MB, 1)) MB ($percent%)"
            }
            
            Show-Progress -Activity "Frontend Download" -Status $status -PercentComplete $percent -Id 2 -ParentId 1
        } | Out-Null
        
        # Download file
        $webClient.DownloadFile($downloadUrl, $filePath)
        
        # Cleanup progress tracking
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
        $webClient.Dispose()
        Hide-Progress -Id 2
        
        if (Test-Path $filePath) {
            $fileSize = (Get-Item $filePath).Length
            Write-DetailedLog "Download completed: $fileName ($([math]::Round($fileSize / 1MB, 1))MB)" -Level "SUCCESS"
            
            return @{
                Success = $true
                FilePath = $filePath
                Size = $fileSize
            }
        } else {
            return @{
                Success = $false
                Error = "Downloaded file not found at expected path"
            }
        }
        
    } catch {
        $error = "Asset download failed: $($_.Exception.Message)"
        Write-DetailedLog $error -Level "ERROR"
        
        # Cleanup on failure
        if ($webClient) {
            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event -ErrorAction SilentlyContinue
            $webClient.Dispose()
        }
        
        return @{
            Success = $false
            Error = $error
        }
    }
}

function Show-FrontendAccessInfo {
    <#
    .SYNOPSIS
    Displays access information for the deployed frontend.
    
    .EXAMPLE
    Show-FrontendAccessInfo
    #>
    
    $containerPort = ($script:FrontendConfig.ContainerPort -split ':')[0]
    
    Write-LogHeader -Title "FRONTEND ACCESS INFORMATION" -Level 3
    
    $accessInfo = @(
        @{
            Name = "Peviitor Main UI"
            URL = "http://localhost:$containerPort/"
            Description = "Main job search interface"
            Icon = "🌐"
        },
        @{
            Name = "API Documentation"  
            URL = "http://localhost:$containerPort/swagger-ui/"
            Description = "Swagger API documentation"
            Icon = "📚"
        },
        @{
            Name = "API Endpoint"
            URL = "http://localhost:$containerPort/api/"
            Description = "REST API for job data"
            Icon = "🔌"
        }
    )
    
    Write-DetailedLog "Frontend is now accessible at the following URLs:" -Level "SUCCESS"
    
    foreach ($info in $accessInfo) {
        Write-DetailedLog "$($info.Icon) $($info.Name): $($info.URL)" -Level "INFO"
        Write-DetailedLog "   $($info.Description)" -Level "INFO"
    }
    
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "🎉 Frontend deployment completed successfully!" -Level "SUCCESS"
}

function Get-FrontendStatus {
    <#
    .SYNOPSIS
    Gets comprehensive status of the frontend deployment.
    
    .OUTPUTS
    Returns hashtable with detailed status information
    
    .EXAMPLE
    $status = Get-FrontendStatus
    #>
    
    $status = @{
        Container = @{}
        Build = @{}
        API = @{}
        Accessibility = @{}
        IsHealthy = $false
    }
    
    try {
        $containerName = $script:FrontendConfig.ContainerName
        $buildPath = $script:FrontendConfig.BuildPath
        $apiPath = $script:FrontendConfig.APIPath
        $containerPort = ($script:FrontendConfig.ContainerPort -split ':')[0]
        
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
                    $status.Container.IPAddress = $containerInfo[0].NetworkSettings.Networks.($script:FrontendConfig.NetworkName).IPAddress
                }
            } catch {
                # Could not get additional container info
            }
        }
        
        # Build status
        $status.Build = @{
            Path = $buildPath
            Exists = Test-Path $buildPath
            FileCount = 0
        }
        
        if ($status.Build.Exists) {
            $buildFiles = Get-ChildItem -Path $buildPath -Recurse -File -ErrorAction SilentlyContinue
            $status.Build.FileCount = ($buildFiles | Measure-Object).Count
        }
        
        # API status
        $status.API = @{
            Path = $apiPath
            Exists = Test-Path $apiPath
            ConfigExists = Test-Path (Join-Path $apiPath $script:FrontendConfig.APIEnvFile)
            FileCount = 0
        }
        
        if ($status.API.Exists) {
            $apiFiles = Get-ChildItem -Path $apiPath -Recurse -File -ErrorAction SilentlyContinue
            $status.API.FileCount = ($apiFiles | Measure-Object).Count
        }
        
        # Accessibility status
        $status.Accessibility = @{
            MainSite = Test-URLAccessibility -URL "http://localhost:$containerPort/" -TimeoutSeconds 5
            API = Test-URLAccessibility -URL "http://localhost:$containerPort/api/" -TimeoutSeconds 5
            Swagger = Test-URLAccessibility -URL "http://localhost:$containerPort/swagger-ui/" -TimeoutSeconds 5
        }
        
        # Overall health assessment
        $status.IsHealthy = $status.Container.Running -and 
                           $status.Build.Exists -and $status.Build.FileCount -gt 0 -and
                           $status.API.Exists -and $status.API.ConfigExists -and
                           $status.Accessibility.MainSite.IsAccessible
        
    } catch {
        Write-DetailedLog "Error getting frontend status: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $status
}

function Test-URLAccessibility {
    <#
    .SYNOPSIS
    Tests if a URL is accessible.
    
    .PARAMETER URL
    URL to test
    
    .PARAMETER TimeoutSeconds
    Timeout in seconds
    
    .OUTPUTS
    Returns hashtable with accessibility results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        
        [Parameter()]
        [int]$TimeoutSeconds = 10
    )
    
    $result = @{
        URL = $URL
        IsAccessible = $false
        StatusCode = $null
        ResponseTime = $null
        Error = $null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        
        $stopwatch.Stop()
        
        $result.IsAccessible = $true
        $result.StatusCode = $response.StatusCode
        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
        
    } catch {
        $result.Error = $_.Exception.Message
        
        # Try to extract status code from exception
        if ($_.Exception.Response) {
            try {
                $result.StatusCode = [int]$_.Exception.Response.StatusCode
                # Some status codes are acceptable (like 404 for API root)
                if ($result.StatusCode -in @(200, 301, 302, 404)) {
                    $result.IsAccessible = $true
                }
            } catch {
                # Could not get status code
            }
        }
    }
    
    return $result
}

function Write-FrontendReport {
    <#
    .SYNOPSIS
    Displays a comprehensive frontend status report.
    
    .EXAMPLE
    Write-FrontendReport
    #>
    
    $status = Get-FrontendStatus
    
    Write-LogHeader -Title "FRONTEND STATUS REPORT" -Level 3
    
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
    
    # Build status
    $buildIcon = if ($status.Build.Exists -and $status.Build.FileCount -gt 0) { "✅" } else { "❌" }
    Write-DetailedLog "Build Status:" -Level "INFO"
    Write-DetailedLog "  $buildIcon Build Directory: $($status.Build.Path)" -Level "INFO"
    Write-DetailedLog "    Files: $($status.Build.FileCount)" -Level "INFO"
    
    # API status
    $apiIcon = if ($status.API.Exists -and $status.API.ConfigExists) { "✅" } else { "❌" }
    Write-DetailedLog "API Status:" -Level "INFO"
    Write-DetailedLog "  $apiIcon API Directory: $($status.API.Path)" -Level "INFO"
    Write-DetailedLog "    Files: $($status.API.FileCount)" -Level "INFO"
    Write-DetailedLog "    Config: $(if ($status.API.ConfigExists) { 'Present' } else { 'Missing' })" -Level "INFO"
    
    # Accessibility status
    Write-DetailedLog "Accessibility Status:" -Level "INFO"
    
    foreach ($test in @('MainSite', 'API', 'Swagger')) {
        $testResult = $status.Accessibility[$test]
        $accessIcon = if ($testResult.IsAccessible) { "🟢" } else { "🔴" }
        $testName = switch ($test) {
            'MainSite' { 'Main Website' }
            'API' { 'API Endpoint' }
            'Swagger' { 'Swagger UI' }
        }
        
        Write-DetailedLog "  $accessIcon $testName ($($testResult.URL))" -Level "INFO"
        
        if ($testResult.IsAccessible) {
            if ($testResult.ResponseTime) {
                Write-DetailedLog "    Response time: $($testResult.ResponseTime)ms" -Level "INFO"
            }
        } else {
            Write-DetailedLog "    Error: $($testResult.Error)" -Level "ERROR"
        }
    }
    
    # Overall health
    $healthIcon = if ($status.IsHealthy) { "💚" } else { "❤️" }
    $healthStatus = if ($status.IsHealthy) { "HEALTHY" } else { "UNHEALTHY" }
    
    Write-DetailedLog "$healthIcon Frontend Overall Status: $healthStatus" -Level $(if ($status.IsHealthy) { "SUCCESS" } else { "ERROR" })
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Frontend deployment module loaded" -Level "DEBUG"

# Validate configuration on module load
if (-not $Global:PeviitorConfig) {
    Write-DetailedLog "Global Peviitor configuration not found - some functions may not work correctly" -Level "WARN"
}