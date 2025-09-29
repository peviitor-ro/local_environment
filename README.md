# local_environment
Tools for provisioning local, QA, and specialty environments that mirror the peviitor production stack.

## Directory Overview
- `environments/` — OS and platform specific bootstrap scripts.
  - `linux-auth/` — Debian/Ubuntu installer with secure Solr defaults and JMeter plans.
  - `macos-auth/` — macOS automation for the same secure stack.
  - `windows/` — PowerShell automation that validates WSL2/Podman and prepares Docker images.
  - `qa/` — Helper scripts for QA reviewers, with and without Solr authentication.
  - `raspberry-pi/` — Lightweight provisioning scripts for Raspberry Pi OS.
- `containers/` — Docker build contexts for the Solr, PHP API, and Swagger UI services.
- `tests/performance/` — Historical load reports and templates for new JMeter runs.
- `AGENTS.md` — Contributor guidelines and coding conventions.

## Prerequisites
Global tools you will need before running any scripts:
- Docker Engine or Docker Desktop, depending on the platform.
- Git CLI for cloning and pulling updates.
- Java (JDK 11+) for JMeter workloads on Windows.
- Homebrew (macOS) or apt-based package manager (Linux) for dependency installation.

> Tip: Each script re-checks its own prerequisites and attempts to install what is missing when possible.

## Windows Setup
1. Open PowerShell **as Administrator** and change into this repository.
2. Run `powershell -ExecutionPolicy Bypass -File environments/windows/run.ps1`.
   - The script verifies WSL2, installs Podman if needed, and pulls Docker images.
3. When prompted, provide the Solr username and a strong password (≥15 characters, mixed case, digits, symbol).
4. After completion, the working stack resides in `C:\peviitor`.
5. Use `environments/windows/runnew.ps1` when you want a clean reinstall with prerequisite validation.

## Linux Setup (Debian/Ubuntu)
1. `cd environments/linux-auth`
2. `sudo bash run.sh`
3. Optionally create swap space when prompted, then supply Solr credentials.
4. The script installs Docker (if missing), clones the peviitor sources to `/home/<username>/peviitor`, and launches the stack.
5. Re-run the script whenever you need to rebuild the API (`peviitor/build/api`) or front-end (`peviitor/search-engine`).

## macOS Setup
1. `cd environments/macos-auth`
2. `bash run.sh`
3. Ensure Homebrew is installed; the script checks for Docker, Git, and other utilities, then provisions the stack in `~/peviitor`.

## Raspberry Pi Setup
1. `cd environments/raspberry-pi`
2. `bash run.sh`
3. After the containers start, seed data by executing the bundled JMeter plans (`migration.jmx`, `firme.jmx`).

## QA Utilities
- `bash environments/qa/run-auth.sh` — QA stack with Solr authentication enabled.
- `bash environments/qa/run-no-auth.sh` — QA stack without Solr auth for public endpoints.
- `bash environments/qa/solr-auth.sh` / `solr-curl-auth.sh` — quick helpers for logging into Solr or testing secured endpoints.

## Container Builds
Rebuild service images whenever you adjust a Dockerfile:
```
docker build -t peviitor-solr containers/solr
docker build -t peviitor-api containers/php-apache
docker build -t peviitor-swagger containers/swagger-ui
```
Push new image tags to your chosen registry before updating production environments.

## Performance Testing
- Store new JMeter result files and summaries under `tests/performance/`.
- Recommended command: `jmeter -n -t environments/linux-auth/migration.jmx -l results.jtl`.
- Remove large transient logs (`results.jtl`) before committing; keep curated PDFs or Markdown summaries only.

## API Configuration (`api.env`)
Scripts create `peviitor/build/api`; add the file below with your environment-specific values:
```
LOCAL_SERVER=<local server>
PROD_SERVER=<production server>
SOLR_SERVER=172.18.0.10:8983
SOLR_USER=<solr user>
SOLR_PASS=<solr password>
```
Never commit real credentials. Share secrets through your preferred vault.

## Verify Your Environment
After provisioning, confirm the services respond as expected:
- `http://localhost:8983/` — Solr Admin UI
- `http://localhost:8080/api/v0/random/` — API sample endpoint
- `http://localhost:8080/` — Search front-end
If anything fails, re-run the platform script and inspect its log output for missing prerequisites or credential issues.
