# BrowserLauncher.ps1 - Browser launch and access information
# This module handles launching the default browser to display the completed Peviitor installation

# ============================================================================
# BROWSER LAUNCHER CONFIGURATION
# ============================================================================

# Get configuration from global config
$script:BrowserConfig = @{
    # URLs to launch
    URLs = $Global:PeviitorConfig.Browser.URLs
    LaunchDelay = $Global:PeviitorConfig.Browser.LaunchDelay
    
    # Additional configuration
    AccessibilityTimeout = 30  # seconds to wait for services
    BrowserTimeout = 10        # seconds to wait for browser launch
    TabDelay = 2              # seconds between opening tabs
    MaxRetries = 3            # maximum launch attempts
}

# ============================================================================
# BROWSER DETECTION AND LAUNCH
# ============================================================================

function Start-BrowserLaunch {
    <#
    .SYNOPSIS
    Launches the default browser with all Peviitor interfaces after verifying accessibility.
    
    .PARAMETER NoLaunch
    Skip browser launch and only display access information
    
    .PARAMETER WaitForServices
    Wait for all services to be ready before launching
    
    .OUTPUTS
    Returns $true if browser launch was successful
    
    .EXAMPLE
    Start-BrowserLaunch -WaitForServices
    #>
    param(
        [Parameter()]
        [switch]$NoLaunch,
        
        [Parameter()]
        [switch]$WaitForServices = $true
    )
    
    Write-LogHeader -Title "LAUNCHING PEVIITOR INTERFACES" -Level 2
    
    try {
        $launchSteps = @()
        
        if ($WaitForServices) {
            $launchSteps += @{ Name = "Wait for Services"; Function = { Wait-ForAllServices } }
        }
        
        $launchSteps += @(
            @{ Name = "Verify URL Accessibility"; Function = { Test-AllURLsAccessible } }
            @{ Name = "Display Access Information"; Function = { Show-AccessInformation } }
        )
        
        if (-not $NoLaunch) {
            $launchSteps += @{ Name = "Launch Browser"; Function = { Invoke-BrowserLaunch } }
        }
        
        $stepNumber = 1
        $totalSteps = $launchSteps.Count
        
        foreach ($step in $launchSteps) {
            Show-StepProgress -StepNumber $stepNumber -TotalSteps $totalSteps -StepName $step.Name -Activity "Browser Launch"
            
            $result = & $step.Function
            
            if ($result -and (($result -is [bool] -and $result) -or ($result -is [hashtable] -and $result.Success))) {
                Write-DetailedLog "✅ $($step.Name): SUCCESS" -Level "SUCCESS"
            } else {
                if ($step.Name -eq "Launch Browser") {
                    # Browser launch failure is not critical
                    Write-DetailedLog "⚠️ $($step.Name): FAILED (not critical)" -Level "WARN"
                    Write-DetailedLog "You can manually access the URLs shown above" -Level "INFO"
                } else {
                    Write-DetailedLog "❌ $($step.Name): FAILED" -Level "ERROR"
                    
                    if ($step.Name -eq "Verify URL Accessibility") {
                        Write-DetailedLog "Services may still be starting up. Please wait and try accessing manually." -Level "WARN"
                    }
                }
            }
            
            $stepNumber++
        }
        
        Hide-Progress
        
        # Show final success message
        Show-LaunchComplete -BrowserLaunched (-not $NoLaunch)
        
        return $true
        
    } catch {
        Write-DetailedLog "Browser launch process failed: $($_.Exception.Message)" -Level "ERROR"
        
        # Still show access information even if launch fails
        Show-AccessInformation | Out-Null
        
        return $false
    }
}

function Wait-ForAllServices {
    <#
    .SYNOPSIS
    Waits for all Peviitor services to be ready.
    
    .OUTPUTS
    Returns $true if all services are ready
    
    .EXAMPLE
    Wait-ForAllServices
    #>
    
    Write-DetailedLog "Waiting for all services to be ready" -Level "INFO"
    Show-Progress -Activity "Service Readiness" -Status "Checking services..." -PercentComplete 10
    
    try {
        $timeout = $script:BrowserConfig.AccessibilityTimeout
        $startTime = Get-Date
        $urls = $script:BrowserConfig.URLs
        
        $serviceReadyCount = 0
        $totalServices = $urls.Count
        
        while ((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
            $serviceReadyCount = 0
            
            foreach ($urlInfo in $urls) {
                $url = $urlInfo.URL
                $isReady = Test-URLQuick -URL $url
                
                if ($isReady) {
                    $serviceReadyCount++
                }
                
                # Update progress
                $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
                $progressPercent = [math]::Min(90, ($elapsedSeconds / $timeout) * 80 + 10)
                
                Show-Progress -Activity "Service Readiness" -Status "Ready: $serviceReadyCount/$totalServices services ($([math]::Round($elapsedSeconds))s)" -PercentComplete $progressPercent
            }
            
            if ($serviceReadyCount -eq $totalServices) {
                Show-Progress -Activity "Service Readiness" -Status "All services ready" -PercentComplete 100
                Write-DetailedLog "All services are ready ($serviceReadyCount/$totalServices)" -Level "SUCCESS"
                return $true
            }
            
            Start-Sleep -Seconds 2
        }
        
        # Timeout reached
        Write-DetailedLog "Timeout waiting for services. Ready: $serviceReadyCount/$totalServices" -Level "WARN"
        return ($serviceReadyCount -gt 0)  # Continue if at least some services are ready
        
    } catch {
        Write-DetailedLog "Error waiting for services: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Test-AllURLsAccessible {
    <#
    .SYNOPSIS
    Tests accessibility of all Peviitor URLs.
    
    .OUTPUTS
    Returns hashtable with accessibility results
    
    .EXAMPLE
    $results = Test-AllURLsAccessible
    #>
    
    Write-DetailedLog "Testing URL accessibility" -Level "INFO"
    
    $results = @{
        Success = $true
        AccessibleCount = 0
        TotalCount = 0
        Results = @{}
    }
    
    try {
        $urls = $script:BrowserConfig.URLs
        $results.TotalCount = $urls.Count
        
        foreach ($urlInfo in $urls) {
            $url = $urlInfo.URL
            $name = $urlInfo.Name
            
            Write-DetailedLog "Testing accessibility: $name" -Level "DEBUG"
            
            $accessResult = Test-URLAccessibility -URL $url -TimeoutSeconds 10
            $results.Results[$name] = $accessResult
            
            if ($accessResult.IsAccessible) {
                $results.AccessibleCount++
                Write-DetailedLog "✅ $name is accessible" -Level "DEBUG"
            } else {
                Write-DetailedLog "❌ $name is not accessible: $($accessResult.Error)" -Level "WARN"
            }
        }
        
        # Consider successful if at least main UI is accessible
        $mainUIResult = $results.Results["Peviitor Main UI"]
        $results.Success = ($mainUIResult -and $mainUIResult.IsAccessible)
        
        Write-DetailedLog "URL accessibility: $($results.AccessibleCount)/$($results.TotalCount) services accessible" -Level "INFO"
        
    } catch {
        Write-DetailedLog "Error testing URL accessibility: $($_.Exception.Message)" -Level "ERROR"
        $results.Success = $false
    }
    
    return $results
}

function Test-URLQuick {
    <#
    .SYNOPSIS
    Quick test of URL accessibility without detailed error handling.
    
    .PARAMETER URL
    URL to test
    
    .OUTPUTS
    Returns $true if URL is accessible
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$URL
    )
    
    try {
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    } catch {
        # Check if it's an authentication error (401), which means service is up
        if ($_.Exception.Message -like "*401*") {
            return $true
        }
        return $false
    }
}

function Test-URLAccessibility {
    <#
    .SYNOPSIS
    Tests URL accessibility with detailed results.
    
    .PARAMETER URL
    URL to test
    
    .PARAMETER TimeoutSeconds
    Timeout in seconds
    
    .OUTPUTS
    Returns hashtable with accessibility details
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        
        [Parameter()]
        [int]$TimeoutSeconds = 10
    )
    
    $result = @{
        URL = $URL
        IsAccessible = $false
        StatusCode = $null
        ResponseTime = $null
        Error = $null
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $response = Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        
        $stopwatch.Stop()
        
        $result.IsAccessible = $true
        $result.StatusCode = $response.StatusCode
        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
        
    } catch {
        $result.Error = $_.Exception.Message
        
        # Try to extract status code from exception
        if ($_.Exception.Response) {
            try {
                $result.StatusCode = [int]$_.Exception.Response.StatusCode
                
                # Some status codes indicate the service is running
                if ($result.StatusCode -in @(200, 301, 302, 401, 404)) {
                    $result.IsAccessible = $true
                }
            } catch {
                # Could not get status code
            }
        }
        
        # Authentication error means service is running
        if ($_.Exception.Message -like "*401*") {
            $result.IsAccessible = $true
            $result.StatusCode = 401
        }
    }
    
    return $result
}

# ============================================================================
# BROWSER DETECTION
# ============================================================================

function Get-DefaultBrowser {
    <#
    .SYNOPSIS
    Detects the default browser on Windows.
    
    .OUTPUTS
    Returns hashtable with browser information
    
    .EXAMPLE
    $browser = Get-DefaultBrowser
    #>
    
    $browserInfo = @{
        Name = "Unknown"
        Path = $null
        Command = $null
        IsAvailable = $false
    }
    
    try {
        # Method 1: Check registry for default browser
        $progId = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice" -ErrorAction SilentlyContinue
        
        if ($progId -and $progId.ProgId) {
            $browserProgId = $progId.ProgId
            Write-DetailedLog "Default browser ProgId: $browserProgId" -Level "DEBUG"
            
            # Get browser command from registry
            $browserCommand = Get-ItemProperty -Path "HKCR:\$browserProgId\shell\open\command" -ErrorAction SilentlyContinue
            
            if ($browserCommand -and $browserCommand."(default)") {
                $commandLine = $browserCommand."(default)"
                
                # Extract executable path
                if ($commandLine -match '^"([^"]+)"') {
                    $browserInfo.Path = $matches[1]
                } elseif ($commandLine -match '^(\S+)') {
                    $browserInfo.Path = $matches[1]
                }
                
                # Determine browser name from path
                if ($browserInfo.Path) {
                    $browserName = [System.IO.Path]::GetFileNameWithoutExtension($browserInfo.Path)
                    
                    switch -Regex ($browserName) {
                        "chrome" { $browserInfo.Name = "Google Chrome" }
                        "firefox" { $browserInfo.Name = "Mozilla Firefox" }
                        "msedge" { $browserInfo.Name = "Microsoft Edge" }
                        "iexplore" { $browserInfo.Name = "Internet Explorer" }
                        "opera" { $browserInfo.Name = "Opera" }
                        "brave" { $browserInfo.Name = "Brave" }
                        default { $browserInfo.Name = $browserName }
                    }
                    
                    $browserInfo.Command = $commandLine
                    $browserInfo.IsAvailable = Test-Path $browserInfo.Path
                }
            }
        }
        
        # Method 2: Fallback to common browsers
        if (-not $browserInfo.IsAvailable) {
            $commonBrowsers = @(
                @{ Name = "Microsoft Edge"; Path = "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe" },
                @{ Name = "Google Chrome"; Path = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" },
                @{ Name = "Google Chrome"; Path = "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe" },
                @{ Name = "Mozilla Firefox"; Path = "$env:ProgramFiles\Mozilla Firefox\firefox.exe" },
                @{ Name = "Mozilla Firefox"; Path = "$env:ProgramFiles (x86)\Mozilla Firefox\firefox.exe" }
            )
            
            foreach ($browser in $commonBrowsers) {
                if (Test-Path $browser.Path) {
                    $browserInfo.Name = $browser.Name
                    $browserInfo.Path = $browser.Path
                    $browserInfo.Command = "`"$($browser.Path)`" `"%1`""
                    $browserInfo.IsAvailable = $true
                    break
                }
            }
        }
        
        # Method 3: Ultimate fallback - use start command
        if (-not $browserInfo.IsAvailable) {
            $browserInfo.Name = "System Default"
            $browserInfo.Command = "start"
            $browserInfo.IsAvailable = $true
        }
        
        Write-DetailedLog "Detected browser: $($browserInfo.Name)" -Level "DEBUG"
        
    } catch {
        Write-DetailedLog "Error detecting default browser: $($_.Exception.Message)" -Level "WARN"
        
        # Final fallback
        $browserInfo.Name = "System Default"
        $browserInfo.Command = "start"
        $browserInfo.IsAvailable = $true
    }
    
    return $browserInfo
}

# ============================================================================
# BROWSER LAUNCH EXECUTION
# ============================================================================

function Invoke-BrowserLaunch {
    <#
    .SYNOPSIS
    Launches the default browser with all Peviitor URLs.
    
    .OUTPUTS
    Returns $true if browser launch was successful
    
    .EXAMPLE
    Invoke-BrowserLaunch
    #>
    
    Write-DetailedLog "Launching browser with Peviitor interfaces" -Level "INFO"
    Show-Progress -Activity "Browser Launch" -Status "Detecting browser..." -PercentComplete 10
    
    try {
        # Detect default browser
        $browserInfo = Get-DefaultBrowser
        
        if (-not $browserInfo.IsAvailable) {
            Write-DetailedLog "No browser available for launch" -Level "ERROR"
            return $false
        }
        
        Write-DetailedLog "Using browser: $($browserInfo.Name)" -Level "INFO"
        
        Show-Progress -Activity "Browser Launch" -Status "Launching browser..." -PercentComplete 30
        
        # Add delay before launching
        if ($script:BrowserConfig.LaunchDelay -gt 0) {
            Write-DetailedLog "Waiting $($script:BrowserConfig.LaunchDelay) seconds before launch..." -Level "DEBUG"
            Start-Sleep -Seconds $script:BrowserConfig.LaunchDelay
        }
        
        # Launch each URL
        $urls = $script:BrowserConfig.URLs
        $launchedCount = 0
        $totalUrls = $urls.Count
        
        foreach ($urlInfo in $urls) {
            $url = $urlInfo.URL
            $name = $urlInfo.Name
            
            $progressPercent = 30 + (($launchedCount / $totalUrls) * 60)
            Show-Progress -Activity "Browser Launch" -Status "Opening $name..." -PercentComplete $progressPercent
            
            Write-DetailedLog "Launching: $name ($url)" -Level "DEBUG"
            
            $success = Start-BrowserWithURL -BrowserInfo $browserInfo -URL $url -Name $name
            
            if ($success) {
                $launchedCount++
                Write-DetailedLog "✅ Launched: $name" -Level "SUCCESS"
            } else {
                Write-DetailedLog "⚠️ Failed to launch: $name" -Level "WARN"
            }
            
            # Add delay between tabs
            if ($launchedCount -lt $totalUrls) {
                Start-Sleep -Seconds $script:BrowserConfig.TabDelay
            }
        }
        
        Show-Progress -Activity "Browser Launch" -Status "Browser launch completed" -PercentComplete 100
        
        if ($launchedCount -gt 0) {
            Write-DetailedLog "Browser launch successful: $launchedCount/$totalUrls URLs opened" -Level "SUCCESS"
            return $true
        } else {
            Write-DetailedLog "Browser launch failed: no URLs could be opened" -Level "ERROR"
            return $false
        }
        
    } catch {
        Write-DetailedLog "Browser launch error: $($_.Exception.Message)" -Level "ERROR"
        return $false
    } finally {
        Hide-Progress
    }
}

function Start-BrowserWithURL {
    <#
    .SYNOPSIS
    Starts browser with a specific URL.
    
    .PARAMETER BrowserInfo
    Browser information from Get-DefaultBrowser
    
    .PARAMETER URL
    URL to open
    
    .PARAMETER Name
    Display name for the URL
    
    .OUTPUTS
    Returns $true if launch was successful
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$BrowserInfo,
        
        [Parameter(Mandatory=$true)]
        [string]$URL,
        
        [Parameter()]
        [string]$Name = "URL"
    )
    
    try {
        if ($BrowserInfo.Name -eq "System Default" -or $BrowserInfo.Command -eq "start") {
            # Use Windows start command
            Start-Process -FilePath "cmd" -ArgumentList @("/c", "start", "`"$Name`"", "`"$URL`"") -WindowStyle Hidden -ErrorAction Stop
        } else {
            # Use specific browser
            if ($BrowserInfo.Path) {
                Start-Process -FilePath $BrowserInfo.Path -ArgumentList $URL -ErrorAction Stop
            } else {
                # Fallback to start command
                Start-Process -FilePath "cmd" -ArgumentList @("/c", "start", "`"$Name`"", "`"$URL`"") -WindowStyle Hidden -ErrorAction Stop
            }
        }
        
        return $true
        
    } catch {
        Write-DetailedLog "Failed to launch browser for $Name : $($_.Exception.Message)" -Level "DEBUG"
        
        # Try fallback method
        try {
            Start-Process $URL -ErrorAction Stop
            return $true
        } catch {
            Write-DetailedLog "Fallback launch also failed for $Name : $($_.Exception.Message)" -Level "DEBUG"
            return $false
        }
    }
}

# ============================================================================
# ACCESS INFORMATION DISPLAY
# ============================================================================

function Show-AccessInformation {
    <#
    .SYNOPSIS
    Displays comprehensive access information for all Peviitor interfaces.
    
    .OUTPUTS
    Returns $true always
    
    .EXAMPLE
    Show-AccessInformation
    #>
    
    Write-LogHeader -Title "PEVIITOR ACCESS INFORMATION" -Level 2
    
    try {
        $urls = $script:BrowserConfig.URLs
        
        Write-DetailedLog "🎉 Peviitor installation completed successfully!" -Level "SUCCESS"
        Write-DetailedLog "" -Level "INFO"
        Write-DetailedLog "Your Peviitor job search platform is now ready!" -Level "SUCCESS"
        Write-DetailedLog "Access the following interfaces:" -Level "INFO"
        Write-DetailedLog "" -Level "INFO"
        
        # Display each interface with detailed information
        foreach ($urlInfo in $urls) {
            $name = $urlInfo.Name
            $url = $urlInfo.URL
            $description = $urlInfo.Description
            $icon = Get-URLIcon -URL $url
            
            Write-DetailedLog "$icon $name" -Level "SUCCESS"
            Write-DetailedLog "   🔗 $url" -Level "INFO"
            Write-DetailedLog "   📝 $description" -Level "INFO"
            
            # Test accessibility and show status
            $accessTest = Test-URLQuick -URL $url
            if ($accessTest) {
                Write-DetailedLog "   ✅ Service is ready" -Level "SUCCESS"
            } else {
                Write-DetailedLog "   ⏳ Service may still be starting" -Level "WARN"
            }
            
            Write-DetailedLog "" -Level "INFO"
        }
        
        # Display additional information
        Write-DetailedLog "📋 Additional Information:" -Level "INFO"
        Write-DetailedLog "   • All services are running in Docker containers" -Level "INFO"
        Write-DetailedLog "   • Data is stored locally on your machine" -Level "INFO"
        Write-DetailedLog "   • Use 'docker ps' to see running containers" -Level "INFO"
        Write-DetailedLog "   • Check installation logs for troubleshooting" -Level "INFO"
        Write-DetailedLog "" -Level "INFO"
        
        # Display credentials information
        Write-DetailedLog "🔐 Solr Admin Access:" -Level "INFO"
        Write-DetailedLog "   • Use the credentials you set during installation" -Level "INFO"
        Write-DetailedLog "   • Required for Solr administration panel" -Level "INFO"
        Write-DetailedLog "" -Level "INFO"
        
        return $true
        
    } catch {
        Write-DetailedLog "Error displaying access information: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-URLIcon {
    <#
    .SYNOPSIS
    Gets an appropriate icon for a URL based on its purpose.
    
    .PARAMETER URL
    URL to get icon for
    
    .OUTPUTS
    Returns emoji icon string
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$URL
    )
    
    switch -Regex ($URL) {
        "swagger-ui" { return "📚" }
        "solr" { return "🔍" }
        "api" { return "🔌" }
        default { return "🌐" }
    }
}

function Show-LaunchComplete {
    <#
    .SYNOPSIS
    Shows completion message after browser launch.
    
    .PARAMETER BrowserLaunched
    Whether browser was launched successfully
    
    .EXAMPLE
    Show-LaunchComplete -BrowserLaunched $true
    #>
    param(
        [Parameter(Mandatory=$true)]
        [bool]$BrowserLaunched
    )
    
    Write-LogHeader -Title "INSTALLATION COMPLETE" -Level 1
    
    if ($BrowserLaunched) {
        Write-DetailedLog "🚀 Browser launched successfully!" -Level "SUCCESS"
        Write-DetailedLog "The Peviitor interfaces should now be open in your browser." -Level "SUCCESS"
    } else {
        Write-DetailedLog "ℹ️ Please manually open your browser and visit the URLs shown above." -Level "INFO"
    }
    
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "🎊 Welcome to Peviitor - Your Local Job Search Platform!" -Level "SUCCESS"
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "💡 Next Steps:" -Level "INFO"
    Write-DetailedLog "   1. Explore the main interface to search for jobs" -Level "INFO"
    Write-DetailedLog "   2. Check the API documentation for integration" -Level "INFO"
    Write-DetailedLog "   3. Use Solr admin panel for advanced search configuration" -Level "INFO"
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "🛠️ Need help? Check the logs and documentation for troubleshooting." -Level "INFO"
    Write-DetailedLog "" -Level "INFO"
    Write-DetailedLog "Thank you for using the Peviitor installer! 🙏" -Level "SUCCESS"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Test-ServiceHealth {
    <#
    .SYNOPSIS
    Tests the overall health of all Peviitor services.
    
    .OUTPUTS
    Returns hashtable with health status
    
    .EXAMPLE
    $health = Test-ServiceHealth
    #>
    
    $health = @{
        IsHealthy = $false
        ServiceCount = 0
        HealthyCount = 0
        Services = @{}
    }
    
    try {
        $urls = $script:BrowserConfig.URLs
        $health.ServiceCount = $urls.Count
        
        foreach ($urlInfo in $urls) {
            $url = $urlInfo.URL
            $name = $urlInfo.Name
            
            $isHealthy = Test-URLQuick -URL $url
            $health.Services[$name] = $isHealthy
            
            if ($isHealthy) {
                $health.HealthyCount++
            }
        }
        
        $health.IsHealthy = ($health.HealthyCount -eq $health.ServiceCount)
        
    } catch {
        Write-DetailedLog "Error testing service health: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $health
}

function Get-AccessSummary {
    <#
    .SYNOPSIS
    Gets a summary of access information for display.
    
    .OUTPUTS
    Returns hashtable with access summary
    
    .EXAMPLE
    $summary = Get-AccessSummary
    #>
    
    $summary = @{
        URLs = @()
        BrowserInfo = @{}
        ServiceHealth = @{}
        Recommendations = @()
    }
    
    try {
        # Get URL information
        $summary.URLs = $script:BrowserConfig.URLs
        
        # Get browser information
        $summary.BrowserInfo = Get-DefaultBrowser
        
        # Get service health
        $summary.ServiceHealth = Test-ServiceHealth
        
        # Generate recommendations
        if (-not $summary.ServiceHealth.IsHealthy) {
            $unhealthyServices = $summary.ServiceHealth.Services.GetEnumerator() | Where-Object { -not $_.Value }
            $summary.Recommendations += "Some services are not ready: $($unhealthyServices.Key -join ', ')"
        }
        
        if (-not $summary.BrowserInfo.IsAvailable) {
            $summary.Recommendations += "No browser detected - access URLs manually"
        }
        
        if ($summary.ServiceHealth.IsHealthy -and $summary.BrowserInfo.IsAvailable) {
            $summary.Recommendations += "All systems ready - enjoy Peviitor!"
        }
        
    } catch {
        Write-DetailedLog "Error getting access summary: $($_.Exception.Message)" -Level "ERROR"
    }
    
    return $summary
}

function Write-AccessReport {
    <#
    .SYNOPSIS
    Displays a detailed access status report.
    
    .EXAMPLE
    Write-AccessReport
    #>
    
    $summary = Get-AccessSummary
    
    Write-LogHeader -Title "ACCESS STATUS REPORT" -Level 3
    
    # Browser information
    $browserIcon = if ($summary.BrowserInfo.IsAvailable) { "✅" } else { "❌" }
    Write-DetailedLog "Browser Status:" -Level "INFO"
    Write-DetailedLog "  $browserIcon Default Browser: $($summary.BrowserInfo.Name)" -Level "INFO"
    
    # Service health
    Write-DetailedLog "Service Health:" -Level "INFO"
    foreach ($serviceInfo in $summary.ServiceHealth.Services.GetEnumerator()) {
        $serviceName = $serviceInfo.Key
        $isHealthy = $serviceInfo.Value
        $healthIcon = if ($isHealthy) { "🟢" } else { "🔴" }
        
        Write-DetailedLog "  $healthIcon $serviceName: $(if ($isHealthy) { 'Ready' } else { 'Not Ready' })" -Level "INFO"
    }
    
    # URLs
    Write-DetailedLog "Available Interfaces:" -Level "INFO"
    foreach ($urlInfo in $summary.URLs) {
        $icon = Get-URLIcon -URL $urlInfo.URL
        Write-DetailedLog "  $icon $($urlInfo.Name): $($urlInfo.URL)" -Level "INFO"
    }
    
    # Recommendations
    if ($summary.Recommendations.Count -gt 0) {
        Write-DetailedLog "Recommendations:" -Level "INFO"
        foreach ($recommendation in $summary.Recommendations) {
            Write-DetailedLog "  💡 $recommendation" -Level "INFO"
        }
    }
    
    # Overall status
    $overallHealthy = $summary.ServiceHealth.IsHealthy
    $healthIcon = if ($overallHealthy) { "💚" } else { "🔧" }
    $healthStatus = if ($overallHealthy) { "ALL SYSTEMS READY" } else { "SERVICES STARTING" }
    
    Write-DetailedLog "$healthIcon Overall Status: $healthStatus" -Level $(if ($overallHealthy) { "SUCCESS" } else { "WARN" })
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

Write-DetailedLog "Browser launcher module loaded" -Level "DEBUG"

# Validate configuration on module load
if (-not $Global:PeviitorConfig) {
    Write-DetailedLog "Global Peviitor configuration not found - some functions may not work correctly" -Level "WARN"
}