#!/bin/bash

set -e

# This script sets up the local development environment for the Validator project.
# It clones the required repositories and starts the application using Docker Compose.

COMPOSE_FILE="../docker-compose.yml"

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
if [ ! -f ".env" ]; then
    echo "[ERROR] The .env file is missing."
    echo ""
    echo "Please copy the 'env.example' file to a new file named '.env'"
    echo "Then, open the '.env' file and fill in your actual secret values."
    echo ""
    exit 1
fi

# === LOAD ENV ===
echo "Loading variables from .env..."
export $(grep -v '^#' .env | xargs)

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
echo "To stop the application, run 'docker-compose --project-directory . -f \"$COMPOSE_FILE\" down'"
echo ""
