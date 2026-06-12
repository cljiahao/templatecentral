<!-- ref: scaffold/fastapi/config-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Verbatim Config Files

### `Dockerfile`

```dockerfile
# ---- Global build arguments ----
# PYTHON:         Base Python image (pinned for reproducible builds)
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the application server listens on
ARG PYTHON=python:3.13.13-slim
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=8000

# ---- Base ----
# Shared Debian-slim + Python foundation. Installs OS-level packages once.
# The non-root user is created here so all downstream stages inherit it,
# matching the hardening pattern used in the Next.js and Vite Dockerfiles.
FROM ${PYTHON} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
# TZ defaults to UTC — override via TZ env var in your deploy config if needed

WORKDIR ${APP_DIR}

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends dumb-init \
    && groupadd -g ${APP_GID} ${APP_GROUPNAME} \
    && useradd -u ${APP_UID} -g ${APP_GID} -s /sbin/nologin -d ${APP_DIR} ${APP_USERNAME} \
    && chown ${APP_UID}:${APP_GID} ${APP_DIR} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---- Dependencies (dev) ----
# Installs ALL Python packages (including dev deps like pytest, ruff, etc.)
# into a virtual environment. Used by the dev stage.
FROM base AS deps
COPY requirements*.txt pyproject.toml* uv.lock* setup.py* setup.cfg* ./
RUN python -m venv .venv
ENV PATH="${APP_DIR}/.venv/bin:${PATH}"
RUN \
  if [ -f uv.lock ]; then pip install uv && uv sync --frozen; \
  elif [ -f requirements-dev.txt ]; then pip install -r requirements-dev.txt; \
  elif [ -f requirements.txt ]; then pip install -r requirements.txt; \
  elif [ -f pyproject.toml ]; then pip install .; \
  elif [ -f setup.py ]; then pip install .; \
  else echo "No requirements.txt, pyproject.toml, or setup.py found." && exit 1; \
  fi

# ---- Production dependencies ----
# Installs ONLY production packages. If a requirements-prod.txt or similar
# exists it is preferred; otherwise falls back to the same file as deps.
# This venv is what ships in the final prod image.
FROM base AS prod-deps
COPY requirements*.txt pyproject.toml* uv.lock* setup.py* setup.cfg* ./
RUN python -m venv .venv
ENV PATH="${APP_DIR}/.venv/bin:${PATH}"
RUN \
  if [ -f uv.lock ]; then pip install uv && uv sync --frozen --no-dev; \
  elif [ -f requirements-prod.txt ]; then pip install -r requirements-prod.txt; \
  elif [ -f requirements.txt ]; then pip install -r requirements.txt; \
  elif [ -f pyproject.toml ]; then pip install . --no-deps || pip install .; \
  elif [ -f setup.py ]; then pip install .; \
  else echo "No requirements file found." && exit 1; \
  fi

# ---- Development ----
# Full Python environment with all deps + source for live reload.
# Starts uvicorn with hot reload enabled.
FROM deps AS dev
ARG PORT
ARG APP_UID

ENV PORT=${PORT}

COPY ./ ./
RUN chmod +x docker-entrypoint.sh

EXPOSE ${PORT}
USER ${APP_UID}

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["dev"]

# ---- Production ----
# Minimal image with only the production virtual environment and source code.
# No dev dependencies, no build tools, no package manager cache.
# Starts uvicorn in production mode.
FROM base AS prod
ARG APP_UID
ARG APP_GID
ARG APP_DIR
ARG PORT

ENV PATH="${APP_DIR}/.venv/bin:${PATH}" \
    PORT=${PORT}

COPY --chown=${APP_UID}:${APP_GID} --from=prod-deps ${APP_DIR}/.venv ./.venv

COPY --chown=${APP_UID}:${APP_GID} ./ ./
RUN chmod +x docker-entrypoint.sh

EXPOSE ${PORT}
USER ${APP_UID}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:' + str(__import__('os').environ.get('PORT', 8000)) + '/health')" || exit 1

ENTRYPOINT ["dumb-init", "--", "./docker-entrypoint.sh"]
CMD ["prod"]
```

### `docker-entrypoint.sh`

```sh
#!/bin/sh
set -e

MODE="${1:-prod}"
PORT="${PORT:-8000}"
WORKERS="${WORKERS:-2}"

case "$MODE" in
  dev)
    echo "Starting FastAPI dev server (uvicorn --reload)..."
    exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --reload
    ;;

  prod)
    echo "Starting FastAPI production server (uvicorn, $WORKERS workers)..."
    exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --workers "$WORKERS"
    ;;

  *)
    # Pass through any other command (e.g., "alembic upgrade head")
    exec "$@"
    ;;
esac
```

### `.dockerignore`

```
# ==============================================================================
# PYTHON DOCKER IGNORE (Universal) - Production Optimized
# ==============================================================================

# Version Control
.git
.gitignore
.gitattributes
.gitmodules

# Python Virtual Environments (will be created in container)
.venv/
venv/
env/
.env/
ENV/
.conda/

# Python Cache & Bytecode
__pycache__/
*.py[cod]
*$py.class
*.pyo
.pyright/
.ruff_cache/
.pytest_cache/
.coverage
htmlcov/
.hypothesis/

# Distribution & Packaging
dist/
build/
*.egg-info/
*.egg
*.whl
.eggs/
sdist/

# Environment Variables (security) — match at any depth: scaffold secrets live at src/.env
**/.env
**/.env.*
!**/.env.example
!**/.env.default

# IDE and Editor Files
.vscode/
.idea/
*.swp
*.swo
*~
.project
.classpath
.settings/
.vscode-test
.history/
.fleet/

# OS Generated Files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
desktop.ini

# Logs (scaffold writes src/log/)
**/*.log
**/log/

# Runtime Data
pids/
*.pid
*.seed
*.pid.lock

# Testing & Coverage
coverage/
*.lcov
.nyc_output/
test-results/
test-results.xml
junit.xml
.tox/
.nox/

# Temporary Files
tmp/
temp/
*.tmp
*.temp

# Docker Related (don't copy into image)
.dockerignore
Dockerfile*
docker-compose*.yml
docker-compose*.yaml
.docker/

# CI/CD Configuration
.github/
.gitlab-ci.yml
.travis.yml
.circleci/
.azuredevops/
.buildkite/
bitbucket-pipelines.yml
jenkins/
Jenkinsfile*

# Documentation
README*.md
CHANGELOG*.md
CONTRIBUTING*.md
LICENSE*
SECURITY*.md
CODE_OF_CONDUCT*.md
docs/
.docs/

# Security & Certificates
*.pem
*.key
*.crt
*.p12
*.pfx
.secrets/

# Database
*.db
*.sqlite
*.sqlite3
.db/

# Node (if frontend assets exist alongside Python)
node_modules/

# ==============================================================================
# EXCEPTIONS - Files to include despite patterns above
# ==============================================================================

# Dependency files (needed for reproducible builds)
!requirements.txt
!requirements-dev.txt
!pyproject.toml
!uv.lock
!poetry.lock
!setup.py
!setup.cfg

# Essential config files
!alembic.ini
!pyrightconfig.json
!ruff.toml
!.flake8
!pytest.ini
!pyproject.toml
```

### `.gitignore`

```
# Python
__pycache__/
*.py[cod]
*$py.class
*.pyo
*.egg-info/
dist/
build/

# Virtual environments
.venv/
venv/
env/
ENV/

# IDE
.vscode/
.idea/
*.swp
*.swo
.fleet/

# Environment — matches at any depth (scaffold secrets live at src/.env)
.env
.env.*
!.env.example
!.env.default

# Testing
.pytest_cache/
.coverage
htmlcov/
.tox/
.nox/

# Type checking
.pyright/
.ruff_cache/

# Logs
*.log
logs/
log/

# OS
.DS_Store
Thumbs.db

# Database
*.db
*.sqlite
*.sqlite3
# Local agent symlink (.agents -> .claude) — NEVER track it: a git-tracked
# symlink breaks Windows CI build agents (e.g. "Unable to load symbolic/hard
# linked file" on Azure DevOps hosted runners). Recreate it per machine.
.agents
```

### `.env.example`

```
# Application
PROJECT_NAME=My Project
PROJECT_VERSION=v1.0.0
ENVIRONMENT=dev

# API (FASTAPI_ROOT stays empty for local dev; set e.g. `api` when served under a path prefix)
FASTAPI_ROOT=
API_PORT=8000

# CORS (comma-separated origins for production; in dev, localhost ports are allowed by default)
CORS_ORIGINS=http://localhost:3000

# Reverse proxy trust — set to VPC CIDR (e.g. 10.0.0.0/8) or * when behind ALB → Traefik; leave empty for local dev
TRUST_PROXY=
```

### `pyproject.toml`

```toml
[tool.ruff]
line-length = 88
target-version = "py313"

[tool.ruff.lint]
extend-select = ["I"]

[tool.pytest.ini_options]
pythonpath = ["src", "test"]
asyncio_mode = "auto"  # pytest-asyncio: treat `async def test_*` as coroutine tests without per-test markers

markers = [
    "unit: unit tests",
    "end_to_end: end to end tests",
]

addopts = [
    "--import-mode=importlib",
]
```

### `requirements-dev.txt`

Write this file verbatim (dev-only dependencies; not installed in production Docker stages):

```
pytest
pytest-asyncio
httpx
ruff
pyright
```