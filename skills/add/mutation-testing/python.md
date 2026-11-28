<!-- ref: add/mutation-testing/python.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Mutation Testing (mutmut)

Report-only mutation testing with mutmut. Run it on changed modules or one named module (`mutmut run "<module>*"`), not as a blanket gate.

> **Report-only by default.** The CI job uses `continue-on-error: true` — results appear in output without failing the build. To enforce a floor, run `mutmut export-cicd-stats` and threshold `killed / (total - skipped)` from `mutants/mutmut-cicd-stats.json` (`mutmut results` only lists surviving mutants).

### Dependencies

Add to `requirements-dev.txt` (create the file if absent):

```
mutmut==3.8.1
```

> The floor and why it is there: the plugin's `<skill-dir>/../../.claude/rules/fastapi.md`.

Install:

```bash
pip install -r requirements-dev.txt
```

### Steps

#### Step 1 — Add mutmut configuration

Add to `pyproject.toml`. Create the file at the project root if it does not exist:

```toml
[tool.mutmut]
source_paths = ["src/"]
pytest_add_cli_args_test_selection = ["test/"]
```

#### Step 2 — Update .gitignore

Append to `.gitignore`:

```
# mutmut mutation testing
mutants/
```

#### Step 3 — Add CI job

If `.github/workflows/` exists, add a `mutation` job to the primary workflow. It runs after tests pass and never fails the build:

```yaml
  mutation:
    runs-on: ubuntu-latest
    needs: [test]
    continue-on-error: true
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        with:
          python-version: "3.14"
          cache: "pip"
      # Runtime deps first — mutmut executes the test suite, which imports
      # fastapi/pydantic/structlog; requirements-dev.txt alone is not enough.
      - run: pip install --require-hashes -r requirements.txt
      - run: pip install -r requirements-dev.txt
      - run: mutmut run
      - run: mutmut results
```

### Validate

```bash
mutmut run       # paths come from pyproject.toml; prints the killed/survived/no-tests tally when done
mutmut results   # lists surviving (and untested) mutants — `mutmut show <name>` prints the diff
```
