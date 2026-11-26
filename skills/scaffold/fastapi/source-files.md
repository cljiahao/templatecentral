<!-- ref: scaffold/fastapi/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes

The files are real files in `<skill-dir>/fastapi/template/` (`AGENTS.md` in `<skill-dir>/fastapi/template-agents/`, the verify skill at `.claude/skills/api-verify/SKILL.md`, which kit Step E hashes), listed in `<skill-dir>/fastapi/template.manifest`; `tc-copy.sh` copies them, so do not re-type or modify them. Notes:

- `requirements-dev.txt` — Dev-only dependencies, not installed in production Docker stages. `pytest-cov` is required by the seeded CI coverage gate (`pytest --cov=src --cov-report=xml`, harness-kit Step B3) — the FastAPI counterpart to the TS stacks' `@vitest/coverage-v8`.
- `pyrightconfig.json` — Pins pyright to `.venv`, so `python -m pyright src/` resolves imports when the venv is not active.
- `src/core/uvicorn_log_config.json` — Passed to the `uvicorn` CLI via `--log-config` in `docker-entrypoint.sh`. It clears uvicorn's own handlers and re-enables propagation, so uvicorn's startup/access logs get the same structlog JSON formatting as the app.

## Scaffold Steps

### 1. Create target directory and copy the template files

Create `<target>/`, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (later steps run it with other `PART` values).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=fastapi TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`.

Then write `README.md`: name, the one-sentence description from scaffold Step 1, and a Quickstart with the Step 3 commands and the `## Commands` section of `<skill-dir>/fastapi/template-agents/AGENTS.md`. Kit Step E3 never overwrites this prose; it only appends `## Structure`.

Do not create `requirements.txt` yet: Step 3 writes `requirements.in` (direct runtime dependencies) and compiles it into the hashed `requirements.txt`. From then on edit `requirements.in` only, then recompile with `uv pip compile requirements.in --universal --generate-hashes -o requirements.txt`.

### 2. Update project settings

In `src/core/config.py`, update the `CommonSettings` defaults:
- `PROJECT_NAME` — Set to the project name supplied by the user
- `PROJECT_DESCRIPTION` — Set to a relevant one-sentence description
- `PROJECT_VERSION` — Set to `"v0.1.0"` (or user's preferred version)

`CommonSettings` loads `src/.env`, whose values win over these defaults, so set the same `PROJECT_NAME` and `PROJECT_VERSION` in `src/.env.default` too. The user runs `cp src/.env.default src/.env` themselves; the seeded guards block agent access to a real env file, so never read or write one. Continue without it: the quality gates run on the defaults.

### 3. Set up virtual environment and install dependencies

```bash
git init
python3.14 -m venv .venv    # Python 3.14 — matches the Dockerfile image, ruff target-version and pyright pythonVersion
source .venv/bin/activate   # Linux/Mac

# certifi floor: older bundles still trust the compromised eMudhra intermediate CAs (Oct 2026).
cat > requirements.in <<'REQ'
fastapi>=0.162.5
uvicorn[standard]
pydantic>=2.14.3
pydantic-settings
python-dotenv
python-multipart>=0.0.33
structlog>=26.1.0
starlette>=1.10.0
certifi>=2026.10.23
REQ

# uv comes from pip inside the venv. The Dockerfile's prod-deps stage installs requirements.txt with
# --require-hashes, so requirements.in lists runtime packages only.
pip install uv==0.13.7
uv pip compile requirements.in --universal --generate-hashes -o requirements.txt
pip install --require-hashes -r requirements.txt

pip install -r requirements-dev.txt
```

**Checkpoint**: Run `pip check` to detect dependency conflicts. Fix before proceeding.

### 4. Verification gate (do not proceed until this passes)

```bash
ruff format src/           # format fresh files once, so the format check below passes
python -m uvicorn --app-dir src app:app --port 8000 & server=$!   # no --reload: $server is the server itself
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://localhost:8000/health; kill "$server"
python -m pytest test/ -v  # all tests must pass
ruff check src/            # zero lint errors
ruff format --check src/   # zero formatting drift
python -m pyright src/     # zero type errors
```

Do not copy `AGENTS.md` until all checks pass. The gate probes only `/health`: before handing off, also check that the Swagger docs render.

### 6. Write project AGENTS.md
Run kit Step **0** again as `TC_STACK=fastapi TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`, then replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title (the Edit tool). The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing. Check that no placeholder is left anywhere in the project; the command must print nothing:

```bash
grep -rn '__TC_' . --exclude-dir=.venv --exclude-dir=.git
```

### 6b. Seed the agent harness (shared kit)

Load the rest of the kit, with the **fastapi** variant:

```bash
cat "<skill-dir>/shared/harness-kit-fastapi.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Run kit Step **0** now as `TC_STACK=fastapi TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: FastAPI has no `prepare` script for lefthook to hook into, so nothing at install time needs `lefthook.yml`. Then run `lefthook install` inside the venv (`requirements-dev.txt` already installed it), then kit Steps **A through D** (each `tc-copy.sh` run with `TC_STACK=fastapi`).

### 7. `CLAUDE.md` and task management (optional)

Use the scaffold Step 1 answers. If `CLAUDE.md` is wanted, create `CLAUDE.md` at the project root with exactly one line (kit Step E hashes it into `seeded_files`):

```
@AGENTS.md
```

If task management is wanted, append its section to `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/fastapi/template-tail/task-management.md" >> AGENTS.md
```

Then, whatever the answers above, run kit Steps **E through H**: the scaffold is not finished until Step H is done or skipped.

### 8. Remove example code (optional)

Use the scaffold Step 1 answer on removing example code. If yes, once the project is verified, load the cleanup utility with `cat "<skill-dir>/../cleanup/SKILL.md"`.
