<!-- ref: standards/code-standards/fastapi.md
     loaded-by: standards/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## FastAPI / Python

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `PascalCase` | `InterestSettings` |
| Functions | `snake_case` | `get_limits` |
| Constants | `UPPER_SNAKE_CASE` | `INTEREST_RATES` |
| Variables | `snake_case` | `age_in_months` |
| Type aliases | `PascalCase` | `DatedSchedules` |
| Private helpers | `_leading_underscore` | `_coerce_account` |
| Files | `snake_case.py` | `tiered_interest.py` |
| Directories | `snake_case` | `billing_data/` |
| Tests | `test_<function>_<scenario>` | `test_refund_raises_after_window` |

### Type Annotations

- Annotate all public function parameters and return types.
- Use Python 3.10+ union syntax: `int | None` (not `Optional[int]`).
- Use built-in generics: `list[str]`, `dict[str, int]`.
- Use `TypeAlias` for complex reusable types.

### Dataclasses

- Immutable: `@dataclass(frozen=True, slots=True)` — config, lookup data, parameters.
- Mutable: `@dataclass(slots=True)` — state that changes during processing.
- Use `__post_init__` for invariants; fail fast with clear `ValueError`.

### Function Design

- Prefer pure functions: inputs → outputs, no side effects.
- Isolate side effects; keep mutation in functions with `-> None`.
- Keep functions small and single-purpose.
- Use dict dispatch instead of long `if/elif` for key-based branching.

### Error Handling

- Use built-in exceptions with descriptive messages.
- `ValueError` for invalid values; `TypeError` for wrong types.
- Chain exceptions with `from` to preserve traceback.
- Avoid bare `except:` or broad `except Exception:` except at boundaries.
- Custom exceptions (`InvalidInputError`, `NoResultsFound`) for crossing layer boundaries.

### Imports

- Order: stdlib → third-party → local (separated by blank lines, enforced by Ruff).
- Use absolute imports only: `from models.base import BaseModel`.
- Import specific names, not modules.
- No wildcard imports (`from module import *`).
- Avoid barrel re-exports in `__init__.py` unless stable public API.

### Docstrings

- One-line for simple functions; short paragraph for complex ones.
- Focus on *what*, not *how*; inline comments explain *why*.

### Constants

- Include units when helpful (e.g. `HARD_LIMIT_CENTS`).
- Use underscores in numeric literals: `1_000_000`.
- Keep related constants grouped.

### Tooling

- **Ruff** — linting + isort (line-length 88, target version configured in `pyproject.toml` under `[tool.ruff]`).
- **pytest** — testing framework.
- **Pydantic v2** — API schemas with `BaseSchema` (camelCase aliases, `extra="forbid"`).
- NEVER use `@app.on_event("startup")` / `@app.on_event("shutdown")` — removed in Starlette 1.0. Use the `lifespan` context manager (`@asynccontextmanager async def lifespan(app): ...`) passed to `FastAPI(lifespan=lifespan)` instead.
- **Starlette floor.** A published security advisory (BadHost) lets malformed `Host` headers make `request.url.path` return incorrect values in older Starlette, enabling auth bypass in middleware-based path matching — the templateCentral plugin's `.claude/rules/fastapi.md` tracks the required Starlette floor. Prefer endpoint-level `Depends()`/`Security()` over middleware path-matching for auth-critical routes; `scope["path"]` is safe if you must read the path in middleware.

### Backend Testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `add-endpoint`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `pytest` from project root before handoff.

Use `json=data` in test clients (not `content=json.dumps(data)`) — FastAPI enforces `Content-Type: application/json` by default (`strict_content_type=True`), and `json=` sets it automatically.

### Dependency Rules

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

### Security (FastAPI)

**Environment & Secrets**
- All config via Pydantic `BaseSettings` — env vars loaded by `load_dotenv()` in `src/main.py`; NEVER use `os.environ` directly
- Secrets (`SECRET_KEY`, `DATABASE_URL`, API keys) go in `src/.env` — NEVER commit or hardcode
- Use `src/.env.default` for non-sensitive defaults only; secrets must be blank or absent

**Input Validation**
- All request bodies validated by Pydantic schemas with `extra="forbid"`
- NEVER skip `response_model` — it filters outgoing data
- Validate path/query params with FastAPI's type annotations

**CORS**
- In dev, `ALLOWED_CORS` is a fixed list of localhost origins — never `["*"]` with credentials
- In production, set `CORS_ORIGINS` env var; always set explicit methods and headers

**Auth**
- Hash passwords with `argon2id` (`argon2-cffi` package) — never store plaintext. Do not use `passlib` (unmaintained).
- JWT tokens: short expiry; use refresh tokens for long sessions
- NEVER return password hashes or internal IDs in API responses

**Least Privilege**
- Services return Pydantic `response_model` objects — NEVER return raw ORM objects
- NEVER log full request bodies that may contain passwords or PII