# configure-solr.ps1
# Purpose: Configure Solr container, cores, schema without authentication

param(
    [string]$NetworkName = "mynetwork",
    [string]$SolrContainerName = "solr-container",
    [string]$SolrImage = "solr:latest",
    [string]$SolrIp = "172.168.0.10",
    [int]$SolrPort = 8983,
    [string]$AuthCore = "auth",
    [string]$JobsCore = "jobs",
    [string]$LogoCore = "logo",
    [string]$FirmeCore = "firme",
    [string]$InitUser,
    [string]$InitPass
)

$ErrorActionPreference = "Stop"

Write-Host "Configuring Solr container '$SolrContainerName' on port $SolrPort..."

# Start container if not present; otherwise ensure running
$existing = & podman ps -aq -f "name=$SolrContainerName"
if (-not $existing) {
    Write-Host "Starting Solr container using image $SolrImage..."
    & podman run --name $SolrContainerName --network $NetworkName --ip $SolrIp --restart=always `
        -d -p ${SolrPort}:${SolrPort} `
        $SolrImage | Out-Null
} else {
    Write-Host "Solr container exists. Ensuring it is running..."
    $isRunning = (& podman ps -q -f "name=$SolrContainerName")
    if (-not $isRunning) { & podman start $SolrContainerName | Out-Null }
}

Write-Host "Waiting for Solr to start (up to 60 seconds)..."
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$SolrPort/solr/admin/info/system" -UseBasicParsing -TimeoutSec 5
        if ($resp.StatusCode -eq 200) { 
            $ready = $true
            Write-Host "Solr is ready!"
            break 
        }
    } catch {}
    
    if ($i % 10 -eq 0 -and $i -gt 0) {
        Write-Host "Still waiting... ($i seconds)"
    }
    Start-Sleep -Seconds 1
}

if (-not $ready) { 
    Write-Error "Solr failed to start within 60 seconds"
    exit 1
}

# Create cores
Write-Host "Creating Solr cores: $AuthCore, $JobsCore, $LogoCore, $FirmeCore"
$cores = @($AuthCore, $JobsCore, $LogoCore, $FirmeCore)
foreach ($core in $cores) {
    try {
        & podman exec $SolrContainerName bin/solr create_core -c $core | Out-Null
        Write-Host "  Core '$core' created"
    } catch {
        Write-Host "  Core '$core' already exists"
    }
}

# Configure jobs core schema
Write-Host "Configuring jobs core schema..."
$jobsFields = @(
    @{name="job_link"; type="text_general"},
    @{name="job_title"; type="text_general"},
    @{name="company"; type="text_general"},
    @{name="company_str"; type="string"},
    @{name="hiringOrganization.name"; type="text_general"},
    @{name="country"; type="text_general"},
    @{name="city"; type="text_general"},
    @{name="county"; type="text_general"}
)

foreach ($field in $jobsFields) {
    try {
        $jsonData = @{
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
        
        Invoke-RestMethod -Uri "http://localhost:$SolrPort/solr/$JobsCore/schema" -Method Post -Body $jsonData -ContentType "application/json" | Out-Null
        Write-Host "  Added field: $($field.name)"
    } catch {
        Write-Host "  Field $($field.name) may already exist"
    }
}

# Add copy field rules for jobs core
Write-Host "Adding copy field rules for jobs core..."
$copyRules = @(
    @{source="job_link"; dest="_text_"},
    @{source="job_title"; dest="_text_"},
    @{source="company"; dest=@("_text_", "company_str", "hiringOrganization.name")},
    @{source="hiringOrganization.name"; dest="hiringOrganization.name_str"},
    @{source="country"; dest="_text_"},
    @{source="city"; dest="_text_"}
)

foreach ($rule in $copyRules) {
    try {
        $jsonData = @{
            "add-copy-field" = @{
                source = $rule.source
                dest = $rule.dest
            }
        } | ConvertTo-Json -Depth 3 -Compress
        
        Invoke-RestMethod -Uri "http://localhost:$SolrPort/solr/$JobsCore/schema" -Method Post -Body $jsonData -ContentType "application/json" | Out-Null
        Write-Host "  Added copy rule: $($rule.source) -> $($rule.dest)"
    } catch {
        Write-Host "  Copy rule for $($rule.source) may already exist"
    }
}

# Configure firme core schema
Write-Host "Configuring firme core schema..."
$firmeFields = @(
    @{name="cui"; type="plongs"},
    @{name="stare"; type="text_general"},
    @{name="cod_postal"; type="plongs"},
    @{name="cod_stare"; type="plongs"},
    @{name="sector"; type="plongs"},
    @{name="brands"; type="string"},
    @{name="denumire"; type="text_general"}
)

foreach ($field in $firmeFields) {
    try {
        $jsonData = @{
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
        
        Invoke-RestMethod -Uri "http://localhost:$SolrPort/solr/$FirmeCore/schema" -Method Post -Body $jsonData -ContentType "application/json" | Out-Null
        Write-Host "  Added firme field: $($field.name)"
    } catch {
        Write-Host "  Firme field $($field.name) may already exist"
    }
}

# Configure logo core
Write-Host "Configuring logo core schema..."
try {
    $jsonData = @{
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
    
    Invoke-RestMethod -Uri "http://localhost:$SolrPort/solr/$LogoCore/schema" -Method Post -Body $jsonData -ContentType "application/json" | Out-Null
    Write-Host "  Added logo field: url"
} catch {
    Write-Host "  Logo field 'url' may already exist"
}

Write-Host "Solr container setup completed successfully!"
Write-Host "Solr is running without authentication at: http://localhost:$SolrPort/solr/"
Write-Host "Ready for JMeter data migration."

exit 0