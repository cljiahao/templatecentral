<!-- ref: scaffold/shared/harness-kit-ts.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/{nestjs,nextjs,vite-react}/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified as TS stacks (nestjs / nextjs / vite-react); harness-kit.md (index + delta table) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — TS stacks (nestjs / nextjs / vite-react) bodies

Per-stack content for kit Steps A, B, and B2 (TS stacks (nestjs / nextjs / vite-react)): the `settings.json` body, written in Step A, and notes on the per-stack hooks and `lefthook.yml`, which are real files under `template-ts/` that `harness-kit.md` Step 0 copies. The other stack's bodies live in `harness-kit-fastapi.md` — do not load it.

---

## Step A — `.claude/settings.json` (TS stacks (nestjs / nextjs / vite-react))

`.claude/settings.json` — Step A copies it (`PART=settings` of the Step 0 script) from `<skill-dir>/shared/template-settings-ts/.claude/settings.json`; it already names the stack's `user-prompt-guard` runtime.

---

## Step B — hook scripts (TS stacks (nestjs / nextjs / vite-react))

`.claude/hooks/protect-files.sh` (canonical — hard-blocks secrets, `secrets/*`, `.secrets/*` and certs; asks before CI and governance edits). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/protect-files.sh` (uses `node` for JSON parsing).

---

`.claude/hooks/block-no-verify.sh` (runtime varies for JSON parsing only; logic is identical). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/block-no-verify.sh` (uses `node`).

---

`.claude/hooks/user-prompt-guard.cjs` (TS stacks only — `.cjs`, not `.js`; see the delta-table note above). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/user-prompt-guard.cjs`.

---

`.claude/hooks/post-edit-typecheck.sh` (typecheck command differs by stack — see delta table). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/post-edit-typecheck.sh` (uses `node` + `pnpm exec tsc`).

---

`.claude/hooks/post-edit-comment-check.sh` (comment scanner — patterns from `.claude/comment-hygiene-patterns.txt`). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/post-edit-comment-check.sh` (uses `node` for JSON parsing).

---

`.claude/hooks/stop-checks.sh` (test command differs by stack — see delta table). The early exit on a clean tree means a turn that changed nothing (or already committed its work — pre-commit/pre-push and CI gate that path) never pays for a test run; Claude Code also caps consecutive Stop-hook continuations at 8 by default (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/stop-checks.sh` (uses `node` + `pnpm test`).

---

`.claude/hooks/subagent-stop.sh` (file extension and typecheck command differ by stack). Step 0 copies it from `<skill-dir>/shared/template-ts/.claude/hooks/subagent-stop.sh` (checks `.ts|.tsx`, uses `pnpm exec tsc`).

---

## Step B2 — `lefthook.yml` (TS stacks (nestjs / nextjs / vite-react))

`lefthook.yml` TS stacks (nestjs / nextjs / vite-react). Step 0 copies it from `<skill-dir>/shared/template-ts/lefthook.yml`.

> **Hook install:** the TS stacks run Step 0 before their first `pnpm install`, so the `"prepare": "lefthook install || true"` script finds `lefthook.yml` and wires `pre-commit`/`pre-push` during that install. If an install ran before Step 0, it left a stub `lefthook.yml` and Step 0 refuses: report that to the user instead of working around it.
