# Examples

Practical walkthroughs for each scaffold. All assume templateCentral is installed:

```
claude plugin marketplace add cljiahao/templatecentral
```

---

## Next.js (App Router + shadcn/ui + better-auth)

```
User: scaffold a Next.js app called "dashboard"
```

What ships: App Router, shadcn/ui, TanStack Query, better-auth, Vitest, ESLint, Prettier, Docker, AGENTS.md, PostToolUse hook.

**Add auth after scaffolding:**
```
User: add authentication
→ templatecentral:nextjs-add-auth
```

**Add a database:**
```
User: add a PostgreSQL database with Drizzle
→ templatecentral:nextjs-add-database
```

**Add a page:**
```
User: add a settings page
→ templatecentral:nextjs-add-page
```

---

## FastAPI (Python 3.12 + Pydantic v2 + argon2)

```
User: scaffold a FastAPI backend called "api"
```

What ships: structured `src/` layout, Pydantic v2 settings, Ruff, pytest, Docker, AGENTS.md, PostToolUse hook.

**Add JWT auth:**
```
User: add authentication
→ templatecentral:fastapi-add-auth
```

**Add a database (completes the auth stub):**
```
User: add a PostgreSQL database with SQLAlchemy
→ templatecentral:fastapi-add-database
```

**Auth + database together — order matters:**
```
User: add auth and a database
→ templatecentral:fastapi-add-auth first, then templatecentral:fastapi-add-database
```

---

## NestJS (TypeScript + Fastify + Vitest)

```
User: scaffold a NestJS API called "service"
```

What ships: Fastify adapter, class-validator, Vitest, ESLint, Docker, AGENTS.md, PostToolUse hook.

**Add a feature module:**
```
User: add a users module
→ templatecentral:nestjs-add-module
```

**Add auth:**
```
User: add authentication
→ templatecentral:nestjs-add-auth
```

---

## Vite + React (SPA + TanStack Query + shadcn/ui)

```
User: scaffold a Vite React app called "frontend"
```

What ships: React 19, TanStack Query, shadcn/ui, React Hook Form, Zod, Vitest, Docker, AGENTS.md, PostToolUse hook.

**Add a page:**
```
User: add a settings page
→ templatecentral:vite-react-add-page
```

**Add a component:**
```
User: add a data table component
→ templatecentral:vite-react-add-component
```

---

## Full-stack: Next.js frontend + FastAPI backend

```
User: scaffold a Next.js frontend and a FastAPI backend
→ templatecentral:nextjs-scaffold, then templatecentral:fastapi-scaffold

User: connect the frontend to the backend
→ templatecentral:shared-full-stack-pairing
```

---

## Mutation Testing (all stacks)

```
User: add mutation testing
→ templatecentral:add-mutation
```

Adds StrykerJS (TypeScript stacks) or mutmut (FastAPI). Report-only by default — never blocks CI.
See the generated `stryker.config.mjs` or `pyproject.toml [tool.mutmut]` for configuration.

---

## Drift Check (session hygiene)

```
User: check for drift
→ templatecentral:shared-drift-check
```

Checks whether stack dependencies, patterns, and conventions are still current. Run at the start of any session on an existing project.
