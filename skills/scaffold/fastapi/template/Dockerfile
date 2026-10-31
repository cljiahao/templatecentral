# ---- Global build arguments ----
# PYTHON:         Base Python image (pinned for reproducible builds)
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the application server listens on
# Tag floats on purpose (no digest pin: a pinned digest goes stale downstream). Rebuild with
# `--pull --no-cache` to pick up trust-store fixes (eMudhra intermediate CA, Oct 2026).
ARG PYTHON=python:3.14.8-slim
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=8000

# ---- Base ----
# Shared Debian-slim + Python foundation. Installs OS-level packages once.
# The non-root user is created here so all downstream stages inherit it.
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
# into a virtual environment. Used by the dev stage. requirements-dev.txt lists
# dev tools only, so it is installed alongside requirements.txt, never instead of it.
FROM base AS deps
COPY requirements*.txt pyproject.toml* uv.lock* setup.py* setup.cfg* ./
RUN python -m venv .venv
ENV PATH="${APP_DIR}/.venv/bin:${PATH}"
RUN \
  if [ -f uv.lock ]; then pip install uv && uv sync --frozen; \
  elif [ -f requirements-dev.txt ]; then pip install -r requirements.txt -r requirements-dev.txt; \
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
# `requirements.txt` must contain runtime deps ONLY — freeze it before installing
# requirements-dev.txt, or dev tools leak into the prod image.
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
