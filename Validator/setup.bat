@echo off
setlocal enabledelayedexpansion

REM === ÎNCĂRCARE ENV ===
if exist .env (
    echo 🔄 Se încarcă variabilele din .env...
    for /f "usebackq tokens=*" %%a in (".env") do (
        set "line=%%a"
        REM Skip comments and empty lines
        if not "!line:~0,1!"=="#" (
            if not "!line!"=="" (
                set "%%a"
            )
        )
    )
) else (
    echo ❌ Fișierul .env nu există.
    exit /b 1
)

REM === VERIFICARE VARIABILE ===
if "%FRONTEND_REPO%"=="" (
    echo ❌ Lipsesc variabilele FRONTEND_REPO sau BACKEND_REPO.
    echo Adaugă-le în fișierul .env, exemplu:
    echo FRONTEND_REPO=https://github.com/utilizatorul/frontend.git
    echo BACKEND_REPO=https://github.com/utilizatorul/backend.git
    exit /b 1
)

if "%BACKEND_REPO%"=="" (
    echo ❌ Lipsesc variabilele FRONTEND_REPO sau BACKEND_REPO.
    echo Adaugă-le în fișierul .env, exemplu:
    echo FRONTEND_REPO=https://github.com/utilizatorul/frontend.git
    echo BACKEND_REPO=https://github.com/utilizatorul/backend.git
    exit /b 1
)

REM === CLONARE REPOZITORII ===
echo 📥 Clonăm frontend-ul în ./frontend...
git clone "%FRONTEND_REPO%" frontend
if errorlevel 1 (
    echo ❌ Eroare la clonarea frontend-ului.
    exit /b 1
)

echo 📥 Clonăm backend-ul în ./backend...
git clone "%BACKEND_REPO%" backend
if errorlevel 1 (
    echo ❌ Eroare la clonarea backend-ului.
    exit /b 1
)

REM === DOCKERFILE BACKEND ===
echo 🧱 Generăm Dockerfile pentru backend...
(
echo FROM python:3.10-slim
echo.
echo WORKDIR /app
echo.
echo COPY requirements.txt .
echo.
echo RUN pip3 install --no-cache-dir -r requirements.txt
echo.
echo COPY . .
echo.
echo WORKDIR /app/scraper_Api
echo.
echo EXPOSE 8000
echo.
echo CMD ["python3", "manage.py", "runserver", "0.0.0.0:8000"]
) > backend\Dockerfile

echo ✅ Dockerfile backend creat.

REM === DOCKERFILE FRONTEND ===
echo 🧱 Generăm Dockerfile pentru frontend...
(
echo FROM node:23.5.0
echo.
echo WORKDIR /app
echo.
echo COPY package*.json ./
echo.
echo RUN npm install
echo.
echo COPY . .
echo.
echo EXPOSE 3000
echo.
echo CMD ["npx", "vite"]
) > frontend\validator-ui\Dockerfile

echo ✅ Dockerfile frontend creat.

REM === PORNIRE CU DOCKER-COMPOSE ===
echo 🚀 Pornim aplicația cu Docker Compose...
docker-compose up --build -d
if errorlevel 1 (
    echo ❌ Eroare la pornirea Docker Compose.
    exit /b 1
)

echo 🎉 Setup complet:
echo 🔹 Backend: http://localhost:8000
echo 🔹 Frontend: http://localhost:3000
