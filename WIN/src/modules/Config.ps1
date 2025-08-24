# Config.ps1 - Configuration parameters and hardcoded values
# This module contains all configurable parameters for the Peviitor installer
# All hardcoded values from the original bash scripts are centralized here

# Global configuration hashtable
$Global:PeviitorConfig = @{
    
    # ============================================================================
    # NETWORK CONFIGURATION
    # ============================================================================
    Network = @{
        Name = "mynetwork"
        Subnet = "172.168.0.0/16"
        SolrIP = "172.168.0.10"
        ApacheIP = "172.168.0.11"
    }
    
    # ============================================================================
    # PORT CONFIGURATION
    # ============================================================================
    Ports = @{
        Solr = 8983
        Apache = 8081
        ApacheInternal = 80
    }
    
    # ============================================================================
    # CONTAINER CONFIGURATION
    # ============================================================================
    Containers = @{
        Solr = @{
            Name = "solr-container"
            Image = "solr:latest"
            IP = "172.168.0.10"
            Port = "8983:8983"
            RestartPolicy = "always"
        }
        Apache = @{
            Name = "apache-container"
            Image = "alexstefan1702/php-apache"
            IP = "172.168.0.11"
            Port = "8081:80"
            RestartPolicy = "always"
        }
        # Additional containers that might be cleaned up
        DataMigration = "data-migration"
        DeployFE = "deploy-fe"
    }
    
    # ============================================================================
    # SOLR CONFIGURATION
    # ============================================================================
    Solr = @{
        Cores = @("auth", "jobs", "logo", "firme")
        DefaultUser = "solr"
        DefaultPassword = "SolrRocks"
        SecurityFile = "security.json"
        # Pre-configured credentials hash for security.json
        DefaultCredentialsHash = "IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c="
    }
    
    # ============================================================================
    # GITHUB REPOSITORIES
    # ============================================================================
    Repositories = @{
        SearchEngine = @{
            Owner = "peviitor-ro"
            Repo = "search-engine"
            Branch = "main"
            URL = "https://github.com/peviitor-ro/search-engine.git"
            AssetName = "build.zip"
        }
        API = @{
            Owner = "peviitor-ro"
            Repo = "api"
            Branch = "master"
            URL = "https://github.com/peviitor-ro/api.git"
        }
    }
    
    # ============================================================================
    # SERVER CONFIGURATION
    # ============================================================================
    Servers = @{
        LocalSolr = "172.168.0.10:8983"
        ProdServer = "zimbor.go.ro"
        BackendServer = "https://api.laurentiumarian.ro/"
        SwaggerUIPort = 8081
    }
    
    # ============================================================================
    # FILE PATHS AND DIRECTORIES
    # ============================================================================
    Paths = @{
        Base = "$env:USERPROFILE\peviitor"
        Build = "$env:USERPROFILE\peviitor\build"
        API = "$env:USERPROFILE\peviitor\build\api"
        SolrData = "$env:USERPROFILE\peviitor\solr\core\data"
        Logs = ".\peviitor-installer.log"
        TempDownload = "$env:TEMP\peviitor-downloads"
    }
    
    # ============================================================================
    # MINIMUM SYSTEM REQUIREMENTS
    # ============================================================================
    Requirements = @{
        PowerShell = @{
            Major = 5
            Minor = 1
            Description = "PowerShell 5.1 or higher"
        }
        Windows = @{
            MinBuild = 19041
            Description = "Windows 10 build 19041 (20H1) or Windows 11"
        }
        Hardware = @{
            RAM_GB = 8
            DiskSpace_GB = 20
            Description = "8GB RAM and 20GB free disk space"
        }
        Network = @{
            TestHosts = @("github.com", "download.docker.com", "registry-1.docker.io")
            TestPort = 443
            Description = "Internet connectivity to GitHub and Docker Hub"
        }
    }
    
    # ============================================================================
    # SOFTWARE DEPENDENCIES AND VERSIONS
    # ============================================================================
    Dependencies = @{
        DockerDesktop = @{
            MinVersion = "4.0.0"
            DownloadURL = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
            InstallArgs = @("install", "--quiet", "--accept-license")
        }
        Git = @{
            MinVersion = "2.30.0"
            WingetID = "Git.Git"
            ChocolateyID = "git"
        }
        Java = @{
            MinVersion = "11.0.0"
            WingetID = "Microsoft.OpenJDK.11"
            ChocolateyID = "openjdk11"
            RequiredFor = "JMeter execution"
        }
        JMeter = @{
            Version = "5.6.3"
            DownloadURL = "https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
            InstallPath = "$env:ProgramFiles\Apache\JMeter"
            RequiredPlugins = @("jpgc-functions")
            PluginsManagerURL = "https://jmeter-plugins.org/get/"
            CmdRunnerURL = "https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar"
        }
    }
    
    # ============================================================================
    # API ENVIRONMENT CONFIGURATION
    # ============================================================================
    API = @{
        EnvFile = "api.env"
        Configuration = @{
            LOCAL_SERVER = "172.168.0.10:8983"
            PROD_SERVER = "zimbor.go.ro"
            BACK_SERVER = "https://api.laurentiumarian.ro/"
            # SOLR_USER and SOLR_PASS will be set dynamically
        }
    }
    
    # ============================================================================
    # JMETER SCRIPTS AND DATA MIGRATION
    # ============================================================================
    JMeter = @{
        Scripts = @{
            Migration = "migration.jmx"
            Firme = "firme.jmx"
        }
        ExecutionTimeout = 300  # 5 minutes timeout for each script
    }
    
    # ============================================================================
    # SOLR SCHEMA FIELDS CONFIGURATION
    # ============================================================================
    SolrSchema = @{
        JobsCore = @{
            Fields = @(
                @{ name = "job_link"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "job_title"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "company"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "company_str"; type = "string"; stored = $true; indexed = $true; docValues = $true }
                @{ name = "hiringOrganization.name"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "country"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "city"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "county"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
            )
            CopyFields = @(
                @{ source = "job_link"; dest = "_text_" }
                @{ source = "job_title"; dest = "_text_" }
                @{ source = "company"; dest = @("_text_", "company_str", "hiringOrganization.name") }
                @{ source = "country"; dest = "_text_" }
                @{ source = "city"; dest = "_text_" }
            )
            SuggestComponent = @{
                name = "jobTitleSuggester"
                field = "job_title"
                lookupImpl = "FuzzyLookupFactory"
                dictionaryImpl = "DocumentDictionaryFactory"
            }
        }
        LogoCore = @{
            Fields = @(
                @{ name = "url"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
            )
        }
        FirmeCore = @{
            Fields = @(
                @{ name = "cui"; type = "plongs"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "stare"; type = "text_general"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "cod_postal"; type = "plongs"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "cod_stare"; type = "plongs"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "sector"; type = "plongs"; stored = $true; indexed = $true; multiValued = $true }
                @{ name = "brands"; type = "string"; stored = $true; indexed = $true; multiValued = $true }
            )
            CopyFields = @(
                @{ source = "sector"; dest = "_text_" }
                @{ source = "brands"; dest = "_text_" }
                @{ source = "denumire"; dest = "_text_" }
                @{ source = "stare"; dest = "_text_" }
                @{ source = "id"; dest = "_text_" }
            )
        }
    }
    
    # ============================================================================
    # BROWSER LAUNCH CONFIGURATION
    # ============================================================================
    Browser = @{
        URLs = @(
            @{ 
                Name = "Peviitor UI"
                URL = "http://localhost:8081/"
                Description = "Main Peviitor user interface"
            }
            @{ 
                Name = "Solr Admin"
                URL = "http://localhost:8983/solr/"
                Description = "Apache Solr administration panel"
            }
            @{ 
                Name = "API Documentation"
                URL = "http://localhost:8081/swagger-ui/"
                Description = "Swagger API documentation"
            }
        )
        LaunchDelay = 5  # Wait 5 seconds before launching browser
    }
    
    # ============================================================================
    # INSTALLER METADATA
    # ============================================================================
    Installer = @{
        Name = "Peviitor Local Environment Installer"
        Version = "1.0.0"  # Will be replaced during build
        Author = "Peviitor.ro Team"
        Repository = "https://github.com/peviitor-ro/installer"
        SupportURL = "https://github.com/peviitor-ro/installer/issues"
        UpdateCheckURL = "https://api.github.com/repos/peviitor-ro/installer/releases/latest"
    }
    
    # ============================================================================
    # CLEANUP CONFIGURATION
    # ============================================================================
    Cleanup = @{
        Containers = @("apache-container", "solr-container", "data-migration", "deploy-fe")
        Networks = @("mynetwork")
        Directories = @("$env:USERPROFILE\peviitor")
        TempDirectories = @("$env:TEMP\peviitor-downloads")
        # Whether to remove Docker Desktop during uninstall (default: false)
        RemoveDockerDesktop = $false
        RemoveJava = $false
        RemoveGit = $false
        RemoveJMeter = $false
    }
}

# ============================================================================
# CONFIGURATION VALIDATION FUNCTIONS
# ============================================================================

function Test-PeviitorConfig {
    <#
    .SYNOPSIS
    Validates the Peviitor configuration for consistency and completeness.
    
    .DESCRIPTION
    Performs validation checks on the configuration to ensure all required
    values are present and properly formatted.
    #>
    
    $issues = @()
    
    # Validate required sections
    $requiredSections = @('Network', 'Ports', 'Containers', 'Repositories', 'Requirements')
    foreach ($section in $requiredSections) {
        if (-not $Global:PeviitorConfig.ContainsKey($section)) {
            $issues += "Missing required configuration section: $section"
        }
    }
    
    # Validate network configuration
    if ($Global:PeviitorConfig.Network) {
        $network = $Global:PeviitorConfig.Network
        if (-not $network.Subnet -match '^\d+\.\d+\.\d+\.\d+\/\d+$') {
            $issues += "Invalid subnet format: $($network.Subnet)"
        }
    }
    
    # Validate port ranges
    if ($Global:PeviitorConfig.Ports) {
        $ports = $Global:PeviitorConfig.Ports
        foreach ($portName in $ports.Keys) {
            $port = $ports[$portName]
            if ($port -lt 1 -or $port -gt 65535) {
                $issues += "Invalid port number for ${portName}: $port"
            }
        }
    }
    
    if ($issues.Count -gt 0) {
        Write-Warning "Configuration validation issues found:"
        foreach ($issue in $issues) {
            Write-Warning "  - $issue"
        }
        return $false
    }
    
    return $true
}

function Get-PeviitorConfigValue {
    <#
    .SYNOPSIS
    Retrieves a configuration value using dot notation.
    
    .PARAMETER Path
    The configuration path (e.g., "Network.SolrIP")
    
    .PARAMETER Default
    Default value if the path is not found
    
    .EXAMPLE
    Get-PeviitorConfigValue -Path "Ports.Solr" -Default 8983
    #>
    param(
        [string]$Path,
        $Default = $null
    )
    
    $parts = $Path -split '\.'
    $current = $Global:PeviitorConfig
    
    foreach ($part in $parts) {
        if ($current -is [hashtable] -and $current.ContainsKey($part)) {
            $current = $current[$part]
        } else {
            return $Default
        }
    }
    
    return $current
}

# ============================================================================
# MODULE INITIALIZATION
# ============================================================================

# Validate configuration on module load
if (-not (Test-PeviitorConfig)) {
    Write-Error "Configuration validation failed. Please check the configuration values."
}

# Configuration is ready for use
Write-Verbose "Peviitor configuration loaded successfully"