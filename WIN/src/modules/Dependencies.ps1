# Dependencies.ps1 - Software dependencies installation and management
# This module handles Git, Java, and JMeter installation and updates

# ============================================================================
# DEPENDENCIES CONFIGURATION
# ============================================================================

$script:DependenciesConfig = @{
    Git = @{
        MinVersion = "2.30.0"
        WingetId = "Git.Git"
        ChocolateyId = "git"
        DownloadURL = "https://github.com/git-for-windows/git/releases/latest/download/Git-{VERSION}-64-bit.exe"
        InstallArgs = @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS")
        RegistryPath = "HKLM:\SOFTWARE\GitForWindows"
    }
    Java = @{
        MinVersion = "11.0.0"
        WingetId = "Microsoft.OpenJDK.11"
        ChocolateyId = "openjdk11"
        DownloadURL = "https://aka.ms/download-jdk/microsoft-jdk-11.0.19-windows-x64.msi"
        InstallArgs = @("/quiet", "/norestart")
        JavaHome = "$env:ProgramFiles\Microsoft\jdk-11.0.19.7-hotspot"
    }
    JMeter = @{
        Version = "5.6.3"
        DownloadURL = "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
        InstallPath = "$env:ProgramFiles\Apache\JMeter"
        PluginsManagerURL = "https://jmeter-plugins.org/get/"
        CmdRunnerURL = "https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar"
        RequiredPlugins = @("jpgc-functions")
    }
    Timeout = 600  # 10 minutes for installations
}

# ============================================================================
# DEPENDENCY DETECTION AND STATUS
# ============================================================================

function Get-DependenciesStatus {
    <#
    .SYNOPSIS
    Gets the installation status of all required dependencies.
    
    .OUTPUTS
    Returns hashtable with status information for each dependency
    
    .EXAMPLE
    $status = Get-DependenciesStatus
    if (-not $status.Git.IsInstalled) { ... }
    #>
    
    Write-DetailedLog "Checking software dependencies status" -Level "INFO"
    Show-Progress -Activity "Dependencies Check" -Status "Scanning installed software..." -PercentComplete 10
    
    $status = @{
        Git = Get-GitStatus
        Java = Get-JavaStatus  
        JMeter = Get-JMeterStatus
        Summary = @{
            AllInstalled = $false
            NeedInstall = @()
            NeedUpdate = @()
        }
    }
    
    # Generate summary
    $needInstall = @()
    $needUpdate = @()
    
    foreach ($depName in @('Git', 'Java', 'JMeter')) {
        $depStatus = $status[$depName]
        
        if (-not $depStatus.IsInstalled) {
            $needInstall += $depName
        } elseif ($depStatus.NeedsUpdate) {
            $needUpdate += $depName
        }
    }
    
    $status.Summary.NeedInstall = $needInstall
    $status.Summary.NeedUpdate = $needUpdate
    $status.Summary.AllInstalled = ($needInstall.Count -eq 0 -and $needUpdate.Count -eq 0)
    
    Show-Progress -Activity "Dependencies Check" -Status "Dependencies scan completed" -PercentComplete 100
    Hide-Progress
    
    Write-DetailedLog "Dependencies status: Install needed=$($needInstall -join ','), Update needed=$($needUpdate -join ',')" -Level "DEBUG"
    
    return $status
}

function Get-GitStatus {
    <#
    .SYNOPSIS
    Gets Git installation status and version information.
    
    .OUTPUTS
    Returns hashtable with Git status details
    #>
    
    Write-DetailedLog "Checking Git installation status" -Level "DEBUG"
    
    $result = @{
        IsInstalled = $false
        Version = $null
        InstallPath = $null
        Method = $null
        NeedsUpdate = $false
        IsWorking = $false
    }
    
    # Method 1: Check command line
    try {
        $gitVersion = git --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitVersion) {
            $result.IsInstalled = $true
            # Extract version from "git version 2.41.0.windows.1"
            $versionMatch = $gitVersion -match "git version ([\d\.]+)"
            if ($versionMatch) {
                $result.Version = $matches[1]
            } else {
                $result.Version = $gitVersion.Replace("git version ", "").Split()[0]
            }
            $result.Method = "Command"
            
            # Get install path
            $gitPath = (Get-Command git -ErrorAction SilentlyContinue).Source
            if ($gitPath) {
                $result.InstallPath = Split-Path (Split-Path $gitPath)
            }
        }
    } catch {
        # Git command not found
    }
    
    # Method 2: Check registry (if command failed)
    if (-not $result.IsInstalled) {
        try {
            $gitReg = Get-ItemProperty -Path $script:DependenciesConfig.Git.RegistryPath -ErrorAction SilentlyContinue
            if ($gitReg -and $gitReg.CurrentVersion) {
                $result.IsInstalled = $true
                $result.Version = $gitReg.CurrentVersion
                $result.InstallPath = $gitReg.InstallPath
                $result.Method = "Registry"
            }
        } catch {
            # Registry check failed
        }
    }
    
    # Check if update is needed
    if ($result.IsInstalled -and $result.Version) {
        $versionComparison = Compare-SemanticVersion -Version1 $result.Version -Version2 $script:DependenciesConfig.Git.MinVersion
        $result.NeedsUpdate = ($versionComparison -eq -1)
    }
    
    # Test if Git is working
    if ($result.IsInstalled) {
        try {
            $testResult = git --version 2>$null
            $result.IsWorking = ($LASTEXITCODE -eq 0 -and $testResult)
        } catch {
            $result.IsWorking = $false
        }
    }
    
    Write-DetailedLog "Git status: Installed=$($result.IsInstalled), Version=$($result.Version), Working=$($result.IsWorking)" -Level "DEBUG"
    
    return $result
}

function Get-JavaStatus {
    <#
    .SYNOPSIS
    Gets Java installation status and version information.
    
    .OUTPUTS
    Returns hashtable with Java status details
    #>
    
    Write-DetailedLog "Checking Java installation status" -Level "DEBUG"
    
    $result = @{
        IsInstalled = $false
        Version = $null
        InstallPath = $null
        JavaHome = $null
        Method = $null
        NeedsUpdate = $false
        IsWorking = $false
    }
    
    # Method 1: Check command line
    try {
        $javaVersion = java -version 2>&1 | Select-Object -First 1
        if ($javaVersion -and $javaVersion -match 'version "([\d\._]+)"') {
            $result.IsInstalled = $true
            # Convert version format (e.g., "11.0.19_7" to "11.0.19")
            $versionString = $matches[1] -replace '_.*', ''
            $result.Version = $versionString
            $result.Method = "Command"
            
            # Get Java home
            $result.JavaHome = $env:JAVA_HOME
            if (-not $result.JavaHome) {
                # Try to determine from java command path
                $javaPath = (Get-Command java -ErrorAction SilentlyContinue).Source
                if ($javaPath -and $javaPath -match "(.+)\\bin\\java\.exe") {
                    $result.JavaHome = $matches[1]
                }
            }
        }
    } catch {
        # Java command not found
    }
    
    # Method 2: Check common installation paths
    if (-not $result.IsInstalled) {
        $commonPaths = @(
            "$env:ProgramFiles\Microsoft\jdk-*",
            "$env:ProgramFiles\Java\jdk-*",
            "$env:ProgramFiles\OpenJDK\*",
            "$env:ProgramFiles\Eclipse Adoptium\*"
        )
        
        foreach ($pathPattern in $commonPaths) {
            $javaDirs = Get-ChildItem -Path (Split-Path $pathPattern) -Directory -Filter (Split-Path $pathPattern -Leaf) -ErrorAction SilentlyContinue
            
            foreach ($javaDir in $javaDirs) {
                $javaExe = Join-Path $javaDir "bin\java.exe"
                if (Test-Path $javaExe) {
                    $result.IsInstalled = $true
                    $result.InstallPath = $javaDir.FullName
                    $result.Method = "FileSystem"
                    
                    # Try to get version
                    try {
                        $versionOutput = & $javaExe -version 2>&1 | Select-Object -First 1
                        if ($versionOutput -match 'version "([\d\._]+)"') {
                            $result.Version = $matches[1] -replace '_.*', ''
                        }
                    } catch {
                        # Could not get version
                    }
                    break
                }
            }
            
            if ($result.IsInstalled) { break }
        }
    }
    
    # Check if update is needed
    if ($result.IsInstalled -and $result.Version) {
        try {
            $versionComparison = Compare-SemanticVersion -Version1 $result.Version -Version2 $script:DependenciesConfig.Java.MinVersion
            $result.NeedsUpdate = ($versionComparison -eq -1)
        } catch {
            # Version comparison failed, assume no update needed
        }
    }
    
    # Test if Java is working
    if ($result.IsInstalled) {
        try {
            $testResult = java -version 2>&1
            $result.IsWorking = ($LASTEXITCODE -eq 0 -and $testResult)
        } catch {
            $result.IsWorking = $false
        }
    }
    
    Write-DetailedLog "Java status: Installed=$($result.IsInstalled), Version=$($result.Version), Working=$($result.IsWorking)" -Level "DEBUG"
    
    return $result
}

function Get-JMeterStatus {
    <#
    .SYNOPSIS
    Gets JMeter installation status and version information.
    
    .OUTPUTS
    Returns hashtable with JMeter status details
    #>
    
    Write-DetailedLog "Checking JMeter installation status" -Level "DEBUG"
    
    $result = @{
        IsInstalled = $false
        Version = $null
        InstallPath = $null
        Method = $null
        NeedsUpdate = $false
        IsWorking = $false
        PluginsInstalled = @()
        MissingPlugins = @()
    }
    
    # Method 1: Check command line
    try {
        $jmeterVersion = jmeter --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $jmeterVersion) {
            $result.IsInstalled = $true
            # Extract version from output
            if ($jmeterVersion -match "Apache JMeter ([\d\.]+)") {
                $result.Version = $matches[1]
            }
            $result.Method = "Command"
            
            # Get install path
            $jmeterPath = (Get-Command jmeter -ErrorAction SilentlyContinue).Source
            if ($jmeterPath) {
                $result.InstallPath = Split-Path (Split-Path $jmeterPath)
            }
        }
    } catch {
        # JMeter command not found
    }
    
    # Method 2: Check configured install path
    if (-not $result.IsInstalled) {
        $configuredPath = $script:DependenciesConfig.JMeter.InstallPath
        $jmeterBat = Join-Path $configuredPath "bin\jmeter.bat"
        
        if (Test-Path $jmeterBat) {
            $result.IsInstalled = $true
            $result.InstallPath = $configuredPath
            $result.Method = "FileSystem"
            
            # Try to get version
            try {
                $versionOutput = & $jmeterBat --version 2>$null
                if ($versionOutput -match "Apache JMeter ([\d\.]+)") {
                    $result.Version = $matches[1]
                }
            } catch {
                # Could not get version
            }
        }
    }
    
    # Method 3: Check common installation paths
    if (-not $result.IsInstalled) {
        $commonPaths = @(
            "$env:ProgramFiles\Apache\JMeter",
            "$env:ProgramFiles\JMeter",
            "C:\apache-jmeter*"
        )
        
        foreach ($pathPattern in $commonPaths) {
            if ($pathPattern -like "*`**") {
                $jmeterDirs = Get-ChildItem -Path (Split-Path $pathPattern) -Directory -Filter (Split-Path $pathPattern -Leaf) -ErrorAction SilentlyContinue
            } else {
                $jmeterDirs = if (Test-Path $pathPattern) { Get-Item $pathPattern } else { @() }
            }
            
            foreach ($jmeterDir in $jmeterDirs) {
                $jmeterBat = Join-Path $jmeterDir "bin\jmeter.bat"
                if (Test-Path $jmeterBat) {
                    $result.IsInstalled = $true
                    $result.InstallPath = $jmeterDir.FullName
                    $result.Method = "FileSystem"
                    
                    # Try to get version
                    try {
                        $versionOutput = & $jmeterBat --version 2>$null
                        if ($versionOutput -match "Apache JMeter ([\d\.]+)") {
                            $result.Version = $matches[1]
                        }
                    } catch {
                        # Could not get version
                    }
                    break
                }
            }
            
            if ($result.IsInstalled) { break }
        }
    }
    
    # Check if update is needed (compare with required version)
    if ($result.IsInstalled -and $result.Version) {
        try {
            $versionComparison = Compare-SemanticVersion -Version1 $result.Version -Version2 $script:DependenciesConfig.JMeter.Version
            $result.NeedsUpdate = ($versionComparison -eq -1)
        } catch {
            # Version comparison failed, assume no update needed
        }
    }
    
    # Test if JMeter is working
    if ($result.IsInstalled) {
        try {
            $testResult = jmeter --version 2>$null
            $result.IsWorking = ($LASTEXITCODE -eq 0 -and $testResult)
        } catch {
            $result.IsWorking = $false
        }
    }
    
    # Check plugin status if installed
    if ($result.IsInstalled -and $result.InstallPath) {
        $pluginStatus = Get-JMeterPluginStatus -JMeterPath $result.InstallPath
        $result.PluginsInstalled = $pluginStatus.Installed
        $result.MissingPlugins = $pluginStatus.Missing
    }
    
    Write-DetailedLog "JMeter status: Installed=$($result.IsInstalled), Version=$($result.Version), Working=$($result.IsWorking)" -Level "DEBUG"
    
    return $result
}

# ============================================================================
# DEPENDENCY INSTALLATION FUNCTIONS
# ============================================================================

function Install-AllDependencies {
    <#
    .SYNOPSIS
    Installs or updates all required software dependencies.
    
    .PARAMETER Force
    Force reinstallation even if already installed
    
    .OUTPUTS
    Returns $true if all dependencies were installed successfully
    
    .EXAMPLE
    Install-AllDependencies -Force
    #>
    param(
        [Parameter()]
        [switch]$Force
    )
    
    Write-LogHeader -Title "SOFTWARE DEPENDENCIES INSTALLATION" -Level 2
    
    # Ensure administrator privileges
    if (-not (Test-Administrator)) {
        Write-DetailedLog "Administrator privileges required for software installation" -Level "ERROR"
        return $false
    }
    
    try {
        # Get current status
        $status = Get-DependenciesStatus
        
        # Determine what needs to be done
        $installationPlan = @()
        
        if ($Force -or -not $status.Git.IsInstalled -or $status.Git.NeedsUpdate) {
            $installationPlan += @{ Name = "Git"; Action = "Install/Update" }
        }
        
        if ($Force -or -not $status.Java.IsInstalled -or $status.Java.NeedsUpdate) {
            $installationPlan += @{ Name = "Java"; Action = "Install/Update" }
        }
        
        if ($Force -or -not $status.JMeter.IsInstalled -or $status.JMeter.NeedsUpdate) {
            $installationPlan += @{ Name = "JMeter"; Action = "Install/Update" }
        }
        
        if ($installationPlan.Count -eq 0) {
            Write-DetailedLog "✅ All dependencies are already installed and up to date" -Level "SUCCESS"
            return $true
        }
        
        # Display installation plan
        Write-DetailedLog "Installation plan:" -Level "INFO"
        foreach ($item in $installationPlan) {
            Write-DetailedLog "  • $($item.Name): $($item.Action)" -Level "INFO"
        }
        
        # Execute installations
        $stepNumber = 1
        $totalSteps = $installationPlan.Count
        
        foreach ($item in $installationPlan) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName "Installing $($item.Name)" -Activity "Dependencies Installation"
            
            $success = switch ($item.Name) {
                "Git" { Install-Git -Force:$Force }
                "Java" { Install-Java -Force:$Force }
                "JMeter" { Install-JMeter -Force:$Force }
            }
            
            if (-not $success) {
                Write-DetailedLog "❌ Failed to install $($item.Name)" -Level "ERROR"
                return $false
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        
        # Final verification
        Write-DetailedLog "Verifying installations..." -Level "INFO"
        $finalStatus = Get-DependenciesStatus
        
        if ($finalStatus.Summary.AllInstalled) {
            Write-DetailedLog "🎉 All dependencies installed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "❌ Some dependencies are still missing or not working" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-InstallationError -ErrorMessage "Dependencies installation failed" -Exception $_.Exception
        return $false
    }
}

function Install-Git {
    <#
    .SYNOPSIS
    Installs or updates Git for Windows.
    
    .PARAMETER Force
    Force reinstallation even if already installed
    
    .PARAMETER Method
    Installation method preference (Auto, Winget, Chocolatey, Direct)
    
    .OUTPUTS
    Returns $true if installation was successful
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [ValidateSet("Auto", "Winget", "Chocolatey", "Direct")]
        [string]$Method = "Auto"
    )
    
    Write-DetailedLog "Installing Git for Windows" -Level "INFO"
    Show-Progress -Activity "Git Installation" -Status "Checking current installation..." -PercentComplete 10
    
    try {
        # Check current status
        $gitStatus = Get-GitStatus
        
        if ($gitStatus.IsInstalled -and $gitStatus.IsWorking -and -not $Force -and -not $gitStatus.NeedsUpdate) {
            Write-DetailedLog "Git v$($gitStatus.Version) is already installed and working" -Level "SUCCESS"
            return $true
        }
        
        # Choose installation method
        $installMethod = if ($Method -eq "Auto") { 
            Get-BestPackageManagerMethod 
        } else { 
            $Method 
        }
        
        Write-DetailedLog "Using installation method: $installMethod" -Level "INFO"
        
        # Perform installation
        $installResult = switch ($installMethod) {
            "Winget" { Install-GitViaWinget }
            "Chocolatey" { Install-GitViaChocolatey }
            "Direct" { Install-GitViaDirect }
            default { Install-GitViaDirect }
        }
        
        if (-not $installResult) {
            Write-DetailedLog "Git installation failed" -Level "ERROR"
            return $false
        }
        
        # Verify installation
        Show-Progress -Activity "Git Installation" -Status "Verifying installation..." -PercentComplete 90
        
        # Refresh PATH environment variable
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        $verifiedStatus = Get-GitStatus
        
        if ($verifiedStatus.IsInstalled -and $verifiedStatus.IsWorking) {
            Write-DetailedLog "✅ Git v$($verifiedStatus.Version) installed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "❌ Git installation verification failed" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Git installation error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Install-GitViaWinget {
    <#
    .SYNOPSIS
    Installs Git using Windows Package Manager.
    #>
    
    Write-DetailedLog "Installing Git via winget" -Level "DEBUG"
    Show-Progress -Activity "Git Installation" -Status "Installing via winget..." -PercentComplete 30
    
    try {
        $wingetArgs = @("install", $script:DependenciesConfig.Git.WingetId, "--accept-package-agreements", "--accept-source-agreements", "--silent")
        
        Write-DetailedLog "Executing: winget $($wingetArgs -join ' ')" -Level "DEBUG"
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        
        return ($process.ExitCode -eq 0)
        
    } catch {
        Write-DetailedLog "Winget Git installation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-GitViaChocolatey {
    <#
    .SYNOPSIS
    Installs Git using Chocolatey.
    #>
    
    Write-DetailedLog "Installing Git via Chocolatey" -Level "DEBUG"
    Show-Progress -Activity "Git Installation" -Status "Installing via Chocolatey..." -PercentComplete 30
    
    try {
        $chocoArgs = @("install", $script:DependenciesConfig.Git.ChocolateyId, "-y", "--no-progress")
        
        Write-DetailedLog "Executing: choco $($chocoArgs -join ' ')" -Level "DEBUG"
        $process = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
        
        return ($process.ExitCode -eq 0)
        
    } catch {
        Write-DetailedLog "Chocolatey Git installation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-GitViaDirect {
    <#
    .SYNOPSIS
    Installs Git by downloading from GitHub releases.
    #>
    
    Write-DetailedLog "Installing Git via direct download" -Level "DEBUG"
    Show-Progress -Activity "Git Installation" -Status "Getting latest version..." -PercentComplete 20
    
    try {
        # Get latest Git version
        $latestVersion = Get-GitLatestVersion
        if (-not $latestVersion) {
            Write-DetailedLog "Could not determine latest Git version" -Level "ERROR"
            return $false
        }
        
        # Download installer
        Show-Progress -Activity "Git Installation" -Status "Downloading installer..." -PercentComplete 30
        $installerPath = Download-GitInstaller -Version $latestVersion
        
        if (-not $installerPath) {
            Write-DetailedLog "Failed to download Git installer" -Level "ERROR"
            return $false
        }
        
        # Run installer
        Show-Progress -Activity "Git Installation" -Status "Running installer..." -PercentComplete 70
        
        $installArgs = $script:DependenciesConfig.Git.InstallArgs
        Write-DetailedLog "Running Git installer: $installerPath $($installArgs -join ' ')" -Level "DEBUG"
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        # Cleanup installer
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        
        return ($process.ExitCode -eq 0)
        
    } catch {
        Write-DetailedLog "Direct Git installation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-Java {
    <#
    .SYNOPSIS
    Installs or updates Microsoft OpenJDK 11.
    
    .PARAMETER Force
    Force reinstallation even if already installed
    
    .PARAMETER Method
    Installation method preference (Auto, Winget, Chocolatey, Direct)
    
    .OUTPUTS
    Returns $true if installation was successful
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [ValidateSet("Auto", "Winget", "Chocolatey", "Direct")]
        [string]$Method = "Auto"
    )
    
    Write-DetailedLog "Installing Microsoft OpenJDK 11" -Level "INFO"
    Show-Progress -Activity "Java Installation" -Status "Checking current installation..." -PercentComplete 10
    
    try {
        # Check current status
        $javaStatus = Get-JavaStatus
        
        if ($javaStatus.IsInstalled -and $javaStatus.IsWorking -and -not $Force -and -not $javaStatus.NeedsUpdate) {
            Write-DetailedLog "Java v$($javaStatus.Version) is already installed and working" -Level "SUCCESS"
            return $true
        }
        
        # Choose installation method
        $installMethod = if ($Method -eq "Auto") { 
            Get-BestPackageManagerMethod 
        } else { 
            $Method 
        }
        
        Write-DetailedLog "Using installation method: $installMethod" -Level "INFO"
        
        # Perform installation
        $installResult = switch ($installMethod) {
            "Winget" { Install-JavaViaWinget }
            "Chocolatey" { Install-JavaViaChocolatey }
            "Direct" { Install-JavaViaDirect }
            default { Install-JavaViaDirect }
        }
        
        if (-not $installResult) {
            Write-DetailedLog "Java installation failed" -Level "ERROR"
            return $false
        }
        
        # Configure Java environment
        Show-Progress -Activity "Java Installation" -Status "Configuring environment..." -PercentComplete 80
        Set-JavaEnvironment
        
        # Verify installation
        Show-Progress -Activity "Java Installation" -Status "Verifying installation..." -PercentComplete 90
        
        # Refresh environment variables
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        $env:JAVA_HOME = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
        
        $verifiedStatus = Get-JavaStatus
        
        if ($verifiedStatus.IsInstalled -and $verifiedStatus.IsWorking) {
            Write-DetailedLog "✅ Java v$($verifiedStatus.Version) installed successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "❌ Java installation verification failed" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Java installation error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Install-JavaViaWinget {
    <#
    .SYNOPSIS
    Installs Java using Windows Package Manager.
    #>
    
    Write-DetailedLog "Installing Java via winget" -Level "DEBUG"
    Show-Progress -Activity "Java Installation" -Status "Installing via winget..." -PercentComplete 30
    
    try {
        $wingetArgs = @("install", $script:DependenciesConfig.Java.WingetId, "--accept-package-agreements", "--accept-source-agreements", "--silent")
        
        Write-DetailedLog "Executing: winget $($wingetArgs -join ' ')" -Level "DEBUG"
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        
        return ($process.ExitCode -eq 0)
        
    } catch {
        Write-DetailedLog "Winget Java installation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-JavaViaChocolatey {
    <#
    .SYNOPSIS
    Installs Java using Chocolatey.
    #>
    
    Write-DetailedLog "Installing Java via Chocolatey" -Level "DEBUG"
    Show-Progress -Activity "Java Installation" -Status "Installing via Chocolatey..." -PercentComplete 30
    
    try {
        $chocoArgs = @("install", $script:DependenciesConfig.Java.ChocolateyId, "-y", "--no-progress")
        
        Write-DetailedLog "Executing: choco $($chocoArgs -join ' ')" -Level "DEBUG"
        $process = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
        
        return ($process.ExitCode -eq 0)
        
    }