<!-- ref: scaffold/shared/harness-kit-fastapi.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/fastapi/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified as FastAPI; harness-kit.md (index + delta table) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — FastAPI bodies

Per-stack content for kit Steps A, B, B2, and B3 (FastAPI): notes on the `settings.json` that Step A copies from `template-settings-py/`, and notes on the per-stack hooks, `lefthook.yml` and the CI `quality` job, which are real files under `template-py/` and `template-ci/github-py/` that `harness-kit.md` Step 0 and `harness-kit-enforcement.md` Step B3 copy. The other stack's bodies live in `harness-kit-ts.md` — do not load it.

---

## Step A — `.claude/settings.json` (FastAPI)

`.claude/settings.json` — Step A copies it (`PART=settings` of the Step 0 script) from `<skill-dir>/shared/template-settings-py/.claude/settings.json`; it already names the stack's `user-prompt-guard` runtime.

FastAPI: identical shape to the TS body; `UserPromptSubmit` runs `python3` on `user-prompt-guard.py` and the typecheck/test scripts use `pyright`/`pytest`.

---

## Step B — hook scripts (FastAPI)

`.claude/hooks/protect-files.sh` (canonical — hard-blocks secrets, `secrets/*`, `.secrets/*` and certs; asks before CI and governance edits). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/protect-files.sh` (uses `python3` for JSON parsing).

---

`.claude/hooks/block-no-verify.sh` (runtime varies for JSON parsing only; logic is identical). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/block-no-verify.sh` (uses `python3`).

---

`.claude/hooks/user-prompt-guard.py` (FastAPI only). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/user-prompt-guard.py`.

---

`.claude/hooks/post-edit-typecheck.sh` (typecheck command differs by stack — see delta table). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/post-edit-typecheck.sh` (uses `python3` + `pyright`).

---

`.claude/hooks/post-edit-comment-check.sh` (comment scanner — patterns from `.claude/comment-hygiene-patterns.txt`). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/post-edit-comment-check.sh` (uses `python3` for JSON parsing).

---

`.claude/hooks/stop-checks.sh` (test command differs by stack — see delta table). The early exit on a clean tree means a turn that changed nothing (or already committed its work — pre-commit/pre-push and CI gate that path) never pays for a test run; Claude Code also caps consecutive Stop-hook continuations at 8 by default (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/stop-checks.sh` (uses `python3` + `pytest`).

---

`.claude/hooks/subagent-stop.sh` (file extension and typecheck command differ by stack). Step 0 copies it from `<skill-dir>/shared/template-py/.claude/hooks/subagent-stop.sh` (checks `.py`, uses `pyright`).

---

## Step B2 — `lefthook.yml` (FastAPI)

`lefthook.yml` FastAPI (Python tools; no pnpm). Step 0 copies it from `<skill-dir>/shared/template-py/lefthook.yml`.

> **Re-sync hooks after writing this file:** run `lefthook install` (inside the venv) now, after Step 0 has copied this file — Step 4's `pip install -r requirements-dev.txt` does not auto-run it the way the TS `prepare` script does, so `.git/hooks` is empty until this runs at least once.

---

## Step B3 — `.github/workflows/ci.yml` `quality` job (FastAPI)

`.github/workflows/ci.yml` FastAPI (swap the `quality` job; the `changelog`, `readme-freshness`, and `comment-hygiene` jobs and the Azure Pipelines template are identical). The CI copy in `harness-kit-enforcement.md` Step B3 places it from `<skill-dir>/shared/template-ci/github-py/.github/workflows/ci.yml`.
