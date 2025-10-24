@echo off
setlocal

REM This script sets up the local development environment for the Validator project.
REM It clones the required repositories and starts the application using Docker Compose.

set COMPOSE_FILE=..\docker-compose.yml

REM === CHECK PREREQUISITES ===
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Git is not installed or not in your system's PATH.
    echo Please install Git and try again.
    pause
    goto :eof
)

docker-compose --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Docker Compose is not installed or Docker is not running.
    echo Please start Docker Desktop and try again.
    pause
    goto :eof
)

REM === CHECK FOR .env FILE ===
if not exist ".env" (
    echo [ERROR] The .env file is missing.
    echo.
    echo Please copy the 'env.example' file to a new file named '.env'
    echo Then, open the '.env' file and fill in your actual secret values.
    echo.
    pause
    goto :eof
)

REM === LOAD ENV ===
echo "Loading variables from .env..."
for /f "delims=" %%a in ('type ".env" ^| findstr /v "^#"') do set "%%a"

REM === VALIDATE VARIABLES ===
if not defined FRONTEND_REPO (
    echo "[ERROR] FRONTEND_REPO is not defined in your .env file."
    pause
    goto :eof
)
if not defined BACKEND_REPO (
    echo "[ERROR] BACKEND_REPO is not defined in your .env file."
    pause
    goto :eof
)
if not defined POSTGRES_PASSWORD (
    echo "[ERROR] POSTGRES_PASSWORD is not defined in your .env file."
    echo "Please ensure all database credentials are set."
    pause
    goto :eof
)

REM === CLEANUP AND CLONE REPOS ===
if exist "frontend" (
    echo [INFO] Removing existing 'frontend' directory...
    rmdir /s /q "frontend"
)
if exist "backend" (
    echo [INFO] Removing existing 'backend' directory...
    rmdir /s /q "backend"
)

echo.
echo [INFO] Cloning frontend repository...
git clone "%FRONTEND_REPO%" frontend || (
    echo [ERROR] Failed to clone the frontend repository. Please check the URL in your .env file.
    pause
    goto :eof
)

echo.
echo [INFO] Cloning backend repository...
git clone "%BACKEND_REPO%" backend || (
    echo [ERROR] Failed to clone the backend repository. Please check the URL in your .env file.
    pause
    goto :eof
)


REM === STARTING THE APPLICATION ===
echo.
echo [INFO] Pulling the latest images from Docker Hub...
docker-compose --project-directory . -f "%COMPOSE_FILE%" pull

echo.
echo [INFO] Starting the application with Docker Compose...
docker-compose --project-directory . -f "%COMPOSE_FILE%" up -d

echo.
echo =================================================================
echo      SETUP COMPLETE!
echo =================================================================
echo.
echo The application is now running in the background.
echo    - Backend should be available at http://localhost:8000
echo    - Frontend should be available at http://localhost:3000
echo.
echo To stop the application, run 'docker-compose --project-directory . -f "%COMPOSE_FILE%" down'
echo.

pause
endlocal