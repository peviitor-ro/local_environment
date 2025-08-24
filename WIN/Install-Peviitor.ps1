# Install-Peviitor.ps1 - Peviitor Local Environment Installer
# Main orchestrator script that coordinates all installation modules
# Version: 1.0.0 (will be replaced during build)
# Build Date: 2024-01-01 (will be replaced during build)
# Commit Hash: unknown (will be replaced during build)

<#
.SYNOPSIS
    Installs and configures the complete Peviitor local development environment.

.DESCRIPTION
    This script installs and configures a complete local development environment for Peviitor,
    including Docker Desktop, Apache Solr, web frontend, API, and all dependencies.
    
    The installation includes:
    - Docker Desktop and containerization
    - Apache Solr search engine with configured cores
    - Web frontend with job search interface
    - REST API with Swagger documentation
    - JMeter for data migration
    - Git and Java dependencies
    
    All services are configured to work together and accessible via web browser.

.PARAMETER Uninstall
    Removes the complete Peviitor installation including containers, networks, and files.

.PARAMETER Reinstall
    Performs a clean reinstallation by removing existing installation first.

.PARAMETER CheckUpdates
    Checks for newer version of the installer and updates if available.

.PARAMETER Force
    Forces installation/reinstallation without confirmation prompts.

.PARAMETER NoLaunch
    Skips launching browser at the end of installation.

.PARAMETER Verbose
    Enables verbose logging output.

.PARAMETER Verbose
    Enables verbose logging output (built-in PowerShell parameter).

.PARAMETER LogLevel
    Sets the logging level (INFO, DEBUG). Default is INFO.

.EXAMPLE
    .\Install-Peviitor.ps1
    Performs a standard installation with all default settings.

.EXAMPLE
    .\Install-Peviitor.ps1 -Reinstall -Force
    Forces a complete reinstallation without prompts.

.EXAMPLE
    .\Install-Peviitor.ps1 -Uninstall
    Removes the complete Peviitor installation.

.EXAMPLE
    .\Install-Peviitor.ps1 -CheckUpdates
    Checks for installer updates and updates if available.

.NOTES
    - Requires Windows 10 build 19041+ or Windows 11
    - Requires Administrator privileges
    - Requires 8GB+ RAM and 20GB+ free disk space
    - Internet connection required for downloads
    
    For support and documentation, visit:
    https://github.com/peviitor-ro/installer

.LINK
    https://github.com/peviitor-ro/installer
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Remove the complete Peviitor installation")]
    [switch]$Uninstall,
    
    [Parameter(HelpMessage = "Perform a clean reinstallation")]
    [switch]$Reinstall,
    
    [Parameter(HelpMessage = "Check for installer updates")]
    [switch]$CheckUpdates,
    
    [Parameter(HelpMessage = "Force installation without confirmation prompts")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "Skip launching browser at the end")]
    [switch]$NoLaunch,
    
    [Parameter(HelpMessage = "Set logging level (INFO, DEBUG)")]
    [ValidateSet("INFO", "DEBUG")]
    [string]$LogLevel = "INFO"
)

# ============================================================================
# INSTALLER METADATA AND CONFIGURATION
# ============================================================================

# Installer metadata (will be replaced during build)
$script:InstallerMetadata = @{
    Name = "Peviitor Local Environment Installer"
    Version = "1.0.0"
    BuildDate = "2024-01-01"
    CommitHash = "unknown"
    Repository = "https://github.com/peviitor-ro/installer"
    SupportURL = "https://github.com/peviitor-ro/installer/issues"
    Author = "Peviitor.ro Team"
}

# Global installer state
$script:InstallerState = @{
    StartTime = Get-Date
    LogFile = ".\peviitor-installer.log"
    TempCredentials = @{}
    ModulesLoaded = @()
    InstallationSteps = @()
    RollbackActions = @()
}

# ============================================================================
# CORE INSTALLER FUNCTIONS
# ============================================================================

function Initialize-Installer {
    <#
    .SYNOPSIS
    Initializes the installer environment and loads all required modules.
    
    .OUTPUTS
    Returns $true if initialization was successful
    #>
    
    try {
        # Set console title
        $Host.UI.RawUI.WindowTitle = "Peviitor Installer v$($script:InstallerMetadata.Version)"
        
        # Initialize global variables
        $Global:LogLevel = $LogLevel
        $script:InstallerState.LogFile = ".\peviitor-installer-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        
        # Display installer header
        Show-InstallerHeader
        
        # Initialize logging (bootstrap logging before modules)
        Initialize-BootstrapLogging
        
        Write-Host "Initializing Peviitor Installer..." -ForegroundColor Cyan
        Write-Host "Loading modules and validating system..." -ForegroundColor Gray
        
        # Load all modules in dependency order
        $moduleLoadResult = Import-AllModules
        if (-not $moduleLoadResult) {
            Write-Host "Failed to load required modules" -ForegroundColor Red
            return $false
        }
        
        # Validate configuration after modules are loaded
        if (-not (Test-PeviitorConfig)) {
            Write-DetailedLog "Configuration validation failed after module load" -Level "ERROR"
            return $false
        }
        
        Write-DetailedLog "Installer initialized successfully" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-Host "Installer initialization failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-InstallerHeader {
    <#
    .SYNOPSIS
    Displays the installer welcome header.
    #>
    
    $header = @"

================================================================================
                    PEVIITOR LOCAL ENVIRONMENT INSTALLER                    
================================================================================

                          Version: $($script:InstallerMetadata.Version)
                         Build Date: $($script:InstallerMetadata.BuildDate)
                        Repository: $($script:InstallerMetadata.Repository)

"@
    
    Write-Host $header -ForegroundColor Magenta
    Write-Host ""
}

function Initialize-BootstrapLogging {
    <#
    .SYNOPSIS
    Initializes basic logging before modules are loaded.
    #>
    
    try {
        # Create log file
        $logHeader = @"
================================================================================
Peviitor Installer Log
Version: $($script:InstallerMetadata.Version)
Start Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Parameters: $($PSBoundParameters | ConvertTo-Json -Compress)
================================================================================

"@
        
        $logHeader | Set-Content -Path $script:InstallerState.LogFile -Encoding UTF8
        
        # Basic logging function for bootstrap
        $Global:WriteLog = {
            param([string]$Message, [string]$Level = "INFO")
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
            $logEntry = "[$timestamp] [$Level] $Message"
            Add-Content -Path $script:InstallerState.LogFile -Value $logEntry -ErrorAction SilentlyContinue
        }
        
        & $Global:WriteLog "Bootstrap logging initialized"
        
    } catch {
        Write-Warning "Could not initialize logging: $($_.Exception.Message)"
    }
}

# ============================================================================
# MODULE LOADING SYSTEM
# ============================================================================

function Import-AllModules {
    <#
    .SYNOPSIS
    Imports all required modules in the correct dependency order.
    
    .OUTPUTS
    Returns $true if all modules were loaded successfully
    #>
    
    # Module load order (respecting dependencies)
    $moduleOrder = @(
        "Config",           # Must be first - provides configuration for all others
        "Logger",           # Must be early - provides logging for all others  
        "Elevation",        # Early - might restart process
        "SelfUpdate",       # Early - might update and restart
        "Prerequisites",    # Validation before installation
        "DockerDesktop",    # Docker must be ready before containers
        "Dependencies",     # Git, Java, JMeter needed for later steps
        "Environment",      # Environment setup before deployment
        "Frontend",         # Web frontend deployment
        "Solr",            # Search engine deployment
        "JMeterMigration", # Data migration
        "BrowserLauncher"  # Final step - browser launch
    )
    
    Write-Host "Loading installer modules..." -ForegroundColor Cyan
    
    $loadedCount = 0
    $totalModules = $moduleOrder.Count
    
    foreach ($moduleName in $moduleOrder) {
        try {
            $progressPercent = ($loadedCount / $totalModules) * 100
            Write-Progress -Activity "Loading Modules" -Status "Loading $moduleName..." -PercentComplete $progressPercent
            
            $moduleResult = Import-InstallerModule -ModuleName $moduleName
            
            if ($moduleResult) {
                $script:InstallerState.ModulesLoaded += $moduleName
                $loadedCount++
                Write-Host "  [OK] $moduleName" -ForegroundColor Green
            } else {
                Write-Host "  [FAILED] $moduleName" -ForegroundColor Red
                Write-Progress -Activity "Loading Modules" -Completed
                return $false
            }
            
        } catch {
            Write-Host "  [ERROR] $moduleName - $($_.Exception.Message)" -ForegroundColor Red
            Write-Progress -Activity "Loading Modules" -Completed
            return $false
        }
    }
    
    Write-Progress -Activity "Loading Modules" -Completed
    Write-Host "All modules loaded successfully ($loadedCount/$totalModules)" -ForegroundColor Green
    
    return $true
}

function Import-InstallerModule {
    <#
    .SYNOPSIS
    Imports a single installer module with error handling.
    
    .PARAMETER ModuleName
    Name of the module to import
    
    .OUTPUTS
    Returns $true if module was imported successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )
    
    try {
        # In the final combined script, modules will be embedded here
        # For now, this is a placeholder that would be replaced during build
        
        # MODULE CONTENT WILL BE INSERTED HERE DURING BUILD PROCESS
        # Each module's content will be inserted in place of this comment
        
        Write-Verbose "Module $ModuleName loaded successfully"
        & $Global:WriteLog "Module $ModuleName loaded successfully"
        
        return $true
        
    } catch {
        Write-Error "Failed to load module $ModuleName : $($_.Exception.Message)"
        & $Global:WriteLog "Failed to load module $ModuleName : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# MAIN INSTALLATION ORCHESTRATION
# ============================================================================

function Start-PeviitorInstallation {
    <#
    .SYNOPSIS
    Orchestrates the complete Peviitor installation process.
    
    .OUTPUTS
    Returns $true if installation completed successfully
    #>
    
    try {
        Write-LogHeader -Title "PEVIITOR INSTALLATION" -Level 1
        
        # Pre-installation steps
        $preInstallSteps = @(
            @{ Name = "System Requirements"; Function = { Test-SystemRequirements } }
            @{ Name = "Administrator Privileges"; Function = { Assert-Administrator -AllowElevation -ShowPrompt } }
            @{ Name = "Self-Update Check"; Function = { if ($CheckUpdates) { Invoke-SelfUpdate } else { $true } } }
        )
        
        # Main installation steps
        $installSteps = @(
            @{ Name = "Environment Preparation"; Function = { Initialize-PeviitorEnvironment -Force:$Reinstall } }
            @{ Name = "Docker Desktop"; Function = { Install-DockerDesktop -Force:$Force } }
            @{ Name = "Software Dependencies"; Function = { Install-AllDependencies -Force:$Force } }
            @{ Name = "Solr Credentials"; Function = { Get-SolrCredentials } }
            @{ Name = "Apache Solr"; Function = { Deploy-SolrSearch -SolrUser $script:InstallerState.TempCredentials.SolrUser -SolrPassword $script:InstallerState.TempCredentials.SolrPassword -Force:$Force } }
            @{ Name = "Web Frontend"; Function = { Deploy-PeviitorFrontend -SolrUser $script:InstallerState.TempCredentials.SolrUser -SolrPassword $script:InstallerState.TempCredentials.SolrPassword -Force:$Force } }
            @{ Name = "Data Migration"; Function = { Start-DataMigration -SolrUser $script:InstallerState.TempCredentials.SolrUser -SolrPassword $script:InstallerState.TempCredentials.SolrPassword -Force:$Force } }
            @{ Name = "Browser Launch"; Function = { if (-not $NoLaunch) { Start-BrowserLaunch -WaitForServices } else { Show-AccessInformation } } }
        )
        
        # Combine all steps
        $allSteps = $preInstallSteps + $installSteps
        $script:InstallerState.InstallationSteps = $allSteps
        
        # Execute installation steps
        $stepNumber = 1
        $totalSteps = $allSteps.Count
        
        foreach ($step in $allSteps) {
            Write-LogHeader -Title "STEP $stepNumber/$totalSteps - $($step.Name)" -Level 3
            
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Peviitor Installation"
            
            $stepStartTime = Get-Date
            Write-DetailedLog "Starting step: $($step.Name)" -Level "INFO"
            
            try {
                $result = & $step.Function
                
                $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
                $roundedDuration = [math]::Round($stepDuration)
                
                if ($result -and (($result -is [bool] -and $result) -or ($result -is [hashtable] -and $result.Success) -or ($result -is [hashtable] -and $result.IsValid))) {
                    Write-DetailedLog "$($step.Name): SUCCESS ($($roundedDuration)s)" -Level "SUCCESS"
                } else {
                    Write-DetailedLog "$($step.Name): FAILED ($($roundedDuration)s)" -Level "ERROR"
                    
                    # Handle step failure
                    $shouldContinue = Handle-StepFailure -StepName $step.Name -StepNumber $stepNumber -Result $result
                    
                    if (-not $shouldContinue) {
                        return $false
                    }
                }
                
            } catch {
                $stepDuration = ((Get-Date) - $stepStartTime).TotalSeconds
                $roundedDuration = [math]::Round($stepDuration)
                Write-DetailedLog "$($step.Name): EXCEPTION ($($roundedDuration)s)" -Level "ERROR"
                Write-DetailedLog "Exception: $($_.Exception.Message)" -Level "ERROR"
                
                $shouldContinue = Handle-StepFailure -StepName $step.Name -StepNumber $stepNumber -Exception $_.Exception
                
                if (-not $shouldContinue) {
                    return $false
                }
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        
        # Installation completed successfully
        $totalDuration = ((Get-Date) - $script:InstallerState.StartTime)
        Write-InstallationComplete
        Write-DetailedLog "Total installation time: $($totalDuration.ToString('mm\:ss'))" -Level "SUCCESS"
        
        return $true
        
    } catch {
        Write-InstallationError -ErrorMessage "Installation process failed" -Exception $_.Exception
        return $false
    }
}

function Handle-StepFailure {
    <#
    .SYNOPSIS
    Handles installation step failures and determines whether to continue.
    
    .PARAMETER StepName
    Name of the failed step
    
    .PARAMETER StepNumber
    Step number that failed
    
    .PARAMETER Result
    Result object from the failed step
    
    .PARAMETER Exception
    Exception object if step threw an exception
    
    .OUTPUTS
    Returns $true if installation should continue, $false to abort
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$StepName,
        
        [Parameter(Mandatory=$true)]
        [int]$StepNumber,
        
        [Parameter()]
        $Result = $null,
        
        [Parameter()]
        [System.Exception]$Exception = $null
    )
    
    Write-DetailedLog "Handling failure for step: $StepName" -Level "ERROR"
    
    # Determine if failure is critical
    $criticalSteps = @("System Requirements", "Administrator Privileges", "Environment Preparation", "Docker Desktop")
    $isCritical = $StepName -in $criticalSteps
    
    if ($isCritical) {
        Write-DetailedLog "Critical step failed: $StepName" -Level "ERROR"
        Write-DetailedLog "Installation cannot continue" -Level "ERROR"
        
        # Trigger rollback
        Start-InstallationRollback -Reason "Critical step failure: $StepName"
        
        return $false
    } else {
        # Non-critical step failed
        Write-DetailedLog "Non-critical step failed: $StepName" -Level "WARN"
        
        if ($Force) {
            Write-DetailedLog "Continuing installation due to -Force parameter" -Level "WARN"
            return $true
        } else {
            # Ask user if they want to continue
            $userChoice = Get-UserChoice -Message "Step '$StepName' failed. Continue installation?" -DefaultChoice "No"
            
            if ($userChoice -eq "Yes") {
                Write-DetailedLog "User chose to continue installation" -Level "INFO"
                return $true
            } else {
                Write-DetailedLog "User chose to abort installation" -Level "INFO"
                Start-InstallationRollback -Reason "User aborted after step failure: $StepName"
                return $false
            }
        }
    }
}

# ============================================================================
# CREDENTIAL MANAGEMENT
# ============================================================================

function Get-SolrCredentials {
    <#
    .SYNOPSIS
    Collects Solr credentials from the user with validation.
    
    .OUTPUTS
    Returns $true if credentials were collected successfully
    #>
    
    Write-DetailedLog "Collecting Solr credentials" -Level "INFO"
    
    try {
        # Get username
        do {
            $solrUser = Read-Host "Enter Solr username (admin)"
            if ([string]::IsNullOrWhiteSpace($solrUser)) {
                $solrUser = "admin"
            }
        } while ([string]::IsNullOrWhiteSpace($solrUser))
        
        # Get password with validation
        do {
            $solrPassword = Read-Host "Enter Solr password" -AsSecureString
            $solrPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($solrPassword))
            
            if ([string]::IsNullOrWhiteSpace($solrPasswordPlain)) {
                Write-Host "Password cannot be empty. Please try again." -ForegroundColor Yellow
                continue
            }
            
            # Validate password strength
            $passwordValid = Test-PasswordStrength -Password $solrPasswordPlain
            
            if (-not $passwordValid.IsValid) {
                Write-Host "Password requirements not met:" -ForegroundColor Yellow
                foreach ($issue in $passwordValid.Issues) {
                    Write-Host "  - $issue" -ForegroundColor Yellow
                }
                Write-Host "Please try again with a stronger password." -ForegroundColor Yellow
                continue
            }
            
            break
            
        } while ($true)
        
        # Store credentials securely
        $script:InstallerState.TempCredentials = @{
            SolrUser = $solrUser
            SolrPassword = $solrPasswordPlain
        }
        
        Write-DetailedLog "Solr credentials collected successfully" -Level "SUCCESS"
        Write-DetailedLog "Username: $solrUser" -Level "DEBUG"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error collecting Solr credentials: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-PasswordStrength {
    <#
    .SYNOPSIS
    Tests password strength against security requirements.
    
    .PARAMETER Password
    Password to test
    
    .OUTPUTS
    Returns hashtable with validation results
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Password
    )
    
    $result = @{
        IsValid = $true
        Issues = @()
        Score = 0
    }
    
    # Length check
    if ($Password.Length -lt 8) {
        $result.IsValid = $false
        $result.Issues += "Password must be at least 8 characters long"
    } else {
        $result.Score += 1
    }
    
    # Complexity checks
    if ($Password -cnotmatch '[a-z]') {
        $result.Issues += "Password should contain at least one lowercase letter"
    } else {
        $result.Score += 1
    }
    
    if ($Password -cnotmatch '[A-Z]') {
        $result.Issues += "Password should contain at least one uppercase letter"  
    } else {
        $result.Score += 1
    }
    
    if ($Password -notmatch '\d') {
        $result.Issues += "Password should contain at least one digit"
    } else {
        $result.Score += 1
    }
    
    if ($Password -notmatch '[\W_]') {
        $result.Issues += "Password should contain at least one special character"
    } else {
        $result.Score += 1
    }
    
    # For Solr, we require at least 8 characters (basic requirement)
    # Other requirements are recommendations
    $result.IsValid = ($Password.Length -ge 8)
    
    return $result
}

# ============================================================================
# UNINSTALLATION PROCESS
# ============================================================================

function Start-PeviitorUninstall {
    <#
    .SYNOPSIS
    Performs complete uninstallation of Peviitor environment.
    
    .OUTPUTS
    Returns $true if uninstallation completed successfully
    #>
    
    Write-LogHeader -Title "PEVIITOR UNINSTALLATION" -Level 1
    
    try {
        # Show warning and get confirmation
        if (-not $Force) {
            Write-Host ""
            Write-Host "WARNING: This will remove the complete Peviitor installation!" -ForegroundColor Yellow
            Write-Host "   - All containers will be stopped and removed" -ForegroundColor Yellow
            Write-Host "   - All data will be deleted" -ForegroundColor Yellow  
            Write-Host "   - Docker networks will be removed" -ForegroundColor Yellow
            Write-Host "   - Application files will be deleted" -ForegroundColor Yellow
            Write-Host ""
            
            $confirmation = Get-UserChoice -Message "Are you sure you want to continue?" -DefaultChoice "No"
            
            if ($confirmation -ne "Yes") {
                Write-Host "Uninstallation cancelled by user." -ForegroundColor Gray
                return $true
            }
        }
        
        Write-DetailedLog "Starting Peviitor uninstallation" -Level "INFO"
        
        # Uninstallation steps
        $uninstallSteps = @(
            @{ Name = "Stop Containers"; Function = { Stop-PeviitorContainers -Force } }
            @{ Name = "Remove Containers"; Function = { Remove-PeviitorContainers } }
            @{ Name = "Remove Networks"; Function = { Remove-PeviitorNetworks } }
            @{ Name = "Remove Directories"; Function = { Remove-PeviitorDirectories } }
            @{ Name = "Clean Temporary Files"; Function = { Remove-TempFiles } }
        )
        
        $stepNumber = 1
        $totalSteps = $uninstallSteps.Count
        
        foreach ($step in $uninstallSteps) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Uninstallation"
            
            try {
                $result = & $step.Function
                
                if ($result) {
                    Write-DetailedLog "$($step.Name): SUCCESS" -Level "SUCCESS"
                } else {
                    Write-DetailedLog "$($step.Name): PARTIAL" -Level "WARN"
                }
                
            } catch {
                Write-DetailedLog "$($step.Name): ERROR - $($_.Exception.Message)" -Level "ERROR"
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        
        Write-LogHeader -Title "UNINSTALLATION COMPLETE" -Level 1
        Write-DetailedLog "Peviitor has been uninstalled successfully" -Level "SUCCESS"
        Write-DetailedLog "Thank you for using Peviitor!" -Level "INFO"
        
        return $true
        
    } catch {
        Write-InstallationError -ErrorMessage "Uninstallation failed" -Exception $_.Exception
        return $false
    }
}

# ============================================================================
# ROLLBACK AND RECOVERY
# ============================================================================

function Start-InstallationRollback {
    <#
    .SYNOPSIS
    Performs rollback of partial installation.
    
    .PARAMETER Reason
    Reason for the rollback
    
    .OUTPUTS
    Returns $true if rollback completed successfully
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Reason
    )
    
    Write-LogHeader -Title "INSTALLATION ROLLBACK" -Level 1
    Write-DetailedLog "Performing installation rollback" -Level "WARN"
    Write-DetailedLog "Reason: $Reason" -Level "WARN"
    
    try {
        # Execute rollback actions in reverse order
        if ($script:InstallerState.RollbackActions.Count -gt 0) {
            Write-DetailedLog "Executing $($script:InstallerState.RollbackActions.Count) rollback actions" -Level "INFO"
            
            $rollbackActions = [array]$script:InstallerState.RollbackActions
            [array]::Reverse($rollbackActions)
            
            foreach ($action in $rollbackActions) {
                try {
                    Write-DetailedLog "Rollback action: $action" -Level "DEBUG"
                    & $action
                } catch {
                    Write-DetailedLog "Rollback action failed: $($_.Exception.Message)" -Level "WARN"
                }
            }
        }
        
        # Perform comprehensive cleanup
        Write-DetailedLog "Performing comprehensive cleanup" -Level "INFO"
        
        # Use environment module rollback
        Invoke-EnvironmentRollback -Reason $Reason | Out-Null
        
        Write-DetailedLog "Installation rollback completed" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Rollback process failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-UserChoice {
    <#
    .SYNOPSIS
    Gets a Yes/No choice from the user.
    
    .PARAMETER Message
    Message to display
    
    .PARAMETER DefaultChoice
    Default choice (Yes/No)
    
    .OUTPUTS
    Returns "Yes" or "No"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Yes", "No")]
        [string]$DefaultChoice = "No"
    )
    
    if ($Force) {
        return "Yes"
    }
    
    $choices = if ($DefaultChoice -eq "Yes") { "[Y/n]" } else { "[y/N]" }
    
    do {
        $response = Read-Host "$Message $choices"
        
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultChoice
        }
        
        switch ($response.ToLower()) {
            "y" { return "Yes" }
            "yes" { return "Yes" }
            "n" { return "No" }
            "no" { return "No" }
            default {
                Write-Host "Please enter 'y' for Yes or 'n' for No." -ForegroundColor Yellow
            }
        }
    } while ($true)
}

function Show-InstallationSummary {
    <#
    .SYNOPSIS
    Shows a summary of what will be installed.
    #>
    
    Write-LogHeader -Title "INSTALLATION SUMMARY" -Level 2
    
    Write-Host "The following components will be installed:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   * Docker Desktop - Container platform" -ForegroundColor White
    Write-Host "   * Git - Version control system" -ForegroundColor White
    Write-Host "   * Java (OpenJDK 11) - Runtime environment" -ForegroundColor White
    Write-Host "   * Apache JMeter - Load testing tool" -ForegroundColor White
    Write-Host "   * Apache Solr - Search engine" -ForegroundColor White
    Write-Host "   * Peviitor Frontend - Job search interface" -ForegroundColor White
    Write-Host "   * Peviitor API - REST API endpoints" -ForegroundColor White
    Write-Host "   * Swagger UI - API documentation" -ForegroundColor White
    Write-Host ""
    Write-Host "Access URLs after installation:" -ForegroundColor Cyan
    Write-Host "   - Main UI: http://localhost:8081/" -ForegroundColor Green
    Write-Host "   - Solr Admin: http://localhost:8983/solr/" -ForegroundColor Green  
    Write-Host "   - API Docs: http://localhost:8081/swagger-ui/" -ForegroundColor Green
    Write-Host ""
    Write-Host "System Requirements:" -ForegroundColor Cyan
    Write-Host "   - Windows 10 build 19041+ or Windows 11" -ForegroundColor Gray
    Write-Host "   - 8GB+ RAM and 20GB+ free disk space" -ForegroundColor Gray
    Write-Host "   - Administrator privileges" -ForegroundColor Gray
    Write-Host "   - Internet connection" -ForegroundColor Gray
    Write-Host ""
}

function Test-InstallationHealth {
    <#
    .SYNOPSIS
    Performs comprehensive health check of the installation.
    
    .OUTPUTS
    Returns hashtable with health status
    #>
    
    Write-DetailedLog "Performing installation health check" -Level "INFO"
    
    $health = @{
        IsHealthy = $false
        ComponentStatus = @{}
        Issues = @()
        Recommendations = @()
    }
    
    try {
        # Test each component
        $components = @{
            "Docker" = { Test-DockerFunctionality }
            "Environment" = { Test-EnvironmentReadiness }  
            "Frontend" = { (Test-FrontendDeployment).IsWorking }
            "Solr" = { (Test-SolrDeployment).IsWorking }
            "Migration" = { (Test-MigrationStatus).IsComplete }
            "Browser" = { Test-ServiceHealth }
        }
        
        $healthyCount = 0
        $totalComponents = $components.Count
        
        foreach ($componentName in $components.Keys) {
            try {
                $testFunction = $components[$componentName]
                $result = & $testFunction
                
                $isHealthy = if ($result -is [bool]) { 
                    $result 
                } elseif ($result -is [hashtable]) { 
                    $result.IsHealthy -or $result.Success -or $result.IsWorking
                } else { 
                    $false 
                }
                
                $health.ComponentStatus[$componentName] = $isHealthy
                
                if ($isHealthy) {
                    $healthyCount++
                } else {
                    $health.Issues += "Component '$componentName' is not healthy"
                }
                
            } catch {
                $health.ComponentStatus[$componentName] = $false
                $health.Issues += "Component '$componentName' health check failed: $($_.Exception.Message)"
            }
        }
        
        # Overall health assessment
        $health.IsHealthy = ($healthyCount -eq $totalComponents)
        
        # Generate recommendations
        if ($health.IsHealthy) {
            $health.Recommendations += "All components are healthy - installation successful!"
        } else {
            $health.Recommendations += "Some components need attention - check logs for details"
            
            if (-not $health.ComponentStatus["Docker"]) {
                $health.Recommendations += "Restart Docker Desktop and try again"
            }
            
            if (-not $health.ComponentStatus["Frontend"]) {
                $health.Recommendations += "Check if ports 8081 and 8983 are available"
            }
        }
        
        Write-DetailedLog "Health check completed: $healthyCount/$totalComponents components healthy" -Level "INFO"
        
    } catch {
        Write-DetailedLog "Health check failed: $($_.Exception.Message)" -Level "ERROR"
        $health.Issues += "Health check process failed"
    }
    
    return $health
}

function Show-FinalReport {
    <#
    .SYNOPSIS
    Shows comprehensive final installation report.
    #>
    
    $installationEnd = Get-Date
    $totalDuration = $installationEnd - $script:InstallerState.StartTime
    
    Write-LogHeader -Title "INSTALLATION REPORT" -Level 1
    
    # Installation summary
    Write-Host "PEVIITOR INSTALLATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host ""
    
    # Timing information
    Write-Host "Installation completed in: " -NoNewline -ForegroundColor Cyan
    Write-Host $totalDuration.ToString("mm\:ss") -ForegroundColor White
    Write-Host "Completed at: " -NoNewline -ForegroundColor Cyan
    Write-Host $installationEnd.ToString("yyyy-MM-dd HH:mm:ss") -ForegroundColor White
    Write-Host ""
    
    # System information
    Write-Host "System Information:" -ForegroundColor Cyan
    Write-Host "   - Installer Version: v$($script:InstallerMetadata.Version)" -ForegroundColor Gray
    Write-Host "   - Windows Version: $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
    Write-Host "   - PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "   - Installation Path: $((Get-PeviitorConfigValue -Path 'Paths.Base'))" -ForegroundColor Gray
    Write-Host ""
    
    # Access information
    Write-Host "Access Your Installation:" -ForegroundColor Cyan
    Write-Host "   Main Interface:  http://localhost:8081/" -ForegroundColor Green
    Write-Host "   Solr Admin:     http://localhost:8983/solr/" -ForegroundColor Green
    Write-Host "   API Docs:       http://localhost:8081/swagger-ui/" -ForegroundColor Green
    Write-Host ""
    
    # Health check
    $health = Test-InstallationHealth
    $healthStatus = if ($health.IsHealthy) { "ALL SYSTEMS HEALTHY" } else { "NEEDS ATTENTION" }
    
    Write-Host "System Health: " -NoNewline -ForegroundColor $(if ($health.IsHealthy) { "Green" } else { "Yellow" })
    Write-Host $healthStatus -ForegroundColor $(if ($health.IsHealthy) { "Green" } else { "Yellow" })
    
    if (-not $health.IsHealthy) {
        Write-Host "   Issues found:" -ForegroundColor Yellow
        foreach ($issue in $health.Issues) {
            Write-Host "   - $issue" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Next steps
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Explore the job search interface" -ForegroundColor White
    Write-Host "   2. Review the API documentation" -ForegroundColor White
    Write-Host "   3. Configure advanced search settings in Solr admin" -ForegroundColor White
    Write-Host ""
    
    # Support information
    Write-Host "Need Help?" -ForegroundColor Cyan
    Write-Host "   - Documentation: $($script:InstallerMetadata.Repository)" -ForegroundColor Blue
    Write-Host "   - Issues: $($script:InstallerMetadata.SupportURL)" -ForegroundColor Blue
    Write-Host "   - Logs: $($script:InstallerState.LogFile)" -ForegroundColor Blue
    Write-Host ""
    
    Write-Host "Thank you for using Peviitor!" -ForegroundColor Magenta
    Write-Host ""
}

# ============================================================================
# PLACEHOLDER FUNCTIONS (These would be implemented in actual modules)
# ============================================================================

function Write-LogHeader {
    param([string]$Title, [int]$Level)
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Gray
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Gray
    Write-Host ""
}

function Write-DetailedLog {
    param([string]$Message, [string]$Level = "INFO")
    & $Global:WriteLog $Message $Level
    
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "DEBUG" { "Gray" }
        default { "White" }
    }
    
    Write-Host $Message -ForegroundColor $color
}

function Show-StepProgress {
    param([int]$StepNumber, [int]$TotalSteps, [string]$StepName, [string]$Activity)
    $percent = ($StepNumber / $TotalSteps) * 100
    Write-Progress -Activity $Activity -Status "$StepName..." -PercentComplete $percent
}

function Hide-Progress {
    Write-Progress -Activity "Installation" -Completed
}

function Write-InstallationComplete {
    Write-Host "Installation completed successfully!" -ForegroundColor Green
}

function Write-InstallationError {
    param([string]$ErrorMessage, [System.Exception]$Exception)
    Write-Host "$ErrorMessage" -ForegroundColor Red
    if ($Exception) {
        Write-Host "   Exception: $($Exception.Message)" -ForegroundColor Red
    }
}

# Placeholder functions that would be implemented in actual modules
function Test-PeviitorConfig { return $true }
function Test-SystemRequirements { return $true }
function Assert-Administrator { 
    param([switch]$AllowElevation, [switch]$ShowPrompt) 
    return $true 
}
function Invoke-SelfUpdate { return $true }
function Initialize-PeviitorEnvironment { param([switch]$Force) return $true }
function Install-DockerDesktop { param([switch]$Force) return $true }
function Install-AllDependencies { param([switch]$Force) return $true }
function Deploy-SolrSearch { param($SolrUser, $SolrPassword, [switch]$Force) return $true }
function Deploy-PeviitorFrontend { param($SolrUser, $SolrPassword, [switch]$Force) return $true }
function Start-DataMigration { param($SolrUser, $SolrPassword, [switch]$Force) return $true }
function Start-BrowserLaunch { param([switch]$WaitForServices) return $true }
function Show-AccessInformation { return $true }
function Stop-PeviitorContainers { param([switch]$Force) return $true }
function Remove-PeviitorContainers { return $true }
function Remove-PeviitorNetworks { return $true }
function Remove-PeviitorDirectories { return $true }
function Remove-TempFiles { return $true }
function Invoke-EnvironmentRollback { param($Reason) return $true }
function Test-DockerFunctionality { return $true }
function Test-EnvironmentReadiness { return $true }
function Test-FrontendDeployment { return @{ IsWorking = $true } }
function Test-SolrDeployment { return @{ IsWorking = $true } }
function Test-MigrationStatus { return @{ IsComplete = $true } }
function Test-ServiceHealth { return $true }
function Get-PeviitorConfigValue { param($Path) return "C:\Peviitor" }
function Test-UpdateAvailable { return @{ IsAvailable = $false; CurrentVersion = "1.0.0"; LatestVersion = "1.0.0" } }

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

function Main {
    <#
    .SYNOPSIS
    Main entry point for the installer.
    #>
    
    try {
        # Initialize the installer
        $initResult = Initialize-Installer
        if (-not $initResult) {
            exit 1
        }
        
        # Handle different operations
        if ($CheckUpdates) {
            Write-LogHeader -Title "CHECKING FOR UPDATES" -Level 1
            
            $updateResult = Test-UpdateAvailable
            if ($updateResult.IsAvailable) {
                Write-Host "Update available: v$($updateResult.LatestVersion)" -ForegroundColor Green
                Write-Host "Current version: v$($updateResult.CurrentVersion)" -ForegroundColor Gray
                
                $shouldUpdate = Get-UserChoice -Message "Download and install update?" -DefaultChoice "Yes"
                if ($shouldUpdate -eq "Yes") {
                    Invoke-SelfUpdate -RestartArgs $args
                }
            } else {
                Write-Host "You have the latest version: v$($updateResult.CurrentVersion)" -ForegroundColor Green
            }
            
            exit 0
        }
        
        if ($Uninstall) {
            $uninstallResult = Start-PeviitorUninstall
            exit $(if ($uninstallResult) { 0 } else { 1 })
        }
        
        # Show installation summary unless forced
        if (-not $Force -and -not $Reinstall) {
            Show-InstallationSummary
            
            $confirmation = Get-UserChoice -Message "Continue with installation?" -DefaultChoice "Yes"
            if ($confirmation -ne "Yes") {
                Write-Host "Installation cancelled by user." -ForegroundColor Gray
                exit 0
            }
        }
        
        # Start main installation
        $installResult = Start-PeviitorInstallation
        
        if ($installResult) {
            Show-FinalReport
            exit 0
        } else {
            Write-Host ""
            Write-Host "Installation failed. Check the log file for details:" -ForegroundColor Red
            Write-Host "   $($script:InstallerState.LogFile)" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
        
    } catch {
        Write-Host ""
        Write-Host "Installer crashed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Please check the log file for details: $($script:InstallerState.LogFile)" -ForegroundColor Yellow
        Write-Host ""
        
        if ($Global:WriteLog) {
            & $Global:WriteLog "Installer crashed: $($_.Exception.Message)" "ERROR"
            & $Global:WriteLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        }
        
        exit 1
    }
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if script is being executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Main
}