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

Detection signals: `next.config.ts` → nextjs, `pyproject.toml`/FastAPI → fastapi, `vite.config.ts` → vite-react, `nest-cli.json` → nestjs. If ambiguous, ask. Meta-tasks (auditing, adding stacks) stay with the orchestrator.

## Subagent Boundaries

- NEVER invent APIs, libraries, or features not in the stack
- NEVER modify files outside the project directory
- NEVER commit, push, or deploy without explicit user instruction
- NEVER delete user code without confirmation

## Shared Skills

Cross-stack skills available to all subagents — check `claude-skills/shared/` when a task doesn't fit a stack-specific skill:

| Skill | When to use |
|-------|-------------|
| `shared/full-stack-pairing/` | Connecting a frontend to a backend (CORS, proxy, env wiring) |
| `shared/remove-example/` | Removing template example/placeholder code after scaffolding |
| `shared/task-management/` | Complex multi-step features (3+ files, architectural decisions) — opt-in via project `AGENTS.md` |

## Project Memory Requirement

Every scaffolded project **MUST** get its own `AGENTS.md` at the root — scaffolding is not complete without it. It records the stack, template source, architecture decisions, and a "Project-Specific Notes" section. When working inside a scaffolded project, read its `AGENTS.md` first. When making significant decisions, append to "Project-Specific Notes".

For **Claude Code users**, scaffold skills also generate a `CLAUDE.md` at the project root. This file is read automatically by Claude Code at session start. It contains build commands, architecture summary, conventions, and a **Workflow** section that directs:
- **Simple/medium tasks** → templateCentral skills
- **Complex multi-step features** → Superpowers plugin (`/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`)

Both files coexist — `AGENTS.md` is the source of truth for all AI agents, `CLAUDE.md` is a Claude Code-optimized summary with workflow guidance.
