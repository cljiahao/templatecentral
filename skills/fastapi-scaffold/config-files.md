<!-- ref: fastapi-scaffold/config-files.md
     loaded-by: fastapi-scaffold/SKILL.md
     prereq: Stack = FastAPI. Do not invoke this file directly — it is loaded at runtime by the fastapi-scaffold skill. -->
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
ARG PYTHON=python:3.13.3-slim
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
# The entrypoint auto-detects the framework (FastAPI / Django / Flask)
# and runs the appropriate dev server with hot reload enabled.
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
# The entrypoint auto-detects the framework and runs the appropriate
# production server (gunicorn for Django/Flask, uvicorn for FastAPI).
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

# ── Framework detection ──────────────────────────────────────────────
# Checks dependency files to determine which framework is installed,
# then sets the appropriate server command for dev and prod modes.
#
#   FastAPI  → uvicorn (async, ASGI)
#   Django   → gunicorn with WSGI (auto-detects project name from manage.py)
#   Flask    → gunicorn with app:app
#   Fallback → python main.py
# ─────────────────────────────────────────────────────────────────────

detect_framework() {
  DEPS_CONTENT=""
  for f in requirements.txt requirements/*.txt pyproject.toml setup.py setup.cfg; do
    if [ -f "$f" ]; then
      DEPS_CONTENT="$DEPS_CONTENT $(cat "$f")"
    fi
  done

  if echo "$DEPS_CONTENT" | grep -qi "fastapi"; then
    echo "fastapi"
  elif echo "$DEPS_CONTENT" | grep -qi "django"; then
    echo "django"
  elif echo "$DEPS_CONTENT" | grep -qi "flask"; then
    echo "flask"
  else
    echo "unknown"
  fi
}

# For Django, find the WSGI module by locating manage.py's parent settings.
detect_django_wsgi() {
  if [ -f manage.py ]; then
    SETTINGS_MODULE=$(grep -oP "DJANGO_SETTINGS_MODULE.*?['\"]([^'\"]+)['\"]" manage.py 2>/dev/null | head -1 | grep -oP "['\"]([^'\"]+)['\"]" | tr -d "'\"")
    if [ -n "$SETTINGS_MODULE" ]; then
      echo "${SETTINGS_MODULE%.*}.wsgi"
      return
    fi
  fi

  # Fallback: look for wsgi.py anywhere in the project
  WSGI_FILE=$(find . -name "wsgi.py" -not -path "./.venv/*" 2>/dev/null | head -1)
  if [ -n "$WSGI_FILE" ]; then
    echo "$WSGI_FILE" | sed 's|^\./||; s|/|.|g; s|\.py$||'
    return
  fi

  echo "config.wsgi"
}

FRAMEWORK=$(detect_framework)
echo "Detected framework: $FRAMEWORK"

case "$MODE" in
  dev)
    case "$FRAMEWORK" in
      fastapi)
        echo "Starting FastAPI dev server (uvicorn --reload)..."
        exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --reload
        ;;
      django)
        echo "Starting Django dev server..."
        exec python manage.py runserver "0.0.0.0:$PORT"
        ;;
      flask)
        echo "Starting Flask dev server..."
        exec flask run --host 0.0.0.0 --port "$PORT" --reload
        ;;
      *)
        echo "Unknown framework. Running: python main.py"
        exec python main.py
        ;;
    esac
    ;;

  prod)
    case "$FRAMEWORK" in
      fastapi)
        echo "Starting FastAPI production server (uvicorn, $WORKERS workers)..."
        exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --workers "$WORKERS"
        ;;
      django)
        WSGI_MODULE=$(detect_django_wsgi)
        echo "Starting Django production server (gunicorn $WSGI_MODULE, $WORKERS workers)..."
        exec gunicorn "$WSGI_MODULE:application" --bind "0.0.0.0:$PORT" --workers "$WORKERS"
        ;;
      flask)
        echo "Starting Flask production server (gunicorn, $WORKERS workers)..."
        exec gunicorn "app:app" --bind "0.0.0.0:$PORT" --workers "$WORKERS"
        ;;
      *)
        echo "Unknown framework. Running: python main.py"
        exec python main.py
        ;;
    esac
    ;;

  *)
    # Pass through any other command (e.g., "python manage.py migrate")
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
.mypy_cache/
.dmypy.json
.pytype/
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

# Environment Variables (security)
.env
.env.*
!.env.example
!.env.local.example

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

# Logs
*.log
logs/

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

# Jupyter Notebooks
.ipynb_checkpoints/
*.ipynb

# Database
*.db
*.sqlite
*.sqlite3
.db/

# Django Specific
staticfiles/
mediafiles/
media/

# Terraform
*.tfstate
*.tfstate.*
.terraform/

# Kubernetes
*.kubeconfig
k8s/
kubernetes/

# AWS & Cloud
.aws/
.serverless/

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
!mypy.ini
!ruff.toml
!.flake8
!pytest.ini
!pyproject.toml
!manage.py
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

# Environment
.env
.env.local

# Testing
.pytest_cache/
.coverage
htmlcov/
.tox/
.nox/

# Type checking
.mypy_cache/
.dmypy.json
.pytype/
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
```

### `.env.example`

```
# Application
PROJECT_NAME=My Project
PROJECT_VERSION=v1.0.0
ENVIRONMENT=dev

# API
FASTAPI_ROOT=api
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

markers = [
    "unit: unit tests",
    "end_to_end: end to end tests",
]

addopts = [
    "--import-mode=importlib",
]
```

---

