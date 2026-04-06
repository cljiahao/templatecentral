# FastAPI Template

A production-ready FastAPI backend template with layered design, Pydantic v2 schemas, structured logging, and Docker support.

## Stack

- **FastAPI 0.116** with automatic OpenAPI docs
- **Uvicorn** ASGI server with auto-reload in dev
- **Pydantic v2** for data validation with camelCase aliases
- **Pydantic Settings** for environment-based configuration
- **Structured JSON logging** with timed rotating file handler
- **Ruff** for linting and import sorting
- **pytest** with importlib mode
- **Docker** multi-stage build (dev + prod targets)

## Architecture

Layered design with strict dependency rules:

```
core/          (standalone — app infrastructure, config, logging)
api/           →  models/
 ├── routers/     ↑
 ├── services/    utils/
 └── schemas/
```

- `api/services/` contains business logic — called by `api/routers/`, never the reverse
- `models/` never imports from `api/`
- `core/` is standalone infrastructure — imported by `api/` but never by `models/`
- `utils/` are pure helpers — importable by any layer

### Request Flow

```
HTTP Request
  → Router (Pydantic validation)
  → Service (business logic + orchestration)
  → Response
```

## Project Structure

```
├── pyproject.toml                # Ruff + pytest config
├── requirements-dev.txt          # Dev deps (references src/requirements.txt)
├── Dockerfile                    # Multi-stage build (dev/prod)
├── docker-entrypoint.sh          # Framework auto-detection
├── .dockerignore                 # Production-optimized
├── .gitignore
├── .env.example
├── src/
│   ├── main.py                   # Entry point (env loading, Uvicorn)
│   ├── app.py                    # FastAPI app factory (CORS, errors, router)
│   ├── error_handler.py          # Centralized exception → HTTP response mapping
│   ├── requirements.txt          # Runtime dependencies
│   ├── .env.default              # Environment variable template
│   ├── api/                      # HTTP layer
│   │   ├── routes.py             # Root router (includes sub-routers)
│   │   ├── tags.py               # APITags enum for OpenAPI grouping
│   │   ├── routers/              # Endpoint handlers (thin — call services)
│   │   │   └── example.py        # Example router
│   │   ├── schemas/              # Pydantic request/response models
│   │   │   ├── base.py           # BaseSchema (camelCase, extra=forbid)
│   │   │   ├── request/          # Request schemas
│   │   │   └── response/         # Response schemas
│   │   └── services/             # Business logic (parse → process → serialize)
│   │       └── example.py        # Example service
│   ├── models/                   # Domain dataclasses (no API imports)
│   │   └── base.py               # BaseModel + BaseImmutableModel
│   ├── utils/                    # Pure utility functions
│   │   └── date.py               # Date conversion helpers
│   └── core/                     # App infrastructure
│       ├── config.py             # Pydantic Settings (CommonSettings, APISettings)
│       ├── exceptions.py         # Domain exceptions (InvalidInputError, NoResultsFound)
│       ├── logging.py            # JSON-based logging with timed rotation
│       ├── directory_manager.py  # Directory creation utilities
│       └── json/
│           └── logging.json      # Logging configuration
└── test/                         # Tests
    ├── conftest.py               # Shared fixtures (TestClient)
    ├── factories/                # Factory functions for test data
    │   └── models.py
    └── test_api/                 # API endpoint tests
        ├── test_health.py
        └── test_example.py
```

## Getting Started

```bash
# Set up virtual environment
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt

# Create env file
cp src/.env.default src/.env

# Run
cd src
python main.py
```

The API starts at `http://localhost:8000` with auto-reload in dev mode.

## Docker

```bash
# Development (hot reload)
docker build --target dev -t my-api:dev .
docker run -p 8000:8000 -v $(pwd):/app my-api:dev

# Production
docker build --target prod -t my-api:prod .
docker run -p 8000:8000 my-api:prod
```

## Testing

```bash
pytest test/                    # All tests
pytest test/ -m unit            # Unit tests only
pytest test/test_api/           # API tests only
```

## Linting

```bash
ruff check src/ test/           # Lint
ruff check src/ test/ --fix     # Autofix
ruff format src/ test/          # Format
```

## Configuration

Settings loaded from environment variables (or `.env` file):

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | My Project | API title in docs |
| `PROJECT_VERSION` | v1.0.0 | API version |
| `ENVIRONMENT` | dev | dev / uat / prod |
| `FASTAPI_ROOT` | (empty) | Root path prefix |
| `API_PORT` | 8000 | Server port |

## Error Handling

Centralized in `error_handler.py`:

| Exception | HTTP Status | Use Case |
|-----------|------------|----------|
| `InvalidInputError` | 400 | Domain validation failure |
| `NoResultsFound` | 404 | Lookup returned nothing |
| `HTTPException` | varies | FastAPI built-in |
| `RequestValidationError` | 422 | Pydantic validation |
| `Exception` | 500 | Unhandled (message sanitized) |

## Customization Points

- `src/core/config.py` — Add new settings classes
- `src/core/exceptions.py` — Add domain-specific exceptions
- `src/api/tags.py` — Add API tag groups for OpenAPI
- `src/api/routes.py` — Register new routers
- `src/api/schemas/base.py` — Customize schema behavior
- `src/requirements.txt` — Add project dependencies
- `pyproject.toml` — Ruff rules, pytest markers
