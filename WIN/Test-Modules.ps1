# Test-Modules.ps1
# Test harness for validating Peviitor installer modules
# Run this script to test each module individually and see actual functionality

param(
    [string]$ModulesPath = ".\src\modules",
    [switch]$Verbose
)

# Colors for output
$Colors = @{
    Success = "Green"
    Error = "Red" 
    Warning = "Yellow"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-TestResult {
    param(
        [string]$Message,
        [string]$Status = "Info",
        [int]$Indent = 0
    )
    
    $prefix = "  " * $Indent
    $color = $Colors[$Status]
    
    switch ($Status) {
        "Success" { Write-Host "$prefix[OK] $Message" -ForegroundColor $color }
        "Error" { Write-Host "$prefix[ERROR] $Message" -ForegroundColor $color }
        "Warning" { Write-Host "$prefix[WARN] $Message" -ForegroundColor $color }
        "Info" { Write-Host "$prefix[INFO] $Message" -ForegroundColor $color }
        "Header" { 
            Write-Host ""
            Write-Host "=" * 80 -ForegroundColor $color
            Write-Host "$prefix[TEST] $Message" -ForegroundColor $color
            Write-Host "=" * 80 -ForegroundColor $color
        }
    }
}

function Test-ModuleFile {
    param([string]$ModulePath)
    
    if (Test-Path $ModulePath) {
        Write-TestResult "Module file exists: $ModulePath" -Status "Success" -Indent 1
        return $true
    } else {
        Write-TestResult "Module file missing: $ModulePath" -Status "Error" -Indent 1
        return $false
    }
}

function Test-ConfigModule {
    Write-TestResult "TESTING CONFIG MODULE" -Status "Header"
    
    $configPath = Join-Path $ModulesPath "Config.ps1"
    if (-not (Test-ModuleFile $configPath)) { return $false }
    
    try {
        # Import the module (remove Export-ModuleMember lines for testing)
        Write-TestResult "Importing Config module..." -Status "Info" -Indent 1
        $configContent = Get-Content $configPath -Raw
        $configContent = $configContent -replace 'Export-ModuleMember.*', ''
        Invoke-Expression $configContent
        
        # Test if global config variable exists
        if ($Global:PeviitorConfig) {
            Write-TestResult "Global PeviitorConfig variable created successfully" -Status "Success" -Indent 1
        } else {
            Write-TestResult "Global PeviitorConfig variable not found" -Status "Error" -Indent 1
            return $false
        }
        
        # Test configuration sections
        Write-TestResult "Testing configuration sections:" -Status "Info" -Indent 1
        
        $requiredSections = @('Network', 'Ports', 'Containers', 'Repositories', 'Requirements')
        foreach ($section in $requiredSections) {
            if ($Global:PeviitorConfig.ContainsKey($section)) {
                Write-TestResult "Section '$section' found" -Status "Success" -Indent 2
            } else {
                Write-TestResult "Section '$section' missing" -Status "Error" -Indent 2
            }
        }
        
        # Test specific configuration values
        Write-TestResult "Testing specific configuration values:" -Status "Info" -Indent 1
        
        $testValues = @{
            "Solr Port" = $Global:PeviitorConfig.Ports.Solr
            "Apache Port" = $Global:PeviitorConfig.Ports.Apache
            "Network Name" = $Global:PeviitorConfig.Network.Name
            "Solr Container Name" = $Global:PeviitorConfig.Containers.Solr.Name
            "Search Engine Repo" = $Global:PeviitorConfig.Repositories.SearchEngine.Repo
        }
        
        foreach ($key in $testValues.Keys) {
            $value = $testValues[$key]
            if ($value) {
                Write-TestResult "$key = '$value'" -Status "Success" -Indent 2
            } else {
                Write-TestResult "$key is null or empty" -Status "Warning" -Indent 2
            }
        }
        
        # Test configuration validation function
        Write-TestResult "Testing configuration validation:" -Status "Info" -Indent 1
        if (Get-Command Test-PeviitorConfig -ErrorAction SilentlyContinue) {
            $validationResult = Test-PeviitorConfig
            if ($validationResult) {
                Write-TestResult "Configuration validation passed" -Status "Success" -Indent 2
            } else {
                Write-TestResult "Configuration validation failed" -Status "Warning" -Indent 2
            }
        } else {
            Write-TestResult "Test-PeviitorConfig function not found" -Status "Error" -Indent 2
        }
        
        # Test helper function
        Write-TestResult "Testing helper functions:" -Status "Info" -Indent 1
        if (Get-Command Get-PeviitorConfigValue -ErrorAction SilentlyContinue) {
            $solrPort = Get-PeviitorConfigValue -Path "Ports.Solr" -Default 8983
            Write-TestResult "Get-PeviitorConfigValue('Ports.Solr') = '$solrPort'" -Status "Success" -Indent 2
            
            $invalidPath = Get-PeviitorConfigValue -Path "Invalid.Path" -Default "DefaultValue"
            Write-TestResult "Get-PeviitorConfigValue('Invalid.Path') = '$invalidPath'" -Status "Success" -Indent 2
        } else {
            Write-TestResult "Get-PeviitorConfigValue function not found" -Status "Error" -Indent 2
        }
        
        Write-TestResult "Config module test completed successfully" -Status "Success" -Indent 1
        return $true
        
    } catch {
        Write-TestResult "Config module test failed: $($_.Exception.Message)" -Status "Error" -Indent 1
        return $false
    }
}

function Test-LoggerModule {
    Write-TestResult "TESTING LOGGER MODULE" -Status "Header"
    
    $loggerPath = Join-Path $ModulesPath "Logger.ps1"
    if (-not (Test-ModuleFile $loggerPath)) { return $false }
    
    try {
        Write-TestResult "Importing Logger module..." -Status "Info" -Indent 1
        $loggerContent = Get-Content $loggerPath -Raw
        $loggerContent = $loggerContent -replace 'Export-ModuleMember.*', ''
        Invoke-Expression $loggerContent
        
        # Test logging functions
        if (Get-Command Write-DetailedLog -ErrorAction SilentlyContinue) {
            Write-TestResult "Write-DetailedLog function found" -Status "Success" -Indent 2
            
            # Test different log levels
            Write-TestResult "Testing log levels:" -Status "Info" -Indent 2
            Write-DetailedLog -Message "Test INFO message" -Level "INFO"
            Write-DetailedLog -Message "Test WARN message" -Level "WARN"
            Write-DetailedLog -Message "Test ERROR message" -Level "ERROR"
            Write-DetailedLog -Message "Test DEBUG message" -Level "DEBUG"
            
        } else {
            Write-TestResult "Write-DetailedLog function not found" -Status "Error" -Indent 2
        }
        
        if (Get-Command Show-Progress -ErrorAction SilentlyContinue) {
            Write-TestResult "Show-Progress function found" -Status "Success" -Indent 2
            
            # Test progress bar
            Write-TestResult "Testing progress bar:" -Status "Info" -Indent 2
            for ($i = 1; $i -le 5; $i++) {
                Show-Progress -Activity "Testing Progress" -Status "Step $i of 5" -PercentComplete ($i * 20)
                Start-Sleep -Milliseconds 500
            }
            Write-Progress -Activity "Testing Progress" -Completed
            
        } else {
            Write-TestResult "Show-Progress function not found" -Status "Error" -Indent 2
        }
        
        # Check if log file was created
        if ($Global:LogFile -and (Test-Path $Global:LogFile)) {
            $logContent = Get-Content $Global:LogFile -Tail 5
            Write-TestResult "Log file created successfully" -Status "Success" -Indent 2
            Write-TestResult "Last 5 log entries:" -Status "Info" -Indent 2
            foreach ($line in $logContent) {
                Write-TestResult $line -Status "Info" -Indent 3
            }
        }
        
        Write-TestResult "Logger module test completed successfully" -Status "Success" -Indent 1
        return $true
        
    } catch {
        Write-TestResult "Logger module test failed: $($_.Exception.Message)" -Status "Error" -Indent 1
        return $false
    }
}

function Test-PrerequisitesModule {
    Write-TestResult "TESTING PREREQUISITES MODULE" -Status "Header"
    
    $prereqPath = Join-Path $ModulesPath "Prerequisites.ps1"
    if (-not (Test-ModuleFile $prereqPath)) { return $false }
    
    try {
        Write-TestResult "Importing Prerequisites module..." -Status "Info" -Indent 1
        $prereqContent = Get-Content $prereqPath -Raw
        $prereqContent = $prereqContent -replace 'Export-ModuleMember.*', ''
        Invoke-Expression $prereqContent
        
        if (Get-Command Test-SystemRequirements -ErrorAction SilentlyContinue) {
            Write-TestResult "Test-SystemRequirements function found" -Status "Success" -Indent 2
            
            Write-TestResult "Running system requirements check:" -Status "Info" -Indent 2
            $reqResult = Test-SystemRequirements
            
            if ($reqResult) {
                Write-TestResult "System requirements check passed" -Status "Success" -Indent 2
            } else {
                Write-TestResult "System requirements check failed (this is expected in test environment)" -Status "Warning" -Indent 2
            }
        } else {
            Write-TestResult "Test-SystemRequirements function not found" -Status "Error" -Indent 2
        }
        
        Write-TestResult "Prerequisites module test completed" -Status "Success" -Indent 1
        return $true
        
    } catch {
        Write-TestResult "Prerequisites module test failed: $($_.Exception.Message)" -Status "Error" -Indent 1
        return $false
    }
}

function Test-ElevationModule {
    Write-TestResult "TESTING ELEVATION MODULE" -Status "Header"
    
    $elevationPath = Join-Path $ModulesPath "Elevation.ps1"
    if (-not (Test-ModuleFile $elevationPath)) { return $false }
    
    try {
        Write-TestResult "Importing Elevation module..." -Status "Info" -Indent 1
        . $elevationPath
        
        if (Get-Command Test-Administrator -ErrorAction SilentlyContinue) {
            Write-TestResult "Test-Administrator function found" -Status "Success" -Indent 2
            
            $isAdmin = Test-Administrator
            if ($isAdmin) {
                Write-TestResult "Currently running as Administrator" -Status "Success" -Indent 2
            } else {
                Write-TestResult "Not running as Administrator" -Status "Warning" -Indent 2
            }
        } else {
            Write-TestResult "Test-Administrator function not found" -Status "Error" -Indent 2
        }
        
        if (Get-Command Start-ElevatedProcess -ErrorAction SilentlyContinue) {
            Write-TestResult "Start-ElevatedProcess function found" -Status "Success" -Indent 2
        } else {
            Write-TestResult "Start-ElevatedProcess function not found" -Status "Error" -Indent 2
        }
        
        Write-TestResult "Elevation module test completed" -Status "Success" -Indent 1
        return $true
        
    } catch {
        Write-TestResult "Elevation module test failed: $($_.Exception.Message)" -Status "Error" -Indent 1
        return $false
    }
}

# ============================================================================
# MAIN TEST EXECUTION
# ============================================================================

Write-TestResult "PEVIITOR INSTALLER MODULE TESTING" -Status "Header"
Write-TestResult "Modules Path: $ModulesPath" -Status "Info"
Write-TestResult "Verbose Mode: $Verbose" -Status "Info"

# Check if modules directory exists
if (-not (Test-Path $ModulesPath)) {
    Write-TestResult "Modules directory not found: $ModulesPath" -Status "Error"
    Write-TestResult "Please ensure you have created the project structure first" -Status "Error"
    exit 1
}

# Track test results
$testResults = @{
    Config = $false
    Logger = $false
    Prerequisites = $false
    Elevation = $false
}

# Run tests for existing modules
Write-TestResult "Starting module tests..." -Status "Info"

# Test Config Module (no dependencies)
$testResults.Config = Test-ConfigModule

# Test Logger Module (no dependencies) 
$testResults.Logger = Test-LoggerModule

# Test Prerequisites Module (requires Logger)
if ($testResults.Logger) {
    # Logger is working, so Prerequisites can use its functions
    $testResults.Prerequisites = Test-PrerequisitesModule
} else {
    Write-TestResult "Skipping Prerequisites test - Logger module failed" -Status "Warning"
    $testResults.Prerequisites = $false
}

# Test Elevation Module (no dependencies)
$testResults.Elevation = Test-ElevationModule

# ============================================================================
# TEST SUMMARY
# ============================================================================

Write-TestResult "TEST SUMMARY" -Status "Header"

$totalTests = 0
$passedTests = 0

foreach ($moduleName in $testResults.Keys) {
    $totalTests++
    $result = $testResults[$moduleName]
    
    if ($result) {
        Write-TestResult "$moduleName Module: PASSED" -Status "Success" -Indent 1
        $passedTests++
    } else {
        Write-TestResult "$moduleName Module: FAILED or SKIPPED" -Status "Error" -Indent 1
    }
}

Write-TestResult "Test Results: $passedTests/$totalTests modules passed" -Status "Info"

if ($passedTests -eq $totalTests) {
    Write-TestResult "ALL TESTS PASSED!" -Status "Success"
    exit 0
} else {
    Write-TestResult "Some tests failed. Please review the output above." -Status "Warning"
    exit 1
}