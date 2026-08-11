# local_environment
Scripts and Docker build contexts that spin up the peviitor stack locally for development, QA, or demos.

## What’s inside
- `environments/` — one-click installers by platform (`linux-auth/`, `macos-auth/`, `windows/`, `qa/`, `raspberry-pi/`).
- `containers/` — Dockerfiles for Solr, PHP API, and Swagger UI.
- `config/zookeeper/` — sample config for Solr Cloud.
- `tests/performance/` — JMeter plans and archived reports.
- `AGENTS.md` — contributor guide.

## Before you start
- Docker Desktop (Windows/macOS) or Docker Engine + Compose plugin (Linux).
- Git CLI.
- Java 11+ only if you plan to run JMeter.
- Stable internet to pull images and release artifacts.

## Quick start by OS
- **Windows (PowerShell as Administrator)**  
  `powershell -ExecutionPolicy Bypass -File environments/windows/run.ps1`  
  The script checks WSL2/Podman, downloads the latest `build.zip`, and starts Solr + API + front-end under `C:\peviitor`. Provide a Solr password with at least 15 characters including lower/upper/digit/symbol.
- **Linux (Debian/Ubuntu)**  
  `cd environments/linux-auth && sudo bash run.sh`  
  Creates `/home/<user>/peviitor`, builds/starts containers, and seeds configs. Existing folders are backed up with a timestamp.
- **macOS**  
  `cd environments/macos-auth && bash run.sh`  
  Requires Homebrew; the script waits for Docker Desktop and provisions `~/peviitor`.
- **Raspberry Pi**  
  `cd environments/raspberry-pi && bash run.sh`  
  Uses the same Solr/API/front-end stack with lighter defaults.
- **QA helpers**  
  `bash environments/qa/run-auth.sh` (with Solr auth) or `run-no-auth.sh` (without).

## Rebuild images (when Dockerfiles change)
```
docker build -t peviitor-solr containers/solr
docker build -t peviitor-api containers/php-apache
docker build -t peviitor-swagger containers/swagger-ui
```

## Config locations
- API env: `~/peviitor/build/api/api.env` (Windows: `C:\peviitor\build\api\api.env`). Do not commit real credentials.
- Zookeeper: `~/peviitor/config/zookeeper.env` plus `~/peviitor/zookeeper/{data,logs,certs}` placeholders.

## Verify after install
- Solr UI: http://localhost:8983/
- API sample: http://localhost:8080/api/v0/random/
- Front-end: http://localhost:8080/
If something fails, rerun the installer for your platform; it re-checks prerequisites and rebuilds the stack.
