# Vite + React Subagent

## Scope

- Scaffold new Vite + React projects from `templates/vite-react/`
- Write and review code inside scaffolded Vite + React projects
- Add features, pages, components, and external API integrations

**Client env**: `VITE_*` is public in the browser — never secrets (see `code-standards/`, root `AGENTS.md`).

## Stack

Vite 8, React 19, TypeScript 6, shadcn/ui (new-york), Tailwind CSS 4, React Router 7, TanStack React Query 5, React Hook Form + Zod, Framer Motion, Vitest + Testing Library, Sonner, Docker (Nginx for prod).

## Skills Available

| Skill | When to use |
|-------|-------------|
| `scaffold/` | User wants to create a new Vite + React SPA |
| `code-standards/` | Before writing or reviewing any code |
| `add-feature/` | Adding a new domain area under `src/features/` (components + hooks + API layer for a domain — NOT for a single route) |
| `add-page/` | Adding a new URL route with no domain logic (thin page composing from features) |
| `add-component/` | Creating a new React component |
| `add-integration/` | Connecting to an external third-party API (typed client + Zod schemas — NOT for internal app logic, use `add-feature` instead) |
| `add-auth/` | Configuring authentication — wiring auth backend, customizing login UI, protecting routes |
| `add-test/` | Adding tests for components, hooks, or services |
| `add-form/` | Adding a validated form (React Hook Form + Zod + CustomFormField) |

## Shared Skills

Cross-stack skills in `claude-skills/shared/` — use these instead of inventing patterns:

| Skill | When to use |
|-------|-------------|
| `shared/validation-patterns/` | Forms and API responses needing OWASP/CWE-compliant validation |
| `shared/add-error-handling/` | Consistent error boundaries and security-safe error display |
| `shared/full-stack-pairing/` | Connecting this SPA to a backend (CORS, proxy, env wiring) |
| `shared/task-management/` | Complex multi-step features — opt-in via project `AGENTS.md` |
| `shared/remove-example/` | Removing template placeholder code after scaffold |
| `shared/add-pagination/` | Adding pagination to lists and API consumers |

## Architecture & Code Standards

See `.claude/rules/vite-react.md` for boundaries, architecture, and code standards that are automatically loaded when working with Vite + React files.
