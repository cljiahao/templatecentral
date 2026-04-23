# AGENTS.md — templateCentral

templateCentral is a toolkit of project templates and skills for scaffolding new applications. It is NOT an application itself.

## Stack Detection

Detect the stack from the user's request or project files, then read the subagent's `AGENT.md` to find the right skill:

| Stack | Subagent | Template |
|-------|----------|----------|
| Next.js | `claude-skills/nextjs/AGENT.md` | `templates/nextjs/` |
| FastAPI | `claude-skills/fastapi/AGENT.md` | `templates/fastapi/` |
| Vite + React | `claude-skills/vite-react/AGENT.md` | `templates/vite-react/` |
| NestJS | `claude-skills/nestjs/AGENT.md` | `templates/nestjs/` |

Detection signals: `next.config.ts` → nextjs, `requirements.txt` with `fastapi` or `src/app.py` defining the FastAPI app → fastapi, `vite.config.ts` → vite-react, `nest-cli.json` or `@nestjs/core` in `package.json` → nestjs. If ambiguous, ask. Meta-tasks (auditing, adding stacks) stay with the orchestrator.

## Scaffolding flow (order matters)

1. Confirm stack → read `claude-skills/<stack>/AGENT.md` and `scaffold/SKILL.md`.
2. Copy template per skill; configure name/metadata; env **only** from `.env.example` / `.env.default` (no real secrets).
3. Install deps per scaffold (**Node**: default **`pnpm`**, `corepack enable` if needed; **Python**: venv then activate — Windows `.venv\Scripts\activate`, Unix `source .venv/bin/activate`); run **Scaffold verification** gates; fix failures before project docs.
4. Write the **new project’s** `AGENTS.md`, then `CLAUDE.md` if Claude Code — never before gates pass. If they use git: **`git init`**, first commit should include the **lockfile**, never `.env` / `.env.local` with real secrets.
5. Post-scaffold code changes: read the project’s `AGENTS.md` and stack **`code-standards/`** first. After non-trivial work, consider **Independent test workflow** (Tier 1) — a fresh session focused on tests only.

## Backend testing policy

Stacks with a backend (**FastAPI**, **NestJS**, **Next.js** server/API code) **MUST** include automated tests for new or changed backend behavior in the same change as the code:

- **FastAPI** — pytest for routers, services, and domain logic (`test/`).
- **NestJS** — Jest for controllers, services, and repositories (`test/`); e2e where the skill prescribes it.
- **Next.js** — Vitest for `src/app/api/**` and server-only logic they call (`test/api/`). **No** requirement to add tests for React components, pages, or client hooks.

Subagents read their stack’s `code-standards` skill before writing code; those standards include this rule. **Vite + React** is out of scope for this policy (frontend template only).

## Independent test workflow (recommended for AI sessions)

Backend tests must still land in the **same change / PR** as the feature (**Backend testing policy** above). The tiers below are about **who runs which chat or agent session** to reduce shared blind spots — not about deferring tests to a later PR.

| Tier | When | What to do |
|------|------|------------|
| **0 — Default** | Any implementation | Author adds tests in the same session; run **Scaffold verification** or project test/build commands. Often enough for small edits. |
| **1 — Test author (new session)** | After scaffold or a non-trivial feature | Start a **fresh** agent/chat. Role: *you did not write the production code* — read the project `AGENTS.md`, stack **`add-test/`** and **`code-standards/`**, then add or strengthen tests (error/edge paths and assertions appropriate to the stack: API status/validation, services, or UI per skill). Merge into the same branch before merge. |
| **2 — Test reviewer (another new session)** | **Selective** — auth, security-sensitive paths, payments, complex business rules, or pre-release hardening | Another fresh session reviews **only** the test files: missing cases, assertions that cannot fail, gaps vs stated behavior. **Not** required for every PR — use judgment to save time and tokens. |
| **Cheap check** | Always | **CI** runs the suite; fix failures. Prefer this over a third LLM when coverage is straightforward. |

**Token / cost note**: Tier 1 is a strong default for templateCentral-backed work. Tier 2 is **optional** quality insurance, not a mandatory third pass on every change.

## Security & secrets

- **Never** commit real secrets, production `.env` contents, or API keys. Scaffold and templates use `.env.example` / `.env.default` only; users or CI inject secrets at runtime.
- **Never** paste live credentials into `AGENTS.md`, `CLAUDE.md`, generated docs, or chat output. Rotate any secret that was exposed.
- **Never** commit private keys, `.pem` files, or SSH keys — if the project needs them locally, keep them out of git (`.gitignore`) and out of generated docs.
- **Never** put secrets in `NEXT_PUBLIC_*` (Next.js) or `VITE_*` (Vite) — both are exposed in the client bundle.
- **FastAPI**: In development, CORS allows `localhost:3000`, `localhost:5173`, and `127.0.0.1` variants automatically. In production, set `CORS_ORIGINS` env var (comma-separated) to your frontend's domain.
- **Production**: Replace template dev placeholders in env (e.g. NextAuth `AUTH_SECRET`, JWT secrets) with strong values before deploy — call this out in handoff when templates use placeholders.
- Follow each stack’s `code-standards` for auth, env vars, and least-privilege responses.

## Supply chain & reproducibility

- **Node projects**: Use the package manager the scaffold documents (**pnpm** for current templates); after first `pnpm install`, **commit the new lockfile**. Do not delete lockfiles or switch npm/pnpm/yarn without explicit user approval.
- **Python projects**: Install from the template’s `requirements-dev.txt` (or equivalent); do not loosen version pins without user approval.

## Scaffold verification (before project AGENTS.md / CLAUDE.md)

Do not write `AGENTS.md` or `CLAUDE.md` until the stack’s checks pass (fixes first):

| Stack | Required gates |
|-------|------------------|
| **Next.js** | `pnpm test`, `pnpm build`, `pnpm check` |
| **NestJS** | `pnpm test`, `pnpm test:e2e`, `pnpm build` |
| **FastAPI** | API responds, `pytest test/`, `ruff check src/` |
| **Vite + React** | `pnpm dev` OK, `pnpm test`, `pnpm build`, `pnpm check` |

## Subagent Boundaries

- NEVER invent APIs, libraries, or features not in the stack
- NEVER modify files outside the project directory
- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation
- NEVER remove or ignore lockfiles in scaffolded Node projects without explicit user approval
- NEVER scaffold into a **non-empty** target directory without explicit user confirmation (avoid overwriting existing apps)
- NEVER disable TLS verification in application code, HTTP clients, or scaffold scripts (`verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, etc.) unless the user explicitly approves a **narrow, documented dev-only** exception

## Shared Skills

Cross-stack skills available to all subagents — each stack's `AGENT.md` lists which apply. Always check `claude-skills/shared/` before inventing a pattern from scratch:

| Skill | When to use |
|-------|-------------|
| `shared/validation-patterns/` | Forms, API endpoints, file uploads — OWASP/CWE-compliant Zod/Pydantic patterns |
| `shared/add-error-handling/` | Consistent error responses and security boundaries; never expose stack traces |
| `shared/full-stack-pairing/` | Connecting a frontend to a backend (CORS, proxy, env wiring, auth headers) |
| `shared/add-pagination/` | Offset or cursor-based pagination for API routes and list UIs |
| `shared/remove-example/` | Removing template example/placeholder code after scaffolding |
| `shared/task-management/` | Complex multi-step features (3+ files, architectural decisions) — opt-in via project `AGENTS.md` |

## Scaffold: optional Task Management (single source of truth)

Ask whether the user wants structured task management. If **yes**, append **one** of the blocks below to the **new project’s** `AGENTS.md`. If **no**, skip.

**Option A — templateCentral protocol** (no plugin):

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions), follow `claude-skills/shared/task-management/SKILL.md` in templateCentral. Protocol: Plan → Verify → Track → Explain → Document → Capture Lessons. Skip for single-file edits or quick fixes.
```

**Option B — Superpowers** (Claude Code plugin):

```bash
claude plugin marketplace add pcvelz/superpowers
```

Then append:

```markdown
## Task Management

- **Simple tasks**: use templateCentral skills for this stack
- **Complex features** (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`
- All code must follow this file’s conventions and the stack’s code-standards
```

## Project Memory Requirement

Every scaffolded project **MUST** get its own `AGENTS.md` at the root — scaffolding is not complete without it. Records stack, template source, architecture decisions, and a "Project-Specific Notes" section. Read it first on every session; append significant decisions as they happen.

For **Claude Code users**, also generate a `CLAUDE.md` (see below). Both coexist — `AGENTS.md` is the source of truth; `CLAUDE.md` is a short index, not a duplicate.

## Recommended plugins for new projects

After scaffold verification passes, suggest these to the user. Do not install — user decides.

**Day one:**
- **caveman** (`claude plugin marketplace add JuliusBrussee/caveman`) — compresses output prose. **OFF** in sessions writing committed files (`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** (`claude plugin marketplace add pcvelz/superpowers`) — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.
- **claude-mem** (`claude plugin marketplace add thedotmack/claude-mem` then `claude plugin install claude-mem`) — auto-captures tool usage, decisions, and file changes across sessions via SQLite + vector DB. Install in the **scaffolded project**, not in templateCentral (templateCentral uses built-in markdown memory instead).

**As the project grows (5+ features):**
- **codegraph** (`npx @colbymchenry/codegraph`, Node 18+) — symbol navigation; add when grepping for definitions is a regular cost.
- **graphify** (`uv tool install graphifyy && graphify install`, Python 3.10+) — structural overview; use before codegraph for orientation.
- **code-review-graph** (`pip install code-review-graph && code-review-graph install && code-review-graph build`, Python 3.10+) — PR/refactor impact analysis; add when blast radius is non-obvious.

Full decision rules: `README.md → Recommended Plugins`.

## Scaffold: CLAUDE.md (Claude Code only)

Skip if the user does not use Claude Code. Add after `AGENTS.md` and after verification gates pass.

- **Never** duplicate `AGENTS.md` content — one line: "Full context in `AGENTS.md`."
- **Include**: verified Build & Dev commands; templateCentral skills list for this stack (from `claude-skills/<stack>/AGENT.md`); workflow line: simple/medium → templateCentral skills; complex → Superpowers.
- **Never** put secrets or env values in `CLAUDE.md`.

If templateCentral is not on disk, write `AGENTS.md` and a minimal `CLAUDE.md` from verified commands and local content.
