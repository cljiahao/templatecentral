<!-- templateCentral: fastapi@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
FastAPI 0.136+ · Python 3.14 · Pydantic v2 · Uvicorn · Ruff · pytest · pyright

## Commands
`python src/main.py` (localhost:8000) · `python -m pytest test/ -v` · `ruff check src/` · `ruff format src/` · `python -m pyright src/`

## Architecture
- Layered `api/` → `models/`; details in `.claude/rules/fastapi.md`
- Binding invariants (win on conflict): `docs/CONSTITUTION.md`. Path-specific guidance: `.claude/rules/`

## Rules
- Type annotations on all public parameters and return types
- Validate all input with Pydantic at every boundary; `response_model` strips internal fields
- snake_case files, functions, variables; PascalCase classes; UPPER_SNAKE_CASE constants
- No secrets in code: env vars, documented in `.env.example`
- Comments: default none; at most one short why-line above the code
- Tests: one per behaviour, parametrize siblings, none for constants, types or framework behaviour
- New-code gate: 0 new issues, coverage ≥80%, duplication ≤3%, cognitive complexity ≤15; fix the code, never exclude or suppress

## Skills
Plugin: `templatecentral:add` (auth, database, endpoint), `templatecentral:migrate`, `templatecentral:standards`. Project: `/api-verify`.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
