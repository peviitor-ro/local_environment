# run.ps1
# Must be run as Administrator!

$ErrorActionPreference = "Stop"
$dir = Get-Location

function Is-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Is-Administrator)) {
    Write-Warning "This script must be run as Administrator. Please restart PowerShell as Administrator and re-run."
    exit 1
}

# --- Ensure WSL 2 is installed and enabled ---
function Ensure-WSL2 {
    Write-Host "Checking if WSL 2 is installed and enabled..."
    try {
        # Check if 'wsl.exe' exists and works
        $wslVersionInfo = wsl.exe --status 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "WSL not found or not enabled."
        }

        # Check if default WSL version is 2 or above
        $defaultVersionOutput = wsl.exe --list --verbose 2>&1
        $haveWSL2 = $false
        foreach ($line in $defaultVersionOutput) {
            if ($line -match '\d+\s+(\S+)\s+Running\s+(\d)') {
                if ([int]$matches[2] -ge 2) {
                    $haveWSL2 = $true
                    break
                }
            }
        }

        if ($haveWSL2) {
            Write-Host "WSL 2 is installed and enabled."
            return $true
        }
        else {
            Write-Warning "WSL is installed, but no distro is running version 2."
            Write-Host "Setting WSL default version to 2..."
            wsl --set-default-version 2
            return $true
        }
    }
    catch {
        Write-Warning "WSL 2 is not installed or enabled. Starting installation..."

        Write-Host "Enabling WSL and VirtualMachinePlatform features..."
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

        $kernelMsix = "$env:TEMP\wsl_update.msi"
        if (-not (Test-Path $kernelMsix)) {
            Write-Host "Downloading the latest WSL2 Linux kernel update package..."
            Invoke-WebRequest -Uri "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi" -OutFile $kernelMsix
        }
        Write-Host "Installing WSL kernel update..."
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$kernelMsix`" /quiet /norestart"

        Write-Host "Setting WSL default version to 2..."
        wsl --set-default-version 2 2>$null

        Write-Warning "WSL has been installed/enabled. The system must reboot for changes to take effect."
        Write-Host "The script will now reboot your computer automatically."

        if (Test-Path $kernelMsix) { Remove-Item $kernelMsix -Force }
        shutdown.exe /r /t 10 /c "Reboot required to complete WSL installation for Podman environment setup"
        exit 0
    }
}

Ensure-WSL2

# --- Install Chocolatey if missing ---
function Install-Chocolatey {
    Write-Host "Checking Chocolatey installation..."
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey not found. Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Host "Chocolatey installation completed."
        $env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"
    }
    else {
        Write-Host "Chocolatey is already installed."
    }
}

# --- Install Git if missing ---
function Ensure-Git {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Git is not installed. Installing Git via Chocolatey..."
        choco install git -y --no-progress
        Write-Host "Git installed."
    } else {
        Write-Host "Git is installed."
    }
}

# --- Install Podman on Windows ---
function Install-Podman {
    Write-Host "Checking Podman installation..."
    if (-not (Get-Command podman.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Podman not installed. Installing Podman..."

        $podmanInstallerUrl = "https://github.com/containers/podman/releases/download/v4.5.3/podman-4.5.3-windows.zip"
        $tempDir = "$env:TEMP\podman_install"
        $zipFile = "$tempDir\podman.zip"

        if (Test-Path $tempDir) { Remove-Item -Recurse -Force -Path $tempDir }
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        Write-Host "Downloading Podman from $podmanInstallerUrl ..."
        Invoke-WebRequest -Uri $podmanInstallerUrl -OutFile $zipFile

        Write-Host "Extracting Podman..."
        Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force

        $podmanExePathCandidate = Get-ChildItem -Path $tempDir -Recurse -Filter "podman.exe" | Select-Object -First 1 -ExpandProperty FullName

        if (-not $podmanExePathCandidate) {
            Write-Error "Failed to find podman.exe after extraction."
            exit 1
        }

        $installDir = "C:\Program Files\Podman"
        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir | Out-Null
        }

        Write-Host "Copying Podman binaries to $installDir..."
        Copy-Item -Path (Join-Path $tempDir '*') -Destination $installDir -Recurse -Force

        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if (-not $machinePath.Split(";") -contains $installDir) {
            $newPath = "$machinePath;$installDir"
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        }
        if (-not $env:PATH.Split(";") -contains $installDir) {
            $env:PATH += ";$installDir"
        }

        $machines = & podman machine list --format "{{.Name}}" 2>$null
        if (-not $machines -or $machines.Count -eq 0) {
            Write-Host "Initializing Podman machine..."
            & podman machine init
        }
        else {
            Write-Host "Podman machine already initialized."
        }

        Write-Host "Starting Podman machine..."
        & podman machine start

        Remove-Item -Recurse -Force $tempDir
        Write-Host "Podman was installed and initialized successfully."
        Start-Sleep -Seconds 5
    }
    else {
        Write-Host "Podman is already installed."
        $machineStatus = podman machine list --format '{{.Name}} {{.Running}}'
        if ($machineStatus -notmatch "true") {
            Write-Host "Starting Podman machine..."
            podman machine start
            Start-Sleep -Seconds 5
        }
    }
}

# --- Password validation function ---
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

Install-Chocolatey
Ensure-Git
Install-Podman

# Prompt mandatory Solr username/password (login credentials)
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
        Write-Warning "Password must be at least 15 characters OR contain lowercase, uppercase, digit, and special (!@#$%^&*_-[]()). Please try again."
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
if (-not (Test-Path $TARGET_DIR)) {
    New-Item -ItemType Directory -Path $TARGET_DIR | Out-Null
}

Expand-Archive -Path $TMP_FILE -DestinationPath $TARGET_DIR -Force
Remove-Item $TMP_FILE

$htaccessPath = Join-Path $TARGET_DIR "build\.htaccess"
if (Test-Path $htaccessPath) {
    Write-Host "Removing $htaccessPath"
    Remove-Item $htaccessPath
}

Write-Host "Cloning API repo to $TARGET_DIR\build\api"
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git "$TARGET_DIR\build\api"

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

Write-Host "Starting apache-container with Podman..."
podman run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 `
    -v "$TARGET_DIR\build:/var/www/html" alexstefan1702/php-apache

Write-Host "Updating swagger-ui URL inside apache-container..."
podman exec apache-container sh -c "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:8081/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js"
podman restart apache-container

### Solr container setup
$CORE_NAME = "auth"
$CORE_NAME_2 = "jobs"
$CORE_NAME_3 = "logo"
$CONTAINER_NAME = "solr-container"
$SOLR_PORT = 8983

$solrDataHostPath = Join-Path $env:USERPROFILE "peviitor\solr\core\data"
if (-not (Test-Path $solrDataHostPath)) {
    Write-Host "Creating Solr data directory at $solrDataHostPath"
    New-Item -ItemType Directory -Path $solrDataHostPath -Force | Out-Null
}

Write-Host "Starting Solr container on port $SOLR_PORT using Podman..."
podman run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always `
    -d -p $SOLR_PORT:$SOLR_PORT `
    -v "$solrDataHostPath:/var/solr/data:Z" `
    solr:latest

Write-Host "Waiting for Solr to start (15 seconds)..."
Start-Sleep -Seconds 15

Write-Host "Creating Solr cores: $CORE_NAME, $CORE_NAME_2, $CORE_NAME_3"
foreach ($core in @($CORE_NAME, $CORE_NAME_2, $CORE_NAME_3)) {
    podman exec $CONTAINER_NAME bin/solr create_core -c $core
}

function Invoke-PodmanCurl ($container, $core, $jsonData) {
    $jsonStr = $jsonData -replace "`n|\r", ""
    podman exec $container curl -X POST -H "Content-Type: application/json" --data "$jsonStr" "http://localhost:$SOLR_PORT/solr/$core/schema"
}

Write-Host "Adding fields to Solr core $CORE_NAME_2 (jobs)..."

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

podman restart $CONTAINER_NAME

Write-Host "Solr container setup completed."

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "Java not found. Installing OpenJDK 11 via Chocolatey..."
    choco install openjdk11 -y --no-progress
    Write-Host "Java installed."
}
else {
    Write-Host "Java installed:"
    & java -version
}

$JMETER_HOME = Join-Path $env:USERPROFILE "apache-jmeter-5.6.3"
if (-not (Test-Path $JMETER_HOME)) {
    Write-Host "Installing JMeter 5.6.3..."

    $jmeterUrl = "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
    $zipFile = Join-Path $env:TEMP "apache-jmeter-5.6.3.zip"
    Invoke-WebRequest -Uri $jmeterUrl -OutFile $zipFile

    Expand-Archive -Path $zipFile -DestinationPath $env:USERPROFILE -Force
    Remove-Item $zipFile
    Write-Host "JMeter installed to $JMETER_HOME"
} else {
    Write-Host "JMeter already installed at $JMETER_HOME"
}

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

Write-Host "Installing JMeter Plugins Manager command-line tool..."
& java -cp "$pluginManagerJar" org.jmeterplugins.repository.PluginManagerCMDInstaller

Write-Host "You can now run JMeter with command: `"$JMETER_HOME\bin\jmeter.bat`""

# --- Mandatory interactive input for new Solr user and password ---

Write-Host "Please enter the new Solr username (mandatory):"
while ($true) {
    $new_user = Read-Host "New Solr username"
    if ([string]::IsNullOrWhiteSpace($new_user)) {
        Write-Warning "Username cannot be empty. Please enter a valid username."
    }
    else {
        break
    }
}

Write-Host "Please enter the new Solr password (mandatory, input hidden):"
while ($true) {
    $secNewPass = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secNewPass)
    $new_pass_unsecure = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    if (Validate-Password $new_pass_unsecure) {
        Write-Host "Password accepted."
        break
    } else {
        Write-Warning "Password must be at least 15 characters long OR contain lowercase, uppercase, digit, and special (!@#$%^&*_-[]()). Please try again."
    }
}

$old_user = "solr"
$old_pass = "SolrRocks"

$secOldPass = ConvertTo-SecureString $old_pass -AsPlainText -Force
$credOld = New-Object System.Management.Automation.PSCredential($old_user, $secOldPass)

$authUri = "http://localhost:$SOLR_PORT/solr/admin/authentication"
$authJson = @{ "set-user" = @{ $new_user = $new_pass_unsecure } } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri $authUri -Method Post -Body $authJson -ContentType "application/json" -Credential $credOld

$authzUri = "http://localhost:$SOLR_PORT/solr/admin/authorization"
$authzJson = @{ "set-user-role" = @{ $new_user = @("admin") } } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri $authzUri -Method Post -Body $authzJson -ContentType "application/json" -Credential $credOld

$migrationJmx = Join-Path $dir "migration.jmx"
& "$JMETER_HOME\bin\jmeter.bat" -n -t $migrationJmx -Duser=$new_user -Dpass=$new_pass_unsecure

$secNewPass2 = ConvertTo-SecureString $new_pass_unsecure -AsPlainText -Force
$credNew = New-Object System.Management.Automation.PSCredential($new_user, $secNewPass2)

$delJson = @{ "delete-user" = @($old_user) } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri $authUri -Method Post -Body $delJson -ContentType "application/json" -Credential $credNew

Write-Host "Script execution completed."

Write-Host " ================================================================="
Write-Host " ===================== IMPORTANT INFORMATIONS ===================="
Write-Host ""
Write-Host "SOLR is running on http://localhost:$SOLR_PORT/solr/"
Write-Host "UI is running on http://localhost:8081/"
Write-Host "swagger-ui is running on http://localhost:8081/swagger-ui/"
Write-Host "JMeter is installed and configured. You can start it with command: jmeter"
Write-Host "To run the migration script, use:"
Write-Host "  jmeter -n -t $migrationJmx -Duser=<username> -Dpass=<password>"
Write-Host "Local username and password for SOLR: $new_user / [hidden]"
Write-Host "To manage Podman containers, use:"
Write-Host "  podman ps -a"
Write-Host "  podman images"
Write-Host "  podman logs <container_name>"
Write-Host "  podman inspect <container_name>"
Write-Host " ================================================================="
Write-Host " ===================== enjoy local environment ==================="
Write-Host " ====================== peviitor.ro =============================="
Write-Host " ================================================================="

# Cleanup temp files
Remove-Item "$dir\security.json" -ErrorAction SilentlyContinue
Remove-Item "$dir\jmeter.log" -ErrorAction SilentlyContinue

Write-Host " --> end of script execution  <-- "

Write-Host "Launching Google Chrome with URLs..."
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (Test-Path $chromePath) {
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/api/v0/random"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8983/solr/#/jobs/query"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/swagger-ui"
    Start-Process -FilePath $chromePath -ArgumentList "http://localhost:8081/"
}
else {
    Write-Warning "Google Chrome not found at '$chromePath'. Please open the URLs manually."
}

Write-Host "The execution of this script is now completed."
Write-Host "Press any key to exit..."
[void][System.Console]::ReadKey($true)

exit 0