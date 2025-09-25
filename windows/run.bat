@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem =================================================================
rem ================= Local Environment Installer =================
rem ====================== peviitor.ro ============================
rem =================================================================

rem --- Admin check ---
>nul 2>&1 net session || (
    echo ERROR: This script must be run as Administrator.
    pause & exit /b 1
)

rem --- Initialize variables ---
set "POWERSHELL=powershell -NoProfile -ExecutionPolicy Bypass -Command"
set "PEVIITOR_DIR=%USERPROFILE%\peviitor"
set "SOLR_PORT=8983"
set "RESTART_REQUIRED="

rem --- Helper functions ---
goto :main

:handle_error
echo ERROR: %~1
if "%~2" neq "" type "%~2" & del "%~2" 2>nul
pause & exit /b 1

:install_tool
where %1 >nul 2>&1 && (echo %1 already installed.) || (
    echo Installing %1...
    %2
    if errorlevel 1 call :handle_error "%1 installation failed"
)
goto :eof

:check_restart
if defined RESTART_REQUIRED (
    choice /C YN /M "Restart required. Restart now?"
    if errorlevel 2 (
        echo Please restart manually and run this script again.
        pause & exit /b 1
    ) else (
        echo Restarting in 10 seconds...
        shutdown /r /t 10 /c "Restarting to complete installation"
        exit /b 0
    )
)
goto :eof

:validate_password
set "_pwd=%~1"
set "_len=0"
setlocal enabledelayedexpansion
for /l %%i in (0,1,100) do if "!_pwd:~%%i,1!" neq "" set /a _len+=1
if !_len! geq 15 endlocal & exit /b 0
echo !_pwd!| findstr /r "^.*[a-z].*[A-Z].*[0-9].*[!@#$%%^&*_\-\[\]\(\)].*$" >nul && (
    endlocal & exit /b 0
) || (
    endlocal & exit /b 1
)

:run_with_log
%~1 >"%TEMP%\%~2.log" 2>&1
if errorlevel 1 call :handle_error "%~3" "%TEMP%\%~2.log"
del "%TEMP%\%~2.log" 2>nul
goto :eof

:main
rem --- Create workspace ---
if not exist "%PEVIITOR_DIR%" mkdir "%PEVIITOR_DIR%"

rem --- Check WSL installation ---
echo Checking WSL installation...
where wsl.exe >nul 2>&1 || (
    echo Installing WSL...
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul
    
    set "KERNEL_MSI=%TEMP%\wsl_update.msi"
    %POWERSHELL% "Invoke-WebRequest -Uri 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' -OutFile '!KERNEL_MSI!' -UseBasicParsing"
    start /wait msiexec.exe /i "!KERNEL_MSI!" /quiet /norestart
    del /f /q "!KERNEL_MSI!" 2>nul
    
    wsl --set-default-version 2 >nul 2>&1
    set "RESTART_REQUIRED=1"
)

rem --- Check WSL distro ---
wsl --list --quiet >nul 2>&1 || (
    echo Installing Ubuntu...
    wsl --install -d Ubuntu
    set "RESTART_REQUIRED=1"
)

call :check_restart

rem --- Install required tools ---
call :install_tool choco "%POWERSHELL% \"[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))\""
call :install_tool git "choco install git -y --no-progress"

rem --- Install Podman ---
where podman >nul 2>&1 || (
    echo Installing Podman...
    where winget >nul 2>&1 && (
        winget install -e --id RedHat.Podman --accept-source-agreements --accept-package-agreements || call :handle_error "Podman installation failed"
    ) || call :handle_error "winget not available. Please install Podman manually from https://podman.io/getting-started/installation"
    
    set "PODMAN_DIR=C:\Program Files\RedHat\Podman"
    if exist "!PODMAN_DIR!\podman.exe" (
        setx PATH "%PATH%;!PODMAN_DIR!" /M >nul
        set "PATH=%PATH%;!PODMAN_DIR!"
    )
    timeout /t 5 /nobreak >nul
)


rem --- Setup Podman machine ---
wsl --set-default-version 2 >nul 2>&1
echo Setting up Podman machine...

for /f "delims=" %%M in ('podman machine list --format "{{.Name}}" 2^>nul') do set "PM_NAME=%%M"
if not defined PM_NAME (
    call :run_with_log "podman machine init --cpus 2 --memory 2048 --disk-size 20" "podman_init" "Failed to initialize Podman machine"
)

for /f "delims=" %%R in ('podman machine list --format "{{.Running}}" 2^>nul') do if "%%R"=="true" set "MACHINE_RUNNING=1"
if not defined MACHINE_RUNNING (
    call :run_with_log "podman machine start" "podman_start" "Failed to start Podman machine"
)

call :run_with_log "podman version" "podman_verify" "Podman verification failed"
echo Podman setup completed.

rem --- Get Solr credentials ---
echo.
echo =================================================================
echo Please provide Solr credentials
echo =================================================================

set /p SOLR_USER=Enter Solr username: 
:get_password
%POWERSHELL% "[Console]::Error.Write('Enter Solr password (hidden): '); $pwd = Read-Host -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)" > "%TEMP%\pwd.txt"
set /p SOLR_PASS=<"%TEMP%\pwd.txt"
del "%TEMP%\pwd.txt" 2>nul

call :validate_password "%SOLR_PASS%"
if errorlevel 1 (
    echo Password must be 15+ characters OR contain lowercase, uppercase, digit, and special chars. Try again.
    goto get_password
)

echo Credentials accepted: %SOLR_USER% / [hidden]

rem --- Clean workspace ---
if exist "%PEVIITOR_DIR%" rmdir /s /q "%PEVIITOR_DIR%"

rem --- Clean containers and network ---
echo Cleaning up containers...
for %%C in (apache-container solr-container data-migration deploy-fe) do (
    for /f "usebackq delims=" %%I in (`podman ps -aq -f "name=%%C" 2^>nul`) do (
        if not "%%I"=="" podman stop %%I >nul 2>&1 & podman rm %%I >nul 2>&1
    )
)

for /f "delims=" %%N in ('podman network ls --format "{{.Name}}" 2^>nul') do (
    if "%%N"=="mynetwork" podman network rm mynetwork >nul 2>&1
)

call :run_with_log "podman network create --subnet=172.168.0.0/16 mynetwork" "network_create" "Failed to create network"

rem --- Download and setup project ---
echo Downloading latest build...
set "REPO=peviitor-ro/search-engine"
for /f "usebackq delims=" %%U in (`%POWERSHELL% "$r = Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/releases/latest'; ($r.assets | ? name -eq 'build.zip').browser_download_url"`) do set "DOWNLOAD_URL=%%U"

if not defined DOWNLOAD_URL call :handle_error "Could not find build.zip in latest release"

set "TMP_FILE=%TEMP%\build.zip"
%POWERSHELL% "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TMP_FILE%'"
if not exist "%PEVIITOR_DIR%" mkdir "%PEVIITOR_DIR%"
%POWERSHELL% "Expand-Archive -Path '%TMP_FILE%' -DestinationPath '%PEVIITOR_DIR%' -Force"
del /f /q "%TMP_FILE%" 2>nul

if exist "%PEVIITOR_DIR%\build\.htaccess" del /f /q "%PEVIITOR_DIR%\build\.htaccess"

git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git "%PEVIITOR_DIR%\build\api"

rem --- Create API config ---
(
    echo LOCAL_SERVER = 172.168.0.10:8983
    echo PROD_SERVER = zimbor.go.ro
    echo BACK_SERVER = https://api.laurentiumarian.ro/
    echo SOLR_USER = %SOLR_USER%
    echo SOLR_PASS = %SOLR_PASS%
) > "%PEVIITOR_DIR%\build\api\api.env"

rem --- Start containers ---
echo Starting containers...

rem Apache setup
set "APACHE_DOCROOT=%PEVIITOR_DIR%\build"
if exist "%PEVIITOR_DIR%\build\build\index.html" set "APACHE_DOCROOT=%PEVIITOR_DIR%\build\build"

podman run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 -v "%APACHE_DOCROOT%:/var/www/html" alexstefan1702/php-apache >"%TEMP%\apache_start.log" 2>&1
if errorlevel 1 call :handle_error "Failed to start Apache container" "%TEMP%\apache_start.log"
del "%TEMP%\apache_start.log" 2>nul

podman exec apache-container sh -c "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:8081/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js" >nul 2>&1
podman restart apache-container >nul 2>&1

rem Solr setup
%POWERSHELL% "& '%~dp0configure-solr.ps1' -NetworkName 'mynetwork' -SolrContainerName 'solr-container' -SolrIp '172.168.0.10' -SolrPort %SOLR_PORT% -AuthCore 'auth' -JobsCore 'jobs' -LogoCore 'logo' -FirmeCore 'firme' -InitUser '%SOLR_USER%' -InitPass '%SOLR_PASS%'"
if errorlevel 1 call :handle_error "Solr configuration failed"

rem --- Install Java and JMeter ---
call :install_tool java "choco install openjdk11 -y --no-progress"

set "JMETER_HOME=%USERPROFILE%\apache-jmeter-5.6.3"
if not exist "%JMETER_HOME%" (
    echo Installing JMeter...
    set "JMETER_URL=https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
    set "ZIPFILE=%TEMP%\apache-jmeter-5.6.3.zip"
    
    %POWERSHELL% "Invoke-WebRequest -Uri '!JMETER_URL!' -OutFile '!ZIPFILE!'"
    %POWERSHELL% "Expand-Archive -Path '!ZIPFILE!' -DestinationPath '%USERPROFILE%' -Force"
    del /f /q "!ZIPFILE!" 2>nul
    
    rem Download JMeter plugins
    %POWERSHELL% "Invoke-WebRequest -Uri 'https://jmeter-plugins.org/get/' -OutFile '%JMETER_HOME%\lib\ext\jmeter-plugins-manager-1.10.jar'"
    %POWERSHELL% "Invoke-WebRequest -Uri 'https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar' -OutFile '%JMETER_HOME%\lib\cmdrunner-2.3.jar'"
    java -cp "%JMETER_HOME%\lib\ext\jmeter-plugins-manager-1.10.jar" org.jmeterplugins.repository.PluginManagerCMDInstaller
)

rem --- Wait for Solr and run migration ---
echo Waiting for Solr...
for /L %%I in (1,1,30) do (
    curl -s "http://localhost:%SOLR_PORT%/solr/admin/info/system" >nul 2>&1
    if !errorlevel! EQU 0 goto :solr_ready
    timeout /t 1 /nobreak >nul
)
call :handle_error "Solr is not responding"

:solr_ready
echo Solr is ready.

rem Fix and run migration
set "MIGRATION_JMX=%~dp0migration.jmx"
if exist "%MIGRATION_JMX%" (
    %POWERSHELL% "(Get-Content '%MIGRATION_JMX%' -Raw) -replace '172\.168\.0\.10', 'localhost' | Set-Content '%MIGRATION_JMX%' -Encoding UTF8"
    
    if exist "%JMETER_HOME%\bin\jmeter.bat" (
        echo Running data migration...
        call "%JMETER_HOME%\bin\jmeter.bat" -n -t "%MIGRATION_JMX%" -Juser=solr -Jpass=solrRocks
        if errorlevel 1 echo WARNING: Migration had issues but continuing...
        
        curl -s "http://localhost:%SOLR_PORT%/solr/jobs/select?q=*:*&wt=json&rows=0" > "%TEMP%\check.json"
        for /f "tokens=*" %%i in ('findstr "numFound" "%TEMP%\check.json"') do echo Data check: %%i
        del "%TEMP%\check.json" 2>nul
    )
)

rem --- Launch browser ---
echo.
echo =================================================================
echo Setup Complete!
echo.
echo SOLR: http://localhost:%SOLR_PORT%/solr/
echo UI: http://localhost:8081/
echo API: http://localhost:8081/api/
echo Swagger: http://localhost:8081/swagger-ui/
echo.
echo JMeter: %JMETER_HOME%
echo =================================================================

set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" (
    start "" "%CHROME%" "http://localhost:8081/"
    start "" "%CHROME%" "http://localhost:8983/solr/#/jobs/query"
    start "" "%CHROME%" "http://localhost:8081/swagger-ui"
    start "" "%CHROME%" "http://localhost:8081/api/v0/random"
) else (
    echo Chrome not found. Please open URLs manually.
)

rem --- Cleanup ---
del /f /q "%TEMP%\*.json" "%CD%\jmeter.log" 2>nul

echo.
echo Script completed successfully!
pause
exit /b 0
