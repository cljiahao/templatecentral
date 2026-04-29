---
name: fastapi-scaffold
description: Use when the user wants to start a new Python backend project, create a new FastAPI API, or scaffold a project with layered architecture and Docker support.
version: "1.0.0"
---

# Scaffold FastAPI Project

## Inputs

- **Project name** — The name for the new project (e.g., `my-api`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-api`). If not provided, default to `./<project-name>` and confirm with the user.

---

## Part A — Rules

### Dependencies

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate   # Linux/Mac

# Install runtime deps (no versions — resolves latest)
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart "python-json-logger>=3.3.0,<4.0"

# Install dev deps
pip install pytest httpx ruff mypy pytest-asyncio

# Generate requirements.txt
pip freeze > requirements.txt
```

### Directory Structure

```
<project-root>/
├── Dockerfile                              [verbatim]
├── docker-entrypoint.sh                    [verbatim]
├── .dockerignore                           [verbatim]
├── .gitignore                              [verbatim]
├── .env.example                            [verbatim]
├── pyproject.toml                          [verbatim]
├── requirements.txt                        [generate — pip freeze output]
├── requirements-dev.txt                    [generate — package names, no pins]
├── README.md                               [generate]
├── AGENTS.md                               [generate — after verification gate]
├── src/
│   ├── .env.default                        [verbatim]
│   ├── main.py                             [verbatim]
│   ├── app.py                              [verbatim]
│   ├── error_handler.py                    [verbatim]
│   ├── core/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   ├── config.py                       [verbatim]
│   │   ├── exceptions.py                   [verbatim]
│   │   ├── logging.py                      [verbatim]
│   │   ├── directory_manager.py            [verbatim]
│   │   └── json/
│   │       └── logging.json                [verbatim]
│   ├── api/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   ├── routes.py                       [verbatim]
│   │   ├── tags.py                         [verbatim]
│   │   ├── routers/
│   │   │   ├── __init__.py                 [verbatim — empty]
│   │   │   └── example.py                  [verbatim]
│   │   ├── schemas/
│   │   │   ├── __init__.py                 [verbatim — empty]
│   │   │   ├── base.py                     [verbatim]
│   │   │   ├── request/
│   │   │   │   ├── __init__.py             [verbatim — empty]
│   │   │   │   └── example.py              [verbatim]
│   │   │   └── response/
│   │   │       ├── __init__.py             [verbatim — empty]
│   │   │       └── example.py              [verbatim]
│   │   └── services/
│   │       ├── __init__.py                 [verbatim — empty]
│   │       └── example.py                  [verbatim]
│   ├── constants/
│   │   └── __init__.py                     [verbatim — empty]
│   ├── logic/
│   │   └── __init__.py                     [verbatim — empty]
│   ├── models/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   └── base.py                         [verbatim]
│   └── utils/
│       ├── __init__.py                     [verbatim — empty]
│       └── date.py                         [verbatim]
└── test/
    ├── conftest.py                         [verbatim]
    ├── factories/
    │   ├── __init__.py                     [verbatim — empty]
    │   └── models.py                       [verbatim]
    ├── test_api/
    │   ├── __init__.py                     [verbatim — empty]
    │   ├── test_example.py                 [verbatim]
    │   └── test_health.py                  [verbatim]
    ├── test_logic/
    │   └── __init__.py                     [verbatim — empty]
    ├── test_models/
    │   └── __init__.py                     [verbatim — empty]
    └── test_utils/
        └── __init__.py                     [verbatim — empty]
```

### Generation Conventions

**[generate] README.md** — Generate a project README with: project name, brief description, stack (FastAPI, Python 3.12, Pydantic v2, Uvicorn, Ruff, pytest, Docker), quick-start commands (`source .venv/bin/activate`, `python src/main.py`, `pytest test/`, `ruff check src/`), and a note that example code can be removed with the `remove-example` skill.

**[generate] AGENTS.md** — Generated only after the verification gate passes (Step 5). See Step 6 for exact content. Must begin with `<!-- templateCentral: fastapi@1.0.0 -->` as line 1.

**[generate] requirements.txt** — Output of `pip freeze > requirements.txt` after installing all deps. Never write this file manually; always let `pip freeze` produce it.

**[generate] requirements-dev.txt** — Write this file with package names only (no version pins):
```
fastapi
uvicorn[standard]
pydantic
pydantic-settings
python-dotenv
python-multipart
python-json-logger>=3.3.0,<4.0
pytest
httpx
ruff
mypy
pytest-asyncio
```

---

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
ARG PYTHON=python:3.12.10-slim
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

WORKDIR ${APP_DIR}

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends tzdata dumb-init \
    && ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
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
```

### `pyproject.toml`

```toml
[tool.ruff]
line-length = 88
target-version = "py312"

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

## Part C — Verbatim Source Files

### `src/.env.default`

```
# General
PROJECT_NAME=My Project
PROJECT_VERSION=v1.0.0
ENVIRONMENT=dev

# API
FASTAPI_ROOT=

# Ports
API_PORT=8000

# CORS (comma-separated origins for production; in dev, localhost ports are allowed by default)
CORS_ORIGINS=http://localhost:3000
```

### `src/main.py`

```python
import uvicorn
from dotenv import find_dotenv, load_dotenv


def load_environment() -> None:
    """Load environment variables, prioritizing environment-specific settings."""
    general_env_path = find_dotenv(".env")
    if general_env_path:
        load_dotenv(dotenv_path=general_env_path)
        print(f"Loaded general environment variables from: {general_env_path}")
    else:
        print("General .env file not found.")


def run_api() -> None:
    """Runs the FastAPI server using Uvicorn."""
    from core.config import api_settings, common_settings
    from core.logging import logger

    host = "0.0.0.0"
    port = api_settings.API_PORT
    reload = common_settings.ENVIRONMENT not in ["prod", "uat"]

    logger.info(f"Starting server at http://{host}:{port} with reload={reload}")
    uvicorn.run("app:app", host=host, port=port, reload=reload)


if __name__ == "__main__":
    load_environment()
    run_api()
```

### `src/app.py`

```python
import textwrap
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router
from core.config import common_settings, api_settings
from error_handler import configure_exceptions


def configure_cors(app: FastAPI) -> None:
    """Configures Cross-Origin Resource Sharing (CORS) middleware for the FastAPI application.

    Args:
        app: The FastAPI application instance.
    """
    origins = api_settings.ALLOWED_CORS

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization"],
    )


def start_application() -> FastAPI:
    """Initialize and configures the FastAPI application.

    Returns:
        The initialized and configured FastAPI application instance.
    """
    app = FastAPI(
        title=common_settings.PROJECT_NAME,
        version=common_settings.PROJECT_VERSION,
        description=textwrap.dedent(common_settings.PROJECT_DESCRIPTION),
        root_path=f"/{api_settings.FASTAPI_ROOT}" if api_settings.FASTAPI_ROOT else "",
        swagger_ui_parameters={
            "defaultModelsExpandDepth": -1,  # Hide models section by default
            "docExpansion": "none",  # Collapse all sections by default
        },
    )

    configure_cors(app)
    configure_exceptions(app)
    app.include_router(router)

    return app


# Initialize the FastAPI application
app = start_application()
```

### `src/error_handler.py`

```python
from typing import Any, Sequence

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette import status

from core.exceptions import InvalidInputError, NoResultsFound
from core.logging import logger

INTERNAL_SERVER_ERROR_DETAIL = "Internal Server Error"


def _sanitize_errors(errors: Sequence[Any]) -> list[dict]:
    """Make Pydantic validation errors JSON-safe.

    exc.errors() can contain raw exception objects in the 'ctx' dict
    which are not JSON serializable. Convert them to strings.
    """
    safe = []
    for err in errors:
        clean = {**err}
        if "ctx" in clean:
            clean["ctx"] = {
                k: (
                    str(v)
                    if not isinstance(v, (str, int, float, bool, type(None)))
                    else v
                )
                for k, v in clean["ctx"].items()
            }
        safe.append(clean)
    return safe


def configure_exceptions(app: FastAPI) -> None:
    """Register exception handlers so all errors are handled in one place."""

    @app.exception_handler(InvalidInputError)
    async def invalid_input_handler(
        request: Request, exc: InvalidInputError
    ) -> JSONResponse:
        logger.info(
            "Invalid input",
            extra={"path": request.url.path, "detail": str(exc)},
        )
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"detail": str(exc)},
        )

    @app.exception_handler(NoResultsFound)
    async def no_results_handler(
        request: Request, exc: NoResultsFound
    ) -> JSONResponse:
        logger.info(
            "No results found",
            extra={"path": request.url.path, "detail": str(exc)},
        )
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"detail": str(exc)},
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail},
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        safe_errors = _sanitize_errors(exc.errors())
        logger.info(
            "Request validation error",
            extra={"path": request.url.path, "errors": safe_errors},
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={"detail": safe_errors},
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        logger.exception("Unhandled exception", extra={"path": request.url.path})
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"detail": INTERNAL_SERVER_ERROR_DETAIL},
        )
```

### `src/core/__init__.py`

```python
```

*(empty file)*

### `src/core/config.py`

```python
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings


class CommonSettings(BaseSettings):
    """Common settings for the application."""

    PROJECT_NAME: str = Field(default="My Project")
    PROJECT_VERSION: str = Field(default="v1.0.0")
    PROJECT_DESCRIPTION: str = Field(
        default="""
        A FastAPI application built with
        [FastAPI](https://fastapi.tiangolo.com/)

        - [Source Code](https://www.github.com)
        - [Issues](https://www.github.com/issues)
        """
    )
    ENVIRONMENT: str = Field(default="dev")


class APISettings(BaseSettings):
    """API-specific settings."""

    FASTAPI_ROOT: str = Field(default="")
    API_PORT: int = Field(default=8000)
    CORS_ORIGINS: str = Field(default="http://localhost:3000")
    ALLOWED_CORS: list[str] = []

    def model_post_init(self, _) -> None:
        """Compute allowed CORS origins after initialization."""
        self.ALLOWED_CORS = self._compute_allowed_cors()

    def _compute_allowed_cors(self) -> list[str]:
        if common_settings.ENVIRONMENT == "dev":
            return [
                "http://localhost:3000",
                "http://localhost:3001",
                "http://localhost:5173",
                "http://127.0.0.1:3000",
                "http://127.0.0.1:5173",
            ]
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @field_validator("FASTAPI_ROOT", mode="before")
    def remove_trailing_slash(cls, value: str) -> str:
        """Remove any trailing slashes from FASTAPI_ROOT."""
        return value.rstrip("/")


common_settings = CommonSettings()
api_settings = APISettings()
```

### `src/core/exceptions.py`

```python
class InvalidInputError(Exception):
    """Raised when user input fails domain validation (maps to 400)."""

    pass


class NoResultsFound(Exception):
    """Raised when a lookup yields no results (maps to 404)."""

    pass
```

### `src/core/logging.py`

```python
import json
import logging
import logging.config
import logging.handlers
from pathlib import Path
from datetime import datetime as dt

from core.config import common_settings
from core.directory_manager import directory_manager as dm


class MyTimedRotatingFileHandler(logging.handlers.TimedRotatingFileHandler):
    """Custom log handler that rotates log files daily and organizes them by month."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self.namer = self.change_name

    def change_name(self, default_name: str) -> str:
        """Change the log filename to include the current month and year."""
        file_path = Path(default_name)
        tail = file_path.name

        # Ensure log directory and subdirectories exist
        mth_fol = dm.log_dir / dt.now().strftime("%b%Y")
        dm.create_directory(mth_fol)

        # Construct new filename with the month-year prefix
        arr = tail.split(".")
        ext = arr.pop()
        fname = "_".join(arr) + f".{ext}"

        return str(mth_fol / fname)


# Register the custom handler
logging.handlers.MyTimedRotatingFileHandler = MyTimedRotatingFileHandler


def setup_logging() -> None:
    """Set up logging configuration from a JSON file or default settings."""
    logging_config_path = Path(__file__).parent / "json" / "logging.json"
    if not logging_config_path.exists():
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            handlers=[logging.StreamHandler()],
        )
        return

    with logging_config_path.open("rt", encoding="utf-8") as f:
        config = json.load(f)

    # Get handlers that are actually used by loggers
    handlers = config.get("handlers", {})
    loggers = config.get("loggers", {})

    env = common_settings.ENVIRONMENT
    logger_config = loggers.get(env, loggers.get("dev", {}))
    log_handlers = logger_config.get("handlers", [])

    # Only update file paths for handlers that are actually used
    for handler_name, handler_config in handlers.items():
        if "filename" in handler_config and handler_name in log_handlers:
            # Convert relative paths to absolute paths using log directory
            original_filename = handler_config["filename"]
            dm.create_directory(dm.log_dir)
            absolute_path = dm.log_dir / original_filename

            # Update the handler configuration
            handler_config["filename"] = str(absolute_path)

    # Apply the logging configuration
    logging.config.dictConfig(config)


# Setup logging and create logger instance
setup_logging()
logger = logging.getLogger(common_settings.ENVIRONMENT)
```

### `src/core/json/logging.json`

```json
{
  "version": 1,
  "disable_existing_loggers": false,
  "formatters": {
    "simple": {
      "format": "%(name)s : %(asctime)s | %(levelname)s | %(filename)s : %(lineno)s | %(message)s",
      "datefmt": "%Y-%m-%d %H:%M:%S"
    },
    "json": {
      "class": "pythonjsonlogger.json.JsonFormatter",
      "format": "%(name)s  %(asctime)s %(levelname)s %(filename)s %(lineno)s %(message)s",
      "datefmt": "%Y-%m-%d %H:%M:%S"
    }
  },
  "handlers": {
    "console": {
      "class": "logging.StreamHandler",
      "level": "DEBUG",
      "formatter": "simple",
      "stream": "ext://sys.stdout"
    },
    "info_console": {
      "class": "logging.StreamHandler",
      "level": "INFO",
      "formatter": "json",
      "stream": "ext://sys.stdout"
    },
    "error_console": {
      "class": "logging.StreamHandler",
      "level": "ERROR",
      "formatter": "json",
      "stream": "ext://sys.stderr"
    },
    "info_file": {
      "class": "logging.handlers.MyTimedRotatingFileHandler",
      "level": "INFO",
      "formatter": "json",
      "filename": "info.log",
      "when": "midnight",
      "encoding": "utf8",
      "delay": true
    },
    "error_file": {
      "class": "logging.handlers.MyTimedRotatingFileHandler",
      "level": "ERROR",
      "formatter": "json",
      "filename": "errors.log",
      "when": "midnight",
      "encoding": "utf8",
      "delay": true
    }
  },
  "loggers": {
    "dev": {
      "level": "DEBUG",
      "handlers": [
        "console",
        "info_file",
        "error_file"
      ],
      "propagate": false
    },
    "uat": {
      "level": "INFO",
      "handlers": [
        "info_console"
      ],
      "propagate": false
    },
    "prod": {
      "level": "INFO",
      "handlers": [
        "info_console"
      ],
      "propagate": false
    }
  },
  "root": {
    "level": "DEBUG",
    "handlers": [
      "console"
    ]
  }
}
```

### `src/core/directory_manager.py`

```python
from pathlib import Path
from shutil import rmtree


class DirectoryManager:
    """Handles directory structure and ensures required folders exist."""

    def __init__(self) -> None:
        """Initialize directory paths and ensure required folders exist."""
        self.base_dir = Path(__file__).resolve().parent.parent

        # Log folder
        self.log_dir = self.base_dir / "log"

        self._initialize_base_folders()

    def _initialize_base_folders(self) -> None:
        """Initialize base required directory paths."""
        folders = [self.log_dir]
        for folder in folders:
            self.create_directory(folder)

    def create_directory(self, folder_path: Path, to_remove: bool = False) -> None:
        """Helper method to ensure the destination directory exists, and remove it if necessary.

        Args:
            folder_path: The path to the directory.
            to_remove: If True, remove the directory before creating it.
        """
        if to_remove and folder_path.exists():
            try:
                rmtree(folder_path)
            except Exception as e:
                raise OSError(
                    f"Failed to remove existing directory: {folder_path}"
                ) from e

        try:
            folder_path.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            raise OSError(f"Failed to create directory: {folder_path}") from e

    def create_subdirectories(
        self, directory: Path, folder_list: list[str], to_remove: bool = False
    ) -> None:
        """Creates multiple subdirectories under a specified base directory.

        Args:
            directory: The parent directory where the subdirectories will be created.
            folder_list: A list of subdirectory names to create and count.

        Raises:
            TypeError: If non str type is found in folder_list
        """
        for folder in folder_list:
            if not isinstance(folder, str):
                raise TypeError(
                    f"List of folders provided consist non str type: {folder}"
                )
            folder_path = directory / folder
            self.create_directory(folder_path, to_remove)

    def list_png_paths(self, folder_path: Path) -> list[Path]:
        """Returns a list of all .png files in the given directory.

        Args:
            folder_path: The path to the directory.

        Returns:
            A list of Path objects for .png files.

        Raises:
            FileNotFoundError: If the directory does not exist.
            ValueError: If the path is not a directory.
        """
        if not folder_path.exists():
            raise FileNotFoundError(f"Directory not found: {folder_path}")

        if not folder_path.is_dir():
            raise ValueError(f"Path is not a directory: {folder_path}")

        return list(folder_path.glob("*.png"))

    def get_file_count(self, folder_path: Path) -> int:
        """Count the number of files in a directory.

        Args:
            folder_path: The path to the directory for which to count files.

        Returns:
            The total number of files found under given directory.

        Raises:
            ValueError: If the path is not a directory.
        """
        if not folder_path.is_dir():
            raise ValueError(f"Path is not a directory: {folder_path}")
        return sum(1 for item in folder_path.iterdir() if item.is_file())

    def get_folder_count(self, directory: Path) -> int:
        """Count the number of folders in a directory.

        Args:
            directory: The path to the directory for which to count subdirectories.

        Returns:
            The total number of subdirectories under given directory.

        Raises:
            ValueError: If the path is not a directory.
        """
        if not directory.is_dir():
            raise ValueError(f"Path is not a directory: {directory}")
        return sum(1 for item in directory.iterdir() if item.is_dir())

    def count_files_in_subdirectories(
        self, directory: Path, folder_list: list[str]
    ) -> dict[str, int]:
        """Counts the number of files within each specified subdirectory.

        Args:
            directory: The parent directory where the subdirectories will be created.
            folder_list: A list of subdirectory names to create and count.

        Returns:
            A dictionary of file counts based on the subdirectories name.
        """
        return {
            folder: self.get_file_count(directory / folder) for folder in folder_list
        }


directory_manager = DirectoryManager()
```

### `src/api/__init__.py`

```python
```

*(empty file)*

### `src/api/routes.py`

```python
from fastapi import APIRouter

from api.routers import example
from api.tags import APITags

router = APIRouter()

router.include_router(example.router, tags=[APITags.EXAMPLE])


@router.get(
    "/",
    tags=[APITags.MISC],
    summary="Home Route",
    description="A simple home route returning a welcome message.",
    response_model=dict[str, str],
)
def home() -> dict[str, str]:
    """Simple home route."""
    return {"msg": "Hello FastAPI"}


@router.get(
    "/health",
    tags=[APITags.MISC],
    summary="Health Check",
    description="A simple health check returning an OK status.",
    response_model=dict[str, str],
)
def health() -> dict[str, str]:
    """Health check endpoint."""
    return {"status": "OK"}
```

### `src/api/tags.py`

```python
from enum import StrEnum


class APITags(StrEnum):
    MISC = "misc"
    EXAMPLE = "example"
    INFRASTRUCTURE = "infrastructure"
```

### `src/api/routers/__init__.py`

```python
```

*(empty file)*

### `src/api/routers/example.py`

```python
from fastapi import APIRouter

from api.schemas.request.example import ExampleRequest
from api.schemas.response.example import ExampleResponse
from api.services.example import run_example

router = APIRouter()


@router.post(
    "/example",
    response_model=ExampleResponse,
    summary="Example endpoint",
    description="An example endpoint demonstrating the router → service → logic flow.",
)
def example_endpoint(body: ExampleRequest) -> ExampleResponse:
    """Process an example request."""
    return run_example(body)
```

### `src/api/schemas/__init__.py`

```python
```

*(empty file)*

### `src/api/schemas/base.py`

```python
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class BaseSchema(BaseModel):
    """Base schema with common configuration."""

    model_config = ConfigDict(
        extra="forbid",
        from_attributes=True,
        validate_assignment=True,
        validate_default=True,
        populate_by_name=True,
        alias_generator=to_camel,
    )


class BaseRequestSchema(BaseSchema):
    """Base for API request schemas."""

    pass


class BaseResponseSchema(BaseSchema):
    """Base for API response schemas — always serializes using camelCase aliases."""

    model_config = ConfigDict(
        **dict(BaseSchema.model_config),
        serialize_by_alias=True,
    )
```

### `src/api/schemas/request/__init__.py`

```python
```

*(empty file)*

### `src/api/schemas/request/example.py`

```python
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class ExampleRequest(BaseRequestSchema):
    """Example request schema."""

    name: str = Field(description="A name to greet.")
    repeat_count: int = Field(default=1, ge=1, le=10, description="Times to repeat.")
```

### `src/api/schemas/response/__init__.py`

```python
```

*(empty file)*

### `src/api/schemas/response/example.py`

```python
from pydantic import Field

from api.schemas.base import BaseResponseSchema


class ExampleResponse(BaseResponseSchema):
    """Example response schema."""

    message: str = Field(description="The greeting message.")
    items: list[str] = Field(description="Repeated greetings.")
```

### `src/api/services/__init__.py`

```python
```

*(empty file)*

### `src/api/services/example.py`

```python
from api.schemas.request.example import ExampleRequest
from api.schemas.response.example import ExampleResponse


def run_example(request: ExampleRequest) -> ExampleResponse:
    """Orchestrate the example request: parse, process, return."""
    greeting = f"Hello, {request.name}!"
    items = [greeting] * request.repeat_count
    return ExampleResponse(message=greeting, items=items)
```

### `src/constants/__init__.py`

```python
```

*(empty file)*

### `src/logic/__init__.py`

```python
```

*(empty file)*

### `src/models/__init__.py`

```python
```

*(empty file)*

### `src/models/base.py`

```python
from dataclasses import dataclass


@dataclass(slots=True)
class BaseModel:
    """Base for mutable domain models (state that changes during processing)."""

    pass


@dataclass(frozen=True, slots=True)
class BaseImmutableModel:
    """Base for immutable domain models (config, lookup data, parameters)."""

    pass
```

### `src/utils/__init__.py`

```python
```

*(empty file)*

### `src/utils/date.py`

```python
from datetime import date


def year_month_to_date(year_month: str) -> date:
    """Convert 'YYYY-MM' string to a date (first of month)."""
    year, month = year_month.split("-")
    return date(int(year), int(month), 1)


def date_to_year_month(d: date) -> str:
    """Convert a date to 'YYYY-MM' string."""
    return d.strftime("%Y-%m")
```

### `test/conftest.py`

```python
"""Root conftest — shared fixtures available to all tests."""

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    """FastAPI test client."""
    with TestClient(app) as client:
        yield client
```

### `test/factories/__init__.py`

```python
```

*(empty file)*

### `test/factories/models.py`

```python
"""Factory functions for creating test domain models with sensible defaults.

Usage:
    member = create_member(name="Alice")
    member = create_member()  # uses defaults
"""


def create_example_request(
    name: str = "World",
    repeat_count: int = 1,
) -> dict:
    """Create an example request payload."""
    return {
        "name": name,
        "repeatCount": repeat_count,
    }
```

### `test/test_api/__init__.py`

```python
```

*(empty file)*

### `test/test_api/test_example.py`

```python
"""Tests for the example endpoint."""

import pytest
from fastapi.testclient import TestClient

from factories.models import create_example_request


@pytest.mark.unit
def test_example_returns_greeting(client: TestClient) -> None:
    """POST /example returns a greeting with the given name."""
    payload = create_example_request(name="Alice")
    response = client.post("/example", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Alice!"
    assert data["items"] == ["Hello, Alice!"]


@pytest.mark.unit
def test_example_repeats(client: TestClient) -> None:
    """POST /example repeats the greeting repeat_count times."""
    payload = create_example_request(name="Bob", repeat_count=3)
    response = client.post("/example", json=payload)

    assert response.status_code == 200
    assert len(response.json()["items"]) == 3


@pytest.mark.unit
def test_example_rejects_invalid_count(client: TestClient) -> None:
    """POST /example rejects repeat_count outside 1-10."""
    payload = create_example_request(repeat_count=99)
    response = client.post("/example", json=payload)

    assert response.status_code == 422
```

### `test/test_api/test_health.py`

```python
"""Tests for health and home endpoints."""

import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_home_returns_welcome(client: TestClient) -> None:
    """GET / returns a welcome message."""
    response = client.get("/")
    assert response.status_code == 200
    assert "msg" in response.json()


@pytest.mark.unit
def test_health_returns_ok(client: TestClient) -> None:
    """GET /health returns OK status."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "OK"}
```

### `test/test_logic/__init__.py`

```python
```

*(empty file)*

### `test/test_models/__init__.py`

```python
```

*(empty file)*

### `test/test_utils/__init__.py`

```python
```

*(empty file)*

---

## Scaffold Steps

### 1. Create target directory and write all files

Create `<target-directory>/` and write every file listed in the Directory Structure above. Use verbatim content from Parts B and C exactly. Generate `requirements-dev.txt`, `README.md` per conventions. Do NOT create `requirements.txt` yet — it is produced by `pip freeze` in Step 4.

### 2. Update project settings

In `src/core/config.py`, update the `CommonSettings` defaults:
- `PROJECT_NAME` — Set to the project name supplied by the user
- `PROJECT_DESCRIPTION` — Set to a relevant one-sentence description
- `PROJECT_VERSION` — Set to `"v0.1.0"` (or user's preferred version)

### 3. Create environment file

```bash
cp src/.env.default src/.env
```

Update values as needed (project name, port, etc.). Never commit `src/.env`.

### 4. Set up virtual environment and install dependencies

```bash
python -m venv .venv
source .venv/bin/activate   # Linux/Mac

pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart "python-json-logger>=3.3.0,<4.0"
pip install pytest httpx ruff mypy pytest-asyncio

pip freeze > requirements.txt
```

**Checkpoint**: Run `pip check` to detect dependency conflicts. Fix before proceeding.

### 5. Verification gate (do not proceed until this passes)

```bash
python src/main.py &      # starts server; confirm http://localhost:8000 responds
pytest test/ -v           # all tests must pass
ruff check src/           # zero lint errors
ruff format --check src/  # zero formatting drift
```

**Do not generate AGENTS.md until all three checks pass.**

### 6. Generate AGENTS.md (mandatory — after gate passes)

Create `AGENTS.md` in the project root. Line 1 must be the version comment. Fill in the project name and current date:

```markdown
<!-- templateCentral: fastapi@1.0.0 -->
# <Project Name>

## Identity
- **Stack**: FastAPI 0.136+, Python 3.12, Pydantic v2, Uvicorn, Ruff, pytest
- **Scaffolded from**: templateCentral fastapi-scaffold skill
- **Created**: <date>

## Architecture Decisions
- Layered dependency flow: `api/` (routers → services) → `models/` (never reversed)
- Pydantic schemas with camelCase aliases (`BaseSchema`)
- Structured JSON logging with timed rotating file handler
- Centralized exception → HTTP response mapping in `error_handler.py`

## Key Conventions
- snake_case for files/functions/variables; PascalCase for classes; UPPER_SNAKE_CASE for constants
- Type annotations on all public function parameters and return types
- Routers are thin — accept body, call service, return result
- Services orchestrate — parse → process → return
- Absolute imports only; no wildcards; stdlib → third-party → local
- **Testing**: New or changed API/services/domain logic must include pytest coverage in the same change (`pytest test/ -v` from project root)

## Commands
- `python src/main.py` — development server
- `pytest test/ -v` — run tests
- `ruff check src/` — lint
- `ruff format src/` — format

## Code Quality

Every agent writing or modifying code must follow these before marking a task done:

- **YAGNI** — Write only what the current task requires. No speculative helpers, abstractions, or files.
- **DRY** — Don't duplicate logic; extract at the second repetition. Don't extract from a single callsite.
- **SRP** — One responsibility per file and function. Routers route; services orchestrate; models model. Never mix layers.
- **SoC** — Keep concerns separate: routing from business logic, schema conversion in the service layer, config from implementation.
- **No premature abstractions** — Wait for the third callsite before extracting a shared helper.
- **No dead code** — No commented-out blocks, unused imports, unused variables, or TODO stubs.
- **No tech debt shortcuts** — No `# fix later`, `# temp`, or workarounds that degrade the codebase.
- **Validate at every boundary** — User input, API responses, env vars: always validate with Pydantic. Never trust external data.
- **Fail loudly** — No bare `except` or empty exception handlers. Log with context; return meaningful HTTP status codes.
- **Least privilege** — Return only the fields the caller needs. Use `response_model` to strip internal fields.
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

### 6b. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean and the API starts
2. `shared-test-agent` — verify all scaffold tests pass (`pytest test/ -v`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions
4. `shared-review-agent` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6c. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add thedotmack/claude-mem
claude plugin install claude-mem
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **claude-mem** — persists decisions, file changes, and tool usage across sessions via SQLite + vector DB. Installed in the **scaffolded project**, not in templateCentral.
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

### 7. Generate CLAUDE.md (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Write a **short** `CLAUDE.md` (do not duplicate `AGENTS.md` architecture/conventions — point to `AGENTS.md`).

Include **Build & Dev** with verified commands only:
- `source .venv/bin/activate` — venv
- `python src/main.py` — dev server (http://localhost:8000)
- `pytest test/` — tests (project root)
- `ruff check src/` — lint

**templateCentral skills** (this stack): `fastapi-scaffold` (done), `fastapi-code-standards`, `fastapi-add-endpoint`, `fastapi-add-auth`, `fastapi-add-database`, `fastapi-add-integration`, `fastapi-add-test`. **Workflow**: simple/medium → templateCentral skills; complex → Superpowers (see root `AGENTS.md`). **Never** put secrets in `CLAUDE.md`.

### 8. Task management (optional)

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If no, skip.

### 9. Remove example code (optional)

Once the project is verified, use the `shared-remove-example` skill.

FastAPI-specific steps (the skill covers these):
- Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
- Remove `example` import and `include_router` from `src/api/routes.py`
- Remove `EXAMPLE` from `APITags` in `src/api/tags.py`

---

## Rules

- Always create a virtual environment before installing dependencies; NEVER install packages globally
- Always copy `src/.env.default` to `src/.env` before first run — **never** commit `src/.env` or put secrets in generated `AGENTS.md` / `CLAUDE.md`
- Verify the API starts and Swagger docs render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER include `__pycache__/`, `log/`, `src/.env`, or `.venv/` when writing project files
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove `conftest.py` or `factories/` when cleaning up example code — they're shared test infrastructure
