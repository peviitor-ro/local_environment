# Validator — Local development

This folder contains scripts and a Docker Compose setup to run the Validator frontend, backend and a Postgres database locally.

Files of interest
- `docker-compose.yml` — defines services: `db` (Postgres), `backend` (Django) and `frontend` (Vite).
- `linux/setup.sh` — helper script for Linux/macOS/WSL: clones repos, creates frontend .env, pulls and starts compose.
- `windows/setup.bat` — helper script for Windows (cmd/PowerShell): same flow as the bash script.
- `*.env.example` — templates to copy to `.env` and edit. Do NOT commit `.env`.

Quick prerequisites
- Git
- Docker (Desktop on Windows/macOS or Docker Engine + Compose plugin on Linux)
- Enough disk space for images and volumes

Quick start (pick the OS guide below)
- Linux / macOS / WSL: see `linux/README.md`
- Windows (cmd / PowerShell): see `windows/README.md`

Verification & teardown
- Check containers and logs:
  - `docker compose ps`
  - `docker compose logs -f backend`
- Stop and remove containers:
  - `docker compose down`

Notes
- The backend runs with `manage.py runserver` (development mode). For production, replace the run command with a production server and remove dev-only steps.
- If you need private repo access, clone the repositories manually into `frontend` and `backend` before running the scripts.