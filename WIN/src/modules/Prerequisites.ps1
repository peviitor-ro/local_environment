# Prerequisites.ps1 - Complete system validation and requirements checking
# This module validates all system requirements and software dependencies

# ============================================================================
# SYSTEM REQUIREMENTS VALIDATION
# ============================================================================

function Test-SystemRequirements {
    <#
    .SYNOPSIS
    Comprehensive system requirements validation for Peviitor installer.
    
    .DESCRIPTION
    Validates all system requirements including OS version, hardware specs,
    software dependencies, network connectivity, and port availability.
    
    .EXAMPLE
    $result = Test-SystemRequirements
    if (-not $result.IsValid) { exit 1 }
    #>
    
    Write-DetailedLog "Starting comprehensive system requirements validation" -Level "INFO"
    Show-Progress -Activity "System Validation" -Status "Initializing checks..." -PercentComplete 0
    
    $validationResult = @{
        IsValid          = $true
        Issues           = @()
        Warnings         = @()
        SystemInfo       = @{}
        SoftwareVersions = @{}
    }
    
    # Step 1: Operating System Validation
    Show-StepProgress -StepNumber 1 -TotalSteps 8 -StepName "Operating System" -Activity "System Validation"
    $osResult = Test-OperatingSystem
    $validationResult.SystemInfo.OS = $osResult
    if (-not $osResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $osResult.Issues
    }
    
    # Step 2: Hardware Requirements
    Show-StepProgress -StepNumber 2 -TotalSteps 8 -StepName "Hardware Requirements" -Activity "System Validation"
    $hwResult = Test-HardwareRequirements
    $validationResult.SystemInfo.Hardware = $hwResult
    if (-not $hwResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $hwResult.Issues
    }
    
    # Step 3: Administrator Privileges
    Show-StepProgress -StepNumber 3 -TotalSteps 8 -StepName "Administrator Privileges" -Activity "System Validation"
    $adminResult = Test-AdministratorPrivileges
    $validationResult.SystemInfo.Admin = $adminResult
    if (-not $adminResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $adminResult.Issues
    }
    
    # Step 4: PowerShell Requirements
    Show-StepProgress -StepNumber 4 -TotalSteps 8 -StepName "PowerShell Version" -Activity "System Validation"
    $psResult = Test-PowerShellVersion
    $validationResult.SystemInfo.PowerShell = $psResult
    if (-not $psResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $psResult.Issues
    }
    
    # Step 5: Network Connectivity
    Show-StepProgress -StepNumber 5 -TotalSteps 8 -StepName "Network Connectivity" -Activity "System Validation"
    $networkResult = Test-NetworkConnectivity
    $validationResult.SystemInfo.Network = $networkResult
    if (-not $networkResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $networkResult.Issues
    }
    
    # Step 6: Port Availability
    Show-StepProgress -StepNumber 6 -TotalSteps 8 -StepName "Port Availability" -Activity "System Validation"
    $portResult = Test-PortAvailability
    $validationResult.SystemInfo.Ports = $portResult
    if (-not $portResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $portResult.Issues
    }
    
    # Step 7: Software Dependencies
    Show-StepProgress -StepNumber 7 -TotalSteps 8 -StepName "Software Dependencies" -Activity "System Validation"
    $softwareResult = Test-SoftwareDependencies
    $validationResult.SoftwareVersions = $softwareResult
    if (-not $softwareResult.IsValid) {
        $validationResult.Warnings += $softwareResult.Issues
    }
    
    # Step 8: Docker Compatibility
    Show-StepProgress -StepNumber 8 -TotalSteps 8 -StepName "Docker Compatibility" -Activity "System Validation"
    $dockerResult = Test-DockerCompatibility
    $validationResult.SystemInfo.Docker = $dockerResult
    if (-not $dockerResult.IsValid) {
        $validationResult.IsValid = $false
        $validationResult.Issues += $dockerResult.Issues
    }
    
    Hide-Progress
    
    # Generate validation report
    Write-ValidationReport -ValidationResult $validationResult
    
    return $validationResult
}

# ============================================================================
# INDIVIDUAL VALIDATION FUNCTIONS
# ============================================================================

function Test-OperatingSystem {
    <#
    .SYNOPSIS
    Validates operating system requirements.
    #>
    
    Write-DetailedLog "Validating operating system requirements" -Level "DEBUG"
    
    $result = @{
        IsValid      = $true
        Issues       = @()
        OSVersion    = $null
        BuildNumber  = $null
        Architecture = $null
    }
    
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result.OSVersion = $osInfo.Caption
        $result.BuildNumber = $osInfo.BuildNumber
        $result.Architecture = $osInfo.OSArchitecture
        
        # Check Windows version - require Windows 10 build 19041 (20H1) or Windows 11
        if ([int]$osInfo.BuildNumber -lt 19041) {
            $result.IsValid = $false
            $result.Issues += "Windows 10 build 19041 (20H1) or Windows 11 is required. Found: $($osInfo.Caption) build $($osInfo.BuildNumber)"
        }
        
        # Check architecture - require 64-bit
        if ($osInfo.OSArchitecture -ne "64-bit") {
            $result.IsValid = $false
            $result.Issues += "64-bit architecture is required. Found: $($osInfo.OSArchitecture)"
        }
        
        Write-DetailedLog "OS: $($result.OSVersion) Build $($result.BuildNumber) ($($result.Architecture))" -Level "DEBUG"
        
    }
    catch {
        $result.IsValid = $false
        $result.Issues += "Failed to retrieve operating system information: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-HardwareRequirements {
    <#
    .SYNOPSIS
    Validates hardware requirements (RAM, disk space, CPU).
    #>
    
    Write-DetailedLog "Validating hardware requirements" -Level "DEBUG"
    
    $result = @{
        IsValid        = $true
        Issues         = @()
        RAM_GB         = 0
        FreeSpace_GB   = 0
        ProcessorCount = 0
    }
    
    try {
        # Check RAM
        $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $result.RAM_GB = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
        
        if ($result.RAM_GB -lt 8) {
            $result.IsValid = $false
            $result.Issues += "At least 8GB RAM is required. Found: $($result.RAM_GB)GB"
        }
        
        # Check free disk space on system drive
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object DeviceID -eq $env:SystemDrive
        $result.FreeSpace_GB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        
        if ($result.FreeSpace_GB -lt 20) {
            $result.IsValid = $false
            $result.Issues += "At least 20GB free disk space is required. Available: $($result.FreeSpace_GB)GB"
        }
        
        # Check processor count
        $result.ProcessorCount = $computerInfo.NumberOfProcessors
        if ($result.ProcessorCount -lt 2) {
            $result.Issues += "Warning: Single-core processor detected. Multi-core recommended for optimal performance."
        }
        
        Write-DetailedLog "Hardware: $($result.RAM_GB)GB RAM, $($result.FreeSpace_GB)GB free space, $($result.ProcessorCount) processors" -Level "DEBUG"
        
    }
    catch {
        $result.IsValid = $false
        $result.Issues += "Failed to retrieve hardware information: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-AdministratorPrivileges {
    <#
    .SYNOPSIS
    Validates administrator privileges.
    #>
    
    Write-DetailedLog "Validating administrator privileges" -Level "DEBUG"
    
    $result = @{
        IsValid  = $true
        Issues   = @()
        IsAdmin  = $false
        UserName = $env:USERNAME
    }
    
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$currentUser
        $result.IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $result.IsAdmin) {
            $result.IsValid = $false
            $result.Issues += "Administrator privileges are required. Please run as Administrator."
        }
        
        Write-DetailedLog "Running as: $($result.UserName), Admin: $($result.IsAdmin)" -Level "DEBUG"
        
    }
    catch {
        $result.IsValid = $false
        $result.Issues += "Failed to check administrator privileges: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
    Validates PowerShell version requirements.
    #>
    
    Write-DetailedLog "Validating PowerShell version" -Level "DEBUG"
    
    $result = @{
        IsValid         = $true
        Issues          = @()
        Version         = $PSVersionTable.PSVersion
        Edition         = $PSVersionTable.PSEdition
        ExecutionPolicy = $null
    }
    
    try {
        # Check PowerShell version - require 5.1 or higher
        if ($PSVersionTable.PSVersion.Major -lt 5 -or 
            ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
            $result.IsValid = $false
            $result.Issues += "PowerShell 5.1 or higher is required. Found: $($result.Version)"
        }
        
        # Check execution policy
        $result.ExecutionPolicy = Get-ExecutionPolicy
        $restrictivePolicies = @("Restricted", "AllSigned")
        if ($result.ExecutionPolicy -in $restrictivePolicies) {
            $result.Issues += "Warning: Execution policy '$($result.ExecutionPolicy)' may prevent installation. Consider using 'RemoteSigned' or 'Unrestricted'."
        }
        
        Write-DetailedLog "PowerShell: $($result.Version) $($result.Edition), Policy: $($result.ExecutionPolicy)" -Level "DEBUG"
        
    }
    catch {
        $result.IsValid = $false
        $result.Issues += "Failed to check PowerShell version: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
    Validates internet connectivity to required services.
    #>
    
    Write-DetailedLog "Testing network connectivity" -Level "DEBUG"
    
    $result = @{
        IsValid     = $true
        Issues      = @()
        TestedHosts = @{}
    }
    
    # Required hosts for installation
    $requiredHosts = @(
        @{ Host = "github.com"; Port = 443; Description = "GitHub (source repositories)" },
        @{ Host = "download.docker.com"; Port = 443; Description = "Docker Desktop" },
        @{ Host = "registry-1.docker.io"; Port = 443; Description = "Docker Hub" },
        @{ Host = "dlcdn.apache.org"; Port = 443; Description = "Apache JMeter" }
    )
    
    foreach ($hostInfo in $requiredHosts) {
        $hostResult = @{
            IsReachable  = $false
            ResponseTime = 0
            Error        = $null
        }
        
        try {
            Write-DetailedLog "Testing connectivity to $($hostInfo.Host):$($hostInfo.Port)" -Level "DEBUG"
            $testResult = Test-NetConnection -ComputerName $hostInfo.Host -Port $hostInfo.Port -InformationLevel Quiet -WarningAction SilentlyContinue
            
            if ($testResult) {
                $hostResult.IsReachable = $true
                Write-DetailedLog "✓ $($hostInfo.Host) - OK" -Level "DEBUG"
            }
            else {
                $hostResult.Error = "Connection failed"
                Write-DetailedLog "✗ $($hostInfo.Host) - Failed" -Level "DEBUG"
            }
            
        }
        catch {
            $hostResult.Error = $_.Exception.Message
            Write-DetailedLog "✗ $($hostInfo.Host) - Error: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        $result.TestedHosts[$hostInfo.Host] = $hostResult
        
        if (-not $hostResult.IsReachable) {
            $result.Issues += "Cannot reach $($hostInfo.Host) - $($hostInfo.Description)"
        }
    }
    
    # If any critical host is unreachable, mark as invalid
    $criticalHosts = @("github.com", "download.docker.com")
    foreach ($host in $criticalHosts) {
        if (-not $result.TestedHosts[$host].IsReachable) {
            $result.IsValid = $false
        }
    }
    
    if (-not $result.IsValid) {
        $result.Issues += "Internet connectivity is required for installation. Please check your network connection and firewall settings."
    }
    
    return $result
}

function Test-PortAvailability {
    <#
    .SYNOPSIS
    Validates that required ports are available.
    #>
    
    Write-DetailedLog "Checking port availability" -Level "DEBUG"
    
    $result = @{
        IsValid    = $true
        Issues     = @()
        PortStatus = @{}
    }
    
    # Required ports for Peviitor
    $requiredPorts = @(
        @{ Port = 8081; Service = "Apache Web Server (Peviitor UI)" },
        @{ Port = 8983; Service = "Apache Solr (Search Engine)" }
    )
    
    foreach ($portInfo in $requiredPorts) {
        $port = $portInfo.Port
        $portResult = @{
            IsAvailable = $true
            ProcessName = $null
            ProcessId   = $null
        }
        
        try {
            $portInUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            
            if ($portInUse) {
                $portResult.IsAvailable = $false
                
                # Try to get process information
                try {
                    $process = Get-Process -Id $portInUse.OwningProcess -ErrorAction SilentlyContinue
                    if ($process) {
                        $portResult.ProcessName = $process.Name
                        $portResult.ProcessId = $process.Id
                    }
                }
                catch {
                    # Could not get process info
                }
                
                $processInfo = if ($portResult.ProcessName) { " (used by $($portResult.ProcessName))" } else { "" }
                $result.Issues += "Port $port is already in use$processInfo - required for $($portInfo.Service)"
                $result.IsValid = $false
                
                Write-DetailedLog "✗ Port $port - In use$processInfo" -Level "DEBUG"
            }
            else {
                Write-DetailedLog "✓ Port $port - Available" -Level "DEBUG"
            }
            
        }
        catch {
            # Error checking port, assume it's available
            Write-DetailedLog "? Port $port - Could not check status: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        $result.PortStatus[$port] = $portResult
    }
    
    return $result
}

function Test-SoftwareDependencies {
    <#
    .SYNOPSIS
    Checks installed software and versions (non-critical).
    #>
    
    Write-DetailedLog "Checking software dependencies" -Level "DEBUG"
    
    $result = @{
        IsValid   = $true
        Issues    = @()
        Installed = @{}
    }
    
    # Check Docker Desktop
    $dockerResult = Get-SoftwareVersion -SoftwareName "Docker Desktop" -RegistryPaths @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -DisplayNamePattern "*Docker Desktop*"
    $result.Installed.Docker = $dockerResult
    
    # Check Git
    $gitResult = Get-SoftwareVersion -SoftwareName "Git" -Command "git" -VersionArg "--version"
    $result.Installed.Git = $gitResult
    
    # Check Java
    $javaResult = Get-SoftwareVersion -SoftwareName "Java" -Command "java" -VersionArg "-version"
    $result.Installed.Java = $javaResult
    
    # Check JMeter (optional)
    $jmeterResult = Get-SoftwareVersion -SoftwareName "JMeter" -Command "jmeter" -VersionArg "--version"
    $result.Installed.JMeter = $jmeterResult
    
    # Generate recommendations
    if (-not $result.Installed.Docker.IsInstalled) {
        $result.Issues += "Docker Desktop not found - will be installed automatically"
    }
    if (-not $result.Installed.Git.IsInstalled) {
        $result.Issues += "Git not found - will be installed automatically"
    }
    if (-not $result.Installed.Java.IsInstalled) {
        $result.Issues += "Java not found - will be installed automatically"
    }
    
    return $result
}

function Test-DockerCompatibility {
    <#
    .SYNOPSIS
    Validates Docker Desktop compatibility requirements.
    #>
    
    Write-DetailedLog "Checking Docker compatibility" -Level "DEBUG"
    
    $result = @{
        IsValid        = $true
        Issues         = @()
        HyperV         = @{ Supported = $false; Enabled = $false }
        WSL2           = @{ Supported = $false; Enabled = $false }
        Virtualization = @{ Supported = $false; Enabled = $false }
    }
    
    try {
        # Check Hyper-V support
        $hyperVFeature = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online -ErrorAction SilentlyContinue
        if ($hyperVFeature) {
            $result.HyperV.Supported = $true
            $result.HyperV.Enabled = $hyperVFeature.State -eq "Enabled"
        }
        
        # Check WSL2 support
        $wslFeature = Get-WindowsOptionalFeature -FeatureName Microsoft-Windows-Subsystem-Linux -Online -ErrorAction SilentlyContinue
        if ($wslFeature) {
            $result.WSL2.Supported = $true
            $result.WSL2.Enabled = $wslFeature.State -eq "Enabled"
        }
        
        # Check CPU virtualization support
        $processor = Get-CimInstance -ClassName Win32_Processor
        $result.Virtualization.Supported = $processor.VirtualizationFirmwareEnabled -eq $true
        
        # Docker requires either Hyper-V or WSL2
        if (-not ($result.HyperV.Supported -or $result.WSL2.Supported)) {
            $result.IsValid = $false
            $result.Issues += "Docker Desktop requires Hyper-V or WSL2 support. Neither was found."
        }
        
        if (-not $result.Virtualization.Supported) {
            $result.Issues += "Warning: CPU virtualization may not be enabled in BIOS. Docker performance may be affected."
        }
        
        Write-DetailedLog "Docker compatibility: Hyper-V=$($result.HyperV.Supported), WSL2=$($result.WSL2.Supported), Virtualization=$($result.Virtualization.Supported)" -Level "DEBUG"
        
    }
    catch {
        $result.Issues += "Warning: Could not fully check Docker compatibility: $($_.Exception.Message)"
    }
    
    return $result
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Get-SoftwareVersion {
    <#
    .SYNOPSIS
    Gets installed software version information.
    #>
    param(
        [string]$SoftwareName,
        [string[]]$RegistryPaths = @(),
        [string]$DisplayNamePattern = "*$SoftwareName*",
        [string]$Command = "",
        [string]$VersionArg = "--version"
    )
    
    $result = @{
        IsInstalled = $false
        Version     = $null
        InstallPath = $null
        Method      = $null
    }
    
    # Try registry first
    if ($RegistryPaths.Count -gt 0) {
        foreach ($regPath in $RegistryPaths) {
            try {
                $software = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.DisplayName -like $DisplayNamePattern }
                
                if ($software) {
                    $result.IsInstalled = $true
                    $result.Version = $software.DisplayVersion
                    $result.InstallPath = $software.InstallLocation
                    $result.Method = "Registry"
                    break
                }
            }
            catch {
                # Continue to next registry path
            }
        }
    }
    
    # Try command line if registry failed
    if (-not $result.IsInstalled -and $Command) {
        try {
            $versionOutput = & $Command $VersionArg 2>$null
            if ($LASTEXITCODE -eq 0 -and $versionOutput) {
                $result.IsInstalled = $true
                $result.Version = ($versionOutput -join " ").Trim()
                $result.Method = "Command"
            }
        }
        catch {
            # Command not found or failed
        }
    }
    
    Write-DetailedLog "$SoftwareName installed: $($result.IsInstalled), Version: $($result.Version)" -Level "DEBUG"
    
    return $result
}

function Write-ValidationReport {
    <#
    .SYNOPSIS
    Writes a comprehensive validation report.
    #>
    param(
        [hashtable]$ValidationResult
    )
    
    Write-LogHeader -Title "SYSTEM VALIDATION REPORT" -Level 2
    
    if ($ValidationResult.IsValid) {
        Write-DetailedLog "✅ System validation PASSED - Ready for installation" -Level "SUCCESS"
    }
    else {
        Write-DetailedLog "❌ System validation FAILED - Issues must be resolved" -Level "ERROR"
    }
    
    # Report issues
    if ($ValidationResult.Issues.Count -gt 0) {
        Write-DetailedLog "Critical Issues Found:" -Level "ERROR"
        foreach ($issue in $ValidationResult.Issues) {
            Write-DetailedLog "  • $issue" -Level "ERROR"
        }
    }
    
    # Report warnings
    if ($ValidationResult.Warnings.Count -gt 0) {
        Write-DetailedLog "Warnings:" -Level "WARN"
        foreach ($warning in $ValidationResult.Warnings) {
            Write-DetailedLog "  • $warning" -Level "WARN"
        }
    }
    
    # System summary
    Write-LogHeader -Title "System Summary" -Level 3
    $sysInfo = $ValidationResult.SystemInfo
    
    if ($sysInfo.OS) {
        Write-DetailedLog "OS: $($sysInfo.OS.OSVersion) Build $($sysInfo.OS.BuildNumber)" -Level "INFO"
    }
    if ($sysInfo.Hardware) {
        Write-DetailedLog "Hardware: $($sysInfo.Hardware.RAM_GB)GB RAM, $($sysInfo.Hardware.FreeSpace_GB)GB free" -Level "INFO"
    }
    if ($sysInfo.PowerShell) {
        Write-DetailedLog "PowerShell: $($sysInfo.PowerShell.Version) $($sysInfo.PowerShell.Edition)" -Level "INFO"
    }
    
    Write-DetailedLog "System validation completed" -Level "INFO"
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Prerequisites validation module loaded" -Level "DEBUG"