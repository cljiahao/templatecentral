<!-- ref: scaffold/shared/harness-kit.md
     loaded-by: scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; scaffold app+config files already written (or migrate Phase 4/5 in progress). Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit

This file is the index of the single source of truth for the Claude Code agent harness seeded into every scaffolded project. Read the **Per-stack delta table** first, then execute ALL steps in the **Step order** below using the row matching the current stack.

---

## Kit files

The kit is split by stack so a run never loads the other stack's script bodies. The loader (a scaffold stack file or a migrate phase file) cats this index plus exactly three part files — the stack's **one** variant file and both shared files:

| File | Holds | Load for |
|---|---|---|
| `harness-kit-ts.md` | TS bodies for Steps A, B, B2: `settings.json`, the 7 per-stack hooks (`user-prompt-guard.cjs`), `lefthook.yml` | nestjs · nextjs · vite-react |
| `harness-kit-fastapi.md` | FastAPI bodies for Steps A, B, B2, B3: `settings.json`, the 7 per-stack hooks (`user-prompt-guard.py`), `lefthook.yml`, the CI `quality` job | fastapi |
| `harness-kit-enforcement.md` | Step A/B/B2 shared rules + stack-agnostic files (`comment-hygiene-patterns.txt`, `session-context.sh`, `skill-usage-log.sh`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`); Steps B3, B4, B5 | every stack |
| `harness-kit-finalize.md` | Steps C, D, E, E2, E3, F, G, H + the shared AGENTS.md tail fragment | every stack |

## Step order

| Step | Seeds | Where |
|---|---|---|
| A | `.claude/settings.json` | variant (JSON body) + enforcement (merge rules, deny lists, hook inventory) |
| B | `.claude/hooks/` scripts | variant (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`) + enforcement (`comment-hygiene-patterns.txt`, `session-context`, `skill-usage-log`, `chmod`) |
| B2 | git-hook layer | variant (`lefthook.yml`) + enforcement (`.lefthook/commit-msg.sh`, `.gitleaks.toml`, install wiring) |
| B3 | CI quality gates (`.github/workflows/ci.yml`) | enforcement (workflow + TS `quality` job) + fastapi variant (FastAPI `quality` job) |
| B4 | harness integrity verifier | enforcement |
| B5 | `/skill-audit` project skill | enforcement |
| C, D | `FUTURE.md`, `docs/CONSTITUTION.md` | finalize |
| E, E2, E3 | `.claude/harness.json`, base snapshot, per-folder docs | finalize |
| F, G, H | `.agents` symlink, post-scaffold workflow, plugins | finalize |

For Steps A, B, B2 (and B3 on FastAPI) the enforcement file's section is the step: write the variant file's blocks for that step as part of it.

---

## Per-stack delta table

| Stack | JSON-parsing runtime | Typecheck feedback cmd | Stop-checks test cmd | Verify-skill name(s) | Quality-gate line in CONSTITUTION §6 |
|-------|----------------------|------------------------|----------------------|----------------------|---------------------------------------|
| **fastapi** | `python3` | `python -m pyright src/` (errors → `additionalContext`) | `python -m pytest test/ -q` | `api-verify` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` (the `/api-verify` skill) |
| **nestjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `nest-verify` | `pnpm check` |
| **nextjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `next-verify` + `next-migrate` | `pnpm check` |
| **vite-react** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `vite-verify` | `pnpm check` |

**Additional per-stack notes:**
- `user-prompt-guard` filename: `user-prompt-guard.py` for **fastapi**; `user-prompt-guard.cjs` for all TS stacks (`.cjs`, not `.js` — the scaffold's `package.json` sets `"type": "module"` for Next.js/Vite+React, which makes plain `.js` load as ESM and `require()` throw; `.cjs` forces CommonJS regardless of that field).
- `user-prompt-guard` settings.json invocation: `"command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/user-prompt-guard.py"]` (fastapi) vs `"command": "node", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/user-prompt-guard.cjs"]` (TS stacks).
- `harness.json` `"stack"` value: use the lowercase stack name (`fastapi` / `nestjs` / `nextjs` / `vite-react`).
- `harness.json` verify-skill path: use the stack's verify-skill name(s) from the table above (next.js has two skills).
- CLAUDE.md hash in `harness.json`: all stacks use the conditional form `[ -f CLAUDE.md ] && sha256_claude=$(...)` — CLAUDE.md is created in a later optional step.
