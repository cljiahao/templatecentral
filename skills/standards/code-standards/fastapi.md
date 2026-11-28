<!-- ref: standards/code-standards/fastapi.md
     loaded-by: standards/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## FastAPI / Python

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Constants | `UPPER_SNAKE_CASE` | `INTEREST_RATES` |
| Type aliases | `PascalCase` | `DatedSchedules` |
| Private helpers | `_leading_underscore` | `_coerce_account` |
| Tests | `test_<function>_<scenario>` | `test_refund_raises_after_window` |

Ruff N801, N802, N806 and N999 (pep8-naming) enforce class, function, variable and module names. The rows above have no pinned rule.

### Type Annotations

- Annotate all public parameters and return types; `int | None` (not `Optional[int]`), built-in generics (`list[str]`), `TypeAlias` for complex reusable types.

### Dataclasses

- Immutable: `@dataclass(frozen=True, slots=True)` — config, lookup data, parameters.
- Mutable: `@dataclass(slots=True)` — state that changes during processing.
- Use `__post_init__` for invariants; fail fast with clear `ValueError`.

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

### Function Design

- Prefer small, pure, single-purpose functions; isolate mutation in `-> None` functions.
- Dict dispatch over long `if/elif` for key-based branching.

### Quality gate

Targets on new code, the SonarQube default gate: cognitive complexity 15, duplication 3%, coverage 80%. Enforced locally, with no server: ruff `select` in `pyproject.toml` (`C901` is cyclomatic, an approximation of cognitive complexity), `.jscpd.json` and `diff-cover --fail-under=80`.

### Constants

- Include units when helpful (e.g. `HARD_LIMIT_CENTS`).
- Use underscores in numeric literals: `1_000_000`.
- Keep related constants grouped.

### Tooling

- **Ruff** — linting + isort (line-length 88, target version configured in `pyproject.toml` under `[tool.ruff]`).
- **pytest** — testing framework.
- **Pydantic v2** — API schemas with `BaseSchema` (camelCase aliases, `extra="forbid"`).
- Do not use `@app.on_event("startup")` / `@app.on_event("shutdown")`: Starlette 1.0 removed them. Use the `lifespan` context manager (`@asynccontextmanager async def lifespan(app): ...`) passed to `FastAPI(lifespan=lifespan)` instead.
- **Starlette floor** (the plugin's `<skill-dir>/../../.claude/rules/fastapi.md`): older Starlette lets a malformed `Host` header corrupt `request.url.path`, bypassing middleware path-matching auth. Prefer endpoint-level `Depends()`/`Security()` for auth-critical routes; read `scope["path"]` if middleware must match paths.

### Testing

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
- All config via Pydantic `BaseSettings` — env vars are loaded via `pydantic-settings`, which reads `src/.env` directly (works under both the direct `python src/main.py` and the Docker `uvicorn app:app --app-dir src` entry paths); do not read `os.environ` directly
- Use `src/.env.default` for non-sensitive defaults only; secrets must be blank or absent

**Input Validation**
- All request bodies validated by Pydantic schemas with `extra="forbid"`
- Set `response_model` on every route; it filters outgoing data

**CORS**
- In dev, `allowed_cors` is a fixed list of localhost origins — never `["*"]` with credentials
- In production, set `CORS_ORIGINS` env var; always set explicit methods and headers

**Auth**
- Hash passwords with `argon2id` (`argon2-cffi` package) — never store plaintext. Do not use `passlib` (unmaintained).
