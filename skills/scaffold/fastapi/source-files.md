<!-- ref: scaffold/fastapi/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
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
from starlette.types import ASGIApp, Receive, Scope, Send

from api.routes import router
from core.config import common_settings, api_settings
from error_handler import configure_exceptions


_SECURITY_HEADERS = [
    (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"strict-origin-when-cross-origin"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
    (b"x-xss-protection", b"0"),  # Disable legacy XSS auditor (exploitable in older browsers)
    # CSP baseline — tighten after auth/analytics are wired. frame-ancestors replaces X-Frame-Options for CSP2+ browsers.
    (b"content-security-policy", b"frame-ancestors 'none'; base-uri 'self'; object-src 'none'"),
]


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def _send(message: dict) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.extend(_SECURITY_HEADERS)
                message = {**message, "headers": headers}
            await send(message)

        await self.app(scope, receive, _send)


class ForwardedHostMiddleware:
    """Patches scope['server'] from X-Forwarded-Host so request.base_url reflects the public hostname.

    uvicorn's ProxyHeadersMiddleware handles X-Forwarded-Proto and X-Forwarded-For but not
    X-Forwarded-Host, leaving request.base_url with the internal container hostname.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] in ("http", "websocket"):
            headers = dict(scope["headers"])
            if b"x-forwarded-host" in headers:
                host = headers[b"x-forwarded-host"].decode("latin-1").split(",")[0].strip()
                port = scope.get("server", (host, 80))[1]
                scope["server"] = (host, port)
        await self.app(scope, receive, send)


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


def configure_security_headers(app: FastAPI) -> None:
    app.add_middleware(SecurityHeadersMiddleware)


def configure_proxy_headers(app: FastAPI) -> None:
    """Enables reverse-proxy header trust when TRUST_PROXY is set.

    Safe to omit (empty TRUST_PROXY) for local dev or non-proxy deployments.
    Set TRUST_PROXY to a VPC CIDR (e.g. 10.0.0.0/8) or * in AppCentral deployments.
    """
    if not api_settings.TRUST_PROXY:
        return
    from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
    app.add_middleware(ForwardedHostMiddleware)
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=api_settings.TRUST_PROXY)


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

    configure_security_headers(app)
    configure_cors(app)
    configure_proxy_headers(app)
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
from typing import Any

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
    TRUST_PROXY: str = Field(default="")

    def model_post_init(self, __context: Any) -> None:
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

pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart python-json-logger
pip install pytest httpx ruff pyright pytest-asyncio

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

### 6. Write project AGENTS.md

Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

```markdown
<!-- templateCentral: fastapi@4.0.0 -->
# AGENTS.md — [Project Name]

## Stack
FastAPI 0.136+ · Python 3.13 · Pydantic v2 · Uvicorn · Ruff · pytest · pyright

## Commands
```bash
python src/main.py          # dev server (http://localhost:8000)
pytest test/ -v             # run tests (from project root)
ruff check src/             # lint
ruff format src/            # format
python -m pyright src/      # type check
```

## Architecture
- Layered flow: `api/` (routers → services) → `models/` (never reversed)
- Pydantic schemas with camelCase aliases (`BaseSchema`)
- Centralized exception → HTTP response mapping in `error_handler.py`
- Routers are thin — accept body, call service, return result

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/api-verify` | pyright + ruff + tests in one pass |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect SQLAlchemy/Beanie |
| `templatecentral:add (endpoint)` | new route + schema + service method |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |
| `templatecentral:audit` | full ecosystem + accuracy audit |

## Rules (always)
- Type annotations on all public function parameters and return types
- All user input validated with Pydantic at every boundary; use `response_model` to strip internal fields
- snake_case files/functions/variables; PascalCase classes; UPPER_SNAKE_CASE constants
- No secrets in code — use env vars; document in `.env.example`

## AI Harness
PostToolUse: `python -m pyright src/ 2>&1 | tail -5` after every Edit/Write. Feedback-only.
Stop hook: runs `python -m pytest test/ -q` before task completion.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`

> Built-in subagents (/explore, /plan) do not load CLAUDE.md — they read AGENTS.md directly.
> Keep all routing and rules in this file, not in CLAUDE.md.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Project-Specific Notes
<!-- Expand this file as the project grows: architecture decisions, custom patterns, things to avoid -->

<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
```

### 6b. Create .claude/settings.json

Create `.claude/settings.json` at the project root. If the file already exists, merge the `PostToolUse` hook rather than overwriting.

**`.claude/settings.json`**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python -m pyright src/ 2>&1 | tail -5"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python -m pytest test/ -q 2>&1 | tail -20"
          }
        ]
      }
    ]
  }
}
```

`PostToolUse` — fast type feedback via pyright after every edit. Feedback-only; never blocks.
`Stop` — runs full test suite before Claude finishes a task. Exit code 2 asks Claude to fix failures.

Also create `FUTURE.md` at the project root:

**`FUTURE.md`**:
```markdown
# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** The disabled trace hook placeholder in `.claude/settings.json`.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated in v4.0.*
```

### 6c. Create project skill files (`.claude/skills/`)

Create `.claude/skills/api-verify.md`:

```markdown
---
name: api-verify
description: Run pyright, ruff lint, and pytest for this FastAPI project in one pass
---

Run all quality checks in sequence:

```bash
python -m pyright src/ && ruff check src/ && python -m pytest test/ -q
```

Report failures with the exact error output. Fix before proceeding.
```

### 6d. Create `.claude/harness.json`

Compute SHA-256 hashes and write:

```bash
sha256_agents=$(sha256sum AGENTS.md | cut -d' ' -f1)
sha256_claude=$(sha256sum CLAUDE.md | cut -d' ' -f1)
sha256_verify=$(sha256sum .claude/skills/api-verify.md | cut -d' ' -f1)
```

**`.claude/harness.json`**:
```json
{
  "templatecentral_version": "4.0.0",
  "stack": "fastapi",
  "seeded_at": "<date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/skills/api-verify.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/api-verify.md" }
  }
}
```

### 6e. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `api-migrate` — Alembic migration with safety gate (if SQLAlchemy/Alembic is wired up)
- `api-endpoint` — scaffold a new router + schema + service method

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

### 6f. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `templatecentral:build` — verify the scaffold compiles clean and the API starts
2. `templatecentral:test` — verify all scaffold tests pass (`pytest test/ -v`)
3. `templatecentral:review` (update operation) — freshen any deps that have newer compatible versions
4. `templatecentral:review` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6g. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

### 8. Task management (optional)

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from **Scaffold: optional Task Management** in repository root `AGENTS.md` (templateCentral). If no, skip.

### 9. Remove example code (optional)

Once the project is verified, use the `templatecentral:cleanup` skill.

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