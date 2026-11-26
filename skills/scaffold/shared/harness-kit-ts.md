<!-- ref: scaffold/shared/harness-kit-ts.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/{nestjs,nextjs,vite-react}/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified as TS stacks (nestjs / nextjs / vite-react); harness-kit.md (index + delta table) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — TS stacks (nestjs / nextjs / vite-react)

Stack delta for kit Steps A, B and B2. `TC_PART=base` copies the 7 per-stack hooks (`.claude/hooks/protect-files.sh`, `block-no-verify.sh`, `user-prompt-guard.cjs`, `post-edit-typecheck.sh`, `post-edit-comment-check.sh`, `stop-checks.sh`, `subagent-stop.sh`) and `lefthook.yml` from `template-ts/`; `TC_PART=settings` copies `.claude/settings.json` from `template-settings-ts/`. Each script's header states its behaviour.

> **Hook install:** the TS stacks run Step 0 before their first `pnpm install`, so the `"prepare": "lefthook install || true"` script finds `lefthook.yml` and wires `pre-commit`/`pre-push` during that install. If an install ran before Step 0, it left a stub `lefthook.yml` and Step 0 refuses: report that to the user instead of working around it.
