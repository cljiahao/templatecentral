<!-- ref: scaffold/shared/harness-kit-fastapi.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/fastapi/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified as FastAPI; harness-kit.md (index + delta table) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — FastAPI

Stack delta for kit Steps A, B, B2 and B3. `TC_PART=base` copies the 7 per-stack hooks (`.claude/hooks/protect-files.sh`, `block-no-verify.sh`, `user-prompt-guard.py`, `post-edit-typecheck.sh`, `post-edit-comment-check.sh`, `stop-checks.sh`, `subagent-stop.sh`) and `lefthook.yml` from `template-py/`; `TC_PART=settings` copies `.claude/settings.json` from `template-settings-py/`; `TC_PART=ci` copies the `quality` job (`template-ci/github-py/`, `azure-py/`). Each script's header states its behaviour.

> **Re-sync hooks after Step 0:** run `lefthook install` (inside the venv) once `lefthook.yml` is copied. Step 4's `pip install -r requirements-dev.txt` does not auto-run it the way the TS `prepare` script does, so `.git/hooks` is empty until this runs.
