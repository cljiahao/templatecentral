# Architecture

Codemap. Update it in the same change that moves a layer or a shared module.

## Layers

| Layer | Owns |
|-------|------|
| `src/api/routers/` | Thin HTTP handlers: accept a body, call a service, return the result. |
| `src/api/schemas/` | Request and response models. |
| `src/api/services/` | Orchestration of one use case. |
| `src/logic/` | Business rules with no HTTP knowledge. |
| `src/models/` | Domain models. |
| `src/core/` | Config, logging, exceptions, security headers. |
| `src/constants/`, `src/utils/` | Shared constants and small helpers. |

## Dependency direction

`routers` → `services` → `logic` → `models`. Never reversed. `core`, `utils` and `constants` import from no layer above them (`core` → `utils` → `constants`). Imports are absolute; `import-linter` (contract in `pyproject.toml`) names the broken layer rule.

## Reuse

Search these places before creating a new helper.

| Need | Look in |
|------|---------|
| Utilities | `src/utils/` |
| Validation | `src/api/schemas/` (Pydantic) |
| Error handling | `src/core/exceptions.py`, `src/error_handler.py` |
| Logging | `src/core/logging.py` |
| Constants and config | `src/constants/`, `src/core/config.py` |
| Test factories | `test/factories/` |
