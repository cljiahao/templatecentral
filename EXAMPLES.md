# Examples

Practical walkthroughs for each scaffold. All assume templateCentral is installed:

```
claude plugin marketplace add cljiahao/templatecentral
claude plugin install templatecentral
```

---

## Next.js (App Router + shadcn/ui)

```
User: scaffold a Next.js app called "dashboard"
```

What ships: App Router, shadcn/ui, TanStack Query, Vitest, ESLint, Prettier, Docker, AGENTS.md, `.agents → .claude` symlink (cross-vendor), AI harness (7-event hook kit: UserPromptSubmit injection+credential firewall, PreToolUse secrets read/write + git guards, PostToolUse type-check, Stop test gate, SubagentStop type-gate, SessionStart context recovery).

**Add auth after scaffolding:**
```
User: add authentication
→ templatecentral:add
```

**Add a database:**
```
User: add a PostgreSQL database with Drizzle
→ templatecentral:add
```

**Add a page:**
```
User: add a settings page
→ templatecentral:add
```

---

## FastAPI (Python 3.13 + Pydantic v2 + argon2)

```
User: scaffold a FastAPI backend called "api"
```

What ships: structured `src/` layout, Pydantic v2 settings, Ruff, pytest, Docker, AGENTS.md, `.agents → .claude` symlink (cross-vendor), AI harness (7-event hook kit: UserPromptSubmit injection+credential firewall, PreToolUse secrets read/write + git guards, PostToolUse type-check, Stop test gate, SubagentStop type-gate, SessionStart context recovery).

**Add JWT auth:**
```
User: add authentication
→ templatecentral:add
```

**Add a database (completes the auth stub):**
```
User: add a PostgreSQL database with SQLAlchemy
→ templatecentral:add
```

**Auth + database together — order matters:**
```
User: add auth and a database
→ templatecentral:add (auth first, then database)
```

---

## NestJS (TypeScript + Fastify + Vitest)

```
User: scaffold a NestJS API called "service"
```

What ships: Fastify adapter, nestjs-zod, Vitest, ESLint, Docker, AGENTS.md, `.agents → .claude` symlink (cross-vendor), AI harness (7-event hook kit: UserPromptSubmit injection+credential firewall, PreToolUse secrets read/write + git guards, PostToolUse type-check, Stop test gate, SubagentStop type-gate, SessionStart context recovery).

**Add an endpoint (NestJS module):**
```
User: add a users endpoint
→ templatecentral:add
```

**Add auth:**
```
User: add authentication
→ templatecentral:add
```

---

## Vite + React (SPA + TanStack Query + shadcn/ui)

```
User: scaffold a Vite React app called "frontend"
```

What ships: React 19, TanStack Query, shadcn/ui, React Hook Form, Zod, Vitest, Docker, AGENTS.md, `.agents → .claude` symlink (cross-vendor), AI harness (7-event hook kit: UserPromptSubmit injection+credential firewall, PreToolUse secrets read/write + git guards, PostToolUse type-check, Stop test gate, SubagentStop type-gate, SessionStart context recovery).

**Add a page:**
```
User: add a settings page
→ templatecentral:add
```

**Add a component (routed via feature):**
```
User: add a data table component
→ templatecentral:add
```

---

## Full-stack: Next.js frontend + FastAPI backend

```
User: scaffold a Next.js frontend and a FastAPI backend
→ templatecentral:scaffold (run twice — once per project)

User: connect the frontend to the backend
→ templatecentral:add
```

---

## Mutation Testing (all stacks)

```
User: add mutation testing
→ templatecentral:add
```

Adds StrykerJS (TypeScript stacks) or mutmut (FastAPI). Report-only by default — never blocks CI.
See the generated `stryker.config.mjs` or `pyproject.toml [tool.mutmut]` for configuration.

---

## Drift Check (session hygiene)

```
User: check for drift
→ templatecentral:standards
```

Checks whether stack dependencies, patterns, and conventions are still current. Run at the start of any session on an existing project.
