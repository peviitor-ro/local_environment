# SelfUpdate.ps1 - Self-update functionality for Peviitor installer
# This module handles automatic updates from GitHub releases

# ============================================================================
# SELF-UPDATE CONFIGURATION
# ============================================================================

# GitHub repository information for updates
$script:UpdateConfig = @{
    GitHubOwner = "peviitor-ro"
    GitHubRepo = "installer"
    GitHubAPI = "https://api.github.com/repos/peviitor-ro/installer"
    AssetName = "Install-Peviitor.ps1"
    UserAgent = "Peviitor-Installer/1.0"
    TimeoutSeconds = 30
    BackupExtension = ".backup"
}

# Current version (will be injected during build)
$script:CurrentVersion = "1.0.0"
$script:BuildDate = "2024-01-01"
$script:CommitHash = "unknown"

# ============================================================================
# VERSION COMPARISON FUNCTIONS
# ============================================================================

function Compare-SemanticVersion {
    <#
    .SYNOPSIS
    Compares two semantic version strings.
    
    .PARAMETER Version1
    First version to compare (e.g., "1.2.3")
    
    .PARAMETER Version2
    Second version to compare (e.g., "1.3.0")
    
    .OUTPUTS
    Returns -1 if Version1 < Version2, 0 if equal, 1 if Version1 > Version2
    
    .EXAMPLE
    Compare-SemanticVersion -Version1 "1.2.3" -Version2 "1.3.0"  # Returns -1
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version1,
        
        [Parameter(Mandatory=$true)]
        [string]$Version2
    )
    
    try {
        # Clean version strings (remove 'v' prefix if present)
        $v1Clean = $Version1.TrimStart('v')
        $v2Clean = $Version2.TrimStart('v')
        
        # Parse version parts
        $v1Parts = $v1Clean -split '\.' | ForEach-Object { [int]$_ }
        $v2Parts = $v2Clean -split '\.' | ForEach-Object { [int]$_ }
        
        # Pad to same length with zeros
        $maxLength = [Math]::Max($v1Parts.Length, $v2Parts.Length)
        while ($v1Parts.Length -lt $maxLength) { $v1Parts += 0 }
        while ($v2Parts.Length -lt $maxLength) { $v2Parts += 0 }
        
        # Compare each part
        for ($i = 0; $i -lt $maxLength; $i++) {
            if ($v1Parts[$i] -lt $v2Parts[$i]) { return -1 }
            if ($v1Parts[$i] -gt $v2Parts[$i]) { return 1 }
        }
        
        return 0  # Versions are equal
        
    } catch {
        Write-DetailedLog "Error comparing versions '$Version1' and '$Version2': $($_.Exception.Message)" -Level "WARN"
        return 0  # Assume equal if comparison fails
    }
}

function Test-UpdateAvailable {
    <#
    .SYNOPSIS
    Checks if a newer version is available on GitHub.
    
    .OUTPUTS
    Returns hashtable with update information
    
    .EXAMPLE
    $updateInfo = Test-UpdateAvailable
    if ($updateInfo.IsAvailable) { ... }
    #>
    
    Write-DetailedLog "Checking for updates from GitHub..." -Level "INFO"
    Show-Progress -Activity "Update Check" -Status "Connecting to GitHub API..." -PercentComplete 10
    
    $result = @{
        IsAvailable = $false
        CurrentVersion = $script:CurrentVersion
        LatestVersion = $null
        DownloadUrl = $null
        ReleaseDate = $null
        ReleaseNotes = $null
        Error = $null
    }
    
    try {
        # Prepare GitHub API request
        $apiUrl = "$($script:UpdateConfig.GitHubAPI)/releases/latest"
        $headers = @{
            'User-Agent' = $script:UpdateConfig.UserAgent
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        Show-Progress -Activity "Update Check" -Status "Fetching latest release info..." -PercentComplete 30
        
        # Make API request with timeout
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec $script:UpdateConfig.TimeoutSeconds -ErrorAction Stop
        
        Show-Progress -Activity "Update Check" -Status "Analyzing release data..." -PercentComplete 60
        
        # Extract version information
        $result.LatestVersion = $response.tag_name.TrimStart('v')
        $result.ReleaseDate = [DateTime]::Parse($response.published_at)
        $result.ReleaseNotes = $response.body
        
        # Find the installer asset
        $installerAsset = $response.assets | Where-Object { $_.name -eq $script:UpdateConfig.AssetName }
        
        if ($installerAsset) {
            $result.DownloadUrl = $installerAsset.browser_download_url
            
            # Compare versions
            $versionComparison = Compare-SemanticVersion -Version1 $script:CurrentVersion -Version2 $result.LatestVersion
            $result.IsAvailable = ($versionComparison -eq -1)  # Current version is older
            
            if ($result.IsAvailable) {
                Write-DetailedLog "Update available: v$($script:CurrentVersion) → v$($result.LatestVersion)" -Level "INFO"
            } else {
                Write-DetailedLog "Already running latest version: v$($script:CurrentVersion)" -Level "INFO"
            }
        } else {
            $result.Error = "Installer asset '$($script:UpdateConfig.AssetName)' not found in latest release"
            Write-DetailedLog $result.Error -Level "WARN"
        }
        
        Show-Progress -Activity "Update Check" -Status "Update check completed" -PercentComplete 100
        
    } catch {
        $result.Error = "Failed to check for updates: $($_.Exception.Message)"
        Write-DetailedLog $result.Error -Level "WARN"
        
        # Check if it's a network connectivity issue
        if ($_.Exception.Message -match "unable to connect|network|timeout|dns") {
            Write-DetailedLog "Network connectivity issue detected. Continuing with current version." -Level "INFO"
        }
    }
    
    Hide-Progress
    return $result
}

# ============================================================================
# UPDATE DOWNLOAD AND INSTALLATION
# ============================================================================

function Invoke-SelfUpdate {
    <#
    .SYNOPSIS
    Downloads and installs the latest version of the installer.
    
    .PARAMETER Force
    Force update even if no newer version is available
    
    .PARAMETER RestartArgs
    Arguments to pass when restarting the updated script
    
    .OUTPUTS
    Returns $true if update was successful, $false otherwise
    
    .EXAMPLE
    Invoke-SelfUpdate -RestartArgs @("-Verbose", "-NoLaunch")
    #>
    param(
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [string[]]$RestartArgs = @()
    )
    
    Write-LogHeader -Title "SELF-UPDATE PROCESS" -Level 2
    
    try {
        # Check for updates first (unless forced)
        if (-not $Force) {
            $updateInfo = Test-UpdateAvailable
            
            if ($updateInfo.Error) {
                Write-DetailedLog "Update check failed: $($updateInfo.Error)" -Level "ERROR"
                return $false
            }
            
            if (-not $updateInfo.IsAvailable) {
                Write-DetailedLog "No update available. Current version v$($script:CurrentVersion) is latest." -Level "INFO"
                return $true
            }
            
            Write-DetailedLog "Proceeding with update to v$($updateInfo.LatestVersion)" -Level "INFO"
        } else {
            Write-DetailedLog "Forced update requested - downloading latest version" -Level "INFO"
            $updateInfo = Test-UpdateAvailable
            if ($updateInfo.Error -or -not $updateInfo.DownloadUrl) {
                Write-DetailedLog "Cannot perform forced update: $($updateInfo.Error)" -Level "ERROR"
                return $false
            }
        }
        
        # Step 1: Backup current script
        Show-StepProgress -StepNumber 1 -TotalSteps 4 -StepName "Backing up current version" -Activity "Self-Update"
        if (-not (Backup-CurrentScript)) {
            Write-DetailedLog "Failed to backup current script" -Level "ERROR"
            return $false
        }
        
        # Step 2: Download new version
        Show-StepProgress -StepNumber 2 -TotalSteps 4 -StepName "Downloading new version" -Activity "Self-Update"
        $downloadedFile = Download-UpdateFile -DownloadUrl $updateInfo.DownloadUrl
        if (-not $downloadedFile) {
            Write-DetailedLog "Failed to download new version" -Level "ERROR"
            return $false
        }
        
        # Step 3: Validate downloaded file
        Show-StepProgress -StepNumber 3 -TotalSteps 4 -StepName "Validating download" -Activity "Self-Update"
        if (-not (Test-DownloadedFile -FilePath $downloadedFile)) {
            Write-DetailedLog "Downloaded file validation failed" -Level "ERROR"
            Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        
        # Step 4: Replace current script and restart
        Show-StepProgress -StepNumber 4 -TotalSteps 4 -StepName "Installing update" -Activity "Self-Update"
        return Install-Update -NewScriptPath $downloadedFile -RestartArgs $RestartArgs
        
    } catch {
        Write-InstallationError -ErrorMessage "Self-update process failed" -Exception $_.Exception
        return $false
    } finally {
        Hide-Progress
    }
}

function Backup-CurrentScript {
    <#
    .SYNOPSIS
    Creates a backup of the current script file.
    
    .OUTPUTS
    Returns $true if backup was successful
    #>
    
    try {
        $currentScript = $PSCommandPath
        $backupPath = "$currentScript$($script:UpdateConfig.BackupExtension)"
        
        Write-DetailedLog "Creating backup: $backupPath" -Level "DEBUG"
        
        # Remove old backup if exists
        if (Test-Path $backupPath) {
            Remove-Item $backupPath -Force
        }
        
        # Create backup
        Copy-Item $currentScript $backupPath -Force
        
        if (Test-Path $backupPath) {
            Write-DetailedLog "Backup created successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Backup file was not created" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Failed to create backup: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Download-UpdateFile {
    <#
    .SYNOPSIS
    Downloads the update file from GitHub.
    
    .PARAMETER DownloadUrl
    URL to download the update from
    
    .OUTPUTS
    Returns path to downloaded file or $null if failed
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl
    )
    
    try {
        $tempPath = [System.IO.Path]::GetTempPath()
        $downloadPath = Join-Path $tempPath "Install-Peviitor-Update.ps1"
        
        Write-DetailedLog "Downloading update from: $DownloadUrl" -Level "INFO"
        Write-DetailedLog "Download path: $downloadPath" -Level "DEBUG"
        
        # Remove existing download if present
        if (Test-Path $downloadPath) {
            Remove-Item $downloadPath -Force
        }
        
        # Prepare web request with progress tracking
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent', $script:UpdateConfig.UserAgent)
        
        # Register progress event
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            Show-Progress -Activity "Self-Update" -Status "Downloading... ($percent%)" -PercentComplete $percent -Id 2 -ParentId 1
        } | Out-Null
        
        # Download file
        $webClient.DownloadFile($DownloadUrl, $downloadPath)
        
        # Cleanup progress tracking
        Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
        $webClient.Dispose()
        Hide-Progress -Id 2
        
        if (Test-Path $downloadPath) {
            $fileSize = (Get-Item $downloadPath).Length
            Write-DetailedLog "Download completed successfully ($fileSize bytes)" -Level "SUCCESS"
            return $downloadPath
        } else {
            Write-DetailedLog "Downloaded file not found at expected path" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-DetailedLog "Download failed: $($_.Exception.Message)" -Level "ERROR"
        
        # Cleanup on failure
        if ($webClient) {
            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event -ErrorAction SilentlyContinue
            $webClient.Dispose()
        }
        
        return $null
    }
}

function Test-DownloadedFile {
    <#
    .SYNOPSIS
    Validates the downloaded update file.
    
    .PARAMETER FilePath
    Path to the downloaded file
    
    .OUTPUTS
    Returns $true if file is valid
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            Write-DetailedLog "Downloaded file does not exist: $FilePath" -Level "ERROR"
            return $false
        }
        
        $fileInfo = Get-Item $FilePath
        
        # Check file size (should be at least 10KB for a valid PowerShell script)
        if ($fileInfo.Length -lt 10240) {
            Write-DetailedLog "Downloaded file is too small ($($fileInfo.Length) bytes) - likely corrupted" -Level "ERROR"
            return $false
        }
        
        # Check if file is a valid PowerShell script
        $content = Get-Content $FilePath -TotalCount 10 -ErrorAction Stop
        $hasShebang = $content[0] -match '^#.*powershell'
        $hasPowerShellContent = ($content -join "`n") -match '(param\s*\(|function\s+\w+|Write-Host|Write-Output)'
        
        if (-not ($hasShebang -or $hasPowerShellContent)) {
            Write-DetailedLog "Downloaded file does not appear to be a PowerShell script" -Level "ERROR"
            return $false
        }
        
        Write-DetailedLog "Downloaded file validation passed ($($fileInfo.Length) bytes)" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "File validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-Update {
    <#
    .SYNOPSIS
    Replaces current script with update and restarts.
    
    .PARAMETER NewScriptPath
    Path to the new script file
    
    .PARAMETER RestartArgs
    Arguments for restarting the script
    
    .OUTPUTS
    Returns $true if installation started successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$NewScriptPath,
        
        [Parameter()]
        [string[]]$RestartArgs = @()
    )
    
    try {
        $currentScript = $PSCommandPath
        
        Write-DetailedLog "Installing update..." -Level "INFO"
        Write-DetailedLog "Current script: $currentScript" -Level "DEBUG"
        Write-DetailedLog "New script: $NewScriptPath" -Level "DEBUG"
        
        # Prepare restart command
        $restartCommand = "powershell.exe"
        $restartArguments = @("-ExecutionPolicy", "Bypass", "-File", "`"$currentScript`"") + $RestartArgs
        
        Write-DetailedLog "Update will restart with: $restartCommand $($restartArguments -join ' ')" -Level "DEBUG"
        
        # Create update script that will replace the current script and restart
        $updateScriptContent = @"
# Auto-generated update script
Start-Sleep -Seconds 2  # Wait for current process to exit

try {
    # Replace the current script
    Copy-Item -Path "$NewScriptPath" -Destination "$currentScript" -Force
    Remove-Item -Path "$NewScriptPath" -Force -ErrorAction SilentlyContinue
    
    # Start the updated script
    Start-Process -FilePath "$restartCommand" -ArgumentList $($restartArguments | ForEach-Object { "`"$_`"" } | Join-String -Separator ', ') -WindowStyle Normal
} catch {
    Write-Host "Update installation failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    pause
}

# Cleanup this update script
Remove-Item -Path "`$PSCommandPath" -Force -ErrorAction SilentlyContinue
"@
        
        $updateScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
        Set-Content -Path $updateScriptPath -Value $updateScriptContent -Encoding UTF8
        
        Write-DetailedLog "Update installation script created: $updateScriptPath" -Level "DEBUG"
        Write-DetailedLog "Starting update process..." -Level "SUCCESS"
        
        # Start the update script and exit current process
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$updateScriptPath`"") -WindowStyle Hidden
        
        # Give user feedback before exit
        Write-DetailedLog "Update process started. Script will restart automatically." -Level "SUCCESS"
        Start-Sleep -Seconds 2
        
        # Exit current process to allow update
        exit 0
        
    } catch {
        Write-DetailedLog "Failed to install update: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-CurrentVersion {
    <#
    .SYNOPSIS
    Gets the current version of the installer.
    
    .OUTPUTS
    Returns version information hashtable
    #>
    
    return @{
        Version = $script:CurrentVersion
        BuildDate = $script:BuildDate
        CommitHash = $script:CommitHash
    }
}

function Set-CurrentVersion {
    <#
    .SYNOPSIS
    Sets the current version (used during build process).
    
    .PARAMETER Version
    Version string
    
    .PARAMETER BuildDate
    Build date
    
    .PARAMETER CommitHash
    Git commit hash
    #>
    param(
        [string]$Version,
        [string]$BuildDate,
        [string]$CommitHash
    )
    
    if ($Version) { $script:CurrentVersion = $Version }
    if ($BuildDate) { $script:BuildDate = $BuildDate }
    if ($CommitHash) { $script:CommitHash = $CommitHash }
    
    Write-DetailedLog "Version info updated: v$($script:CurrentVersion) ($($script:BuildDate))" -Level "DEBUG"
}

function Show-VersionInfo {
    <#
    .SYNOPSIS
    Displays current version information.
    #>
    
    Write-LogHeader -Title "VERSION INFORMATION" -Level 3
    Write-DetailedLog "Current Version: v$($script:CurrentVersion)" -Level "INFO"
    Write-DetailedLog "Build Date: $($script:BuildDate)" -Level "INFO"
    Write-DetailedLog "Commit Hash: $($script:CommitHash)" -Level "INFO"
    Write-DetailedLog "GitHub Repository: $($script:UpdateConfig.GitHubOwner)/$($script:UpdateConfig.GitHubRepo)" -Level "INFO"
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Self-update module loaded (v$($script:CurrentVersion))" -Level "DEBUG"