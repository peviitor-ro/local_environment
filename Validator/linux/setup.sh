#!/bin/bash

set -e

# This script sets up the local development environment for the Validator project.
# It clones the required repositories and starts the application using Docker Compose.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"

# === CHECK PREREQUISITES ===
if ! command -v git &> /dev/null; then
    echo "[ERROR] Git is not installed. Please install Git and try again."
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo "[ERROR] Docker Compose is not installed or Docker is not running. Please start Docker and try again."
    exit 1
fi

# === CHECK FOR .env FILE ===
if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] The .env file is missing."
    echo ""
    echo "Please copy the 'env.example' file to a new file named '.env'"
    echo "Place the file in the 'local_environment/Validator' directory."
    echo "Then, open the '.env' file and fill in your actual secret values."
    echo ""
    exit 1
fi

# === LOAD ENV ===
echo "Loading variables from .env..."
export $(grep -v '^#' "$ENV_FILE" | xargs)

# === VALIDATE VARIABLES ===
if [ -z "$FRONTEND_REPO" ]; then
    echo "[ERROR] FRONTEND_REPO is not defined in your .env file."
    exit 1
fi
if [ -z "$BACKEND_REPO" ]; then
    echo "[ERROR] BACKEND_REPO is not defined in your .env file."
    exit 1
fi
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "[ERROR] POSTGRES_PASSWORD is not defined in your .env file."
    echo "Please ensure all database credentials are set."
    exit 1
fi

# === CLEANUP AND CLONE REPOS ===
cd "$ROOT_DIR"

if [ -d "frontend" ]; then
    echo "[INFO] Removing existing 'frontend' directory..."
    rm -rf "frontend"
fi
if [ -d "backend" ]; then
    echo "[INFO] Removing existing 'backend' directory..."
    rm -rf "backend"
fi

echo ""
echo "[INFO] Cloning frontend repository..."
git clone "$FRONTEND_REPO" frontend || {
    echo "[ERROR] Failed to clone the frontend repository. Please check the URL in your .env file."
    exit 1
}

echo ""
echo "[INFO] Cloning backend repository..."
git clone "$BACKEND_REPO" backend || {
    echo "[ERROR] Failed to clone the backend repository. Please check the URL in your .env file."
    exit 1
}

# === CREATE FRONTEND .env FILE ===
echo ""
echo "[INFO] Creating frontend .env file..."
cat > frontend/validator-ui/.env << 'EOF'
# Frontend environment variables for Vite
# Backend API URL
VITE_BASE_URL=http://localhost:8000
EOF

# === STARTING THE APPLICATION ===
echo ""
echo "[INFO] Pulling the latest images from Docker Hub..."
docker compose --project-directory . -f "$COMPOSE_FILE" pull

echo ""
echo "[INFO] Starting the application with Docker Compose..."
docker compose --project-directory . -f "$COMPOSE_FILE" up -d

echo ""
echo "================================================================="
echo "      SETUP COMPLETE!"
echo "================================================================="
echo ""
echo "The application is now running in the background."
echo "   - Backend should be available at http://localhost:8000"
echo "   - Frontend should be available at http://localhost:3000"
echo ""
echo "To stop the application, run 'docker compose --project-directory . -f \"$COMPOSE_FILE\" down'"
echo ""
