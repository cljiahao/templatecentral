---
name: fastapi-code-standards
description: Use when writing or reviewing Python code in a FastAPI project — covers naming, types, imports, error handling, and layer dependency rules.
---

# FastAPI / Python Code Standards

## Code Quality (enforce before marking any task done)

- **YAGNI** — only what the task requires; no speculative helpers or files
- **DRY** — extract at second repetition; inline if only one callsite
- **SRP** — one responsibility per file/function; routers route, services orchestrate, models model
- **SoC** — routing separate from business logic; schema conversion in the service layer
- **No premature abstractions** — wait for the third callsite
- **No dead code** — no commented-out code, unused imports, or TODO stubs
- **Validate at boundaries** — Pydantic for all user input, API responses, and env vars
- **Fail loudly** — no bare `except`; log with context; return meaningful HTTP status codes
- **Least privilege** — use `response_model` to strip internal fields; never expose raw DB rows
- **No secrets** — no hardcoded tokens or keys; env vars only; document in `.env.example`

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `PascalCase` | `InterestSettings` |
| Functions | `snake_case` | `get_limits` |
| Constants | `UPPER_SNAKE_CASE` | `INTEREST_RATES` |
| Variables | `snake_case` | `age_in_months` |
| Type aliases | `PascalCase` | `DatedSchedules` |
| Private helpers | `_leading_underscore` | `_coerce_account` |
| Files | `snake_case.py` | `tiered_interest.py` |
| Directories | `snake_case` | `cpf_data/` |
| Tests | `test_<function>_<scenario>` | `test_withdrawal_raises_below_55` |

## Type Annotations

- Annotate all public function parameters and return types.
- Use Python 3.10+ union syntax: `int | None` (not `Optional[int]`).
- Use built-in generics: `list[str]`, `dict[str, int]`.
- Use `TypeAlias` for complex reusable types.

## Dataclasses

- Immutable: `@dataclass(frozen=True, slots=True)` — config, lookup data, parameters.
- Mutable: `@dataclass(slots=True)` — state that changes during processing.
- Use `__post_init__` for invariants; fail fast with clear `ValueError`.

## Function Design

- Prefer pure functions: inputs → outputs, no side effects.
- Isolate side effects; keep mutation in functions with `-> None`.
- Keep functions small and single-purpose.
- Use dict dispatch instead of long `if/elif` for key-based branching.

## Error Handling

- Use built-in exceptions with descriptive messages.
- `ValueError` for invalid values; `TypeError` for wrong types.
- Chain exceptions with `from` to preserve traceback.
- Avoid bare `except:` or broad `except Exception:` except at boundaries.
- Custom exceptions (`InvalidInputError`, `NoResultsFound`) for crossing layer boundaries.

## Imports

- Order: stdlib → third-party → local (separated by blank lines, enforced by Ruff).
- Use absolute imports only: `from models.base import BaseModel`.
- Import specific names, not modules.
- No wildcard imports (`from module import *`).
- Avoid barrel re-exports in `__init__.py` unless stable public API.

## Docstrings

- One-line for simple functions; short paragraph for complex ones.
- Focus on *what*, not *how*; inline comments explain *why*.

## Constants

- Include units when helpful (e.g. `HARD_LIMIT_CENTS`).
- Use underscores in numeric literals: `1_000_000`.
- Keep related constants grouped.

## Tooling

- **Ruff** — linting + isort (line-length 88, target version configured in `ruff.toml`).
- **pytest** — testing framework.
- **Pydantic v2** — API schemas with `BaseSchema` (camelCase aliases, `extra="forbid"`).

## Backend testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `add-endpoint`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `pytest` from project root before handoff.

Use `json=data` in test clients (not `content=json.dumps(data)`) — FastAPI 0.132+ requires `Content-Type: application/json` by default (`strict_content_type=True`), and `json=` sets it automatically.

## Dependency Rules

```
core/          (standalone — app infrastructure, config, logging)
api/           →  models/
 ├── routers/     ↑
 ├── services/    utils/
 └── schemas/
```

- `api/services/` contains business logic — called by `api/routers/`, never the reverse.
- `models/` **never** imports from `api/`.
- `core/` is standalone infrastructure — imported by `api/` but never by `models/`.
- `utils/` are pure helpers — importable by any layer.

## Security

### Environment & Secrets
- All config via Pydantic `BaseSettings` — env vars loaded by `load_dotenv()` in `src/main.py`; NEVER use `os.environ` directly in application code
- Secrets (`SECRET_KEY`, `DATABASE_URL`, API keys) go in `src/.env` — NEVER commit `src/.env` or hardcode secrets in source
- Use `src/.env.default` for non-sensitive defaults only; secrets must be blank or absent

### Input Validation
- All request bodies validated by Pydantic schemas with `extra="forbid"` — rejects unexpected fields automatically
- NEVER skip `response_model` — it filters outgoing data, preventing accidental exposure of internal fields
- Validate path/query params with FastAPI's type annotations — NEVER cast raw strings manually

### CORS
- In dev, `ALLOWED_CORS` is a fixed list of localhost origins (`localhost:3000`, `localhost:5173`, `127.0.0.1` variants) — never `["*"]` with credentials (CORS spec forbids it)
- In production, set `CORS_ORIGINS` env var (comma-separated origins); `_compute_allowed_cors()` in `src/core/config.py` reads it automatically
- Always set explicit methods and headers alongside `allow_credentials=True` — wildcard `["*"]` for methods/headers is invalid with credentials per the CORS spec

### Auth
- Hash passwords with `argon2id` (`argon2-cffi` package) — never store plaintext. Do not use `passlib` (unmaintained).
- JWT tokens should have short expiry; use refresh tokens for long sessions
- NEVER return password hashes or internal IDs in API responses

### Least Privilege
- Services return Pydantic `response_model` objects — NEVER return raw ORM/database objects directly
- Use `exclude` or explicit field selection to strip internal fields before returning
- NEVER log full request bodies that may contain passwords or PII

