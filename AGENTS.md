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
- **Production**: Replace template dev placeholders in env (e.g. NextAuth `AUTH_SECRET`, JWT secrets) with strong values before deploy — call this out in handoff when templates use placeholders.
- Follow each stack’s `code-standards` for auth, env vars, and least-privilege responses.

## Supply chain & reproducibility

- **Node projects**: Use the package manager the scaffold documents (**pnpm** for current templates); after first `pnpm install`, **commit the new lockfile**. Do not delete lockfiles or switch npm/pnpm/yarn without explicit user approval.
- **Python projects**: Install from the template’s `requirements-dev.txt` (or equivalent); do not loosen version pins without user approval.

## Scaffold verification (before project AGENTS.md / CLAUDE.md)

Do not write `AGENTS.md` or `CLAUDE.md` until the stack’s checks pass (fixes first):

| Stack | Required gates |
|-------|------------------|
| **Next.js** | `pnpm test`, `pnpm build` |
| **NestJS** | `pnpm test`, `pnpm test:e2e`, `pnpm build` |
| **FastAPI** | API responds, `pytest test/`, `ruff check src/` |
| **Vite + React** | `pnpm dev` OK, `pnpm test`, `pnpm build` |

Optional when `package.json` defines them: Next.js `pnpm check` (format + lint + typecheck); `pnpm lint` on Node stacks before handoff if not already covered above.

## Subagent Boundaries

- NEVER invent APIs, libraries, or features not in the stack
- NEVER modify files outside the project directory
- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation
- NEVER remove or ignore lockfiles in scaffolded Node projects without explicit user approval
- NEVER scaffold into a **non-empty** target directory without explicit user confirmation (avoid overwriting existing apps)
- NEVER disable TLS verification in application code, HTTP clients, or scaffold scripts (`verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, etc.) unless the user explicitly approves a **narrow, documented dev-only** exception

## Shared Skills

Cross-stack skills available to all subagents — check `claude-skills/shared/` when a task doesn't fit a stack-specific skill:

| Skill | When to use |
|-------|-------------|
| `shared/full-stack-pairing/` | Connecting a frontend to a backend (CORS, proxy, env wiring) |
| `shared/remove-example/` | Removing template example/placeholder code after scaffolding |
| `shared/task-management/` | Complex multi-step features (3+ files, architectural decisions) — opt-in via project `AGENTS.md` |

## Scaffold: optional Task Management (single source of truth)

Scaffold skills ask whether the user wants structured task management for **future** complex work. If **yes**, append to the **new project’s** `AGENTS.md` using **one** of the blocks below (not both). If **no**, skip.

**Option A — templateCentral protocol** (no plugin):

```markdown
## Task Management

For complex, multi-step tasks (3+ files, architectural decisions), follow the task management protocol at `claude-skills/shared/task-management/SKILL.md` in templateCentral.

Protocol summary: Plan → Verify → Track → Explain → Document → Capture Lessons.

Skip for simple changes (single-file edits, scaffolding, quick fixes).
```

**Option B — Superpowers** (Claude Code; user installs in their session):

```bash
/plugin marketplace add pcvelz/superpowers
/plugin install superpowers-extended-cc@superpowers-extended-cc-marketplace
```

Then append:

```markdown
## Task Management

- **Simple tasks**: use templateCentral skills for this stack (see project `AGENTS.md` / `CLAUDE.md` skill list)
- **Complex features** (3+ files, architectural decisions): Superpowers workflow — `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`
- All code must follow the conventions in this file and the project's code-standards, regardless of workflow used
```

## Project Memory Requirement

Every scaffolded project **MUST** get its own `AGENTS.md` at the root — scaffolding is not complete without it. It records the stack, template source, architecture decisions, and a "Project-Specific Notes" section. When working inside a scaffolded project, read its `AGENTS.md` first. When making significant decisions, append to "Project-Specific Notes".

For **Claude Code users**, scaffold skills also generate a `CLAUDE.md` — see **Scaffold: CLAUDE.md (Claude Code)** below.

Both files coexist — `AGENTS.md` is the source of truth for all AI agents; `CLAUDE.md` is a short Claude Code index (not a second copy of long architecture text).

## Scaffold: CLAUDE.md (Claude Code only)

Skip if the user does not use Claude Code. Add `CLAUDE.md` in the **new project** after `AGENTS.md` and after scaffold **verification gates** pass.

**Rules (accuracy, security, tokens)**  
- **Do not** duplicate Identity / Architecture / Key Conventions from `AGENTS.md` — include one line: full context is in **`AGENTS.md`**.  
- **Do** include **Build & Dev** commands that were actually verified during scaffold (from template or scripts).  
- **Do** include a **Workflow** line or tiny table: simple/medium → templateCentral stack skills; complex → Superpowers (`/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`) — same idea as above under Project Memory.  
- **Do** include a **templateCentral skills** bullet list for that stack (from `claude-skills/<stack>/AGENT.md`).  
- **Never** put secrets or env values in `CLAUDE.md`.

If templateCentral repo is not on disk, still write `AGENTS.md` and a minimal `CLAUDE.md` using the verified commands and local `AGENTS.md` content.
