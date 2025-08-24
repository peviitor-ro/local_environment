# Environment.ps1 - Environment setup and cleanup management
# This module handles directory creation, Docker network setup, and cleanup operations

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

# Get configuration from the global config
$script:EnvConfig = @{
    # Directory paths
    BasePath = $Global:PeviitorConfig.Paths.Base
    BuildPath = $Global:PeviitorConfig.Paths.Build
    APIPath = $Global:PeviitorConfig.Paths.API
    SolrDataPath = $Global:PeviitorConfig.Paths.SolrData
    TempPath = $Global:PeviitorConfig.Paths.TempDownload
    
    # Docker configuration
    NetworkName = $Global:PeviitorConfig.Network.Name
    NetworkSubnet = $Global:PeviitorConfig.Network.Subnet
    ContainerNames = @(
        $Global:PeviitorConfig.Containers.Solr.Name,
        $Global:PeviitorConfig.Containers.Apache.Name,
        $Global:PeviitorConfig.Containers.DataMigration,
        $Global:PeviitorConfig.Containers.DeployFE
    )
    
    # Cleanup configuration
    MaxRetries = 3
    RetryDelay = 5  # seconds
}

# ============================================================================
# ENVIRONMENT PREPARATION
# ============================================================================

function Initialize-PeviitorEnvironment {
    <#
    .SYNOPSIS
    Initializes a clean Peviitor environment by cleaning up existing resources
    and creating fresh directory structure and Docker network.
    
    .PARAMETER Force
    Force cleanup even if containers are running
    
    .PARAMETER SkipCleanup
    Skip cleanup phase and only create new environment
    
    .OUTPUTS
    Returns $true if environment initialization was successful
    
    .EXAMPLE
    Initialize-PeviitorEnvironment -Force
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$SkipCleanup
    )
    
    Write-LogHeader -Title "PEVIITOR ENVIRONMENT INITIALIZATION" -Level 2
    
    try {
        $initSteps = @(
            @{ Name = "Docker Service Check"; Function = { Test-DockerService } }
            @{ Name = "Cleanup Existing Environment"; Function = { if (-not $SkipCleanup) { Remove-ExistingEnvironment -Force:$Force } else { $true } } }
            @{ Name = "Create Directory Structure"; Function = { New-DirectoryStructure } }
            @{ Name = "Setup Docker Network"; Function = { New-DockerNetwork } }
            @{ Name = "Set Permissions"; Function = { Set-DirectoryPermissions } }
            @{ Name = "Validate Environment"; Function = { Test-EnvironmentReadiness } }
        )
        
        $stepNumber = 1
        $totalSteps = $initSteps.Count
        
        foreach ($step in $initSteps) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Environment Setup"
            
            $result = & $step.Function
            
            if ($result) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } else {
                Write-DetailedLog "❌ $($step.Name): FAILED" -Level "ERROR"
                Write-DetailedLog "Environment initialization failed at step: $($step.Name)" -Level "ERROR"
                return $false
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        Write-DetailedLog "🎉 Peviitor environment initialized successfully" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-InstallationError -ErrorMessage "Environment initialization failed" -Exception $_.Exception
        return $false
    }
}

function Test-DockerService {
    <#
    .SYNOPSIS
    Verifies that Docker service is running and accessible.
    
    .OUTPUTS
    Returns $true if Docker is ready
    #>
    
    Write-DetailedLog "Checking Docker service status" -Level "INFO"
    
    try {
        # Check if Docker command is available
        $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
            Write-DetailedLog "Docker service is ready (version: $dockerVersion)" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Docker service is not responding" -Level "ERROR"
            Write-DetailedLog "Please ensure Docker Desktop is running and try again" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error checking Docker service: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# CLEANUP OPERATIONS
# ============================================================================

function Remove-ExistingEnvironment {
    <#
    .SYNOPSIS
    Removes existing Peviitor environment including containers, networks, and files.
    
    .PARAMETER Force
    Force removal even if containers are running
    
    .OUTPUTS
    Returns $true if cleanup was successful
    
    .EXAMPLE
    Remove-ExistingEnvironment -Force
    #>
    param(
        [Parameter()]
        [switch]$Force
    )
    
    Write-DetailedLog "Cleaning up existing Peviitor environment" -Level "INFO"
    
    try {
        $cleanupSteps = @(
            @{ Name = "Stop Running Containers"; Function = { Stop-PeviitorContainers -Force:$Force } }
            @{ Name = "Remove Containers"; Function = { Remove-PeviitorContainers } }
            @{ Name = "Remove Docker Networks"; Function = { Remove-PeviitorNetworks } }
            @{ Name = "Clean Directories"; Function = { Remove-PeviitorDirectories } }
            @{ Name = "Clean Temp Files"; Function = { Remove-TempFiles } }
        )
        
        $stepNumber = 1
        $totalSteps = $cleanupSteps.Count
        
        foreach ($step in $cleanupSteps) {
            Show-Progress -Activity "Environment Cleanup" -Status $step.Name -PercentComplete (($stepNumber / $totalSteps) * 100)
            
            $result = & $step.Function
            
            if ($result) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } else {
                Write-DetailedLog "⚠️ $($step.Name): PARTIAL" -Level "WARN"
                # Continue with other cleanup steps even if one fails
            }
            
            $stepNumber++
        }
        
        Write-DetailedLog "Environment cleanup completed" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Environment cleanup error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Stop-PeviitorContainers {
    <#
    .SYNOPSIS
    Stops all Peviitor-related containers.
    
    .PARAMETER Force
    Force stop containers
    
    .OUTPUTS
    Returns $true if all containers were stopped or were not running
    #>
    param(
        [Parameter()]
        [switch]$Force
    )
    
    Write-DetailedLog "Stopping Peviitor containers" -Level "DEBUG"
    
    try {
        $runningContainers = @()
        
        foreach ($containerName in $script:EnvConfig.ContainerNames) {
            # Check if container exists and is running
            $containerStatus = docker ps -q -f name=$containerName 2>$null
            
            if ($containerStatus) {
                $runningContainers += $containerName
                Write-DetailedLog "Found running container: $containerName" -Level "DEBUG"
            }
        }
        
        if ($runningContainers.Count -eq 0) {
            Write-DetailedLog "No Peviitor containers are currently running" -Level "INFO"
            return $true
        }
        
        # Stop containers
        foreach ($containerName in $runningContainers) {
            Write-DetailedLog "Stopping container: $containerName" -Level "INFO"
            
            if ($Force) {
                docker kill $containerName 2>$null | Out-Null
            } else {
                docker stop $containerName 2>$null | Out-Null
            }
            
            if ($LASTEXITCODE -eq 0) {
                Write-DetailedLog "Container stopped: $containerName" -Level "SUCCESS"
            } else {
                Write-DetailedLog "Failed to stop container: $containerName" -Level "WARN"
            }
        }
        
        return $true
        
    } catch {
        Write-DetailedLog "Error stopping containers: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-PeviitorContainers {
    <#
    .SYNOPSIS
    Removes all Peviitor-related containers.
    
    .OUTPUTS
    Returns $true if all containers were removed or did not exist
    #>
    
    Write-DetailedLog "Removing Peviitor containers" -Level "DEBUG"
    
    try {
        $existingContainers = @()
        
        foreach ($containerName in $script:EnvConfig.ContainerNames) {
            # Check if container exists (running or stopped)
            $containerExists = docker ps -aq -f name=$containerName 2>$null
            
            if ($containerExists) {
                $existingContainers += $containerName
                Write-DetailedLog "Found existing container: $containerName" -Level "DEBUG"
            }
        }
        
        if ($existingContainers.Count -eq 0) {
            Write-DetailedLog "No Peviitor containers to remove" -Level "INFO"
            return $true
        }
        
        # Remove containers
        foreach ($containerName in $existingContainers) {
            Write-DetailedLog "Removing container: $containerName" -Level "INFO"
            
            docker rm -f $containerName 2>$null | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-DetailedLog "Container removed: $containerName" -Level "SUCCESS"
            } else {
                Write-DetailedLog "Failed to remove container: $containerName" -Level "WARN"
            }
        }
        
        return $true
        
    } catch {
        Write-DetailedLog "Error removing containers: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-PeviitorNetworks {
    <#
    .SYNOPSIS
    Removes Peviitor Docker networks.
    
    .OUTPUTS
    Returns $true if networks were removed or did not exist
    #>
    
    Write-DetailedLog "Removing Peviitor Docker networks" -Level "DEBUG"
    
    try {
        $networkName = $script:EnvConfig.NetworkName
        
        # Check if network exists
        $networkExists = docker network ls -q -f name=$networkName 2>$null
        
        if (-not $networkExists) {
            Write-DetailedLog "Network '$networkName' does not exist" -Level "INFO"
            return $true
        }
        
        Write-DetailedLog "Removing Docker network: $networkName" -Level "INFO"
        docker network rm $networkName 2>$null | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-DetailedLog "Network removed: $networkName" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Failed to remove network: $networkName" -Level "WARN"
            
            # Try to inspect the network to see what's using it
            $networkInfo = docker network inspect $networkName 2>$null | ConvertFrom-Json
            if ($networkInfo -and $networkInfo.Containers) {
                Write-DetailedLog "Network is still in use by containers:" -Level "WARN"
                foreach ($container in $networkInfo.Containers.PSObject.Properties) {
                    Write-DetailedLog "  - $($container.Value.Name)" -Level "WARN"
                }
            }
            
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error removing networks: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-PeviitorDirectories {
    <#
    .SYNOPSIS
    Removes Peviitor directories and files.
    
    .OUTPUTS
    Returns $true if directories were removed or did not exist
    #>
    
    Write-DetailedLog "Cleaning Peviitor directories" -Level "DEBUG"
    
    try {
        $basePath = $script:EnvConfig.BasePath
        
        if (-not (Test-Path $basePath)) {
            Write-DetailedLog "Base directory does not exist: $basePath" -Level "INFO"
            return $true
        }
        
        Write-DetailedLog "Removing directory tree: $basePath" -Level "INFO"
        
        # Try to remove with retries (sometimes files are locked)
        $retryCount = 0
        $maxRetries = $script:EnvConfig.MaxRetries
        
        while ($retryCount -lt $maxRetries) {
            try {
                Remove-Item $basePath -Recurse -Force -ErrorAction Stop
                
                if (-not (Test-Path $basePath)) {
                    Write-DetailedLog "Directory removed successfully: $basePath" -Level "SUCCESS"
                    return $true
                }
                
            } catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-DetailedLog "Retry $retryCount/$maxRetries: Failed to remove directory, retrying in $($script:EnvConfig.RetryDelay) seconds..." -Level "WARN"
                    Start-Sleep -Seconds $script:EnvConfig.RetryDelay
                } else {
                    Write-DetailedLog "Failed to remove directory after $maxRetries attempts: $($_.Exception.Message)" -Level "ERROR"
                    return $false
                }
            }
        }
        
        return $false
        
    } catch {
        Write-DetailedLog "Error removing directories: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-TempFiles {
    <#
    .SYNOPSIS
    Removes temporary files created during installation.
    
    .OUTPUTS
    Returns $true if temp files were cleaned
    #>
    
    Write-DetailedLog "Cleaning temporary files" -Level "DEBUG"
    
    try {
        $tempPath = $script:EnvConfig.TempPath
        
        if (Test-Path $tempPath) {
            Write-DetailedLog "Removing temp directory: $tempPath" -Level "DEBUG"
            Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Clean up any Docker-related temp files
        $dockerTempFiles = @(
            "$env:TEMP\docker-*",
            "$env:TEMP\peviitor-*"
        )
        
        foreach ($pattern in $dockerTempFiles) {
            $files = Get-ChildItem -Path $env:TEMP -Filter (Split-Path $pattern -Leaf) -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                try {
                    Remove-Item $file.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    Write-DetailedLog "Removed temp file: $($file.Name)" -Level "DEBUG"
                } catch {
                    # Continue if some temp files can't be removed
                }
            }
        }
        
        return $true
        
    } catch {
        Write-DetailedLog "Error cleaning temp files: $($_.Exception.Message)" -Level "WARN"
        return $true  # Don't fail environment setup for temp file issues
    }
}

# ============================================================================
# DIRECTORY STRUCTURE CREATION
# ============================================================================

function New-DirectoryStructure {
    <#
    .SYNOPSIS
    Creates the complete Peviitor directory structure.
    
    .OUTPUTS
    Returns $true if directory structure was created successfully
    
    .EXAMPLE
    New-DirectoryStructure
    #>
    
    Write-DetailedLog "Creating Peviitor directory structure" -Level "INFO"
    
    try {
        # Define all directories that need to be created
        $directories = @(
            $script:EnvConfig.BasePath,
            $script:EnvConfig.BuildPath,
            $script:EnvConfig.APIPath,
            $script:EnvConfig.SolrDataPath,
            $script:EnvConfig.TempPath,
            (Join-Path $script:EnvConfig.BasePath "logs"),
            (Join-Path $script:EnvConfig.BasePath "config"),
            (Join-Path $script:EnvConfig.BasePath "backup")
        )
        
        foreach ($directory in $directories) {
            if (-not (Test-Path $directory)) {
                Write-DetailedLog "Creating directory: $directory" -Level "DEBUG"
                
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                
                if (Test-Path $directory) {
                    Write-DetailedLog "Created: $directory" -Level "SUCCESS"
                } else {
                    Write-DetailedLog "Failed to create: $directory" -Level "ERROR"
                    return $false
                }
            } else {
                Write-DetailedLog "Directory already exists: $directory" -Level "DEBUG"
            }
        }
        
        Write-DetailedLog "Directory structure created successfully" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Error creating directory structure: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Set-DirectoryPermissions {
    <#
    .SYNOPSIS
    Sets appropriate permissions on Peviitor directories.
    
    .OUTPUTS
    Returns $true if permissions were set successfully
    #>
    
    Write-DetailedLog "Setting directory permissions" -Level "INFO"
    
    try {
        $basePath = $script:EnvConfig.BasePath
        
        if (-not (Test-Path $basePath)) {
            Write-DetailedLog "Base path does not exist: $basePath" -Level "ERROR"
            return $false
        }
        
        # Set permissions for the current user and SYSTEM
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        Write-DetailedLog "Setting permissions for user: $currentUser" -Level "DEBUG"
        
        # Use icacls to set permissions (more reliable than .NET methods)
        $icaclsArgs = @(
            "`"$basePath`"",
            "/grant",
            "`"$currentUser`":(OI)(CI)F",
            "/T",
            "/Q"
        )
        
        $process = Start-Process -FilePath "icacls" -ArgumentList $icaclsArgs -Wait -PassThru -NoNewWindow -WindowStyle Hidden
        
        if ($process.ExitCode -eq 0) {
            Write-DetailedLog "Permissions set successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Failed to set permissions (icacls exit code: $($process.ExitCode))" -Level "WARN"
            # Don't fail the entire process for permission issues
            return $true
        }
        
    } catch {
        Write-DetailedLog "Error setting permissions: $($_.Exception.Message)" -Level "WARN"
        # Don't fail the entire process for permission issues
        return $true
    }
}

# ============================================================================
# DOCKER NETWORK MANAGEMENT
# ============================================================================

function New-DockerNetwork {
    <#
    .SYNOPSIS
    Creates the Docker network for Peviitor containers.
    
    .OUTPUTS
    Returns $true if network was created successfully
    
    .EXAMPLE
    New-DockerNetwork
    #>
    
    Write-DetailedLog "Setting up Docker network" -Level "INFO"
    
    try {
        $networkName = $script:EnvConfig.NetworkName
        $networkSubnet = $script:EnvConfig.NetworkSubnet
        
        # Check if network already exists
        $existingNetwork = docker network ls -q -f name=$networkName 2>$null
        
        if ($existingNetwork) {
            Write-DetailedLog "Docker network already exists: $networkName" -Level "INFO"
            
            # Verify the network configuration
            $networkInfo = docker network inspect $networkName 2>$null | ConvertFrom-Json
            
            if ($networkInfo -and $networkInfo[0].IPAM.Config[0].Subnet -eq $networkSubnet) {
                Write-DetailedLog "Network configuration is correct" -Level "SUCCESS"
                return $true
            } else {
                Write-DetailedLog "Network configuration is incorrect, recreating..." -Level "WARN"
                
                # Remove and recreate the network
                docker network rm $networkName 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-DetailedLog "Failed to remove existing network" -Level "ERROR"
                    return $false
                }
            }
        }
        
        # Create the network
        Write-DetailedLog "Creating Docker network: $networkName (subnet: $networkSubnet)" -Level "INFO"
        
        $createResult = docker network create --subnet=$networkSubnet $networkName 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $createResult) {
            Write-DetailedLog "Docker network created successfully: $networkName" -Level "SUCCESS"
            
            # Verify the network was created properly
            $verifyNetwork = docker network ls -q -f name=$networkName 2>$null
            if ($verifyNetwork) {
                Write-DetailedLog "Network verification successful" -Level "SUCCESS"
                return $true
            } else {
                Write-DetailedLog "Network creation verification failed" -Level "ERROR"
                return $false
            }
        } else {
            Write-DetailedLog "Failed to create Docker network: $networkName" -Level "ERROR"
            
            # Try to get more information about the failure
            $networkError = docker network create --subnet=$networkSubnet $networkName 2>&1
            Write-DetailedLog "Docker network error: $networkError" -Level "ERROR"
            
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error creating Docker network: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-DockerNetwork {
    <#
    .SYNOPSIS
    Tests if the Docker network is properly configured.
    
    .OUTPUTS
    Returns $true if network is ready for use
    #>
    
    Write-DetailedLog "Testing Docker network configuration" -Level "DEBUG"
    
    try {
        $networkName = $script:EnvConfig.NetworkName
        $networkSubnet = $script:EnvConfig.NetworkSubnet
        
        # Check if network exists
        $networkExists = docker network ls -q -f name=$networkName 2>$null
        
        if (-not $networkExists) {
            Write-DetailedLog "Docker network does not exist: $networkName" -Level "ERROR"
            return $false
        }
        
        # Inspect network configuration
        $networkInfo = docker network inspect $networkName 2>$null | ConvertFrom-Json
        
        if (-not $networkInfo) {
            Write-DetailedLog "Could not inspect Docker network: $networkName" -Level "ERROR"
            return $false
        }
        
        # Verify network configuration
        $actualSubnet = $networkInfo[0].IPAM.Config[0].Subnet
        
        if ($actualSubnet -eq $networkSubnet) {
            Write-DetailedLog "Docker network is properly configured" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Docker network has incorrect subnet. Expected: $networkSubnet, Actual: $actualSubnet" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Error testing Docker network: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

function Test-EnvironmentReadiness {
    <#
    .SYNOPSIS
    Validates that the environment is ready for Peviitor deployment.
    
    .OUTPUTS
    Returns $true if environment is ready
    
    .EXAMPLE
    Test-EnvironmentReadiness
    #>
    
    Write-DetailedLog "Validating environment readiness" -Level "INFO"
    
    try {
        $validationTests = @(
            @{ Name = "Directory Structure"; Function = { Test-DirectoryStructure } }
            @{ Name = "Docker Network"; Function = { Test-DockerNetwork } }
            @{ Name = "Directory Permissions"; Function = { Test-DirectoryPermissions } }
            @{ Name = "Disk Space"; Function = { Test-DiskSpace } }
        )
        
        $allTestsPassed = $true
        
        foreach ($test in $validationTests) {
            Write-DetailedLog "Testing: $($test.Name)" -Level "DEBUG"
            
            $result = & $test.Function
            
            if ($result) {
                Write-DetailedLog "✅ $($test.Name): PASSED" -Level "SUCCESS"
            } else {
                Write-DetailedLog "❌ $($test.Name): FAILED" -Level "ERROR"
                $allTestsPassed = $false
            }
        }
        
        if ($allTestsPassed) {
            Write-DetailedLog "Environment readiness validation passed" -Level "SUCCESS"
        } else {
            Write-DetailedLog "Environment readiness validation failed" -Level "ERROR"
        }
        
        return $allTestsPassed
        
    } catch {
        Write-DetailedLog "Error validating environment readiness: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-DirectoryStructure {
    <#
    .SYNOPSIS
    Tests if all required directories exist and are accessible.
    
    .OUTPUTS
    Returns $true if directory structure is valid
    #>
    
    $requiredDirs = @(
        $script:EnvConfig.BasePath,
        $script:EnvConfig.BuildPath,
        $script:EnvConfig.SolrDataPath,
        $script:EnvConfig.TempPath
    )
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            Write-DetailedLog "Required directory missing: $dir" -Level "ERROR"
            return $false
        }
        
        # Test if directory is writable
        try {
            $testFile = Join-Path $dir ".write-test"
            Set-Content -Path $testFile -Value "test" -ErrorAction Stop
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        } catch {
            Write-DetailedLog "Directory not writable: $dir" -Level "ERROR"
            return $false
        }
    }
    
    return $true
}

function Test-DirectoryPermissions {
    <#
    .SYNOPSIS
    Tests if directory permissions are set correctly.
    
    .OUTPUTS
    Returns $true if permissions are correct
    #>
    
    try {
        $basePath = $script:EnvConfig.BasePath
        
        # Test write access
        $testFile = Join-Path $basePath "permission-test.tmp"
        Set-Content -Path $testFile -Value "permission test" -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        return $true
        
    } catch {
        Write-DetailedLog "Directory permission test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-DiskSpace {
    <#
    .SYNOPSIS
    Tests if there is sufficient disk space for Peviitor installation.
    
    .OUTPUTS
    Returns $true if disk space is sufficient
    #>
    
    try {
        $basePath = $script:EnvConfig.BasePath
        $drive = (Get-Item $basePath).Root.Name
        
        $driveInfo = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object DeviceID -eq $drive.TrimEnd('\')
        $freeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
        
        # Require at least 5GB free space for Peviitor
        $requiredSpaceGB = 5
        
        if ($freeSpaceGB -ge $requiredSpaceGB) {
            Write-DetailedLog "Disk space check passed: $freeSpaceGB GB available" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Insufficient disk space: $freeSpaceGB GB available, $requiredSpaceGB GB required" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Disk space check failed: $($_.Exception.Message)" -Level "WARN"
        return $true  # Don't fail environment setup for disk space check errors
    }
}

# ============================================================================
# ENVIRONMENT STATUS AND REPORTING
# ============================================================================

function Get-EnvironmentStatus {
    <#
    .SYNOPSIS
    Gets comprehensive status of the Peviitor environment.
    
    .OUTPUTS
    Returns hashtable with environment status details
    
    .EXAMPLE
    $status = Get-EnvironmentStatus
    #>
    
    $status = @{
        Directories = @{}
        DockerNetwork = @{}
        Containers = @{}
        DiskSpace = @{}
        IsReady = $false
    }
    
    try {
        # Check directories
        $requiredDirs = @(
            $script:EnvConfig.BasePath,
            $script:EnvConfig.BuildPath,
            $script:EnvConfig.APIPath,
            $script:EnvConfig.SolrDataPath
        )
        
        foreach ($dir in $requiredDirs) {
            $dirName = Split-Path $dir -Leaf
            $status.Directories[$dirName] = @{
                Path = $dir
                Exists = Test-Path $dir
                Writable = $false
            }
            
            if ($status.Directories[$dirName].Exists) {
                try {
                    $testFile = Join-Path $dir ".write-test"
                    Set-Content -Path $testFile -Value "test" -ErrorAction Stop
                    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                    $status.Directories[$dirName].Writable = $true
                } catch {
                    # Not writable
                }
            }
        }
        
        # Check Docker network
        $networkName = $script:EnvConfig.NetworkName
        $networkExists = docker network ls -q -f name=$networkName 2>$null
        
        $status.DockerNetwork = @{
            Name = $networkName
            Exists = [bool]$networkExists
            Subnet = $null
        }
        
        if ($networkExists) {
            try {
                $networkInfo = docker network inspect $networkName 2>$null | ConvertFrom-Json
                if ($networkInfo) {
                    $status.DockerNetwork.Subnet = $networkInfo[0].IPAM.Config[0].Subnet
                }
            } catch {
                # Could not get network info
            }
        }
        
        # Check containers
        foreach ($containerName in $script:EnvConfig.ContainerNames) {
            $containerExists = docker ps -aq -f name=$containerName 2>$null
            $containerRunning = docker ps -q -f name=$containerName 2>$null
            
            $status.Containers[$containerName] = @{
                Exists = [bool]$containerExists
                Running = [bool]$containerRunning
            }
        }
        
        # Check disk space
        try {
            $basePath = $script:EnvConfig.BasePath
            $drive = if (Test-Path $basePath) { 
                (Get-Item $basePath).Root.Name 
            } else { 
                $env:SystemDrive 
            }
            
            $driveInfo = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object DeviceID -eq $drive.TrimEnd('\')
            if ($driveInfo) {
                $status.DiskSpace = @{
                    Drive = $drive
                    FreeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
                    TotalSpaceGB = [math]::Round($driveInfo.Size / 1GB, 2)
                }
            }
        } catch {
            # Could not get disk space info
        }
        
        # Determine if environment is ready
        $dirsReady = $status.Directories.Values | Where-Object { -not $_.Exists -or -not $_.Writable } | Measure-Object | Select-Object -ExpandProperty Count
        $networkReady = $status.DockerNetwork.Exists
        $containersClean = ($status.Containers.Values | Where-Object { $_.Running } | Measure-Object | Select-Object -ExpandProperty Count) -eq 0
        
        $status.IsReady = ($dirsReady -eq 0) -and $networkReady -and $containersClean
        
    } catch {
        Write-DetailedLog "Error getting environment status: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $status
}

function Write-EnvironmentReport {
    <#
    .SYNOPSIS
    Displays a comprehensive environment status report.
    
    .EXAMPLE
    Write-EnvironmentReport
    #>
    
    $status = Get-EnvironmentStatus
    
    Write-LogHeader -Title "PEVIITOR ENVIRONMENT REPORT" -Level 3
    
    # Directories report
    Write-DetailedLog "Directory Status:" -Level "INFO"
    foreach ($dirInfo in $status.Directories.GetEnumerator()) {
        $dirStatus = $dirInfo.Value
        $statusIcon = if ($dirStatus.Exists -and $dirStatus.Writable) { "✅" } 
                     elseif ($dirStatus.Exists) { "⚠️" } 
                     else { "❌" }
        
        Write-DetailedLog "  $statusIcon $($dirInfo.Key): $($dirStatus.Path)" -Level "INFO"
        if (-not $dirStatus.Exists) {
            Write-DetailedLog "    - Directory does not exist" -Level "WARN"
        } elseif (-not $dirStatus.Writable) {
            Write-DetailedLog "    - Directory is not writable" -Level "WARN"
        }
    }
    
    # Docker network report
    Write-DetailedLog "Docker Network Status:" -Level "INFO"
    $networkIcon = if ($status.DockerNetwork.Exists) { "✅" } else { "❌" }
    Write-DetailedLog "  $networkIcon Network: $($status.DockerNetwork.Name)" -Level "INFO"
    if ($status.DockerNetwork.Exists -and $status.DockerNetwork.Subnet) {
        Write-DetailedLog "    - Subnet: $($status.DockerNetwork.Subnet)" -Level "INFO"
    }
    
    # Containers report
    $runningContainers = $status.Containers.GetEnumerator() | Where-Object { $_.Value.Running }
    if ($runningContainers) {
        Write-DetailedLog "Running Containers:" -Level "INFO"
        foreach ($container in $runningContainers) {
            Write-DetailedLog "  🔄 $($container.Key)" -Level "INFO"
        }
    } else {
        Write-DetailedLog "No Peviitor containers are currently running" -Level "INFO"
    }
    
    # Disk space report
    if ($status.DiskSpace.FreeSpaceGB) {
        Write-DetailedLog "Disk Space:" -Level "INFO"
        Write-DetailedLog "  💽 Drive $($status.DiskSpace.Drive): $($status.DiskSpace.FreeSpaceGB)GB free of $($status.DiskSpace.TotalSpaceGB)GB total" -Level "INFO"
    }
    
    # Overall status
    $overallIcon = if ($status.IsReady) { "✅" } else { "⚠️" }
    $overallMessage = if ($status.IsReady) { "Environment is ready for deployment" } else { "Environment requires setup" }
    Write-DetailedLog "$overallIcon $overallMessage" -Level $(if ($status.IsReady) { "SUCCESS" } else { "WARN" })
}

# ============================================================================
# ENVIRONMENT ROLLBACK AND RECOVERY
# ============================================================================

function Invoke-EnvironmentRollback {
    <#
    .SYNOPSIS
    Performs emergency rollback of environment changes.
    
    .PARAMETER Reason
    Reason for the rollback
    
    .OUTPUTS
    Returns $true if rollback was successful
    
    .EXAMPLE
    Invoke-EnvironmentRollback -Reason "Installation failure"
    #>
    param(
        [Parameter()]
        [string]$Reason = "Unknown error"
    )
    
    Write-LogHeader -Title "ENVIRONMENT ROLLBACK" -Level 2
    Write-DetailedLog "Performing environment rollback due to: $Reason" -Level "WARN"
    
    try {
        # Stop any containers that might be running
        Write-DetailedLog "Stopping all Peviitor containers..." -Level "INFO"
        Stop-PeviitorContainers -Force
        
        # Remove containers
        Write-DetailedLog "Removing all Peviitor containers..." -Level "INFO"
        Remove-PeviitorContainers
        
        # Remove networks
        Write-DetailedLog "Removing Docker networks..." -Level "INFO"
        Remove-PeviitorNetworks
        
        # Clean up directories (but preserve logs)
        Write-DetailedLog "Cleaning up directories..." -Level "INFO"
        $basePath = $script:EnvConfig.BasePath
        if (Test-Path $basePath) {
            # Move logs to temp location for preservation
            $logsPath = Join-Path $basePath "logs"
            $tempLogsPath = Join-Path $env:TEMP "peviitor-rollback-logs-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            
            if (Test-Path $logsPath) {
                try {
                    Move-Item $logsPath $tempLogsPath -Force
                    Write-DetailedLog "Logs preserved at: $tempLogsPath" -Level "INFO"
                } catch {
                    Write-DetailedLog "Could not preserve logs: $($_.Exception.Message)" -Level "WARN"
                }
            }
            
            # Remove base directory
            Remove-Item $basePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-DetailedLog "Environment rollback completed" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Error during environment rollback: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-EnvironmentRecovery {
    <#
    .SYNOPSIS
    Tests if the environment can be recovered from a failed state.
    
    .OUTPUTS
    Returns hashtable with recovery assessment
    
    .EXAMPLE
    $recovery = Test-EnvironmentRecovery
    #>
    
    Write-DetailedLog "Assessing environment recovery options" -Level "INFO"
    
    $assessment = @{
        CanRecover = $true
        Issues = @()
        Recommendations = @()
        RecoverySteps = @()
    }
    
    try {
        # Check for stuck containers
        foreach ($containerName in $script:EnvConfig.ContainerNames) {
            $containerStatus = docker ps -a -f name=$containerName --format "{{.Status}}" 2>$null
            
            if ($containerStatus -and $containerStatus -like "*Exited*") {
                $assessment.Issues += "Container '$containerName' is in exited state"
                $assessment.RecoverySteps += "Remove container: $containerName"
            } elseif ($containerStatus -and $containerStatus -like "*Restarting*") {
                $assessment.Issues += "Container '$containerName' is stuck restarting"
                $assessment.RecoverySteps += "Force stop and remove container: $containerName"
                $assessment.CanRecover = $false
            }
        }
        
        # Check for network conflicts
        $networkName = $script:EnvConfig.NetworkName
        $networkExists = docker network ls -q -f name=$networkName 2>$null
        
        if ($networkExists) {
            $networkInfo = docker network inspect $networkName 2>$null | ConvertFrom-Json
            if ($networkInfo -and $networkInfo[0].Containers -and ($networkInfo[0].Containers | Get-Member -MemberType NoteProperty).Count -gt 0) {
                $assessment.Issues += "Docker network '$networkName' has attached containers"
                $assessment.RecoverySteps += "Force remove all containers from network"
            }
        }
        
        # Check for file locks
        $basePath = $script:EnvConfig.BasePath
        if (Test-Path $basePath) {
            try {
                $testFile = Join-Path $basePath "recovery-test.tmp"
                Set-Content -Path $testFile -Value "test" -ErrorAction Stop
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            } catch {
                $assessment.Issues += "Directory '$basePath' appears to be locked or inaccessible"
                $assessment.RecoverySteps += "Check for processes using the directory"
                $assessment.CanRecover = $false
            }
        }
        
        # Generate recommendations
        if ($assessment.Issues.Count -eq 0) {
            $assessment.Recommendations += "Environment appears clean - proceed with normal setup"
        } else {
            $assessment.Recommendations += "Clean up existing resources before retrying"
            if (-not $assessment.CanRecover) {
                $assessment.Recommendations += "Manual intervention may be required"
                $assessment.Recommendations += "Consider restarting Docker Desktop"
            }
        }
        
    } catch {
        $assessment.CanRecover = $false
        $assessment.Issues += "Error assessing recovery: $($_.Exception.Message)"
        $assessment.Recommendations += "Manual diagnosis required"
    }
    
    return $assessment
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Wait-ForDirectoryAccess {
    <#
    .SYNOPSIS
    Waits for a directory to become accessible.
    
    .PARAMETER Path
    Directory path to wait for
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait
    
    .OUTPUTS
    Returns $true if directory became accessible within timeout
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [Parameter()]
        [int]$TimeoutSeconds = 30
    )
    
    $startTime = Get-Date
    
    while ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            if (Test-Path $Path) {
                $testFile = Join-Path $Path "access-test.tmp"
                Set-Content -Path $testFile -Value "test" -ErrorAction Stop
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                return $true
            }
        } catch {
            # Directory not accessible yet
        }
        
        Start-Sleep -Seconds 2
    }
    
    return $false
}

function Get-DirectorySize {
    <#
    .SYNOPSIS
    Gets the size of a directory and its contents.
    
    .PARAMETER Path
    Directory path
    
    .OUTPUTS
    Returns size in bytes, or 0 if directory doesn't exist
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    try {
        if (Test-Path $Path) {
            $size = (Get-ChildItem $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum
            return [long]$size
        } else {
            return 0
        }
    } catch {
        return 0
    }
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Environment setup module loaded" -Level "DEBUG"

# Validate configuration on module load
if (-not $Global:PeviitorConfig) {
    Write-DetailedLog "Global Peviitor configuration not found - some functions may not work correctly" -Level "WARN"
}