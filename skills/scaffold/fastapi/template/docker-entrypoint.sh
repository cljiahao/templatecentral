#!/bin/sh
set -e

MODE="${1:-prod}"
PORT="${PORT:-8000}"
WORKERS="${WORKERS:-2}"

case "$MODE" in
  dev)
    echo "Starting FastAPI dev server (uvicorn --reload)..."
    exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --reload --no-server-header --log-config src/core/uvicorn_log_config.json
    ;;

  prod)
    echo "Starting FastAPI production server (uvicorn, $WORKERS workers)..."
    exec uvicorn app:app --app-dir src --host 0.0.0.0 --port "$PORT" --workers "$WORKERS" --no-server-header --log-config src/core/uvicorn_log_config.json
    ;;

  *)
    # Pass through any other command (e.g., "alembic upgrade head")
    exec "$@"
    ;;
esac
