# Linux / macOS / WSL — quick guide

Target: run the Validator stack locally using the provided bash helper or Docker Compose directly.

Prerequisites
- Git installed and on PATH
- Docker Engine and Compose v2 (use `docker compose`), or Docker Desktop on macOS
- A copy of the `.env` file in the `Validator` folder (see 'Prepare .env')

Prepare `.env`
1. Copy the example to `.env`:

```bash
cd /path/to/local_environment/Validator
cp linux/env.example ./.env
```

2. Edit `.env` and set at minimum:
- `FRONTEND_REPO` — git URL for frontend
- `BACKEND_REPO` — git URL for backend
- `POSTGRES_PASSWORD` — DB password used by compose

Run the setup script

```bash
cd /path/to/local_environment/Validator
bash linux/setup.sh
```

What the script does
- Verifies `git` and `docker compose` are available
- Loads `.env` and validates required vars
- Removes any existing `frontend` or `backend` directories, then clones the repos
- Creates `frontend/validator-ui/.env` with `VITE_BASE_URL=http://localhost:8000`
- Runs `docker compose pull` and `docker compose up -d`

Run compose manually (optional)

```bash
cd /path/to/local_environment/Validator
docker compose pull
docker compose up -d
```

Verify
- Containers: `docker compose ps`
- Logs: `docker compose logs -f backend`
- Backend: http://localhost:8000
- Frontend: http://localhost:3000

Stop / cleanup
- Stop: `docker compose down`
- Remove volumes (destructive): `docker compose down -v`

Common issues
- "docker compose: command not found": install Docker Compose v2 or use `docker-compose` (update script if needed).
- Ports in use: change host ports in `docker-compose.yml` or stop conflicting services.

WSL notes
- Ensure Docker Desktop integration with WSL is enabled or the Docker socket is reachable from WSL.
