---
name: fastapi-scaffold
description: Scaffold a new FastAPI project with layered architecture, Pydantic validation, and Docker support
version: "1.0.0"
---

# Scaffold FastAPI Project

## Inputs

- **Project name** — The name for the new project (e.g., `my-api`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-api`). If not provided, default to `./<project-name>` and confirm with the user.

---

## Part A — Rules

### Dependencies

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate   # Linux/Mac

# Install runtime deps (no versions — resolves latest)
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart python-json-logger

# Install dev deps
pip install pytest httpx ruff mypy pytest-asyncio

# Generate requirements.txt
pip freeze > requirements.txt
```

### Directory Structure

```
<project-root>/
├── Dockerfile                              [verbatim]
├── docker-entrypoint.sh                    [verbatim]
├── .dockerignore                           [verbatim]
├── .gitignore                              [verbatim]
├── .env.example                            [verbatim]
├── pyproject.toml                          [verbatim]
├── requirements.txt                        [generate — pip freeze output]
├── requirements-dev.txt                    [generate — package names, no pins]
├── README.md                               [generate]
├── AGENTS.md                               [generate — after verification gate]
├── src/
│   ├── .env.default                        [verbatim]
│   ├── main.py                             [verbatim]
│   ├── app.py                              [verbatim]
│   ├── error_handler.py                    [verbatim]
│   ├── core/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   ├── config.py                       [verbatim]
│   │   ├── exceptions.py                   [verbatim]
│   │   ├── logging.py                      [verbatim]
│   │   ├── directory_manager.py            [verbatim]
│   │   └── json/
│   │       └── logging.json                [verbatim]
│   ├── api/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   ├── routes.py                       [verbatim]
│   │   ├── tags.py                         [verbatim]
│   │   ├── routers/
│   │   │   ├── __init__.py                 [verbatim — empty]
│   │   │   └── example.py                  [verbatim]
│   │   ├── schemas/
│   │   │   ├── __init__.py                 [verbatim — empty]
│   │   │   ├── base.py                     [verbatim]
│   │   │   ├── request/
│   │   │   │   ├── __init__.py             [verbatim — empty]
│   │   │   │   └── example.py              [verbatim]
│   │   │   └── response/
│   │   │       ├── __init__.py             [verbatim — empty]
│   │   │       └── example.py              [verbatim]
│   │   └── services/
│   │       ├── __init__.py                 [verbatim — empty]
│   │       └── example.py                  [verbatim]
│   ├── constants/
│   │   └── __init__.py                     [verbatim — empty]
│   ├── logic/
│   │   └── __init__.py                     [verbatim — empty]
│   ├── models/
│   │   ├── __init__.py                     [verbatim — empty]
│   │   └── base.py                         [verbatim]
│   └── utils/
│       ├── __init__.py                     [verbatim — empty]
│       └── date.py                         [verbatim]
└── test/
    ├── conftest.py                         [verbatim]
    ├── factories/
    │   ├── __init__.py                     [verbatim — empty]
    │   └── models.py                       [verbatim]
    ├── test_api/
    │   ├── __init__.py                     [verbatim — empty]
    │   ├── test_example.py                 [verbatim]
    │   └── test_health.py                  [verbatim]
    ├── test_logic/
    │   └── __init__.py                     [verbatim — empty]
    ├── test_models/
    │   └── __init__.py                     [verbatim — empty]
    └── test_utils/
        └── __init__.py                     [verbatim — empty]
```

### Generation Conventions

**[generate] README.md** — Generate a project README with: project name, brief description, stack (FastAPI, Python 3.13, Pydantic v2, Uvicorn, Ruff, pytest, Docker), quick-start commands (`source .venv/bin/activate`, `python src/main.py`, `pytest test/`, `ruff check src/`), and a note that example code can be removed with the `remove-example` skill.

**[generate] AGENTS.md** — Generated only after the verification gate passes (Step 5). See Step 6 for exact content. Must begin with `<!-- templateCentral: fastapi@1.0.0 -->` as line 1.

**[generate] requirements.txt** — Output of `pip freeze > requirements.txt` after installing all deps. Never write this file manually; always let `pip freeze` produce it.

**[generate] requirements-dev.txt** — Write this file with package names only (no version pins):
```
fastapi
uvicorn[standard]
pydantic
pydantic-settings
python-dotenv
python-multipart
python-json-logger
pytest
httpx
ruff
mypy
pytest-asyncio
```

---


## Part B — Verbatim Config Files

Load config file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/fastapi-scaffold/config-files.md"
```
Generate each file exactly as shown.

## Part C — Verbatim Source Files

Load source file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/fastapi-scaffold/source-files.md"
```
Generate each file exactly as shown.
