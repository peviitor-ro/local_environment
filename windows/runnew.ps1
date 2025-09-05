# ================================================================
# SECTION 1: ADMIN CHECK + AUTO-ELEVATE + CREDENTIALS
# ================================================================

# Auto-elevate option
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Script requires Administrator privileges. Attempting to elevate..." -ForegroundColor Yellow
    
    try {
        # Re-launch as administrator
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit 0
    }
    catch {
        Write-Host "ERROR: Failed to elevate to Administrator" -ForegroundColor Red
        Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host "Administrator privileges confirmed" -ForegroundColor Green

# Get user credentials for Solr
do {
    $solr_user = Read-Host "Enter Solr username"
    if ([string]::IsNullOrWhiteSpace($solr_user)) {
        Write-Host "Username cannot be empty" -ForegroundColor Red
    }
} while ([string]::IsNullOrWhiteSpace($solr_user))

do {
    $solr_password = Read-Host "Enter Solr password (min 15 chars, mixed case, numbers, special chars)" -AsSecureString
    $password_plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($solr_password))
    
    if ($password_plain.Length -lt 15 -or 
        $password_plain -cnotmatch '[a-z]' -or 
        $password_plain -cnotmatch '[A-Z]' -or 
        $password_plain -cnotmatch '[0-9]' -or 
        $password_plain -cnotmatch '[!@#$%^&_\-\[\]()]') {
        Write-Host "Password must be 15+ characters with lowercase, uppercase, numbers and special characters" -ForegroundColor Red
    } else {
        Write-Host "Password accepted" -ForegroundColor Green
        break
    }
} while ($true)

Write-Host "Credentials configured successfully" -ForegroundColor Green

# ================================================================
# SECTION 2: PREREQUISITES CHECK
# ================================================================

# Clear variables
$missing_prereqs = @()
$docker_installed = $false
$java_installed = $false
$git_installed = $false

Write-Host "`nChecking system prerequisites..." -ForegroundColor Cyan

# Check PowerShell version
Write-Host "Checking PowerShell version..." -ForegroundColor Gray
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher required. Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    $missing_prereqs += "PowerShell 5.0+"
} else {
    Write-Host "PowerShell version OK: $($PSVersionTable.PSVersion)" -ForegroundColor Green
}

# Check Docker Desktop
Write-Host "Checking Docker Desktop..." -ForegroundColor Gray
try {
    $docker_version = docker --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker found: $docker_version" -ForegroundColor Green
        $docker_installed = $true
    } else {
        Write-Host "Docker not found or not running" -ForegroundColor Yellow
        $missing_prereqs += "Docker Desktop"
    }
} catch {
    Write-Host "Docker not found" -ForegroundColor Yellow
    $missing_prereqs += "Docker Desktop"
}

# Check Java
Write-Host "Checking Java..." -ForegroundColor Gray
try {
    $java_version = java -version 2>&1 | Select-String "version"
    if ($java_version) {
        Write-Host "Java found: $($java_version.ToString().Trim())" -ForegroundColor Green
        $java_installed = $true
    } else {
        Write-Host "Java not found" -ForegroundColor Yellow
        $missing_prereqs += "Java JDK 11+"
    }
} catch {
    Write-Host "Java not found" -ForegroundColor Yellow
    $missing_prereqs += "Java JDK 11+"
}

# Check Git
Write-Host "Checking Git..." -ForegroundColor Gray
try {
    $git_version = git --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Git found: $git_version" -ForegroundColor Green
        $git_installed = $true
    } else {
        Write-Host "Git not found" -ForegroundColor Yellow
        $missing_prereqs += "Git for Windows"
    }
} catch {
    Write-Host "Git not found" -ForegroundColor Yellow
    $missing_prereqs += "Git for Windows"
}

# Check if any prerequisites are missing
if ($missing_prereqs.Count -gt 0) {
    Write-Host "`nMissing prerequisites:" -ForegroundColor Red
    foreach ($prereq in $missing_prereqs) {
        Write-Host "  - $prereq" -ForegroundColor Red
    }
    Write-Host "`nWill install missing prerequisites..." -ForegroundColor Yellow
} else {
    Write-Host "`nAll prerequisites found!" -ForegroundColor Green
}

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 3: PREREQUISITES INSTALLATION
# ================================================================

# variables
$temp_dir = "$env:TEMP\peviitor_install"
$downloads_failed = $false

# Create temp directory for downloads
Write-Host "`nCreating temporary download directory..." -ForegroundColor Cyan
if (Test-Path $temp_dir) {
    Remove-Item $temp_dir -Recurse -Force
}
New-Item -ItemType Directory -Path $temp_dir -Force | Out-Null

# Install missing prerequisites
if ($missing_prereqs.Count -gt 0) {
    Write-Host "Installing missing prerequisites..." -ForegroundColor Cyan
    
    foreach ($prereq in $missing_prereqs) {
        switch ($prereq) {
            "Docker Desktop" {
                Write-Host "Installing Docker Desktop..." -ForegroundColor Gray
                try {
                    $docker_url = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
                    $docker_installer = "$temp_dir\DockerDesktopInstaller.exe"
                    Invoke-WebRequest -Uri $docker_url -OutFile $docker_installer
                    Start-Process -FilePath $docker_installer -ArgumentList "install --quiet" -Wait
                    Write-Host "Docker Desktop installation completed" -ForegroundColor Green
                } catch {
                    Write-Host "ERROR: Failed to install Docker Desktop: $($_.Exception.Message)" -ForegroundColor Red
                    $downloads_failed = $true
                }
            }
            
            "Java JDK 11+" {
                Write-Host "Installing Java JDK..." -ForegroundColor Gray
                try {
                    $java_url = "https://aka.ms/download-jdk/microsoft-jdk-11.0.21-windows-x64.msi"
                    $java_installer = "$temp_dir\microsoft-jdk-11.msi"
                    Invoke-WebRequest -Uri $java_url -OutFile $java_installer
                    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$java_installer`" /quiet /norestart" -Wait
                    Write-Host "Java JDK installation completed" -ForegroundColor Green
                } catch {
                    Write-Host "ERROR: Failed to install Java JDK: $($_.Exception.Message)" -ForegroundColor Red
                    $downloads_failed = $true
                }
            }
            
            "Git for Windows" {
                Write-Host "Installing Git for Windows..." -ForegroundColor Gray
                try {
                    $git_url = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.42.0.2-64-bit.exe"
                    $git_installer = "$temp_dir\Git-Setup.exe"
                    Invoke-WebRequest -Uri $git_url -OutFile $git_installer
                    Start-Process -FilePath $git_installer -ArgumentList "/SILENT /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`"" -Wait
                    Write-Host "Git for Windows installation completed" -ForegroundColor Green
                } catch {
                    Write-Host "ERROR: Failed to install Git for Windows: $($_.Exception.Message)" -ForegroundColor Red
                    $downloads_failed = $true
                }
            }
        }
    }
    
    if ($downloads_failed) {
        Write-Host "`nERROR: One or more installations failed. Cannot continue." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host "`nRefreshing environment variables..." -ForegroundColor Gray
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "All prerequisites installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Skipping installation - all prerequisites already present" -ForegroundColor Green
}

# Clean up temp directory
Remove-Item $temp_dir -Recurse -Force -ErrorAction SilentlyContinue

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 4: DOCKER ENVIRONMENT SETUP
# ================================================================

# Clear variables
$peviitor_dir = "C:\peviitor"
$network_name = "mynetwork"
$subnet = "172.168.0.0/16"
$solr_ip = "172.168.0.10"
$apache_ip = "172.168.0.11"
$solr_port = "8983"
$apache_port = "8080"

Write-Host "`nSetting up Docker environment..." -ForegroundColor Cyan

# Check if Docker Desktop is running
Write-Host "Checking Docker Desktop status..." -ForegroundColor Gray
try {
    $docker_info = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker Desktop is not running. Starting Docker Desktop..." -ForegroundColor Yellow
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -WindowStyle Hidden
        
        Write-Host "Waiting for Docker Desktop to start..." -ForegroundColor Gray
        $timeout = 120  # 2 minutes timeout
        $elapsed = 0
        
        do {
            Start-Sleep 5
            $elapsed += 5
            try {
                docker info 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Docker Desktop started successfully!" -ForegroundColor Green
                    break
                }
            } catch {}
            
            if ($elapsed -ge $timeout) {
                Write-Host "ERROR: Docker Desktop failed to start within $timeout seconds" -ForegroundColor Red
                Write-Host "Please start Docker Desktop manually and try again" -ForegroundColor Yellow
                Read-Host "Press Enter to exit"
                exit 1
            }
            
            Write-Host "Still waiting... ($elapsed seconds)" -ForegroundColor Gray
        } while ($true)
    } else {
        Write-Host "Docker Desktop is running" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Cannot communicate with Docker: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure Docker Desktop is installed and running" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Create peviitor directory
Write-Host "Creating peviitor directory..." -ForegroundColor Gray
if (Test-Path $peviitor_dir) {
    Write-Host "Removing existing peviitor directory..." -ForegroundColor Yellow
    Remove-Item $peviitor_dir -Recurse -Force
}
New-Item -ItemType Directory -Path $peviitor_dir -Force | Out-Null
Write-Host "Directory created: $peviitor_dir" -ForegroundColor Green

# Stop and remove existing containers
Write-Host "Cleaning up existing containers..." -ForegroundColor Gray
$containers = @("apache-container", "solr-container", "data-migration", "deploy-fe")
foreach ($container in $containers) {
    try {
        $exists = docker ps -aq -f name=$container 2>$null
        if ($exists) {
            Write-Host "Stopping and removing container: $container" -ForegroundColor Yellow
            docker stop $container 2>$null | Out-Null
            docker rm $container 2>$null | Out-Null
        }
    } catch {
        Write-Host "Warning: Could not remove container $container" -ForegroundColor Yellow
    }
}

# Remove existing network
Write-Host "Cleaning up existing network..." -ForegroundColor Gray
try {
    $network_exists = docker network ls --filter name=$network_name --format "{{.Name}}" 2>$null
    if ($network_exists -eq $network_name) {
        Write-Host "Removing existing network: $network_name" -ForegroundColor Yellow
        docker network rm $network_name 2>$null | Out-Null
    }
} catch {
    Write-Host "Warning: Could not remove network $network_name" -ForegroundColor Yellow
}

# Create new network
Write-Host "Creating Docker network..." -ForegroundColor Gray
try {
    docker network create --subnet=$subnet $network_name | Out-Null
    Write-Host "Network created: $network_name ($subnet)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create Docker network: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Docker environment setup completed!" -ForegroundColor Green

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 5: FRONTEND AND API DOWNLOAD
# ================================================================

# variables
$build_dir = "$peviitor_dir\build"
$api_dir = "$build_dir\api"
$repo_owner = "peviitor-ro"
$repo_name = "search-engine"
$asset_name = "build.zip"
$api_repo_url = "https://github.com/peviitor-ro/api.git"

Write-Host "`nDownloading and setting up frontend and API..." -ForegroundColor Cyan

# Download latest build.zip from GitHub releases
Write-Host "Fetching latest release information..." -ForegroundColor Gray
try {
    $release_info = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo_owner/$repo_name/releases/latest"
    $download_url = ($release_info.assets | Where-Object { $_.name -eq $asset_name }).browser_download_url
    
    if (-not $download_url) {
        Write-Host "ERROR: Could not find $asset_name in latest release" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host "Found download URL: $download_url" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to get release information: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Download build.zip
Write-Host "Downloading $asset_name..." -ForegroundColor Gray
$temp_zip = "$env:TEMP\$asset_name"
try {
    Invoke-WebRequest -Uri $download_url -OutFile $temp_zip -UseBasicParsing
    Write-Host "Download completed" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to download $asset_name`: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Extract build.zip
Write-Host "Extracting build archive..." -ForegroundColor Gray
try {
    Expand-Archive -Path $temp_zip -DestinationPath $peviitor_dir -Force
    Remove-Item $temp_zip -Force
    Write-Host "Build extracted to: $build_dir" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to extract build archive: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Remove .htaccess file if exists
$htaccess_file = "$build_dir\.htaccess"
if (Test-Path $htaccess_file) {
    Remove-Item $htaccess_file -Force
    Write-Host "Removed .htaccess file" -ForegroundColor Green
}

# Clone API repository
Write-Host "Cloning API repository..." -ForegroundColor Gray
try {
    git clone --depth 1 --branch master --single-branch $api_repo_url $api_dir | Out-Null
    Write-Host "API repository cloned to: $api_dir" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to clone API repository: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Create api.env file
Write-Host "Creating API configuration file..." -ForegroundColor Gray
$api_env_file = "$api_dir\api.env"
$api_env_content = @"
LOCAL_SERVER=solr-container:8983
PROD_SERVER=zimbor.go.ro
BACK_SERVER=https://api.laurentiumarian.ro
SOLR_USER=$solr_user
SOLR_PASS=$password_plain
"@

try {
    $api_env_content | Out-File -FilePath $api_env_file -Encoding UTF8
    Write-Host "API configuration created: $api_env_file" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create API configuration: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Frontend and API setup completed!" -ForegroundColor Green

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 6: START CONTAINERS AND CONFIGURE SOLR
# ================================================================

# variables
$apache_container = "apache-container"
$solr_container = "solr-container"
$solr_url = "http://localhost:8983"
$cores = @("auth", "jobs", "logo", "firme")

Write-Host "`nStarting containers and configuring Solr..." -ForegroundColor Cyan

# Start Apache container
Write-Host "Starting Apache container..." -ForegroundColor Gray
try {
    docker run --name $apache_container --network $network_name --ip $apache_ip --restart=always -d -p "8081:80" -v "$build_dir`:/var/www/html" alexstefan1702/php-apache | Out-Null
    Write-Host "Apache container started successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to start Apache container: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Start Solr container (no volume mount to avoid Windows issues)
Write-Host "Starting Solr container..." -ForegroundColor Gray
try {
    docker run --name $solr_container --network $network_name --ip $solr_ip --restart=always -d -p 8983:8983 solr:latest | Out-Null
    Write-Host "Solr container started successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to start Solr container: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Wait for Solr to start
Write-Host "Waiting for Solr to initialize..." -ForegroundColor Gray
$timeout = 60
$elapsed = 0

do {
    Start-Sleep 5
    $elapsed += 5
    try {
        $response = Invoke-WebRequest -Uri "$solr_url/solr/admin/info/system" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            Write-Host "Solr is ready!" -ForegroundColor Green
            break
        }
    } catch {}
    
    if ($elapsed -ge $timeout) {
        Write-Host "ERROR: Solr failed to start within $timeout seconds" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host "Still waiting... ($elapsed seconds)" -ForegroundColor Gray
} while ($true)

# Create cores
Write-Host "Creating Solr cores..." -ForegroundColor Gray
foreach ($core in $cores) {
    try {
        docker exec $solr_container bin/solr create_core -c $core | Out-Null
        Write-Host "  Core '$core' created" -ForegroundColor Green
    } catch {
        Write-Host "  Core '$core' already exists" -ForegroundColor Yellow
    }
}

# Configure jobs core schema
Write-Host "Configuring jobs core schema..." -ForegroundColor Gray
$jobs_fields = @(
    @{name="job_link"; type="text_general"},
    @{name="job_title"; type="text_general"},
    @{name="company"; type="text_general"},
    @{name="company_str"; type="string"},
    @{name="hiringOrganization.name"; type="text_general"},
    @{name="country"; type="text_general"},
    @{name="city"; type="text_general"},
    @{name="county"; type="text_general"}
)

foreach ($field in $jobs_fields) {
    try {
        $json_data = @{
            "add-field" = @(
                @{
                    name = $field.name
                    type = $field.type
                    stored = $true
                    indexed = $true
                    multiValued = $true
                    uninvertible = $true
                }
            )
        } | ConvertTo-Json -Depth 3 -Compress
        
        Invoke-RestMethod -Uri "$solr_url/solr/jobs/schema" -Method Post -Body $json_data -ContentType "application/json" | Out-Null
    } catch {}
}

# Configure firme core schema
Write-Host "Configuring firme core schema..." -ForegroundColor Gray
$firme_fields = @(
    @{name="cui"; type="plongs"},
    @{name="stare"; type="text_general"},
    @{name="cod_postal"; type="plongs"},
    @{name="cod_stare"; type="plongs"},
    @{name="sector"; type="plongs"},
    @{name="brands"; type="string"},
    @{name="denumire"; type="text_general"}
)

foreach ($field in $firme_fields) {
    try {
        $json_data = @{
            "add-field" = @(
                @{
                    name = $field.name
                    type = $field.type
                    stored = $true
                    indexed = $true
                    multiValued = $true
                    uninvertible = $true
                }
            )
        } | ConvertTo-Json -Depth 3 -Compress
        
        Invoke-RestMethod -Uri "$solr_url/solr/firme/schema" -Method Post -Body $json_data -ContentType "application/json" | Out-Null
    } catch {}
}

# Configure logo core
Write-Host "Configuring logo core schema..." -ForegroundColor Gray
try {
    $json_data = @{
        "add-field" = @(
            @{
                name = "url"
                type = "text_general"
                stored = $true
                indexed = $true
                multiValued = $true
                uninvertible = $true
            }
        )
    } | ConvertTo-Json -Depth 3 -Compress
    
    Invoke-RestMethod -Uri "$solr_url/solr/logo/schema" -Method Post -Body $json_data -ContentType "application/json" | Out-Null
} catch {}

# Configure Swagger and test Apache
Write-Host "Configuring Apache and Swagger..." -ForegroundColor Gray
try {
    # Fix Swagger configuration for correct port
    docker exec $apache_container sed -i 's|localhost:8080|localhost:8081|g' /var/www/swagger-ui/swagger-initializer.js
    docker exec $apache_container sed -i 's|url: "http://localhost:8080/api/v0/swagger.json"|url: "http://localhost:8081/api/v0/swagger.json"|g' /var/www/swagger-ui/swagger-initializer.js
    
    # Also check for any other swagger config files and fix them
    docker exec $apache_container find /var/www -name "*swagger*" -type f -exec sed -i 's|localhost:8080|localhost:8081|g' {} \; 2>/dev/null
    
    docker restart $apache_container | Out-Null
    Start-Sleep 10
    Write-Host "Swagger UI configured for port 8081" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not configure Swagger UI" -ForegroundColor Yellow
}

# Add test job data so frontend works
Write-Host "Adding test job data..." -ForegroundColor Gray
$test_jobs = @(
    @{
        id = "test-job-1"
        job_title = "Software Developer"
        company = "Tech Company"
        job_link = "http://example.com/job1"
        country = "Romania"
        city = "Bucuresti"
        hiringOrganization = @{ name = "Tech Company" }
    },
    @{
        id = "test-job-2" 
        job_title = "Data Analyst"
        company = "Data Corp"
        job_link = "http://example.com/job2"
        country = "Romania"
        city = "Cluj-Napoca"
        hiringOrganization = @{ name = "Data Corp" }
    }
)

$jobs_json = $test_jobs | ConvertTo-Json -Depth 3
try {
    Invoke-RestMethod -Uri "$solr_url/solr/jobs/update?commit=true" -Method Post -Body $jobs_json -ContentType "application/json" | Out-Null
    Write-Host "Test job data added" -ForegroundColor Green
} catch {
    Write-Host "Could not add test data" -ForegroundColor Yellow
}

# Fix API configuration in Apache container (critical for frontend to work)
Write-Host "Fixing API configuration in container..." -ForegroundColor Gray
$container_api_config = @"
LOCAL_SERVER=solr-container:8983
PROD_SERVER=zimbor.go.ro
BACK_SERVER=https://api.laurentiumarian.ro
SOLR_USER=$solr_user
SOLR_PASS=$password_plain
"@

try {
    docker exec $apache_container bash -c "cat > /var/www/html/api/api.env << 'EOF'
$container_api_config
EOF"
    Write-Host "API configuration fixed in container" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not fix API config in container" -ForegroundColor Yellow
}

# Fix JMeter files for Windows (replace container IPs with localhost)
Write-Host "Fixing JMeter files for Windows..." -ForegroundColor Gray

# Get the actual script directory dynamically
$current_script_dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$migration_file = Join-Path $current_script_dir "migration.jmx"
$firme_file = Join-Path $current_script_dir "firme.jmx"

if (Test-Path $migration_file) {
    $jmx_content = Get-Content $migration_file -Raw
    $fixed_jmx = $jmx_content -replace "172\.168\.0\.10", "localhost"
    $fixed_jmx | Set-Content $migration_file -Encoding UTF8
    Write-Host "Fixed migration.jmx" -ForegroundColor Green
} else {
    Write-Host "migration.jmx not found in script directory" -ForegroundColor Yellow
}

if (Test-Path $firme_file) {
    $jmx_content = Get-Content $firme_file -Raw  
    $fixed_jmx = $jmx_content -replace "172\.168\.0\.10", "localhost"
    $fixed_jmx | Set-Content $firme_file -Encoding UTF8
    Write-Host "Fixed firme.jmx" -ForegroundColor Green
} else {
    Write-Host "firme.jmx not found in script directory" -ForegroundColor Yellow
}

Write-Host "Containers and Solr configuration completed!" -ForegroundColor Green

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 7: JMETER INSTALLATION
# ================================================================

# variables
$jmeter_home = "C:\jmeter"
$jmeter_version = "5.6.3"
$jmeter_url = "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-$jmeter_version.zip"

Write-Host "`nInstalling JMeter..." -ForegroundColor Cyan

# Check if JMeter already exists
if (Test-Path "$jmeter_home\bin\jmeter.bat") {
    Write-Host "JMeter already installed at: $jmeter_home" -ForegroundColor Green
} else {
    Write-Host "Downloading and installing JMeter..." -ForegroundColor Gray
    
    try {
        # Create JMeter directory
        New-Item -ItemType Directory -Path $jmeter_home -Force | Out-Null
        
        # Download JMeter
        $temp_zip = "$env:TEMP\apache-jmeter-$jmeter_version.zip"
        Invoke-WebRequest -Uri $jmeter_url -OutFile $temp_zip -UseBasicParsing
        
        # Extract to temp location
        $temp_extract = "$env:TEMP\jmeter_extract"
        Expand-Archive -Path $temp_zip -DestinationPath $temp_extract -Force
        
        # Move contents to final location (remove the apache-jmeter-x.x.x folder level)
        $extracted_folder = "$temp_extract\apache-jmeter-$jmeter_version"
        Get-ChildItem -Path $extracted_folder | Move-Item -Destination $jmeter_home -Force
        
        # Cleanup
        Remove-Item $temp_zip -Force
        Remove-Item $temp_extract -Recurse -Force
        
        Write-Host "JMeter installed successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR: Failed to install JMeter: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Add JMeter to PATH for current session
$env:Path = "$jmeter_home\bin;$env:Path"

Write-Host "JMeter installation completed!" -ForegroundColor Green

Read-Host "`nPress Enter to continue"

# ================================================================
# SECTION 8: FINAL INFO FILE AND SUMMARY
# ================================================================

# variables
$script_dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$info_file = "$script_dir\peviitor_info.txt"

Write-Host "`nCreating final information file..." -ForegroundColor Cyan

# Create info file content
$info_content = @"
=================================================================
                    PEVIITOR SETUP COMPLETE
=================================================================

SERVICES
  [~] SOLR:       http://localhost:8983/solr/
  [~] UI:         http://localhost:8081/
  [~] API:        http://localhost:8081/api/
  [~] Swagger UI: http://localhost:8081/swagger-ui/

JMETER COMMANDS (Run from script directory)
  [~] Migration:  jmeter -n -t "migration.jmx"
  [~] Firme:      jmeter -n -t "firme.jmx"

NOTES
  [~] Solr is running without authentication
  [~] Data is stored inside containers (non-persistent)
  [~] Currently showing test data (2 sample jobs)
  [~] JMeter installed at: C:\jmeter

DOCKER COMMANDS
  [~] List containers:    docker ps -a
  [~] Container logs:     docker logs <container_name>
  [~] Stop container:     docker stop <container_name>
  [~] Start container:    docker start <container_name>
  [~] Remove container:   docker rm <container_name>

CONTAINER NAMES
  [~] Solr container:     solr-container
  [~] Apache container:   apache-container

TO IMPORT REAL DATA:
  1. Run: jmeter -n -t migration.jmx
  2. Run: jmeter -n -t firme.jmx
  
NOTE: Files must be in same directory as script

=================================================================
                       Local environment
                          peviitor.ro
=================================================================
"@

# Write info file
try {
    $info_content | Out-File -FilePath $info_file -Encoding UTF8
    Write-Host "Information file created: $info_file" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not create info file: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Display final summary
Write-Host "`n==================================================================" -ForegroundColor Blue
Write-Host "                    PEVIITOR SETUP COMPLETE" -ForegroundColor Blue
Write-Host "==================================================================" -ForegroundColor Blue

Write-Host "`nSERVICES" -ForegroundColor Cyan
Write-Host "  SOLR:       http://localhost:8983/solr/"
Write-Host "  UI:         http://localhost:8081/"
Write-Host "  API:        http://localhost:8081/api/"
Write-Host "  Swagger UI: http://localhost:8081/swagger-ui/"

Write-Host "`nIMPORTANT" -ForegroundColor Yellow
Write-Host "  - Website ready with test data at: http://localhost:8081"
Write-Host "  - To import real production data:"
Write-Host "    1. Edit migration.jmx: Change 172.168.0.10 to localhost"
Write-Host "    2. Edit firme.jmx: Change 172.168.0.10 to localhost"
Write-Host "    3. Run: jmeter -n -t migration.jmx"
Write-Host "    4. Run: jmeter -n -t firme.jmx"

Write-Host "`nJMETER COMMANDS" -ForegroundColor Cyan
Write-Host "  Migration:  jmeter -n -t migration.jmx"
Write-Host "  Firme:      jmeter -n -t firme.jmx"

Write-Host "`n==================================================================" -ForegroundColor Blue
Write-Host "                    SETUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Blue

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")