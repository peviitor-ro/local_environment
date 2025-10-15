#!/bin/bash

set -e  # oprește la prima eroare

# === ÎNCĂRCARE ENV ===
if [ -f .env ]; then
  echo "🔄 Se încarcă variabilele din .env..."
  export $(grep -v '^#' .env | xargs)
fi

# === VERIFICARE VARIABILE ===
if [ -z "$FRONTEND_REPO" ] || [ -z "$BACKEND_REPO" ]; then
  echo "❌ Lipsesc variabilele FRONTEND_REPO sau BACKEND_REPO."
  echo "Adaugă-le în fișierul .env, exemplu:"
  echo "FRONTEND_REPO=https://github.com/utilizatorul/frontend.git"
  echo "BACKEND_REPO=https://github.com/utilizatorul/backend.git"
  exit 1
fi

# === CLONARE REPOZITORII ===
# echo "📥 Clonăm frontend-ul în ./frontend..."
# git clone "$FRONTEND_REPO" frontend

echo "📥 Clonăm backend-ul în ./backend..."
git clone "$BACKEND_REPO" backend

# === DOCKERFILE PERSONALIZAT BACKEND ===
DOCKERFILE="backend/Dockerfile"

echo "🧱 Suprascriem Dockerfile-ul din backend..."
cat > "$DOCKERFILE" <<EOF
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .

RUN pip3 install --no-cache-dir -r requirements.txt

COPY . .

WORKDIR /app/scraper_Api

EXPOSE 8000

CMD ["python3", "manage.py", "runserver", "0.0.0.0:8000"]
EOF

echo "✅ Dockerfile backend actualizat."

# === PORNIRE CU DOCKER-COMPOSE ===
echo "🚀 Pornim aplicația cu Docker Compose..."
docker-compose up --build -d

echo "🎉 Setup complet:"
echo "🔹 Backend: http://localhost:8000"
# echo "🔹 Frontend: http://localhost:3000"