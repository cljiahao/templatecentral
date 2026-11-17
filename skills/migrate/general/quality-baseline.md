<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md; standards/drift-check/implementation.md → standards/SKILL.md
     prereq: Stack known. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline

**Target.** Sonar way on new code: 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%. Cognitive complexity 15 is the rule threshold behind "0 new issues".

## Modes

```bash
bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --static   # default
bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --full --label after
```

From the drift-check skill the path is `<skill-dir>/../migrate/general/quality-baseline.sh`. Run it once per package of a monorepo; for FastAPI activate the project's virtualenv first.

- `--static` counts files and lines. It runs no project script, test or hook and no tool, uses no network and installs nothing. Use it before any approval and in drift-check. Git reads the tree and may run filters that the user's git config defines. Neither mode intentionally writes to the project; the last row reports any write.
- `--full` runs the project's lint, typecheck and tests (project code executes) and installs the pinned tools named in the script header into its own scratch directory (network). Run it only after the user's yes to the quality pass or to drift-check Step 5. Each tool is limited to 10 minutes. `--keep-coverage <dir>` also copies the Cobertura XML to `<dir>/cobertura.xml`; the directory must be outside the project and its parent must exist.

Exit 2 is a usage error. The last row says `unchanged`, `unchanged in git; the run wrote ignored files: …` (logs or caches the project's own tests wrote; report them), or `CHANGED (…)`; on `CHANGED` stop and show the files it names.

## Read the output

- A number is the measurement. `n/a (reason)` means the tool or its input is absent or was not run; record it as it is, never estimate it, and name the missing tool in the report.
- `complexity over 15` for FastAPI is cyclomatic (Ruff C901), a proxy for Sonar's cognitive rule.
- `test cases` is a static count; a parametrized case counts once.
- The versions row lists the pins; an `after` run uses the same ones.

## Record

Note what later steps adapt to and never replace: test sharding, a coverage threshold above 80% (keep it), an existing Sonar or quality pipeline (read its config; call no remote service), workspace layout, another git-hook manager. `docs/quality-baseline.md` stays under 60 lines. The first baseline run after the user's consent creates it with the `before` column; the final run of the quality pass adds `after`. Drift-check compares against its latest column.
