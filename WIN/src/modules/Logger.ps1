# Logger.ps1 - Logging and progress bar functions
# This module handles all logging operations and progress display

# ============================================================================
# GLOBAL LOGGING VARIABLES
# ============================================================================

# Initialize global logging variables
$Global:LogFile = ".\peviitor-installer.log"
$Global:LogLevel = "DEBUG"
$Global:LogStartTime = Get-Date

# ============================================================================
# CORE LOGGING FUNCTIONS
# ============================================================================

function Write-DetailedLog {
    <#
    .SYNOPSIS
    Writes detailed log messages to both file and console with timestamp and level.
    
    .PARAMETER Message
    The message to log
    
    .PARAMETER Level
    Log level: INFO, WARN, ERROR, DEBUG
    
    .PARAMETER NoConsole
    If specified, only writes to file (no console output)
    
    .PARAMETER NoFile
    If specified, only writes to console (no file output)
    
    .EXAMPLE
    Write-DetailedLog -Message "Starting installation" -Level "INFO"
    Write-DetailedLog -Message "Docker not found" -Level "ERROR"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO",
        
        [Parameter()]
        [switch]$NoConsole,
        
        [Parameter()]
        [switch]$NoFile
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to file unless NoFile is specified
    if (-not $NoFile) {
        try {
            Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch {
            # If file logging fails, continue without it
            Write-Host "[WARN] Failed to write to log file: $_" -ForegroundColor Yellow
        }
    }
    
    # Write to console unless NoConsole is specified
    if (-not $NoConsole) {
        switch ($Level) {
            "INFO" { Write-Host "ℹ️ $Message" -ForegroundColor Cyan }
            "SUCCESS" { Write-Host "✅ $Message" -ForegroundColor Green }
            "WARN" { Write-Host "⚠️ $Message" -ForegroundColor Yellow }
            "ERROR" { Write-Host "❌ $Message" -ForegroundColor Red }
            "DEBUG" { 
                if ($Global:LogLevel -eq "DEBUG") {
                    Write-Host "🔍 $Message" -ForegroundColor Gray 
                }
            }
        }
    }
}

function Write-LogHeader {
    <#
    .SYNOPSIS
    Writes a formatted header to both console and log file.
    
    .PARAMETER Title
    The header title
    
    .PARAMETER Level
    Header level (1-3) affects formatting
    
    .EXAMPLE
    Write-LogHeader -Title "STARTING PEVIITOR INSTALLATION" -Level 1
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,
        
        [Parameter()]
        [ValidateRange(1,3)]
        [int]$Level = 1
    )
    
    $separator = switch ($Level) {
        1 { "=" * 80 }
        2 { "-" * 60 }
        3 { "." * 40 }
    }
    
    $headerColor = switch ($Level) {
        1 { "Magenta" }
        2 { "Blue" }  
        3 { "Cyan" }
    }
    
    # Log to file
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = @"
[$timestamp] [HEADER] $separator
[$timestamp] [HEADER] $Title
[$timestamp] [HEADER] $separator
"@
    
    try {
        Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        # Continue if file logging fails
    }
    
    # Display on console
    Write-Host ""
    Write-Host $separator -ForegroundColor $headerColor
    Write-Host $Title -ForegroundColor $headerColor
    Write-Host $separator -ForegroundColor $headerColor
    Write-Host ""
}

# ============================================================================
# PROGRESS BAR FUNCTIONS
# ============================================================================

function Show-Progress {
    <#
    .SYNOPSIS
    Displays progress bars with logging integration.
    
    .PARAMETER Activity
    The main activity description
    
    .PARAMETER Status
    Current status description
    
    .PARAMETER PercentComplete
    Percentage complete (0-100)
    
    .PARAMETER Id
    Progress bar ID for nested progress bars
    
    .PARAMETER ParentId
    Parent progress bar ID for nested progress
    
    .PARAMETER LogProgress
    Also log progress to file
    
    .EXAMPLE
    Show-Progress -Activity "Installing Docker" -Status "Downloading..." -PercentComplete 25
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity,
        
        [Parameter(Mandatory=$true)]
        [string]$Status,
        
        [Parameter()]
        [ValidateRange(0,100)]
        [int]$PercentComplete = 0,
        
        [Parameter()]
        [int]$Id = 1,
        
        [Parameter()]
        [int]$ParentId = 0,
        
        [Parameter()]
        [switch]$LogProgress
    )
    
    # Show progress bar
    if ($ParentId -gt 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id -ParentId $ParentId
    } else {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Id $Id
    }
    
    # Log progress if requested
    if ($LogProgress) {
        Write-DetailedLog -Message "$Activity - $Status ($PercentComplete%)" -Level "DEBUG" -NoConsole
    }
}

function Hide-Progress {
    <#
    .SYNOPSIS
    Hides a progress bar.
    
    .PARAMETER Id
    Progress bar ID to hide
    
    .EXAMPLE
    Hide-Progress -Id 1
    #>
    param(
        [Parameter()]
        [int]$Id = 1
    )
    
    Write-Progress -Id $Id -Completed
}

function Show-StepProgress {
    <#
    .SYNOPSIS
    Shows progress for multi-step operations.
    
    .PARAMETER StepNumber
    Current step number
    
    .PARAMETER TotalSteps
    Total number of steps
    
    .PARAMETER StepName
    Name of current step
    
    .PARAMETER Activity
    Overall activity name
    
    .EXAMPLE
    Show-StepProgress -StepNumber 3 -TotalSteps 10 -StepName "Installing Java" -Activity "System Setup"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [int]$StepNumber,
        
        [Parameter(Mandatory=$true)]
        [int]$TotalSteps,
        
        [Parameter(Mandatory=$true)]
        [string]$StepName,
        
        [Parameter()]
        [string]$Activity = "Installation Progress"
    )
    
    $percentComplete = [math]::Round(($StepNumber / $TotalSteps) * 100, 1)
    $status = "Step $StepNumber of $TotalSteps - $StepName"
    
    Show-Progress -Activity $Activity -Status $status -PercentComplete $percentComplete -LogProgress
    Write-DetailedLog -Message "[$StepNumber/$TotalSteps] $StepName" -Level "INFO"
}

# ============================================================================
# SPECIALIZED LOGGING FUNCTIONS
# ============================================================================

function Write-InstallationStart {
    <#
    .SYNOPSIS
    Logs the start of installation with system information.
    
    .PARAMETER InstallerVersion
    Version of the installer
    
    .EXAMPLE
    Write-InstallationStart -InstallerVersion "1.0.0"
    #>
    param(
        [Parameter()]
        [string]$InstallerVersion = "Unknown"
    )
    
    Write-LogHeader -Title "PEVIITOR LOCAL ENVIRONMENT INSTALLER" -Level 1
    
    # System information
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    $totalRAM = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
    
    $systemInfo = @"
Installer Version: $InstallerVersion
Start Time: $($Global:LogStartTime.ToString("yyyy-MM-dd HH:mm:ss"))
Operating System: $($osInfo.Caption) Build $($osInfo.BuildNumber)
Computer: $($computerInfo.Name)
User: $env:USERNAME
Total RAM: ${totalRAM}GB
PowerShell Version: $($PSVersionTable.PSVersion)
Execution Policy: $(Get-ExecutionPolicy)
"@

    Write-DetailedLog -Message "Installation started" -Level "INFO"
    Write-DetailedLog -Message "System Information:`n$systemInfo" -Level "DEBUG"
}

function Write-InstallationComplete {
    <#
    .SYNOPSIS
    Logs successful completion of installation.
    
    .PARAMETER Duration
    Installation duration
    
    .EXAMPLE
    Write-InstallationComplete
    #>
    param()
    
    $endTime = Get-Date
    $duration = $endTime - $Global:LogStartTime
    $durationText = "{0:mm}m {0:ss}s" -f $duration
    
    Write-LogHeader -Title "INSTALLATION COMPLETED SUCCESSFULLY" -Level 1
    Write-DetailedLog -Message "Installation completed in $durationText" -Level "SUCCESS"
    Write-DetailedLog -Message "Log file: $Global:LogFile" -Level "INFO"
    
    # Display success URLs
    $urls = @(
        "🌐 Peviitor UI: http://localhost:8081/",
        "🔍 Solr Admin: http://localhost:8983/solr/", 
        "📚 API Docs: http://localhost:8081/swagger-ui/"
    )
    
    Write-Host ""
    Write-Host "🎉 SUCCESS! Your Peviitor environment is ready:" -ForegroundColor Green
    foreach ($url in $urls) {
        Write-Host "   $url" -ForegroundColor Cyan
    }
    Write-Host ""
}

function Write-InstallationError {
    <#
    .SYNOPSIS
    Logs installation failure with error details.
    
    .PARAMETER ErrorMessage
    The error message
    
    .PARAMETER Exception
    Exception object if available
    
    .EXAMPLE
    Write-InstallationError -ErrorMessage "Docker installation failed"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage,
        
        [Parameter()]
        [System.Exception]$Exception
    )
    
    $endTime = Get-Date
    $duration = $endTime - $Global:LogStartTime
    $durationText = "{0:mm}m {0:ss}s" -f $duration
    
    Write-LogHeader -Title "INSTALLATION FAILED" -Level 1
    Write-DetailedLog -Message "Installation failed after $durationText" -Level "ERROR"
    Write-DetailedLog -Message "Error: $ErrorMessage" -Level "ERROR"
    
    if ($Exception) {
        Write-DetailedLog -Message "Exception Details: $($Exception.Message)" -Level "ERROR"
        Write-DetailedLog -Message "Stack Trace: $($Exception.StackTrace)" -Level "DEBUG"
    }
    
    Write-DetailedLog -Message "Check log file for details: $Global:LogFile" -Level "ERROR"
    
    Write-Host ""
    Write-Host "💥 Installation failed: $ErrorMessage" -ForegroundColor Red
    Write-Host "📋 Check log file: $Global:LogFile" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Clear-LogFile {
    <#
    .SYNOPSIS
    Clears or creates a new log file.
    
    .EXAMPLE
    Clear-LogFile
    #>
    
    try {
        if (Test-Path $Global:LogFile) {
            Remove-Item $Global:LogFile -Force
        }
        New-Item -Path $Global:LogFile -ItemType File -Force | Out-Null
        Write-DetailedLog -Message "Log file initialized: $Global:LogFile" -Level "DEBUG"
    }
    catch {
        Write-Host "⚠️ Warning: Could not initialize log file: $_" -ForegroundColor Yellow
    }
}

function Set-LogLevel {
    <#
    .SYNOPSIS
    Sets the global log level.
    
    .PARAMETER Level
    Log level to set
    
    .EXAMPLE
    Set-LogLevel -Level "DEBUG"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("INFO", "DEBUG")]
        [string]$Level
    )
    
    $Global:LogLevel = $Level
    Write-DetailedLog -Message "Log level set to: $Level" -Level "DEBUG"
}

function Get-LogSummary {
    <#
    .SYNOPSIS
    Gets a summary of log entries by level.
    
    .EXAMPLE
    Get-LogSummary
    #>
    
    if (-not (Test-Path $Global:LogFile)) {
        Write-Host "No log file found" -ForegroundColor Yellow
        return
    }
    
    $logContent = Get-Content $Global:LogFile
    $summary = @{
        INFO = 0
        WARN = 0  
        ERROR = 0
        DEBUG = 0
        SUCCESS = 0
        Total = $logContent.Count
    }
    
    foreach ($line in $logContent) {
        if ($line -match '\[(\w+)\]') {
            $level = $matches[1]
            if ($summary.ContainsKey($level)) {
                $summary[$level]++
            }
        }
    }
    
    Write-Host "Log Summary:" -ForegroundColor Cyan
    Write-Host "  Total Entries: $($summary.Total)" -ForegroundColor Gray
    Write-Host "  INFO: $($summary.INFO)" -ForegroundColor Cyan
    Write-Host "  SUCCESS: $($summary.SUCCESS)" -ForegroundColor Green
    Write-Host "  WARN: $($summary.WARN)" -ForegroundColor Yellow
    Write-Host "  ERROR: $($summary.ERROR)" -ForegroundColor Red
    Write-Host "  DEBUG: $($summary.DEBUG)" -ForegroundColor Gray
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Initialize logging when module is loaded
Clear-LogFile
Write-DetailedLog -Message "Logger module loaded successfully" -Level "DEBUG"
Write-DetailedLog -Message "Log file path: $Global:LogFile" -Level "DEBUG"