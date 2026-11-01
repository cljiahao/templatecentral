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

- Annotate all public parameters and return types; `int | None` (not `Optional[int]`), built-in generics (`list[str]`), `TypeAlias` for complex reusable types.

### Dataclasses

- Immutable: `@dataclass(frozen=True, slots=True)` — config, lookup data, parameters.
- Mutable: `@dataclass(slots=True)` — state that changes during processing.
- Use `__post_init__` for invariants; fail fast with clear `ValueError`.

### Function Design

- Prefer small, pure, single-purpose functions; isolate mutation in `-> None` functions.
- Dict dispatch over long `if/elif` for key-based branching.

### Error Handling

- Built-in exceptions with descriptive messages (`ValueError` for values, `TypeError` for types).
- Chain exceptions with `from` to preserve traceback.
- Avoid bare `except:` or broad `except Exception:` except at boundaries.
- Custom exceptions (`InvalidInputError`, `NoResultsFound`) for crossing layer boundaries.

### Imports

- Order: stdlib → third-party → local (separated by blank lines, enforced by Ruff).
- Use absolute imports only: `from models.base import BaseModel`.
- Import specific names, not modules.
- No wildcard imports (`from module import *`).
- Avoid barrel re-exports in `__init__.py` unless stable public API.

### Comments & Docstrings

- Follow `code-standards/comments.md`.
- Docstrings: one-line for simple functions, short paragraph for complex ones; describe the contract (args, returns, behavior), not the implementation.
- Keep Ruff's comment rules in `pyproject.toml` (`comments.md` → Enforcement).

### Static Analysis (`ruff`)

`pyproject.toml` pins `[tool.ruff.lint] select` (not `extend-select`, which would add to ruff's large default set): `E4`/`E7`/`E9`/`F`, `I`, `B`, `S`, `FAST`, `SIM`/`C4`/`RET`, `PT`, `PIE`, `UP`, and comment hygiene (`ERA`, `PGH003`, `PGH004`, `RUF100`, `TD005`). `S101`/`S105` are off under `test/**`. Not enabled: `PL`, `ANN`, `ARG` (framework callback signatures), `TRY`/`EM`, `DTZ`, `FIX`, `TD001`–`TD004`/`TD006`/`TD007`.

### Constants

- Include units when helpful (e.g. `HARD_LIMIT_CENTS`).
- Use underscores in numeric literals: `1_000_000`.
- Keep related constants grouped.

### Tooling

- **Ruff** — linting + isort (line-length 88, target version configured in `pyproject.toml` under `[tool.ruff]`).
- **pytest** — testing framework.
- **Pydantic v2** — API schemas with `BaseSchema` (camelCase aliases, `extra="forbid"`).
- NEVER use `@app.on_event("startup")` / `@app.on_event("shutdown")` — removed in Starlette 1.0. Use the `lifespan` context manager (`@asynccontextmanager async def lifespan(app): ...`) passed to `FastAPI(lifespan=lifespan)` instead.
- **Starlette floor** (`.claude/rules/fastapi.md`): older Starlette lets a malformed `Host` header corrupt `request.url.path`, bypassing middleware path-matching auth. Prefer endpoint-level `Depends()`/`Security()` for auth-critical routes; read `scope["path"]` if middleware must match paths.

### Backend Testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `templatecentral:add (endpoint)`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `python -m pytest test/ -q` from project root before handoff.

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
- All config via Pydantic `BaseSettings` — env vars are loaded via `pydantic-settings`, which reads `src/.env` directly (works under both the direct `python src/main.py` and the Docker `uvicorn app:app --app-dir src` entry paths); NEVER use `os.environ` directly
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