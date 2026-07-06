<!-- ref: add/mutation-testing/python.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Mutation Testing (mutmut)

Add report-only mutation testing to a FastAPI project scaffolded from templateCentral. Uses mutmut (the `requirements-dev.txt` floor below resolves the current major).

> **Report-only by default.** The CI job uses `continue-on-error: true` — results appear in output without failing the build. To enforce a floor, add a threshold check on `mutmut results`.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Dependencies

Add to `requirements-dev.txt` (create the file if absent):

```
mutmut>=3.5.0
```

Install:

```bash
pip install mutmut
```

### Steps

#### Step 0 — Verify context

Check `AGENTS.md` line 1 for `<!-- templateCentral: fastapi@`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### Step 1 — Add mutmut configuration

Add to `pyproject.toml`. Create the file at the project root if it does not exist:

```toml
[tool.mutmut]
paths_to_mutate = ["src/"]
tests_dir = "test/"
```

#### Step 2 — Update .gitignore

Append to `.gitignore`:

```
# mutmut mutation testing
.mutmut-cache
```

#### Step 3 — Add CI job

If `.github/workflows/` exists, add a `mutation` job to the primary workflow. It runs after tests pass and never fails the build:

```yaml
  mutation:
    runs-on: ubuntu-latest
    needs: [test]
    continue-on-error: true
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-python@v5
        with:
          python-version: "3.13"
          cache: "pip"
      - run: pip install -r requirements-dev.txt
      - run: mutmut run --paths-to-mutate src/ || true
      - run: mutmut results
        continue-on-error: true
```

### Validate

```bash
mutmut run --paths-to-mutate src/    # runs mutation tests
mutmut results                        # prints kill-rate summary
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — confirm no errors after config addition
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check config correctness
