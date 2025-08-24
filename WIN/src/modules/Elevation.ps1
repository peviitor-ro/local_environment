# Elevation.ps1 - Complete privilege elevation functionality
# This module handles UAC elevation and administrator privilege management

# ============================================================================
# ELEVATION STATUS DETECTION
# ============================================================================

function Test-Administrator {
    <#
    .SYNOPSIS
    Tests if the current PowerShell session is running as Administrator.
    
    .OUTPUTS
    Returns $true if running as Administrator, $false otherwise
    
    .EXAMPLE
    if (-not (Test-Administrator)) { Request-Elevation }
    #>
    
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$currentUser
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        Write-DetailedLog "Administrator privilege check: $isAdmin" -Level "DEBUG"
        return $isAdmin
        
    } catch {
        Write-DetailedLog "Failed to check administrator privileges: $($_.Exception.Message)" -Level "WARN"
        return $false
    }
}

function Test-ElevationCapability {
    <#
    .SYNOPSIS
    Tests if the system can perform UAC elevation.
    
    .OUTPUTS
    Returns hashtable with elevation capability information
    
    .EXAMPLE
    $elevationInfo = Test-ElevationCapability
    if (-not $elevationInfo.CanElevate) { ... }
    #>
    
    Write-DetailedLog "Testing UAC elevation capability" -Level "DEBUG"
    
    $result = @{
        CanElevate = $true
        Issues = @()
        UACEnabled = $true
        UserType = $null
        IsBuiltinAdmin = $false
    }
    
    try {
        # Check if UAC is enabled
        $uacRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $enableLUA = Get-ItemProperty -Path $uacRegPath -Name "EnableLUA" -ErrorAction SilentlyContinue
        
        if ($enableLUA -and $enableLUA.EnableLUA -eq 0) {
            $result.UACEnabled = $false
            Write-DetailedLog "UAC is disabled in registry" -Level "DEBUG"
        }
        
        # Check user account type
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $result.UserType = if ($currentUser.IsSystem) { "System" } 
                          elseif ($currentUser.IsGuest) { "Guest" }
                          else { "Standard" }
        
        # Check if user is member of local Administrators group
        $adminGroupSid = [Security.Principal.SecurityIdentifier]"S-1-5-32-544"
        $result.IsBuiltinAdmin = $currentUser.Groups -contains $adminGroupSid
        
        # Determine elevation capability
        if ($result.UserType -eq "Guest") {
            $result.CanElevate = $false
            $result.Issues += "Guest accounts cannot be elevated to Administrator"
        }
        
        if (-not $result.IsBuiltinAdmin -and $result.UACEnabled) {
            $result.CanElevate = $false
            $result.Issues += "User is not a member of the local Administrators group"
        }
        
        Write-DetailedLog "Elevation capability: CanElevate=$($result.CanElevate), UAC=$($result.UACEnabled), UserType=$($result.UserType), IsAdmin=$($result.IsBuiltinAdmin)" -Level "DEBUG"
        
    } catch {
        Write-DetailedLog "Error testing elevation capability: $($_.Exception.Message)" -Level "WARN"
        $result.Issues += "Unable to determine elevation capability: $($_.Exception.Message)"
    }
    
    return $result
}

# ============================================================================
# ELEVATION REQUEST AND HANDLING
# ============================================================================

function Request-Elevation {
    <#
    .SYNOPSIS
    Requests administrator elevation by restarting the script with elevated privileges.
    
    .PARAMETER ScriptPath
    Path to the script to elevate (defaults to current script)
    
    .PARAMETER Arguments
    Arguments to pass to the elevated script
    
    .PARAMETER ShowElevationPrompt
    Show custom elevation prompt before UAC
    
    .PARAMETER WaitForExit
    Wait for elevated process to complete
    
    .OUTPUTS
    Returns $true if elevation was successful, $false otherwise
    
    .EXAMPLE
    Request-Elevation -Arguments @("-Verbose", "-Force") -ShowElevationPrompt
    #>
    param(
        [Parameter()]
        [string]$ScriptPath = $PSCommandPath,
        
        [Parameter()]
        [string[]]$Arguments = $script:MyInvocation.BoundParameters.Keys,
        
        [Parameter()]
        [switch]$ShowElevationPrompt,
        
        [Parameter()]
        [switch]$WaitForExit
    )
    
    Write-LogHeader -Title "REQUESTING ADMINISTRATOR ELEVATION" -Level 2
    
    # Check if already running as administrator
    if (Test-Administrator) {
        Write-DetailedLog "Already running as Administrator - no elevation needed" -Level "SUCCESS"
        return $true
    }
    
    # Test elevation capability
    $elevationInfo = Test-ElevationCapability
    if (-not $elevationInfo.CanElevate) {
        Write-DetailedLog "Cannot elevate to Administrator:" -Level "ERROR"
        foreach ($issue in $elevationInfo.Issues) {
            Write-DetailedLog "  • $issue" -Level "ERROR"
        }
        Write-DetailedLog "Please run PowerShell as Administrator manually" -Level "ERROR"
        return $false
    }
    
    try {
        # Show custom elevation prompt if requested
        if ($ShowElevationPrompt) {
            Show-ElevationPrompt
        }
        
        # Prepare arguments for elevated script
        $elevatedArguments = @()
        
        # Add execution policy bypass
        $elevatedArguments += "-ExecutionPolicy"
        $elevatedArguments += "Bypass"
        
        # Add window style (normal for user interaction)
        $elevatedArguments += "-WindowStyle"
        $elevatedArguments += "Normal"
        
        # Add script file
        $elevatedArguments += "-File"
        $elevatedArguments += "`"$ScriptPath`""
        
        # Add original arguments
        if ($Arguments -and $Arguments.Count -gt 0) {
            # Reconstruct original parameters
            $originalArgs = Get-OriginalArguments
            foreach ($arg in $originalArgs) {
                $elevatedArguments += $arg
            }
        }
        
        Write-DetailedLog "Elevating with arguments: $($elevatedArguments -join ' ')" -Level "DEBUG"
        Write-DetailedLog "Starting elevated PowerShell process..." -Level "INFO"
        
        # Prepare process start info
        $startInfo = @{
            FilePath = "powershell.exe"
            ArgumentList = $elevatedArguments
            Verb = "RunAs"
            WindowStyle = "Normal"
            Wait = $WaitForExit
        }
        
        # Start elevated process
        $elevatedProcess = Start-Process @startInfo -PassThru
        
        if ($elevatedProcess) {
            Write-DetailedLog "Elevated process started successfully (PID: $($elevatedProcess.Id))" -Level "SUCCESS"
            Write-DetailedLog "Current process will now exit to allow elevated execution" -Level "INFO"
            
            # Wait a moment for the elevated process to initialize
            Start-Sleep -Seconds 1
            
            # Exit current process
            exit 0
        } else {
            Write-DetailedLog "Failed to start elevated process" -Level "ERROR"
            return $false
        }
        
    } catch [System.ComponentModel.Win32Exception] {
        # User cancelled UAC prompt
        if ($_.Exception.NativeErrorCode -eq 1223) {
            Write-DetailedLog "User cancelled UAC elevation prompt" -Level "WARN"
            Write-DetailedLog "Administrator privileges are required for installation. Please try again and accept the UAC prompt." -Level "ERROR"
        } else {
            Write-DetailedLog "Win32 error during elevation: $($_.Exception.Message) (Code: $($_.Exception.NativeErrorCode))" -Level "ERROR"
        }
        return $false
        
    } catch {
        Write-DetailedLog "Unexpected error during elevation: $($_.Exception.Message)" -Level "ERROR"
        Write-DetailedLog "Exception type: $($_.Exception.GetType().Name)" -Level "DEBUG"
        return $false
    }
}

function Show-ElevationPrompt {
    <#
    .SYNOPSIS
    Shows a custom elevation prompt to prepare user for UAC.
    #>
    
    Write-Host ""
    Write-Host "🔐 ADMINISTRATOR PRIVILEGES REQUIRED" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The Peviitor installer needs Administrator privileges to:" -ForegroundColor White
    Write-Host "  • Install Docker Desktop" -ForegroundColor Cyan
    Write-Host "  • Install Git and Java" -ForegroundColor Cyan  
    Write-Host "  • Configure Windows features" -ForegroundColor Cyan
    Write-Host "  • Manage Docker containers and networks" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You will see a Windows UAC prompt asking for permission." -ForegroundColor White
    Write-Host "Please click 'Yes' to continue with the installation." -ForegroundColor Green
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Get-OriginalArguments {
    <#
    .SYNOPSIS
    Gets the original command line arguments that were passed to the script.
    
    .OUTPUTS
    Returns array of arguments to preserve when elevating
    #>
    
    try {
        $originalArgs = @()
        
        # Get the original command line from environment
        $commandLine = [Environment]::CommandLine
        Write-DetailedLog "Original command line: $commandLine" -Level "DEBUG"
        
        # Parse arguments from MyInvocation if available
        if ($script:MyInvocation.BoundParameters) {
            foreach ($param in $script:MyInvocation.BoundParameters.GetEnumerator()) {
                $paramName = $param.Key
                $paramValue = $param.Value
                
                if ($paramValue -is [switch] -and $paramValue) {
                    $originalArgs += "-$paramName"
                } elseif ($paramValue -and $paramValue -isnot [switch]) {
                    $originalArgs += "-$paramName"
                    $originalArgs += "`"$paramValue`""
                }
            }
        }
        
        # Add unbounded arguments if any
        if ($script:MyInvocation.UnboundArguments) {
            foreach ($arg in $script:MyInvocation.UnboundArguments) {
                $originalArgs += "`"$arg`""
            }
        }
        
        Write-DetailedLog "Reconstructed arguments: $($originalArgs -join ' ')" -Level "DEBUG"
        return $originalArgs
        
    } catch {
        Write-DetailedLog "Failed to get original arguments: $($_.Exception.Message)" -Level "WARN"
        return @()
    }
}

# ============================================================================
# ELEVATION VERIFICATION AND UTILITIES
# ============================================================================

function Assert-Administrator {
    <#
    .SYNOPSIS
    Ensures the script is running as Administrator, elevating if necessary.
    
    .PARAMETER AllowElevation
    Allow automatic elevation if not running as admin
    
    .PARAMETER ShowPrompt
    Show elevation prompt before UAC
    
    .OUTPUTS
    Returns $true if running as admin, exits process if elevation fails
    
    .EXAMPLE
    Assert-Administrator -AllowElevation -ShowPrompt
    #>
    param(
        [Parameter()]
        [switch]$AllowElevation = $true,
        
        [Parameter()]
        [switch]$ShowPrompt = $true
    )
    
    if (Test-Administrator) {
        Write-DetailedLog "✅ Running with Administrator privileges" -Level "SUCCESS"
        return $true
    }
    
    Write-DetailedLog "⚠️ Administrator privileges required" -Level "WARN"
    
    if ($AllowElevation) {
        Write-DetailedLog "Attempting automatic elevation..." -Level "INFO"
        $elevated = Request-Elevation -ShowElevationPrompt:$ShowPrompt
        
        if (-not $elevated) {
            Write-DetailedLog "❌ Elevation failed or was cancelled" -Level "ERROR"
            Write-DetailedLog "Please run this script as Administrator" -Level "ERROR"
            exit 1
        }
        
        # If we reach here, elevation process should have exited
        return $true
    } else {
        Write-DetailedLog "❌ This script must be run as Administrator" -Level "ERROR"
        Write-DetailedLog "Please right-click PowerShell and select 'Run as Administrator'" -Level "ERROR"
        exit 1
    }
}

function Get-ElevationStatus {
    <#
    .SYNOPSIS
    Gets comprehensive information about current elevation status.
    
    .OUTPUTS
    Returns hashtable with elevation status details
    
    .EXAMPLE
    $status = Get-ElevationStatus
    Write-Host "Running as: $($status.UserName) (Admin: $($status.IsAdmin))"
    #>
    
    $status = @{
        IsAdmin = Test-Administrator
        UserName = $env:USERNAME
        UserDomain = $env:USERDOMAIN
        ProcessId = $PID
        ProcessName = (Get-Process -Id $PID).Name
        ElevationCapability = Test-ElevationCapability
        RunningTime = (Get-Date) - (Get-Process -Id $PID).StartTime
    }
    
    # Add detailed user information
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $status.UserSid = $currentUser.User.Value
        $status.AuthenticationType = $currentUser.AuthenticationType
        $status.IsSystem = $currentUser.IsSystem
        $status.IsGuest = $currentUser.IsGuest
        $status.IsAnonymous = $currentUser.IsAnonymous
    } catch {
        Write-DetailedLog "Could not get detailed user information: $($_.Exception.Message)" -Level "DEBUG"
    }
    
    return $status
}

function Write-ElevationStatus {
    <#
    .SYNOPSIS
    Displays current elevation status information.
    
    .EXAMPLE
    Write-ElevationStatus
    #>
    
    $status = Get-ElevationStatus
    
    Write-LogHeader -Title "ELEVATION STATUS" -Level 3
    
    Write-DetailedLog "User: $($status.UserDomain)\$($status.UserName)" -Level "INFO"
    Write-DetailedLog "Process: $($status.ProcessName) (PID: $($status.ProcessId))" -Level "INFO"
    Write-DetailedLog "Administrator: $($status.IsAdmin)" -Level $(if ($status.IsAdmin) { "SUCCESS" } else { "WARN" })
    Write-DetailedLog "Running Time: $($status.RunningTime.ToString('mm\:ss'))" -Level "INFO"
    
    if ($status.ElevationCapability) {
        $capability = $status.ElevationCapability
        Write-DetailedLog "UAC Enabled: $($capability.UACEnabled)" -Level "INFO"
        Write-DetailedLog "Can Elevate: $($capability.CanElevate)" -Level $(if ($capability.CanElevate) { "SUCCESS" } else { "WARN" })
        
        if ($capability.Issues.Count -gt 0) {
            Write-DetailedLog "Elevation Issues:" -Level "WARN"
            foreach ($issue in $capability.Issues) {
                Write-DetailedLog "  • $issue" -Level "WARN"
            }
        }
    }
}

# ============================================================================
# INTEGRATION WITH OTHER MODULES
# ============================================================================

function Invoke-ElevatedOperation {
    <#
    .SYNOPSIS
    Executes an operation with guaranteed administrator privileges.
    
    .PARAMETER ScriptBlock
    Script block to execute with elevated privileges
    
    .PARAMETER Description
    Description of the operation for logging
    
    .OUTPUTS
    Returns $true if operation completed successfully
    
    .EXAMPLE
    $success = Invoke-ElevatedOperation -ScriptBlock { Install-Software } -Description "Installing software"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [string]$Description = "Elevated operation"
    )
    
    Write-DetailedLog "Executing elevated operation: $Description" -Level "INFO"
    
    # Ensure we have administrator privileges
    if (-not (Test-Administrator)) {
        Write-DetailedLog "Administrator privileges required for: $Description" -Level "WARN"
        $elevated = Request-Elevation
        
        if (-not $elevated) {
            Write-DetailedLog "Cannot execute elevated operation without administrator privileges" -Level "ERROR"
            return $false
        }
    }
    
    try {
        Write-DetailedLog "Executing: $Description" -Level "DEBUG"
        $result = Invoke-Command -ScriptBlock $ScriptBlock
        Write-DetailedLog "Elevated operation completed successfully: $Description" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-DetailedLog "Elevated operation failed: $Description" -Level "ERROR"
        Write-DetailedLog "Error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Store original invocation details for elevation
if (-not $script:MyInvocation) {
    $script:MyInvocation = $MyInvocation
}

Write-DetailedLog "Elevation module loaded" -Level "DEBUG"

# Check and log current elevation status on module load
$currentStatus = Get-ElevationStatus
Write-DetailedLog "Current elevation status: Admin=$($currentStatus.IsAdmin), User=$($currentStatus.UserName), CanElevate=$($currentStatus.ElevationCapability.CanElevate)" -Level "DEBUG"