# run.ps1
# Run as Administrator

$ErrorActionPreference = "Stop"
$dir = Get-Location

# --- Function to install Chocolatey (package manager) if missing ---
function Install-Chocolatey {
    Write-Host "Checking Chocolatey installation..."
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey not found. Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "Chocolatey installation completed."
    }
    else {
        Write-Host "Chocolatey is already installed."
    }
}

# --- Function to install git via Chocolatey if missing ---
function Ensure-Git {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Git is not installed. Installing Git via Chocolatey..."
        choco install git -y --no-progress
        Write-Host "Git installed."
    } else {
        Write-Host "Git is installed."
    }
}

# --- Function to install Podman on Windows ---
function Install-Podman {
    Write-Host "Checking Podman installation..."
    if (-not (Get-Command podman.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Podman not installed. Installing Podman..."

        $podmanInstallerUrl = "https://github.com/containers/podman/releases/download/v4.5.3/podman-4.5.3-windows.zip"
        $tempDir = "$env:TEMP\podman_install"
        $zipFile = "$tempDir\podman.zip"

        # Clean/create temp directory
        if (Test-Path $tempDir) { Remove-Item -Recurse -Force -Path $tempDir }
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        Write-Host "Downloading Podman from $podmanInstallerUrl ..."
        Invoke-WebRequest -Uri $podmanInstallerUrl -OutFile $zipFile

        Write-Host "Extracting Podman..."
        Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force

        # Podman executable path inside extracted folder
        $podmanExePathCandidate = Join-Path $tempDir "podman.exe"
        if (-not (Test-Path $podmanExePathCandidate)) {
            # Look deeper in extracted folders
            $podmanExePathCandidate = Get-ChildItem -Path $tempDir -Recurse -Filter "podman.exe" | Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $podmanExePathCandidate) {
            Write-Error "Failed to find podman.exe after extraction."
            exit 1
        }

        # Copy podman.exe to a folder in PATH or add extracted folder to PATH temporarily
        $installDir = "C:\Program Files\Podman"
        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir | Out-Null
        }

        Write-Host "Copying Podman binaries to $installDir..."
        Copy-Item -Path (Join-Path $tempDir '*') -Destination $installDir -Recurse -Force

        # Add installDir to PATH for current session & system permanently
        if (-not $env:PATH.Split(";") -contains $installDir) {
            $newPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + $installDir
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            $env:PATH += ";" + $installDir
        }

        # Initialize and start Podman machine (WSL2 VM)
        Write-Host "Initializing and starting Podman machine..."
        & podman machine init
        & podman machine start

        # Clean up temporary files
        Remove-Item -Recurse -Force $tempDir

        Write-Host "Podman was installed and initialized successfully."
    }
    else {
        Write-Host "Podman is already installed."
        # Ensure podman machine is started
        $machineStatus = podman machine list --format '{{.Name}} {{.Running}}'
        if ($machineStatus -notmatch "true") {
            Write-Host "Starting Podman machine..."
            podman machine start
        }
    }
}

# --- Validate password function ---
function Validate-Password($password) {
    $lengthValid = $password.Length -ge 15
    $hasLower = $password -match '[a-z]'
    $hasUpper = $password -match '[A-Z]'
    $hasDigit = $password -match '\d'
    $hasSpecial = $password -match '[!@#$%^&*_\-\[\]\(\)]'
    return ($lengthValid -or ($hasLower -and $hasUpper -and $hasDigit -and $hasSpecial))
}

Write-Host " ================================================================="
Write-Host " ================= local environment installer ==================="
Write-Host " ====================== peviitor.ro =============================="
Write-Host " ================================================================="

# Install prerequisites
Install-Chocolatey
Ensure-Git
Install-Podman

# Prompt for Solr username and password with validation
$solr_user = Read-Host "Enter the Solr username"

while ($true) {
    Write-Host "Enter the Solr password (input hidden):"
    $secPassword = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPassword)
    $unsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    if (Validate-Password $unsecurePassword) {
        Write-Host "Password accepted."
        break
    } else {
        Write-Warning "Password must be at least 15 characters long OR contain at least one lowercase letter, one uppercase letter, one digit, and one special character (!@#$%^&*_-[]()). Please try again."
    }
}

Write-Host " ================================================================="
Write-Host " ===================== use those credentials ====================="
Write-Host " ====================== for SOLR login ==========================="
Write-Host " ================================================================="
Write-Host "You entered user: $solr_user"
Write-Host "You entered password: [hidden]"

$peviitorPath = "$env:USERPROFILE\peviitor"
if (Test-Path $peviitorPath) {
    Write-Host "Removing existing peviitor folder..."
    Remove-Item -Recurse -Force $peviitorPath
}

# Stop & remove containers if exist, remove network
$containers = "apache-container", "solr-container", "data-migration", "deploy-fe"
foreach ($container in $containers) {
    $exists = podman ps -aq -f "name=$container"
    if (-not [string]::IsNullOrEmpty($exists)) {
        Write-Host "Stopping and removing container: $container"
        podman stop $container | Out-Null
        podman rm $container | Out-Null
    }
}

$network = "mynetwork"
$networks = podman network ls --format "{{.Name}}"
if ($networks -contains $network) {
    Write-Host "Removing existing network $network"
    podman network rm $network | Out-Null
}

Write-Host "Creating network $network with subnet 172.168.0.0/16..."
podman network create --subnet=172.168.0.0/16 $network | Out-Null

# Download build.zip from latest Github release
$REPO = "peviitor-ro/search-engine"
$ASSET_NAME = "build.zip"
$TARGET_DIR = $peviitorPath

Write-Host "Fetching download link for $ASSET_NAME from GitHub repo $REPO latest release..."
$releaseData = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/releases/latest"
$DOWNLOAD_URL = $releaseData.assets | Where-Object { $_.name -eq $ASSET_NAME } | Select-Object -ExpandProperty browser_download_url

if (-not $DOWNLOAD_URL) {
    Write-Error "ERROR: Could not find download URL for $ASSET_NAME in the latest release."
    exit 1
}

Write-Host "Download URL found: $DOWNLOAD_URL"
Write-Host "Downloading $ASSET_NAME to temporary folder..."

$TMP_FILE = "$env:TEMP\$ASSET_NAME"
Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $TMP_FILE

Write-Host "Extracting archive to $TARGET_DIR..."
# Ensure target dir exists
if (-not (Test-Path $TARGET_DIR)) {
    New-Item -ItemType Directory -Path $TARGET_DIR | Out-Null
}

Expand-Archive -Path $TMP_FILE -DestinationPath $TARGET_DIR -Force

# Remove temp file
Remove-Item $TMP_FILE

# Remove .htaccess if exists
$htaccessPath = Join-Path $TARGET_DIR "build\.htaccess"
if (Test-Path $htaccessPath) {
    Write-Host "Removing $htaccessPath"
    Remove-Item $htaccessPath
}

# Clone the API repo
Write-Host "Cloning API repo to $TARGET_DIR\build\api"
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git "$TARGET_DIR\build\api"

# Create api.env file with Solr credentials
$envContent = @"
LOCAL_SERVER = 172.168.0.10:8983
PROD_SERVER = zimbor.go.ro
BACK_SERVER = https://api.laurentiumarian.ro/
SOLR_USER = $solr_user
SOLR_PASS = $unsecurePassword
"@

$envPath = Join-Path "$TARGET_DIR\build\api" "api.env"
Write-Host "Creating api.env file at $envPath"
$envContent | Set-Content -Path $envPath -Force

# Run Podman container for apache web server
Write-Host "Starting apache-container with Podman..."
podman run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 `
    -v "$TARGET_DIR\build:/var/www/html" alexstefan1702/php-apache

# Update swagger URL inside container (assuming a Linux environment inside container)
Write-Host "Updating swagger-ui URL inside apache-container..."
podman exec apache-container sh -c "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:8081/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js"

podman restart apache-container

# Parameters: existing $dir, $peviitorPath, $unsecurePassword, etc. assumed defined previously

# Variables for Solr setup
$CORE_NAME = "auth"
$CORE_NAME_2 = "jobs"
$CORE_NAME_3 = "logo"
$CONTAINER_NAME = "solr-container"
$SOLR_PORT = 8983

# Container volume path mapping:
# Adapt your peviitor solr data path for Windows environment (using USERPROFILE)
$solrDataHostPath = Join-Path $env:USERPROFILE "peviitor\solr\core\data"

if (-not (Test-Path $solrDataHostPath)) {
    Write-Host "Creating Solr data directory at $solrDataHostPath"
    New-Item -ItemType Directory -Path $solrDataHostPath -Force | Out-Null
}

Write-Host " --> Starting Solr container on port $SOLR_PORT using Podman..."
# Run Solr container
podman run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always `
    -d -p $SOLR_PORT:$SOLR_PORT `
    -v "$solrDataHostPath:/var/solr/data:Z" ` # ':Z' relabels volume for SELinux compatibility in WSL/Podman
    solr:latest

Write-Host "Waiting for Solr to start (15 seconds)..."
Start-Sleep -Seconds 15

# NOTE: Windows cannot chmod/chown like Linux, but Podman in WSL should handle volume permissions.

# Create Solr cores
Write-Host " --> Creating Solr cores: $CORE_NAME, $CORE_NAME_2, $CORE_NAME_3"
foreach ($core in @($CORE_NAME, $CORE_NAME_2, $CORE_NAME_3)) {
    podman exec $CONTAINER_NAME bin/solr create_core -c $core
}

# Define function to POST JSON via curl inside container
function Invoke-PodmanCurl ($container, $core, $jsonData) {
    $jsonStr = $jsonData -replace "`n|\r", "" # remove newlines for CLI
    podman exec $container curl -X POST -H "Content-Type: application/json" --data "$jsonStr" "http://localhost:$SOLR_PORT/solr/$core/schema"
}

Write-Host " --> Adding fields to Solr core: $CORE_NAME_2 (jobs)"

# Example field additions (adapted from your bash script fields):

$fieldJsonTemplate = @"
{{
  "add-field": [
    {{
      "name": "{0}",
      "type": "{1}",
      "stored": true,
      "indexed": true,
      "multiValued": {2},
      "uninvertible": true
    }}
  ]
}}
"@

# List of fields to add for jobs core (adjusting booleans and commas as per JSON standard)
$fieldsToAdd = @(
    @{name="job_link"; type="text_general"; multiValued=$true},
    @{name="job_title"; type="text_general"; multiValued=$true},
    @{name="company"; type="text_general"; multiValued=$true},
    @{name="company_str"; type="string"; multiValued=$false},
    @{name="hiringOrganization.name"; type="text_general"; multiValued=$true},
    @{name="country"; type="text_general"; multiValued=$true},
    @{name="city"; type="text_general"; multiValued=$true},
    @{name="county"; type="text_general"; multiValued=$true}
)

foreach ($field in $fieldsToAdd) {
    $jsonData = $fieldJsonTemplate -f $field.name, $field.type, ($field.multiValued.ToString().ToLower())
    Write-Host "Adding field $($field.name) to $CORE_NAME_2"
    Invoke-PodmanCurl -container $CONTAINER_NAME -core $CORE_NAME_2 -jsonData $jsonData
}

# Add copy-fields similarly with JSON data structure (fill only needed ones)
$copyFieldJsons = @(
    '{ "add-copy-field": { "source": "job_link", "dest": "_text_" } }',
    '{ "add-copy-field": { "source": "job_title", "dest": "_text_" } }',
    '{ "add-copy-field": { "source": "company", "dest": ["_text_", "company_str", "hiringOrganization.name"] } }',
    '{ "add-copy-field": { "source": "hiringOrganization.name", "dest": "hiringOrganization.name_str" } }',
    '{ "add-copy-field": { "source": "country", "dest": "_text_" } }',
    '{ "add-copy-field": { "source": "city", "dest": "_text_" } }'
)

foreach ($copyJson in $copyFieldJsons) {
    Write-Host "Adding copy-field..."
    Invoke-PodmanCurl -container $CONTAINER_NAME -core $CORE_NAME_2 -jsonData $copyJson
}

# Add fields for logo core ($CORE_NAME_3)
# Example one url field:
$logoFieldJson = @"
{
  "add-field": [
    {
      "name": "url",
      "type": "text_general",
      "stored": true,
      "indexed": true,
      "multiValued": true,
      "uninvertible": true
    }
  ]
}
"@
Write-Host "Adding url field to core $CORE_NAME_3"
Invoke-PodmanCurl -container $CONTAINER_NAME -core $CORE_NAME_3 -jsonData $logoFieldJson

# Create security.json for authentication and copy into container
$securityFilePath = Join-Path $dir "security.json"
$securityJson = @"
{
  "authentication": {
    "blockUnknown": true,
    "class": "solr.BasicAuthPlugin",
    "credentials": { "solr": "IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c=" },
    "realm": "My Solr users",
    "forwardCredentials": false
  },
  "authorization": {
    "class": "solr.RuleBasedAuthorizationPlugin",
    "permissions": [ { "name": "security-edit", "role": "admin" } ],
    "user-role": { "solr": "admin" }
  }
}
"@
$securityJson | Set-Content -Path $securityFilePath -Encoding utf8 -Force

Write-Host "Copying security.json into Solr container and restarting container..."
podman cp $securityFilePath "$CONTAINER_NAME:/var/solr/data/security.json"
podman restart $CONTAINER_NAME

# Add SuggestComponent to jobs core
$suggestComponentJson = @"
{
  "add-searchcomponent": {
    "name": "suggest",
    "class": "solr.SuggestComponent",
    "suggester": {
      "name": "jobTitleSuggester",
      "lookupImpl": "FuzzyLookupFactory",
      "dictionaryImpl": "DocumentDictionaryFactory",
      "field": "job_title",
      "suggestAnalyzerFieldType": "text_general",
      "buildOnCommit": true,
      "buildOnStartup": false
    }
  }
}
"@
Invoke-PodmanCurl -container $CONTAINER_NAME -core $CORE_NAME_2 -jsonData $suggestComponentJson

$requestHandlerJson = @"
{
  "add-requesthandler": {
    "name": "/suggest",
    "class": "solr.SearchHandler",
    "startup": "lazy",
    "defaults": {
      "suggest": true,
      "suggest.dictionary": "jobTitleSuggester",
      "suggest.count": 10
    },
    "components": ["suggest"]
  }
}
"@
Invoke-PodmanCurl -container $CONTAINER_NAME -core $CORE_NAME_2 -jsonData $requestHandlerJson

# (Optional) Set ownership and permissions inside container if needed
# podman exec $CONTAINER_NAME chown solr:solr /var/solr/data/security.json
# podman exec $CONTAINER_NAME chmod 600 /var/solr/data/security.json

# Restart container after changes
podman restart $CONTAINER_NAME

Write-Host "Solr container setup completed."

# --- Java Installation for JMeter (Windows) ---
# You can optionally deploy OpenJDK 11 on Windows using Chocolatey here

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "Java not found. Installing OpenJDK 11 via Chocolatey..."
    choco install openjdk11 -y --no-progress
    Write-Host "Java installed."
}
else {
    Write-Host "Java is installed:"
    & java -version
}

# --- JMeter Installation on Windows ---

$JMETER_HOME = Join-Path $env:USERPROFILE "apache-jmeter-5.6.3"
if (-not (Test-Path $JMETER_HOME)) {
    Write-Host "Installing JMeter 5.6.3..."

    # Download archive
    $jmeterUrl = "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
    $zipFile = Join-Path $env:TEMP "apache-jmeter-5.6.3.zip"
    Invoke-WebRequest -Uri $jmeterUrl -OutFile $zipFile

    # Extract archive
    Expand-Archive -Path $zipFile -DestinationPath $env:USERPROFILE -Force

    Remove-Item $zipFile
    Write-Host "JMeter installed to $JMETER_HOME"
} else {
    Write-Host "JMeter already installed at $JMETER_HOME"
}

# Download plugins manager jars (adjust URLs if necessary)
$jmeterLibExt = Join-Path $JMETER_HOME "lib\ext"
$jmeterLib = Join-Path $JMETER_HOME "lib"

$pluginManagerJar = Join-Path $jmeterLibExt "jmeter-plugins-manager-1.10.jar"
$pluginManagerUrl = "https://jmeter-plugins.org/get/"

if (-not (Test-Path $pluginManagerJar)) {
    Write-Host "Downloading JMeter Plugins Manager..."
    Invoke-WebRequest -Uri $pluginManagerUrl -OutFile $pluginManagerJar
}

$cmdRunnerJar = Join-Path $jmeterLib "cmdrunner-2.3.jar"
$cmdRunnerUrl = "https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar"
if (-not (Test-Path $cmdRunnerJar)) {
    Write-Host "Downloading CmdRunner..."
    Invoke-WebRequest -Uri $cmdRunnerUrl -OutFile $cmdRunnerJar
}

# Run PluginManagerCMDInstaller
Write-Host "Installing JMeter Plugins Manager command-line tool..."
& java -cp "$pluginManagerJar" org.jmeterplugins.repository.PluginManagerCMDInstaller

# Install required plugins if needed, e.g., jpgc-functions
# You need to run something like:
# & "$JMETER_HOME\bin\PluginsManagerCMD.bat" install jpgc-functions
# (Adjust as per JMeter Windows installation)

Write-Host "You can now run JMeter with command: `"$JMETER_HOME\bin\jmeter.bat`""

# --- User creation and migration with Solr authentication ---
# Assuming $new_user and $new_pass provided as script parameters or prompt
if ($args.Count -ge 2) {
    $new_user = $args[0]
    $new_pass = $args[1]

    $old_user = "solr"
    $old_pass = "SolrRocks"

    # Create new Solr user
    $authUri = "http://localhost:$SOLR_PORT/solr/admin/authentication"
    $authJson = @{ "set-user" = @{ $new_user = $new_pass } } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $authUri -Method Post -Body $authJson -ContentType "application/json" -Credential (New-Object System.Management.Automation.PSCredential($old_user, (ConvertTo-SecureString $old_pass -AsPlainText -Force)))

    # Assign admin role
    $authzUri = "http://localhost:$SOLR_PORT/solr/admin/authorization"
    $authzJson = @{ "set-user-role" = @{ $new_user = @("admin") } } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $authzUri -Method Post -Body $authzJson -ContentType "application/json" -Credential (New-Object System.Management.Automation.PSCredential($old_user, (ConvertTo-SecureString $old_pass -AsPlainText -Force)))

    # Run migration script via JMeter
    $migrationJmx = Join-Path $dir "migration.jmx"
    & "$JMETER_HOME\bin\jmeter.bat" -n -t $migrationJmx -Duser=$new_user -Dpass=$new_pass

    # Delete old user
    $delJson = @{ "delete-user" = @($old_user) } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $authUri -Method Post -Body $delJson -ContentType "application/json" -Credential (New-Object System.Management.Automation.PSCredential($new_user, (ConvertTo-SecureString $new_pass -AsPlainText -Force)))

} else {
    Write-Warning "New Solr username and password not specified as script arguments. Skipping user creation and migration."
}

Write-Host "Script execution completed."

Write-Host " ================================================================="
Write-Host " ===================== IMPORTANT INFORMATIONS ===================="
Write-Host ""
Write-Host "SOLR is running on http://localhost:$SOLR_PORT/solr/"
Write-Host "UI is running on http://localhost:8081/"
Write-Host "swagger-ui is running on http://localhost:8081/swagger-ui/"
Write-Host "JMeter is installed and configured. you can start it with command: jmeter"
Write-Host "To run the migration script, use command:"
Write-Host "  jmeter -n -t $migrationJmx -Duser=<username> -Dpass=<password>"
Write-Host "Local username and password for SOLR: $new_user / [hidden]"
Write-Host "To manage Podman containers:"
Write-Host "  podman ps -a
podman images
podman logs <container_name>
podman inspect <container_name>"
Write-Host " ================================================================="
Write-Host " ===================== enjoy local environment ==================="
Write-Host " ====================== peviitor.ro =============================="
Write-Host " ================================================================="


# Cleanup local files if exist
Remove-Item "$dir\security.json" -ErrorAction SilentlyContinue
Remove-Item "$dir\jmeter.log" -ErrorAction SilentlyContinue

Write-Host " --> end of script execution  <-- "

# --- Open Google Chrome with the specified URLs ---
Write-Host "Launching Google Chrome with URLs..."

# Define Chrome path; adjust if installed elsewhere
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"

if (Test-Path $chromePath) {
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/api/v0/random"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8983/solr/#/jobs/query"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/swagger-ui"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/"
} else {
    Write-Warning "Google Chrome not found at '$chromePath'. Please open the URLs manually."
}

Write-Host "The execution of this script is now completed."
Write-Host "Press any key to exit..."
[void][System.Console]::ReadKey($true)
