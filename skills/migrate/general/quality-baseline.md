<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md; standards/drift-check/implementation.md → standards/SKILL.md
     prereq: Stack known. Writes no project file. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline (measure only)

**Target.** Sonar way on new code: 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%. Cognitive complexity 15 is the rule threshold behind "0 new issues".

## When to run

- Before any write (`implementation.md` Phase 2), with `--label before`.
- After a quality pass, with `--label after`, to fill the `after` column.
- From `standards/drift-check` Step 5, with the label `before` and no file written.

## Run

From the project root, or once per package of a monorepo, with the project's virtualenv active for FastAPI:

```bash
bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --label before
```

From the drift-check skill the path is `<skill-dir>/../migrate/general/quality-baseline.sh`. The script reads and writes nothing in the project, creates and removes its own scratch directory, never runs a project script, and calls each tool directly with the project's own config. It prints one markdown table; exit 2 is a usage error. A run can take several minutes; each tool is limited to 10 minutes.

## Read the output

- A number is the measurement. `n/a (reason)` means the tool or its input is absent; record it as it is, never estimate it. In the report, name the missing tool and offer to add it in the quality pass (a dependency change needs its own confirmation).
- `complexity over 15` for FastAPI is cyclomatic (Ruff C901), a proxy for Sonar's cognitive rule.
- `test cases` is a static count; a parametrized case counts once.
- `project tree after the run` must say `unchanged`. If it says `CHANGED`, stop, show `git status`, and tell the user which files a measurement wrote.
- The tool versions row is the pin; a later `after` run uses the same ones.

## Around the run

- Record what later steps adapt to and never replace: test sharding or matrix jobs, a coverage threshold above 80% (keep it), an existing Sonar or quality pipeline (read `sonar-project.properties`, the pipeline step and any local `.scannerwork/` report; call no remote service), workspace layout, another git-hook manager.
- For each non-zero count, list up to five worst offenders with file paths from the tool's own output (run that tool once, read-only).
- Print one table per package. The report written to `docs/quality-baseline.md` stays under 60 lines.
