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

# Reverse proxy trust — set to VPC CIDR (e.g. 10.0.0.0/8) or * when behind ALB → Traefik; leave empty for local dev
TRUST_PROXY=
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
import ipaddress
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

    Trust model: only mounted when TRUST_PROXY is set (see configure_proxy_headers), and added
    AFTER ProxyHeadersMiddleware so it runs outermost — scope['client'] is still the direct peer
    (the proxy), validated against TRUST_PROXY before the header is honored. Without this guard
    any client reaching the app directly could spoof generated URLs (e.g. password-reset links).
    """

    def __init__(self, app: ASGIApp, trusted: str = "*") -> None:
        self.app = app
        self.trust_all = trusted.strip() == "*"
        self.trusted_networks = (
            []
            if self.trust_all
            else [
                ipaddress.ip_network(t.strip(), strict=False)
                for t in trusted.split(",")
                if t.strip()
            ]
        )

    def _peer_is_trusted(self, scope: Scope) -> bool:
        if self.trust_all:
            return True
        client = scope.get("client")
        if not client:
            return False
        try:
            peer = ipaddress.ip_address(client[0])
        except ValueError:
            return False
        return any(peer in net for net in self.trusted_networks)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] in ("http", "websocket") and self._peer_is_trusted(scope):
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
    One-hop (ALB → App): set TRUST_PROXY to the ALB's VPC CIDR (e.g. 10.0.0.0/8).
    Two-hop (ALB → Traefik → App): set TRUST_PROXY to Traefik's container CIDR or use *.
    Use * only in closed networks — it trusts any forwarded IP.
    """
    if not api_settings.TRUST_PROXY:
        return
    from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware
    # Order matters: the last middleware added runs outermost. ForwardedHostMiddleware must run
    # BEFORE ProxyHeadersMiddleware rewrites scope['client'], so it can validate the direct peer.
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=api_settings.TRUST_PROXY)
    app.add_middleware(ForwardedHostMiddleware, trusted=api_settings.TRUST_PROXY)


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
    """Make Pydantic validation errors JSON-safe and strip submitted values.

    exc.errors() can contain raw exception objects in the 'ctx' dict
    which are not JSON serializable. Convert them to strings.
    Drop 'input' (echoes the submitted value — e.g. passwords — into
    responses and logs) and 'url' (Pydantic docs link, noise).
    """
    safe = []
    for err in errors:
        clean = {k: v for k, v in err.items() if k not in ("input", "url")}
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
            headers=dict(exc.headers) if exc.headers else None,
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
async def home() -> dict[str, str]:
    """Simple home route."""
    return {"msg": "Hello FastAPI"}


@router.get(
    "/health",
    tags=[APITags.MISC],
    summary="Health Check",
    description="A simple health check returning an OK status.",
    response_model=dict[str, str],
)
async def health() -> dict[str, str]:
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
async def example_endpoint(body: ExampleRequest) -> ExampleResponse:
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

Create `<target-directory>/` and write every file listed in the Directory Structure above. Use verbatim content from Parts B and C exactly. Write `requirements-dev.txt` verbatim from Part B (config-files.md). Generate `README.md` per conventions. Do NOT create `requirements.txt` yet — it is produced by `pip freeze` in Step 4.

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

**Do not generate AGENTS.md until all checks pass.**

### 6. Write project AGENTS.md

Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

```markdown
<!-- templateCentral: fastapi@5.0.0 -->
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
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: `python -m pyright src/ 2>&1 | tail -5` after every Edit/Write. Feedback-only.
Stop hook: runs full test suite; exit 2 feeds failures to Claude via stderr; exit 0 on pass.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
```

### 6b. Create .claude/settings.json

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (below). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present.

**`.claude/settings.json`**:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(**/.env)",
      "Read(**/.env.local)",
      "Read(**/.env.*.local)",
      "Read(**/.env.development)",
      "Read(**/.env.development.*)",
      "Read(**/.env.dev)",
      "Read(**/.env.production)",
      "Read(**/.env.production.*)",
      "Read(**/.env.staging)",
      "Read(**/.env.staging.*)",
      "Read(**/.env.uat)",
      "Read(**/.env.test)",
      "Read(./secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/protect-files.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "python3 .claude/hooks/user-prompt-guard.py" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-edit-typecheck.sh" }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-tool-failure.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/stop-checks.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/subagent-stop.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-context.sh" }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

Hook logic lives in `.claude/hooks/` scripts (seeded below) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `.github/workflows/`, cert/credential files; warns on governance files (`AGENTS.md`, `CLAUDE.md`, `Dockerfile`). Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — blocks `git commit --no-verify`, direct commits/force-push to protected branches (`main`/`uat`/`develop`), and `rm -rf` on source dirs.
- `user-prompt-guard.py` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs).
- `post-edit-typecheck.sh` (PostToolUse) — incremental `pyright` feedback, filtered to Python edits in-script; activates `.venv` and no-ops if pyright is absent. Feedback-only.
- `post-tool-failure.sh` (PostToolUseFailure) — surfaces tool error context for self-correction.
- `stop-checks.sh` (Stop) — runs `pytest`; exit 2 forces a fix before the turn ends.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted Python changes so it can't hand back broken code.
- `session-context.sh` (SessionStart: startup/resume/compact) — re-injects AGENTS.md routing context + universal invariants. This is the working post-compaction recovery path; PostCompact is observability-only and cannot inject context, so it is not used.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**`.claude/hooks/protect-files.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block; exit 1 = warn (human approval expected); exit 0 = allow.
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
[ -z "$file" ] && exit 0
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || root="."
rel="${file#"$root"/}"

if [[ "$rel" == .github/workflows/* ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition — requires human review." >&2
  exit 2
elif [[ "$rel" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json) reason="harness config — editing it can silently disable every hook" ;;
  .claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  Dockerfile) reason="container image definition" ;;
esac
if [ -n "$reason" ]; then
  echo "PROTECTED FILE: $rel — $reason. Confirm human approval and note it in the PR." >&2
  exit 1
fi
exit 0
```

**`.claude/hooks/block-no-verify.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception: print('')" 2>/dev/null)
[ -z "$cmd" ] && exit 0

if echo "$cmd" | grep -qE 'git[[:space:]]+commit' && echo "$cmd" | grep -qE '\-\-no-verify|[[:space:]]-[a-z]*n'; then
  echo "BLOCKED: --no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "uat" || "$branch" == "develop" ]]; then
    echo "BLOCKED: direct commit to protected branch '$branch'. Create a feature branch first." >&2
    exit 2
  fi
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+push' && { { echo "$cmd" | grep -qE '\-\-force([[:space:]=]|$)|[[:space:]]-[a-z]*f' && echo "$cmd" | grep -qE '\bmain\b|\buat\b|\bdevelop\b'; } || echo "$cmd" | grep -qE '[[:space:]]\+(main|uat|develop)\b'; }; then
  echo "BLOCKED: force-push to a protected branch (--force/-f or +refspec). Open a PR instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/])(src|app|lib|test|\.claude|\.husky|\.git|node_modules)([[:space:]/]|$)'; then
  echo "BLOCKED: recursive rm on a source directory. Confirm with a human first." >&2
  exit 2
fi
exit 0
```

**`.claude/hooks/user-prompt-guard.py`**:
```python
#!/usr/bin/env python3
# UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
import json, re, sys

try:
    prompt = json.load(sys.stdin).get('prompt', '') or ''
except Exception:
    sys.exit(0)
lower = prompt.lower()

injection = [
    'ignore previous instructions',
    'ignore all instructions',
    'disregard your',
    'forget your instructions',
    'override your',
    'new instructions:',
    'system prompt:',
    'your real instructions',
    'you are now a different ai',
    'you are no longer bound',
    'pretend you are not bound',
    'pretend you have no restrictions',
    'act as if you have no restrictions',
    'developer mode enabled',
]
for p in injection:
    if p in lower:
        sys.stderr.write(f'Blocked: prompt matches an injection pattern (OWASP LLM01): "{p}"\n')
        sys.exit(2)

credentials = [
    (r'AKIA[0-9A-Z]{16}', 'AWS access key ID'),
    (r'ghp_[A-Za-z0-9]{36}', 'GitHub personal access token'),
    (r'github_pat_[A-Za-z0-9_]{82}', 'GitHub fine-grained PAT'),
    (r'sk-ant-[A-Za-z0-9\-_]{90,}', 'Anthropic API key'),
    (r'-----BEGIN [A-Z ]*PRIVATE KEY-----', 'PEM private key block'),
    (r'mongodb(\+srv)?://[^:]+:[^@]+@', 'database URL with embedded credentials'),
]
for pat, label in credentials:
    if re.search(pat, prompt):
        sys.stderr.write(f'Blocked: prompt may contain a real credential — {label} (OWASP LLM02). Do not paste secrets; use env vars.\n')
        sys.exit(2)
sys.exit(0)
```

**`.claude/hooks/post-edit-typecheck.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on Python edits only. Feedback-only (never blocks).
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py) ;; *) exit 0 ;; esac
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
python -m pyright src/ 2>&1 | tail -5
exit 0
```

**`.claude/hooks/post-tool-failure.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUseFailure — surface tool error context for self-correction. Always exit 0.
input=$(cat)
printf '%s' "$input" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); sys.stderr.write('Tool failure: '+str(d.get('tool_name','unknown'))+((' — '+str(d.get('error'))) if d.get('error') else '')+'\n')
except Exception: pass" 2>/dev/null
exit 0
```

**`.claude/hooks/stop-checks.sh`**:
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print(json.loads(sys.stdin.read() or '{}').get('stop_hook_active', False))
except: print(False)" 2>/dev/null)
[ "$active" = "True" ] && exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(python -m pytest test/ -q 2>&1); EC=$?
echo "$OUTPUT" | tail -20 >&2
[ $EC -ne 0 ] && exit 2 || exit 0
```

**`.claude/hooks/subagent-stop.sh`**:
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted Python changes so it can't hand back broken code.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
if git diff --name-only HEAD 2>/dev/null | grep -qE '\.py$' || \
   git diff --cached --name-only 2>/dev/null | grep -qE '\.py$'; then
  OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
  if [ $EC -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
exit 0
```

**`.claude/hooks/session-context.sh`**:
```bash
#!/usr/bin/env bash
# SessionStart(startup|resume|compact) — re-inject routing context + universal invariants.
# Plain stdout is added to Claude's context (per Claude Code hooks docs); this is what survives compaction.
echo "=== templateCentral routing context ==="
head -30 AGENTS.md 2>/dev/null

# If a CONSTITUTION.md exists, re-inject it (project binding invariants survive compaction)
if [ -f docs/CONSTITUTION.md ]; then
  echo ""
  echo "=== Project invariants (docs/CONSTITUTION.md) ==="
  cat docs/CONSTITUTION.md
fi

cat <<'EOF'

## Always-on invariants (survive compaction)
1. Secrets are never read or written by the agent — .env* and secrets/** are guarded.
2. Run the quality gate (typecheck + tests) before declaring any task done.
3. Work on a feature branch — never commit directly to main/uat/develop.
4. Protected files — AGENTS.md, CLAUDE.md, Dockerfile, .claude/settings.json, .claude/hooks/*, docs/CONSTITUTION.md — require human approval.
5. Respect the architecture/dependency boundaries documented in AGENTS.md and docs/CONSTITUTION.md.
EOF
```

Make all hook scripts executable:
```bash
chmod +x .claude/hooks/*.sh
```

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

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated.*
```

### 6c. Create project skill files (`.claude/skills/`)

Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Run `mkdir -p .claude/skills/api-verify`, then create `.claude/skills/api-verify/SKILL.md`:

```markdown
---
name: api-verify
description: Run pyright, ruff lint, and pytest for this FastAPI project in one pass
allowed-tools: Bash(python *), Bash(ruff *)
---

Run all quality checks in sequence:

```bash
python -m pyright src/ && ruff check src/ && python -m pytest test/ -q
```

Report failures with the exact error output. Fix before proceeding.
```

### 6d. Seed `docs/CONSTITUTION.md`

Create `docs/CONSTITUTION.md` as the binding invariants document for this project.
It takes precedence over `AGENTS.md` and all skill guidance when there is a conflict.
Fill in the `[...]` placeholders with the actual project values.

**`docs/CONSTITUTION.md`**:
```markdown
# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **[Project Name]**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Define the load-bearing architectural rules: layering, module boundaries,
factory/composition-root patterns, forbidden cross-imports, etc.]

## 3. Security Invariants

- Secrets NEVER appear in code, git, logs, or build output — use environment
  variables loaded from a secrets manager.
- All API routes authenticate before executing business logic.
- All mutations write to an audit log.

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 401, 200, and at least one error path.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- Every PR to `uat` and `main` requires the PR template fully filled.

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval noted in the PR under
`## Protected File Changes`. Agents MUST NOT modify them without approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Add project-specific protected files here]

### Behavioural rules

- Run the quality gate (`python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` — the `/api-verify` skill) before declaring any task done.
- Never use `--no-verify` on commits — this bypasses pre-commit hooks.
- Work on a feature branch — never commit directly to `main`, `uat`, or `develop`.
```

### 6e. Create `.claude/harness.json`

Compute SHA-256 hashes and write:

```bash
sha256_agents=$(shasum -a 256 AGENTS.md | cut -d' ' -f1)
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/*; do shasum -a 256 "$h"; done
sha256_claude=$(shasum -a 256 CLAUDE.md | cut -d' ' -f1)
sha256_settings=$(shasum -a 256 .claude/settings.json | cut -d' ' -f1)
sha256_verify=$(shasum -a 256 .claude/skills/api-verify/SKILL.md | cut -d' ' -f1)
```

**`.claude/harness.json`**:
```json
{
  "templatecentral_version": "4.6.0",
  "stack": "fastapi",
  "seeded_at": "<date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/settings.json": { "origin_hash": "<sha256_settings>", "path": ".claude/settings.json" },
    ".claude/skills/api-verify/SKILL.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/api-verify/SKILL.md" },
    ".claude/hooks/protect-files.sh": { "origin_hash": "<sha256_hook_1>", "path": ".claude/hooks/protect-files.sh" },
    ".claude/hooks/block-no-verify.sh": { "origin_hash": "<sha256_hook_2>", "path": ".claude/hooks/block-no-verify.sh" },
    ".claude/hooks/user-prompt-guard.py": { "origin_hash": "<sha256_hook_3>", "path": ".claude/hooks/user-prompt-guard.py" },
    ".claude/hooks/post-edit-typecheck.sh": { "origin_hash": "<sha256_hook_4>", "path": ".claude/hooks/post-edit-typecheck.sh" },
    ".claude/hooks/post-tool-failure.sh": { "origin_hash": "<sha256_hook_5>", "path": ".claude/hooks/post-tool-failure.sh" },
    ".claude/hooks/stop-checks.sh": { "origin_hash": "<sha256_hook_6>", "path": ".claude/hooks/stop-checks.sh" },
    ".claude/hooks/subagent-stop.sh": { "origin_hash": "<sha256_hook_7>", "path": ".claude/hooks/subagent-stop.sh" },
    ".claude/hooks/session-context.sh": { "origin_hash": "<sha256_hook_8>", "path": ".claude/hooks/session-context.sh" }
  }
}
```

Then create the cross-vendor symlink so the project works with any agent framework that resolves from `.agents/`:

```bash
ln -s .claude .agents
```

### 6f. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `api-migrate` — Alembic migration with safety gate (if SQLAlchemy/Alembic is wired up)
- `api-endpoint` — scaffold a new router + schema + service method

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

### 6g. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — verify the scaffold compiles clean and the API starts
2. the test utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/test/SKILL.md"` — verify all scaffold tests pass (`pytest test/ -v`)
3. the review utility (update operation) — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6h. Install Claude Code plugins

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

Once the project is verified, use the cleanup utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/cleanup/SKILL.md"`.

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