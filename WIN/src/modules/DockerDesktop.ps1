# DockerDesktop.ps1 - Docker Desktop installation and management
# This module handles Docker Desktop installation, configuration, and verification

# ============================================================================
# DOCKER DESKTOP CONFIGURATION
# ============================================================================

$script:DockerConfig = @{
    MinVersion = "4.0.0"
    DownloadURL = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    InstallTimeout = 600  # 10 minutes
    ServiceTimeout = 120  # 2 minutes
    HealthCheckTimeout = 300  # 5 minutes
    InstallArgs = @("install", "--quiet", "--accept-license")
    ServiceName = "com.docker.service"
    ProcessName = "Docker Desktop"
}

# ============================================================================
# DOCKER DETECTION AND VERSION CHECKING
# ============================================================================

function Test-DockerDesktopInstalled {
    <#
    .SYNOPSIS
    Checks if Docker Desktop is installed and returns version information.
    
    .OUTPUTS
    Returns hashtable with installation status and version details
    
    .EXAMPLE
    $dockerInfo = Test-DockerDesktopInstalled
    if ($dockerInfo.IsInstalled) { ... }
    #>
    
    Write-DetailedLog "Checking Docker Desktop installation status" -Level "DEBUG"
    
    $result = @{
        IsInstalled = $false
        Version = $null
        InstallPath = $null
        Method = $null
        IsServiceRunning = $false
        IsProcessRunning = $false
        NeedsUpdate = $false
    }
    
    # Method 1: Check registry (most reliable)
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        try {
            $dockerApp = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -like "*Docker Desktop*" }
            
            if ($dockerApp) {
                $result.IsInstalled = $true
                $result.Version = $dockerApp.DisplayVersion
                $result.InstallPath = $dockerApp.InstallLocation
                $result.Method = "Registry"
                break
            }
        } catch {
            # Continue to next registry path
        }
    }
    
    # Method 2: Check command line (if registry failed)
    if (-not $result.IsInstalled) {
        try {
            $dockerVersion = docker --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
                $result.IsInstalled = $true
                $result.Version = ($dockerVersion -replace "Docker version ", "" -split ",")[0].Trim()
                $result.Method = "Command"
            }
        } catch {
            # Docker command not found
        }
    }
    
    # Method 3: Check common installation paths
    if (-not $result.IsInstalled) {
        $commonPaths = @(
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
            "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
        )
        
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                $result.IsInstalled = $true
                $result.InstallPath = Split-Path $path
                $result.Method = "FileSystem"
                
                # Try to get version from file properties
                try {
                    $fileInfo = Get-ItemProperty $path
                    $result.Version = $fileInfo.VersionInfo.ProductVersion
                } catch {
                    $result.Version = "Unknown"
                }
                break
            }
        }
    }
    
    # Check service status if installed
    if ($result.IsInstalled) {
        $result.IsServiceRunning = Test-DockerService
        $result.IsProcessRunning = Test-DockerProcess
        
        # Check if update is needed
        if ($result.Version -and $result.Version -ne "Unknown") {
            $versionComparison = Compare-SemanticVersion -Version1 $result.Version -Version2 $script:DockerConfig.MinVersion
            $result.NeedsUpdate = ($versionComparison -eq -1)
        }
    }
    
    Write-DetailedLog "Docker Desktop status: Installed=$($result.IsInstalled), Version=$($result.Version), Method=$($result.Method)" -Level "DEBUG"
    
    return $result
}

function Test-DockerService {
    <#
    .SYNOPSIS
    Tests if Docker service is running.
    
    .OUTPUTS
    Returns $true if Docker service is running
    #>
    
    try {
        $service = Get-Service -Name $script:DockerConfig.ServiceName -ErrorAction SilentlyContinue
        return ($service -and $service.Status -eq "Running")
    } catch {
        return $false
    }
}

function Test-DockerProcess {
    <#
    .SYNOPSIS
    Tests if Docker Desktop process is running.
    
    .OUTPUTS
    Returns $true if Docker Desktop process is running
    #>
    
    try {
        $process = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
        return ($process -ne $null)
    } catch {
        return $false
    }
}

# ============================================================================
# DOCKER DESKTOP INSTALLATION
# ============================================================================

function Install-DockerDesktop {
    <#
    .SYNOPSIS
    Installs Docker Desktop using the best available method.
    
    .PARAMETER Force
    Force reinstallation even if already installed
    
    .PARAMETER Method
    Preferred installation method (Auto, Direct, Winget, Chocolatey)
    
    .OUTPUTS
    Returns $true if installation was successful
    
    .EXAMPLE
    Install-DockerDesktop -Method "Auto"
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [ValidateSet("Auto", "Direct", "Winget", "Chocolatey")]
        [string]$Method = "Auto"
    )
    
    Write-LogHeader -Title "DOCKER DESKTOP INSTALLATION" -Level 2
    
    # Ensure administrator privileges
    if (-not (Test-Administrator)) {
        Write-DetailedLog "Administrator privileges required for Docker Desktop installation" -Level "ERROR"
        return $false
    }
    
    try {
        # Check current installation status
        $dockerInfo = Test-DockerDesktopInstalled
        
        if ($dockerInfo.IsInstalled -and -not $Force -and -not $dockerInfo.NeedsUpdate) {
            Write-DetailedLog "Docker Desktop v$($dockerInfo.Version) is already installed and up to date" -Level "SUCCESS"
            return Test-DockerFunctionality
        }
        
        if ($dockerInfo.IsInstalled -and ($Force -or $dockerInfo.NeedsUpdate)) {
            Write-DetailedLog "Docker Desktop update/reinstallation required" -Level "INFO"
            if ($dockerInfo.NeedsUpdate) {
                Write-DetailedLog "Current version: v$($dockerInfo.Version), Required: v$($script:DockerConfig.MinVersion)+" -Level "INFO"
            }
        }
        
        # Choose installation method
        $installMethod = if ($Method -eq "Auto") { 
            Get-BestInstallationMethod 
        } else { 
            $Method 
        }
        
        Write-DetailedLog "Using installation method: $installMethod" -Level "INFO"
        
        # Perform installation
        $installResult = switch ($installMethod) {
            "Winget" { Install-DockerViaWinget }
            "Chocolatey" { Install-DockerViaChocolatey }
            "Direct" { Install-DockerViaDirect }
            default { Install-DockerViaDirect }
        }
        
        if (-not $installResult) {
            Write-DetailedLog "Docker Desktop installation failed" -Level "ERROR"
            return $false
        }
        
        # Post-installation verification
        Write-DetailedLog "Verifying Docker Desktop installation..." -Level "INFO"
        $success = Test-DockerInstallation
        
        if ($success) {
            Write-DetailedLog "✅ Docker Desktop installation completed successfully" -Level "SUCCESS"
        } else {
            Write-DetailedLog "❌ Docker Desktop installation verification failed" -Level "ERROR"
        }
        
        return $success
        
    } catch {
        Write-InstallationError -ErrorMessage "Docker Desktop installation failed" -Exception $_.Exception
        return $false
    }
}

function Get-BestInstallationMethod {
    <#
    .SYNOPSIS
    Determines the best installation method based on system capabilities.
    
    .OUTPUTS
    Returns the recommended installation method
    #>
    
    Write-DetailedLog "Determining best Docker Desktop installation method" -Level "DEBUG"
    
    # Check if winget is available
    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        try {
            $wingetVersion = winget --version
            if ($wingetVersion) {
                Write-DetailedLog "Winget is available: $wingetVersion" -Level "DEBUG"
                return "Winget"
            }
        } catch {
            # Winget not working properly
        }
    }
    
    # Check if chocolatey is available
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        try {
            $chocoVersion = choco --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-DetailedLog "Chocolatey is available: $chocoVersion" -Level "DEBUG"
                return "Chocolatey"
            }
        } catch {
            # Chocolatey not working properly
        }
    }
    
    # Fall back to direct download
    Write-DetailedLog "Using direct download method" -Level "DEBUG"
    return "Direct"
}

function Install-DockerViaWinget {
    <#
    .SYNOPSIS
    Installs Docker Desktop using Windows Package Manager (winget).
    
    .OUTPUTS
    Returns $true if installation was successful
    #>
    
    Write-DetailedLog "Installing Docker Desktop via winget" -Level "INFO"
    Show-Progress -Activity "Docker Installation" -Status "Installing via winget..." -PercentComplete 20
    
    try {
        $wingetArgs = @("install", "Docker.DockerDesktop", "--accept-package-agreements", "--accept-source-agreements", "--silent")
        
        Write-DetailedLog "Executing: winget $($wingetArgs -join ' ')" -Level "DEBUG"
        
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-DetailedLog "Winget installation completed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Winget installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Winget installation error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-DockerViaChocolatey {
    <#
    .SYNOPSIS
    Installs Docker Desktop using Chocolatey.
    
    .OUTPUTS
    Returns $true if installation was successful
    #>
    
    Write-DetailedLog "Installing Docker Desktop via Chocolatey" -Level "INFO"
    Show-Progress -Activity "Docker Installation" -Status "Installing via Chocolatey..." -PercentComplete 20
    
    try {
        $chocoArgs = @("install", "docker-desktop", "-y", "--no-progress")
        
        Write-DetailedLog "Executing: choco $($chocoArgs -join ' ')" -Level "DEBUG"
        
        $process = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-DetailedLog "Chocolatey installation completed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Chocolatey installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Chocolatey installation error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-DockerViaDirect {
    <#
    .SYNOPSIS
    Installs Docker Desktop by downloading installer directly from Docker.
    
    .OUTPUTS
    Returns $true if installation was successful
    #>
    
    Write-DetailedLog "Installing Docker Desktop via direct download" -Level "INFO"
    Show-Progress -Activity "Docker Installation" -Status "Downloading installer..." -PercentComplete 10
    
    try {
        # Download installer
        $installerPath = Download-DockerInstaller
        if (-not $installerPath) {
            return $false
        }
        
        Show-Progress -Activity "Docker Installation" -Status "Running installer..." -PercentComplete 50
        
        # Run installer
        Write-DetailedLog "Running Docker Desktop installer: $installerPath" -Level "INFO"
        
        $installArgs = $script:DockerConfig.InstallArgs
        Write-DetailedLog "Install arguments: $($installArgs -join ' ')" -Level "DEBUG"
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        # Cleanup installer
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        
        if ($process.ExitCode -eq 0) {
            Write-DetailedLog "Docker Desktop installer completed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Docker Desktop installer failed with exit code: $($process.ExitCode)" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Direct installation error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Download-DockerInstaller {
    <#
    .SYNOPSIS
    Downloads Docker Desktop installer from official source.
    
    .OUTPUTS
    Returns path to downloaded installer or $null if failed
    #>
    
    try {
        $tempPath = [System.IO.Path]::GetTempPath()
        $installerPath = Join-Path $tempPath "DockerDesktopInstaller.exe"
        
        # Remove existing installer
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force
        }
        
        Write-DetailedLog "Downloading from: $($script:DockerConfig.DownloadURL)" -Level "DEBUG"
        Write-DetailedLog "Download path: $installerPath" -Level "DEBUG"
        
        # Create WebClient with progress tracking
        $webClient = New-Object System.Net.WebClient
        
        # Register progress event
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            $received = $Event.SourceEventArgs.BytesReceived
            $total = $Event.SourceEventArgs.TotalBytesToReceive
            
            $status = if ($total -gt 0) {
                $receivedMB = [math]::Round($received / 1MB, 1)
                $totalMB = [math]::Round($total / 1MB, 1)
                "Downloading... $receivedMB MB / $totalMB MB ($percent%)"
            } else {
                "Downloading... $([math]::Round($received / 1MB, 1)) MB ($percent%)"
            }
            
            Show-Progress -Activity "Docker Installation" -Status $status -PercentComplete $percent -Id 2 -ParentId 1
        } | Out-Null
        
        # Download file
        $webClient.DownloadFile($script:DockerConfig.DownloadURL, $installerPath)
        
        # Cleanup progress tracking
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
        $webClient.Dispose()
        Hide-Progress -Id 2
        
        if (Test-Path $installerPath) {
            $fileSize = (Get-Item $installerPath).Length
            Write-DetailedLog "Download completed: $([math]::Round($fileSize / 1MB, 1)) MB" -Level "SUCCESS"
            return $installerPath
        } else {
            Write-DetailedLog "Downloaded installer not found at expected path" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-DetailedLog "Docker installer download failed: $($_.Exception.Message)" -Level "ERROR"
        
        # Cleanup on failure
        if ($webClient) {
            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event -ErrorAction SilentlyContinue
            $webClient.Dispose()
        }
        
        return $null
    }
}

# ============================================================================
# DOCKER DESKTOP CONFIGURATION AND STARTUP
# ============================================================================

function Start-DockerDesktop {
    <#
    .SYNOPSIS
    Starts Docker Desktop and waits for it to be ready.
    
    .PARAMETER WaitForReady
    Wait for Docker to be fully operational
    
    .OUTPUTS
    Returns $true if Docker started successfully
    
    .EXAMPLE
    Start-DockerDesktop -WaitForReady
    #>
    param(
        [Parameter()]
        [switch]$WaitForReady = $true
    )
    
    Write-DetailedLog "Starting Docker Desktop" -Level "INFO"
    Show-Progress -Activity "Docker Startup" -Status "Starting Docker Desktop..." -PercentComplete 10
    
    try {
        # Find Docker Desktop executable
        $dockerExePath = Find-DockerExecutable
        if (-not $dockerExePath) {
            Write-DetailedLog "Docker Desktop executable not found" -Level "ERROR"
            return $false
        }
        
        # Check if already running
        if (Test-DockerProcess) {
            Write-DetailedLog "Docker Desktop is already running" -Level "INFO"
        } else {
            Write-DetailedLog "Starting Docker Desktop: $dockerExePath" -Level "DEBUG"
            Start-Process -FilePath $dockerExePath -WindowStyle Hidden
            
            # Wait for process to start
            Show-Progress -Activity "Docker Startup" -Status "Waiting for Docker Desktop process..." -PercentComplete 30
            $processStarted = Wait-ForDockerProcess -TimeoutSeconds 60
            
            if (-not $processStarted) {
                Write-DetailedLog "Docker Desktop process failed to start" -Level "ERROR"
                return $false
            }
        }
        
        if ($WaitForReady) {
            # Wait for Docker service to be ready
            Show-Progress -Activity "Docker Startup" -Status "Waiting for Docker service..." -PercentComplete 60
            $serviceReady = Wait-ForDockerService -TimeoutSeconds $script:DockerConfig.ServiceTimeout
            
            if (-not $serviceReady) {
                Write-DetailedLog "Docker service failed to start within timeout" -Level "ERROR"
                return $false
            }
            
            # Wait for Docker daemon to be responsive
            Show-Progress -Activity "Docker Startup" -Status "Testing Docker functionality..." -PercentComplete 90
            $dockerReady = Wait-ForDockerReady -TimeoutSeconds $script:DockerConfig.HealthCheckTimeout
            
            if (-not $dockerReady) {
                Write-DetailedLog "Docker daemon is not responding" -Level "ERROR"
                return $false
            }
        }
        
        Show-Progress -Activity "Docker Startup" -Status "Docker Desktop is ready" -PercentComplete 100
        Write-DetailedLog "✅ Docker Desktop started successfully" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error starting Docker Desktop: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Find-DockerExecutable {
    <#
    .SYNOPSIS
    Finds the Docker Desktop executable path.
    
    .OUTPUTS
    Returns path to Docker Desktop executable or $null if not found
    #>
    
    $possiblePaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe",
        "$env:ProgramFiles\Docker\Docker\frontend\Docker Desktop.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-DetailedLog "Found Docker Desktop executable: $path" -Level "DEBUG"
            return $path
        }
    }
    
    Write-DetailedLog "Docker Desktop executable not found in common locations" -Level "WARN"
    return $null
}

function Wait-ForDockerProcess {
    <#
    .SYNOPSIS
    Waits for Docker Desktop process to start.
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    
    .OUTPUTS
    Returns $true if process started within timeout
    #>
    param(
        [int]$TimeoutSeconds = 60
    )
    
    $startTime = Get-Date
    
    while ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if (Test-DockerProcess) {
            return $true
        }
        
        Start-Sleep -Seconds 2
    }
    
    return $false
}

function Wait-ForDockerService {
    <#
    .SYNOPSIS
    Waits for Docker service to be running.
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    
    .OUTPUTS
    Returns $true if service is running within timeout
    #>
    param(
        [int]$TimeoutSeconds = 120
    )
    
    $startTime = Get-Date
    
    while ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if (Test-DockerService) {
            return $true
        }
        
        Start-Sleep -Seconds 5
    }
    
    return $false
}

function Wait-ForDockerReady {
    <#
    .SYNOPSIS
    Waits for Docker daemon to be fully operational.
    
    .PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
    
    .OUTPUTS
    Returns $true if Docker is ready within timeout
    #>
    param(
        [int]$TimeoutSeconds = 300
    )
    
    $startTime = Get-Date
    
    while ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            # Test Docker with a simple command
            $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
            
            if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
                Write-DetailedLog "Docker daemon is ready (Server version: $dockerVersion)" -Level "SUCCESS"
                return $true
            }
        } catch {
            # Docker not ready yet
        }
        
        Start-Sleep -Seconds 10
    }
    
    return $false
}

# ============================================================================
# INSTALLATION VERIFICATION
# ============================================================================

function Test-DockerInstallation {
    <#
    .SYNOPSIS
    Comprehensive test of Docker Desktop installation and functionality.
    
    .OUTPUTS
    Returns $true if Docker is properly installed and functional
    
    .EXAMPLE
    $isWorking = Test-DockerInstallation
    #>
    
    Write-LogHeader -Title "DOCKER INSTALLATION VERIFICATION" -Level 3
    
    $verificationSteps = @(
        @{ Name = "Installation Detection"; Function = { Test-DockerDesktopInstalled } }
        @{ Name = "Docker Desktop Startup"; Function = { Start-DockerDesktop -WaitForReady } }
        @{ Name = "Docker Functionality"; Function = { Test-DockerFunctionality } }
        @{ Name = "Docker Network"; Function = { Test-DockerNetworking } }
    )
    
    $stepNumber = 1
    $totalSteps = $verificationSteps.Count
    
    foreach ($step in $verificationSteps) {
        Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Docker Verification"
        
        try {
            $result = & $step.Function
            
            if ($result) {
                Write-DetailedLog "✅ $($step.Name): PASSED" -Level "SUCCESS"
            } else {
                Write-DetailedLog "❌ $($step.Name): FAILED" -Level "ERROR"
                return $false
            }
        } catch {
            Write-DetailedLog "❌ $($step.Name): ERROR - $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
        
        $stepNumber++
    }
    
    Hide-Progress
    Write-DetailedLog "🎉 Docker Desktop verification completed successfully" -Level "SUCCESS"
    return $true
}

function Test-DockerFunctionality {
    <#
    .SYNOPSIS
    Tests basic Docker functionality with simple commands.
    
    .OUTPUTS
    Returns $true if Docker commands work properly
    #>
    
    Write-DetailedLog "Testing Docker functionality" -Level "DEBUG"
    
    $tests = @(
        @{ Name = "Docker Version"; Command = "docker --version" }
        @{ Name = "Docker Info"; Command = "docker info --format '{{.ServerVersion}}'" }
        @{ Name = "Docker PS"; Command = "docker ps" }
    )
    
    foreach ($test in $tests) {
        try {
            Write-DetailedLog "Running: $($test.Command)" -Level "DEBUG"
            $output = Invoke-Expression $test.Command 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-DetailedLog "$($test.Name): OK" -Level "DEBUG"
            } else {
                Write-DetailedLog "$($test.Name): Failed (Exit Code: $LASTEXITCODE)" -Level "ERROR"
                return $false
            }
        } catch {
            Write-DetailedLog "$($test.Name): Exception - $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    
    return $true
}

function Test-DockerNetworking {
    <#
    .SYNOPSIS
    Tests Docker networking capabilities.
    
    .OUTPUTS
    Returns $true if Docker networking works
    #>
    
    Write-DetailedLog "Testing Docker networking" -Level "DEBUG"
    
    try {
        # Test network creation and removal
        $testNetworkName = "peviitor-test-network"
        
        # Create test network
        $createResult = docker network create $testNetworkName 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-DetailedLog "Failed to create test network" -Level "ERROR"
            return $false
        }
        
        # List networks to verify creation
        $networks = docker network ls --format "{{.Name}}" 2>$null
        if ($networks -notcontains $testNetworkName) {
            Write-DetailedLog "Test network not found in network list" -Level "ERROR"
            return $false
        }
        
        # Remove test network
        docker network rm $testNetworkName 2>$null | Out-Null
        
        Write-DetailedLog "Docker networking test: OK" -Level "DEBUG"
        return $true
        
    } catch {
        Write-DetailedLog "Docker networking test failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Docker Desktop module loaded" -Level "DEBUG"