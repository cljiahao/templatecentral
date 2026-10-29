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

    host = "0.0.0.0"  # noqa: S104 — container-bound; only reachable via the reverse proxy
    port = api_settings.API_PORT
    reload = common_settings.ENVIRONMENT not in ["prod", "uat"]

    logger.info(f"Starting server at http://{host}:{port} with reload={reload}")
    # log_config=None — uvicorn's own default LOGGING_CONFIG installs handlers directly on
    # the uvicorn/uvicorn.access loggers with propagate=False, which bypasses the root
    # handler setup_logging() configures. Without this, uvicorn's own startup/access logs
    # never go through structlog's JSON formatting in prod, only app-level logger calls do.
    uvicorn.run(
        "app:app",
        host=host,
        port=port,
        reload=reload,
        log_config=None,
        server_header=False,
    )


if __name__ == "__main__":
    load_environment()
    run_api()
