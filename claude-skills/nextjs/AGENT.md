# Next.js Subagent

## Scope

- Scaffold new Next.js projects from `templates/nextjs/`
- Write and review code inside scaffolded Next.js projects
- Add features, pages, API routes, components, and third-party integrations

## Stack

Next.js 16, React 19, TypeScript 5.9, shadcn/ui (new-york), Tailwind CSS 4, TanStack React Query, NextAuth (Auth.js), React Hook Form + Zod, Framer Motion, Axios, Docker.

## Skills Available

| Skill | When to use |
|-------|-------------|
| `scaffold/` | User wants to create a new Next.js project |
| `code-standards/` | Before writing or reviewing any code |
| `add-feature/` | Adding a new domain area under `src/features/` (components + hooks + API layer for a domain — NOT for a single route) |
| `add-page/` | Adding a new URL route with no domain logic (thin page composing from features) |
| `add-api-route/` | Adding a server-side API endpoint under `src/app/api/` |
| `add-component/` | Creating a new React component |
| `add-integration/` | Connecting to an external third-party API (GitHub, Stripe, etc. — NOT for internal app logic, use `add-feature` instead) |
| `add-auth/` | Configuring authentication — adding SSO providers, customizing login UI, protecting routes |
| `add-test/` | Adding tests for API route handlers (backend only) |
| `add-form/` | Adding a validated form (React Hook Form + Zod + CustomFormField) |
| `add-database/` | Adding a database — Prisma (SQL) or Mongoose (MongoDB) |

## Architecture & Code Standards

See `.claude/rules/nextjs.md` for boundaries, architecture, and code standards that are automatically loaded when working with Next.js files.
