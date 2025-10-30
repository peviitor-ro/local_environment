# Windows — quick guide (cmd / PowerShell)

This guide covers running the provided `setup.bat` and alternative manual compose commands.

Prerequisites
- Git installed and in PATH
- Docker Desktop running (includes Docker Compose) or `docker-compose` binary

Prepare `.env`
1. Copy the example to `.env` (PowerShell):

```powershell
cd C:\path\to\local_environment\Validator
Copy-Item -Path .\windows\env.example -Destination .\.env
```

Or (cmd):

```
cd C:\path\to\local_environment\Validator
copy windows\env.example .\.env
```

2. Edit `Validator\.env` and set at minimum:
- `FRONTEND_REPO`, `BACKEND_REPO`, `POSTGRES_PASSWORD`

Run the Windows setup script

Open Command Prompt or PowerShell and run:

```powershell
cd C:\path\to\local_environment\Validator
.\windows\setup.bat
```

What the script does
- Checks for git and docker-compose
- Validates `.env` values, clones frontend and backend into `frontend` and `backend`
- Creates `frontend\validator-ui\.env` with `VITE_BASE_URL=http://localhost:8000`
- Runs `docker-compose pull` and `docker-compose up -d`

If you prefer to run compose manually (PowerShell / cmd)

```powershell
cd C:\path\to\local_environment\Validator
docker compose pull
docker compose up -d
```

Verify
- `docker compose ps`
- `docker compose logs -f backend`
- Backend: http://localhost:8000
- Frontend: http://localhost:3000

Stop / cleanup
- `docker compose down`
- `docker compose down -v` (removes volumes - destructive)

Common Windows issues
- Docker Desktop not running: open Docker Desktop and wait until it is ready.

PowerShell execution: running the batch from PowerShell is fine; no special execution policy changes are required for `.bat` files.
