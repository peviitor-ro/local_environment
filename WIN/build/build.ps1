# build.ps1 - Peviitor Installer Build System
# Combines all individual modules into a single distributable installer
# Author: Peviitor.ro Team
# Version: 1.0.0

<#
.SYNOPSIS
    Builds the Peviitor installer by combining all modules into a single file.

.DESCRIPTION
    This build script takes all individual PowerShell modules (.ps1 files) and combines
    them into a single distributable Install-Peviitor.ps1 file. It handles:
    
    - Module dependency ordering
    - Version stamping from Git
    - Code injection and replacement
    - Build validation
    - Output file generation
    
.PARAMETER OutputPath
    Path where the built installer will be created. Default is "dist/Install-Peviitor.ps1"

.PARAMETER Version
    Override version number. If not specified, uses Git tag or commit hash

.PARAMETER BuildDate
    Override build date. If not specified, uses current date

.PARAMETER Validate
    Only validate the build without creating output file

.PARAMETER Clean
    Clean the output directory before building

.PARAMETER Verbose
    Enable verbose build output

.EXAMPLE
    .\build.ps1
    Standard build with auto-detected version

.EXAMPLE
    .\build.ps1 -OutputPath "release/Install-Peviitor.ps1" -Version "2.1.0"
    Build with custom output path and version

.EXAMPLE
    .\build.ps1 -Validate -Verbose
    Validate build configuration with detailed output
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Output path for the built installer")]
    [string]$OutputPath = "dist/Install-Peviitor.ps1",
    
    [Parameter(HelpMessage = "Source directory containing module files")]
    [string]$SourceDir = "modules",
    
    [Parameter(HelpMessage = "Version number override")]
    [string]$Version = "",
    
    [Parameter(HelpMessage = "Build date override")]
    [string]$BuildDate = "",
    
    [Parameter(HelpMessage = "Only validate build configuration")]
    [switch]$Validate,
    
    [Parameter(HelpMessage = "Clean output directory before build")]
    [switch]$Clean,
    
    [Parameter(HelpMessage = "Skip module validation during build")]
    [switch]$SkipValidation
)

# ============================================================================
# BUILD CONFIGURATION
# ============================================================================

# Build metadata
$script:BuildConfig = @{
    ProjectName = "Peviitor Local Environment Installer"
    Repository = "https://github.com/peviitor-ro/installer"
    Author = "Peviitor.ro Team"
    SourceDir = "modules"
    TemplateFile = "Install-Peviitor.template.ps1"
    OutputDir = Split-Path $OutputPath -Parent
    OutputFile = Split-Path $OutputPath -Leaf
}

# Module load order (must match the orchestrator)
$script:ModuleOrder = @(
    "Config",           # Must be first - provides configuration
    "Logger",           # Must be early - provides logging
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

# Build markers for template replacement
$script:BuildMarkers = @{
    ModuleInjection = "# MODULE CONTENT WILL BE INSERTED HERE DURING BUILD PROCESS"
    VersionPlaceholder = "1.0.0"
    DatePlaceholder = "2024-01-01"
    CommitPlaceholder = "unknown"
}

# ============================================================================
# BUILD FUNCTIONS
# ============================================================================

function Write-BuildLog {
    <#
    .SYNOPSIS
    Writes formatted build log messages.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    # Handle empty messages gracefully
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ""
        return
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "DEBUG" { "Gray" }
        default { "White" }
    }
    
    $prefix = switch ($Level) {
        "SUCCESS" { "[✓]" }
        "ERROR" { "[✗]" }
        "WARN" { "[!]" }
        "DEBUG" { "[•]" }
        default { "[i]" }
    }
    
    Write-Host "[$timestamp] $prefix $Message" -ForegroundColor $color
}

function Test-BuildEnvironment {
    <#
    .SYNOPSIS
    Validates the build environment and prerequisites.
    #>
    
    Write-BuildLog "Validating build environment..." -Level "INFO"
    
    $issues = @()
    
    # Try to auto-detect module location
    $possibleDirs = @(
        $script:BuildConfig.SourceDir,
        ".",
        "..",
        "src",
        "source",
        "powershell",
        "ps1"
    )
    
    $foundSourceDir = $null
    foreach ($dir in $possibleDirs) {
        if (Test-Path $dir) {
            # Check if this directory contains any of our expected modules
            $moduleCount = 0
            foreach ($moduleName in $script:ModuleOrder) {
                $modulePath = Join-Path $dir "$moduleName.ps1"
                if (Test-Path $modulePath) {
                    $moduleCount++
                }
            }
            
            if ($moduleCount -gt 0) {
                $foundSourceDir = $dir
                $script:BuildConfig.SourceDir = $dir
                Write-BuildLog "Auto-detected source directory: $dir (found $moduleCount modules)" -Level "SUCCESS"
                break
            }
        }
    }
    
    if (-not $foundSourceDir) {
        $issues += "No source directory found with modules. Tried: $($possibleDirs -join ', ')"
    }
    
    # Check if all required modules exist
    $foundModules = @()
    $missingModules = @()
    
    foreach ($moduleName in $script:ModuleOrder) {
        $modulePath = Join-Path $script:BuildConfig.SourceDir "$moduleName.ps1"
        if (Test-Path $modulePath) {
            $foundModules += $moduleName
            Write-BuildLog "Found module: $moduleName" -Level "DEBUG"
        } else {
            $missingModules += $moduleName
        }
    }
    
    if ($foundModules.Count -gt 0) {
        Write-BuildLog "Found $($foundModules.Count) modules: $($foundModules -join ', ')" -Level "SUCCESS"
    }
    
    if ($missingModules.Count -gt 0) {
        Write-BuildLog "Missing $($missingModules.Count) modules: $($missingModules -join ', ')" -Level "WARN"
        # Only treat as error if we found no modules at all
        if ($foundModules.Count -eq 0) {
            $issues += "No modules found in source directory: $($script:BuildConfig.SourceDir)"
        }
    }
    
    # Check if template exists (use the current fixed script as template)
    if (-not (Test-Path $script:BuildConfig.TemplateFile)) {
        Write-BuildLog "Template file not found, will use embedded template structure" -Level "WARN"
    }
    
    # Check Git availability
    try {
        $null = git --version 2>$null
        Write-BuildLog "Git detected - version info will be available" -Level "SUCCESS"
    } catch {
        Write-BuildLog "Git not available - using default version info" -Level "WARN"
    }
    
    if ($issues.Count -gt 0) {
        Write-BuildLog "Build environment validation failed:" -Level "ERROR"
        foreach ($issue in $issues) {
            Write-BuildLog "  - $issue" -Level "ERROR"
        }
        
        # Show helpful suggestions
        Write-BuildLog "" -Level "INFO"
        Write-BuildLog "Suggestions:" -Level "INFO"
        Write-BuildLog "  - Run: .\build.ps1 -SourceDir \"path\\to\\your\\modules\"" -Level "INFO"
        Write-BuildLog "  - Or create a 'modules' directory with your .ps1 files" -Level "INFO"
        Write-BuildLog "  - Current directory: $(Get-Location)" -Level "INFO"
        
        return $false
    }
    
    Write-BuildLog "Build environment validated successfully" -Level "SUCCESS"
    return $true
}

function Get-BuildMetadata {
    <#
    .SYNOPSIS
    Extracts version and build metadata from Git and parameters.
    #>
    
    Write-BuildLog "Gathering build metadata..." -Level "INFO"
    
    $metadata = @{
        Version = $Version
        BuildDate = $BuildDate
        CommitHash = "unknown"
        Repository = $script:BuildConfig.Repository
        Author = $script:BuildConfig.Author
    }
    
    # Auto-detect version from Git if not specified
    if ([string]::IsNullOrEmpty($metadata.Version)) {
        try {
            # Try to get latest Git tag
            $gitTag = git describe --tags --abbrev=0 2>$null
            if ($gitTag) {
                $metadata.Version = $gitTag.Trim('v')
                Write-BuildLog "Version detected from Git tag: $($metadata.Version)" -Level "SUCCESS"
            } else {
                # Fallback to commit count
                $commitCount = git rev-list --count HEAD 2>$null
                if ($commitCount) {
                    $metadata.Version = "0.1.$commitCount"
                    Write-BuildLog "Version generated from commit count: $($metadata.Version)" -Level "INFO"
                } else {
                    $metadata.Version = "1.0.0-dev"
                    Write-BuildLog "Using default development version: $($metadata.Version)" -Level "WARN"
                }
            }
        } catch {
            $metadata.Version = "1.0.0-dev"
            Write-BuildLog "Git not available, using default version: $($metadata.Version)" -Level "WARN"
        }
    }
    
    # Get commit hash
    try {
        $metadata.CommitHash = git rev-parse --short HEAD 2>$null
        if ($metadata.CommitHash) {
            Write-BuildLog "Commit hash: $($metadata.CommitHash)" -Level "DEBUG"
        }
    } catch {
        Write-BuildLog "Could not determine commit hash" -Level "DEBUG"
    }
    
    # Set build date
    if ([string]::IsNullOrEmpty($metadata.BuildDate)) {
        $metadata.BuildDate = Get-Date -Format "yyyy-MM-dd"
    }
    
    Write-BuildLog "Build metadata collected:" -Level "INFO"
    Write-BuildLog "  Version: $($metadata.Version)" -Level "INFO"
    Write-BuildLog "  Date: $($metadata.BuildDate)" -Level "INFO"
    Write-BuildLog "  Commit: $($metadata.CommitHash)" -Level "INFO"
    
    return $metadata
}

function Read-ModuleContent {
    <#
    .SYNOPSIS
    Reads and processes individual module content.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )
    
    $modulePath = Join-Path $script:BuildConfig.SourceDir "$ModuleName.ps1"
    
    if (-not (Test-Path $modulePath)) {
        throw "Module file not found: $modulePath"
    }
    
    Write-BuildLog "Reading module: $ModuleName" -Level "DEBUG"
    
    try {
        $content = Get-Content $modulePath -Raw -ErrorAction Stop
        
        # Basic content validation
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "Module content is empty"
        }
        
        # Check for basic PowerShell syntax (functions, variables)
        if ($content -notmatch 'function\s+\w+' -and $content -notmatch '\$\w+') {
            Write-BuildLog "Module $ModuleName appears to have no functions or variables" -Level "WARN"
        }
        
        # Remove any existing module export commands that might conflict
        $content = $content -replace 'Export-ModuleMember.*', ''
        
        # Add module boundary comments
        $processedContent = @"
# ============================================================================
# MODULE: $ModuleName
# ============================================================================

$content

# ============================================================================
# END MODULE: $ModuleName
# ============================================================================

"@
        
        Write-BuildLog "Module $ModuleName processed successfully ($($content.Length) chars)" -Level "DEBUG"
        return $processedContent
        
    } catch {
        throw "Error reading module $ModuleName : $($_.Exception.Message)"
    }
}

function Build-CombinedInstaller {
    <#
    .SYNOPSIS
    Combines all modules into the final installer script.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Metadata
    )
    
    Write-BuildLog "Building combined installer..." -Level "INFO"
    
    # Start with the template or current script structure
    if (Test-Path $script:BuildConfig.TemplateFile) {
        $baseContent = Get-Content $script:BuildConfig.TemplateFile -Raw
        Write-BuildLog "Using template file: $($script:BuildConfig.TemplateFile)" -Level "INFO"
    } else {
        # Use the current fixed script as the base template
        $baseContent = @'
# Install-Peviitor.ps1 - Peviitor Local Environment Installer
# Main orchestrator script that coordinates all installation modules
# Version: {VERSION} (will be replaced during build)
# Build Date: {BUILD_DATE} (will be replaced during build)
# Commit Hash: {COMMIT_HASH} (will be replaced during build)

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

.NOTES
    - Requires Windows 10 build 19041+ or Windows 11
    - Requires Administrator privileges
    - Requires 8GB+ RAM and 20GB+ free disk space
    - Internet connection required for downloads
    
    This file was automatically generated by the build system.
    Do not edit directly - modify the source modules instead.
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

# Installer metadata (replaced during build)
$script:InstallerMetadata = @{
    Name = "Peviitor Local Environment Installer"
    Version = "{VERSION}"
    BuildDate = "{BUILD_DATE}"
    CommitHash = "{COMMIT_HASH}"
    Repository = "{REPOSITORY}"
    Author = "{AUTHOR}"
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

{MODULE_CONTENT}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

function Main {
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
                    Invoke-SelfUpdate
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
        exit 1
    }
}

# Only run main if script is being executed directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
'@
        Write-BuildLog "Using embedded template structure" -Level "INFO"
    }
    
    # Collect all module content
    Write-BuildLog "Processing $($script:ModuleOrder.Count) modules..." -Level "INFO"
    $allModuleContent = @()
    
    foreach ($moduleName in $script:ModuleOrder) {
        try {
            $moduleContent = Read-ModuleContent -ModuleName $moduleName
            $allModuleContent += $moduleContent
            Write-BuildLog "✓ $moduleName" -Level "SUCCESS"
        } catch {
            Write-BuildLog "✗ $moduleName - $($_.Exception.Message)" -Level "ERROR"
            throw "Failed to process module: $moduleName"
        }
    }
    
    # Combine all module content
    $combinedModules = $allModuleContent -join "`n"
    
    # Replace placeholders in template
    $finalContent = $baseContent
    $finalContent = $finalContent -replace '\{VERSION\}', $Metadata.Version
    $finalContent = $finalContent -replace '\{BUILD_DATE\}', $Metadata.BuildDate
    $finalContent = $finalContent -replace '\{COMMIT_HASH\}', $Metadata.CommitHash
    $finalContent = $finalContent -replace '\{REPOSITORY\}', $Metadata.Repository
    $finalContent = $finalContent -replace '\{AUTHOR\}', $Metadata.Author
    $finalContent = $finalContent -replace '\{MODULE_CONTENT\}', $combinedModules
    
    # Also replace the old-style placeholders for compatibility
    $finalContent = $finalContent -replace $script:BuildMarkers.VersionPlaceholder, $Metadata.Version
    $finalContent = $finalContent -replace $script:BuildMarkers.DatePlaceholder, $Metadata.BuildDate
    $finalContent = $finalContent -replace $script:BuildMarkers.CommitPlaceholder, $Metadata.CommitHash
    
    Write-BuildLog "Combined installer built successfully" -Level "SUCCESS"
    Write-BuildLog "  Total size: $($finalContent.Length) characters" -Level "INFO"
    Write-BuildLog "  Modules: $($script:ModuleOrder.Count)" -Level "INFO"
    
    return $finalContent
}

function Save-BuildOutput {
    <#
    .SYNOPSIS
    Saves the built installer to the output file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Metadata
    )
    
    # Create output directory if it doesn't exist
    $outputDir = $script:BuildConfig.OutputDir
    if (-not [string]::IsNullOrEmpty($outputDir) -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        Write-BuildLog "Created output directory: $outputDir" -Level "INFO"
    }
    
    # Save the file
    try {
        $Content | Set-Content -Path $OutputPath -Encoding UTF8 -NoNewline
        
        $fileInfo = Get-Item $OutputPath
        Write-BuildLog "Build output saved successfully" -Level "SUCCESS"
        Write-BuildLog "  File: $OutputPath" -Level "INFO"
        Write-BuildLog "  Size: $([math]::Round($fileInfo.Length / 1KB, 1)) KB" -Level "INFO"
        
        # Create build info file
        $buildInfoPath = $OutputPath -replace '\.ps1$', '.build-info.json'
        $buildInfo = @{
            Version = $Metadata.Version
            BuildDate = $Metadata.BuildDate
            CommitHash = $Metadata.CommitHash
            BuildTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Modules = $script:ModuleOrder
            OutputFile = $OutputPath
            FileSize = $fileInfo.Length
        }
        
        $buildInfo | ConvertTo-Json -Depth 3 | Set-Content -Path $buildInfoPath -Encoding UTF8
        Write-BuildLog "Build info saved: $buildInfoPath" -Level "DEBUG"
        
        return $true
    } catch {
        Write-BuildLog "Failed to save build output: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-BuildOutput {
    <#
    .SYNOPSIS
    Validates the built installer for basic correctness.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    Write-BuildLog "Validating build output..." -Level "INFO"
    
    if (-not (Test-Path $FilePath)) {
        Write-BuildLog "Build output file not found: $FilePath" -Level "ERROR"
        return $false
    }
    
    try {
        # Test PowerShell syntax
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $FilePath -Raw), [ref]$null)
        Write-BuildLog "✓ PowerShell syntax validation passed" -Level "SUCCESS"
    } catch {
        Write-BuildLog "✗ PowerShell syntax validation failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    # Test for required functions
    $content = Get-Content $FilePath -Raw
    $requiredFunctions = @(
        'Initialize-Installer',
        'Start-PeviitorInstallation',
        'Import-AllModules'
    )
    
    foreach ($func in $requiredFunctions) {
        if ($content -match "function\s+$func") {
            Write-BuildLog "✓ Required function found: $func" -Level "DEBUG"
        } else {
            Write-BuildLog "✗ Required function missing: $func" -Level "ERROR"
            return $false
        }
    }
    
    # Test for version replacement
    if ($content -match '\{VERSION\}|\{BUILD_DATE\}|\{COMMIT_HASH\}') {
        Write-BuildLog "✗ Unreplaced placeholders found in output" -Level "ERROR"
        return $false
    }
    
    Write-BuildLog "Build output validation passed" -Level "SUCCESS"
    return $true
}

# ============================================================================
# MAIN BUILD PROCESS
# ============================================================================

function Start-Build {
    <#
    .SYNOPSIS
    Orchestrates the complete build process.
    #>
    
    $buildStartTime = Get-Date
    
    Write-BuildLog "Starting Peviitor Installer Build" -Level "SUCCESS"
    Write-BuildLog "=================================" -Level "SUCCESS"
    
    try {
        # Clean output directory if requested
        if ($Clean -and (Test-Path $script:BuildConfig.OutputDir)) {
            Remove-Item -Path "$($script:BuildConfig.OutputDir)\*" -Recurse -Force
            Write-BuildLog "Output directory cleaned" -Level "INFO"
        }
        
        # Step 1: Validate build environment
        if (-not (Test-BuildEnvironment)) {
            throw "Build environment validation failed"
        }
        
        # Step 2: Gather build metadata
        $metadata = Get-BuildMetadata
        
        # Step 3: If validation only, stop here
        if ($Validate) {
            Write-BuildLog "Validation complete - build would succeed" -Level "SUCCESS"
            return $true
        }
        
        # Step 4: Build the combined installer
        $combinedContent = Build-CombinedInstaller -Metadata $metadata
        
        # Step 5: Save the output
        if (-not (Save-BuildOutput -Content $combinedContent -Metadata $metadata)) {
            throw "Failed to save build output"
        }
        
        # Step 6: Validate the output (unless skipped)
        if (-not $SkipValidation) {
            if (-not (Test-BuildOutput -FilePath $OutputPath)) {
                throw "Build output validation failed"
            }
        }
        
        # Build completed successfully
        $buildDuration = ((Get-Date) - $buildStartTime).TotalSeconds
        Write-BuildLog " " -Level "INFO"
        Write-BuildLog "BUILD COMPLETED SUCCESSFULLY!" -Level "SUCCESS"
        Write-BuildLog "=============================" -Level "SUCCESS"
        Write-BuildLog "Version: $($metadata.Version)" -Level "INFO"
        Write-BuildLog "Output: $OutputPath" -Level "INFO"
        Write-BuildLog "Build time: $([math]::Round($buildDuration, 1))s" -Level "INFO"
        Write-BuildLog " " -Level "INFO"
        Write-BuildLog "Ready for distribution! 🚀" -Level "SUCCESS"
        
        return $true
        
    } catch {
        $buildDuration = ((Get-Date) - $buildStartTime).TotalSeconds
        Write-BuildLog " " -Level "ERROR"
        Write-BuildLog "BUILD FAILED!" -Level "ERROR"
        Write-BuildLog "=============" -Level "ERROR"
        Write-BuildLog "Error: $($_.Exception.Message)" -Level "ERROR"
        Write-BuildLog "Build time: $([math]::Round($buildDuration, 1))s" -Level "ERROR"
        
        return $false
    }
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Show build header
Write-Host ""
Write-Host "Peviitor Installer Build System" -ForegroundColor Magenta
Write-Host "===============================" -ForegroundColor Magenta
Write-Host ""

# Start the build process
$buildResult = Start-Build

# Exit with appropriate code
exit $(if ($buildResult) { 0 } else { 1 })