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
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from api.routes import router
from core.config import api_settings, common_settings
from error_handler import configure_exceptions

_SECURITY_HEADERS = [
    (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"strict-origin-when-cross-origin"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
    (
        b"x-xss-protection",
        b"0",
    ),  # Disable legacy XSS auditor (exploitable in older browsers)
    # CSP baseline — tighten after auth/analytics are wired. frame-ancestors replaces X-Frame-Options for CSP2+ browsers.
    (
        b"content-security-policy",
        b"frame-ancestors 'none'; base-uri 'self'; object-src 'none'",
    ),
]


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def _send(message: Message) -> None:
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
                host = (
                    headers[b"x-forwarded-host"].decode("latin-1").split(",")[0].strip()
                )
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
from collections.abc import Sequence
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette import status

from core.exceptions import InvalidInputError, NoResultsFound
from core.logging import logger

INTERNAL_SERVER_ERROR_DETAIL = "Internal server error"


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
        logger.info("Invalid input", path=request.url.path, detail=str(exc))
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"detail": str(exc)},
        )

    @app.exception_handler(NoResultsFound)
    async def no_results_handler(request: Request, exc: NoResultsFound) -> JSONResponse:
        logger.info("No results found", path=request.url.path, detail=str(exc))
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
            path=request.url.path,
            errors=safe_errors,
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={"detail": safe_errors},
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled exception", path=request.url.path)
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
        return [
            origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()
        ]

    @field_validator("FASTAPI_ROOT", mode="before")
    @classmethod
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
import logging
import logging.handlers
import sys
from datetime import datetime as dt
from pathlib import Path
from typing import Any

import structlog

from core.config import common_settings
from core.directory_manager import directory_manager as dm

# Keys whose values are redacted anywhere in a log event — the structlog analogue of
# pino's `redact`. Matched case-insensitively; extend for your domain. Prefer this over
# scattered "never log X" comments: it is a safety net that holds even when a caller slips.
_SENSITIVE_KEYS = {
    "password",
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "cookie",
    "set-cookie",
    "secret",
    "api_key",
}


def _redact_sensitive(
    _logger: Any, _method_name: str, event_dict: dict[str, Any]
) -> dict[str, Any]:
    """Redact sensitive values by key, recursing into nested dicts (parity with pino's `*.token`)."""

    def scrub(value: Any) -> Any:
        if isinstance(value, dict):
            return {
                k: ("***" if k.lower() in _SENSITIVE_KEYS else scrub(v))
                for k, v in value.items()
            }
        return value

    return scrub(event_dict)


class MyTimedRotatingFileHandler(logging.handlers.TimedRotatingFileHandler):
    """Custom log handler that rotates log files daily and organizes them by month."""

    def __init__(self, **kwargs: Any) -> None:
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


# Processors shared by structlog (app) logs and stdlib (uvicorn/library) logs so both render
# identically. merge_contextvars pulls request-scoped context (e.g. request_id, bound per
# request in middleware) into every line and propagates it correctly across async/await.
_shared_processors: list[Any] = [
    structlog.contextvars.merge_contextvars,
    structlog.stdlib.add_logger_name,
    structlog.stdlib.add_log_level,
    structlog.stdlib.PositionalArgumentsFormatter(),
    structlog.processors.TimeStamper(fmt="iso"),
    structlog.processors.StackInfoRenderer(),
    structlog.processors.UnicodeDecoder(),
    _redact_sensitive,
]


def setup_logging() -> None:
    """Configure structlog + stdlib logging: JSON in prod/uat, colored console in dev."""
    env = common_settings.ENVIRONMENT
    use_json = env != "dev"

    # structlog side: run the shared chain, then hand the event to a stdlib formatter.
    structlog.configure(
        processors=[
            *_shared_processors,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    # stdlib side: one ProcessorFormatter renders BOTH structlog records and plain stdlib
    # records — uvicorn/library logs run through foreign_pre_chain first, so they match.
    def make_formatter(render: Any) -> structlog.stdlib.ProcessorFormatter:
        return structlog.stdlib.ProcessorFormatter(
            foreign_pre_chain=_shared_processors,
            processors=[
                structlog.stdlib.ProcessorFormatter.remove_processors_meta,
                *render,
            ],
        )

    console_render: list[Any] = (
        [structlog.processors.format_exc_info, structlog.processors.JSONRenderer()]
        if use_json
        else [structlog.dev.ConsoleRenderer(colors=True)]
    )

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(make_formatter(console_render))
    handlers: list[logging.Handler] = [console_handler]

    # Dev also writes daily-rotating JSON files; prod/uat log JSON to stdout only — never rely
    # on local disk in production (the platform ships stdout to the log aggregator).
    if not use_json:
        dm.create_directory(dm.log_dir)
        file_formatter = make_formatter(
            [structlog.processors.format_exc_info, structlog.processors.JSONRenderer()]
        )
        for filename, level in (("info.log", logging.INFO), ("errors.log", logging.ERROR)):
            file_handler = MyTimedRotatingFileHandler(
                filename=str(dm.log_dir / filename),
                when="midnight",
                encoding="utf8",
                delay=True,
            )
            file_handler.setLevel(level)
            file_handler.setFormatter(file_formatter)
            handlers.append(file_handler)

    root = logging.getLogger()
    root.handlers = handlers
    root.setLevel(logging.INFO if use_json else logging.DEBUG)


# Configure logging at import and expose a bound logger. Bind per-request context in
# middleware with structlog.contextvars.bind_contextvars(request_id=...); it flows to
# every line for that request automatically. Structured fields are passed as kwargs
# (logger.info("Event", key=value)), NOT via stdlib's extra={...}.
setup_logging()
logger: structlog.stdlib.BoundLogger = structlog.stdlib.get_logger(common_settings.ENVIRONMENT)
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
    return {"msg": "Hello FastAPI"}


@router.get(
    "/health",
    tags=[APITags.MISC],
    summary="Health Check",
    description="A simple health check returning an OK status.",
    response_model=dict[str, str],
)
async def health() -> dict[str, str]:
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
        extra="forbid",
        from_attributes=True,
        validate_assignment=True,
        validate_default=True,
        populate_by_name=True,
        alias_generator=to_camel,
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

### `test/test_utils/test_logging.py`

```python
"""Tests for the structlog configuration in core.logging."""

import logging

import pytest

from core.logging import _redact_sensitive, logger, setup_logging


@pytest.mark.unit
def test_logger_supports_structured_calls() -> None:
    """The exported logger binds context and exposes structlog methods."""
    bound = logger.bind(request_id="test-123")
    assert hasattr(bound, "info")
    assert hasattr(bound, "exception")


@pytest.mark.unit
def test_setup_logging_is_idempotent() -> None:
    """Re-running setup_logging replaces root handlers rather than stacking them."""
    setup_logging()
    first = len(logging.getLogger().handlers)
    setup_logging()
    assert len(logging.getLogger().handlers) == first
    assert first >= 1


@pytest.mark.unit
def test_sensitive_keys_are_redacted_recursively() -> None:
    """The redaction processor masks sensitive keys at any nesting depth."""
    event = {"password": "hunter2", "user": {"token": "abc"}, "path": "/x"}
    result = _redact_sensitive(None, "info", event)
    assert result["password"] == "***"
    assert result["user"]["token"] == "***"
    assert result["path"] == "/x"
```

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
git init
python -m venv .venv
source .venv/bin/activate   # Linux/Mac

pip install "fastapi>=0.136" "uvicorn[standard]" "pydantic>=2.9.0" pydantic-settings python-dotenv python-multipart "structlog>=25.1" "starlette>=1.0.1"
pip install -r requirements-dev.txt

pip freeze > requirements.txt
```

**Checkpoint**: Run `pip check` to detect dependency conflicts. Fix before proceeding.

### 5. Verification gate (do not proceed until this passes)

```bash
python src/main.py &       # starts server; confirm http://localhost:8000 responds
python -m pytest test/ -v  # all tests must pass
ruff check src/            # zero lint errors
ruff format --check src/   # zero formatting drift
python -m pyright src/     # zero type errors
```

> Run `ruff format src/` once first if this is a fresh scaffold — formatting drift on newly generated files will cause the format check to fail until formatted.

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
python src/main.py            # dev server (http://localhost:8000)
python -m pytest test/ -v     # run tests (from project root)
ruff check src/               # lint
ruff format src/              # format
python -m pyright src/        # type check
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

## Rules (always)
- Type annotations on all public function parameters and return types
- All user input validated with Pydantic at every boundary; use `response_model` to strip internal fields
- snake_case files/functions/variables; PascalCase classes; UPPER_SNAKE_CASE constants
- No secrets in code — use env vars; document in `.env.example`
- Comments explain *why*, not *what* — no commented-out code (Ruff `ERA`), no change-narration (`# was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

## AI Harness
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`; a second Bash guard blocks `--no-verify` and force-pushes to protected branches. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/clear/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
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

### 6b. Seed the agent harness (shared kit)

Load the shared harness kit using the **fastapi** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Execute kit Steps **A through D** now (settings.json, hook scripts, FUTURE.md, CONSTITUTION.md). Then continue with step 6c below to create the verify skill. After step 6c, execute kit Steps **E through H** (harness.json requires the verify skill to exist first — Step E's prerequisites note explains this).

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

### 6d. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `api-migrate` — Alembic migration with safety gate (if SQLAlchemy/Alembic is wired up)
- `api-endpoint` — scaffold a new router + schema + service method

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

Now execute kit Steps **E through H** using the **fastapi** row: harness.json (Step E — includes the `api-verify` skill hash), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail check (Step G — the `## AI Harness` and `## Skills Security` sections are already embedded above, so skip the append), and plugin install (Step H).

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

### 8. Task management (optional)

Ask whether the user wants structured task management for complex features. If yes, append this to the project's `AGENTS.md`:

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`. Skip for single-file edits or quick fixes.
```

If no, skip.

### 9. Remove example code (optional)

Once the project is verified, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

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