# Examples

Practical walkthroughs for each scaffold. All assume templateCentral is installed:

```
claude plugin marketplace add cljiahao/templatecentral
claude plugin install templatecentral
```

Every scaffold also ships `AGENTS.md` + `CLAUDE.md`, the `.agents → .claude` symlink, and the AI harness hook kit (see README → What You Get), so the per-stack lists below omit them.

---

## Next.js (App Router + shadcn/ui)

```
User: scaffold a Next.js app called "dashboard"
```

What ships: App Router, shadcn/ui, TanStack Query, Vitest, ESLint, Prettier, Docker.

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

## FastAPI (Python 3.13 + Pydantic v2)

```
User: scaffold a FastAPI backend called "api"
```

What ships: layered `src/` layout, pydantic-settings config, structlog, Ruff, pytest, Docker.

**Add JWT auth (argon2 hashing; stubbed until a database exists):**
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

What ships: Fastify adapter, nestjs-zod, Vitest, ESLint, Docker.

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

What ships: React 19, TanStack Query, shadcn/ui, React Hook Form, Zod, Vitest, Docker.

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
→ templatecentral:add (integration)

User: check the frontend and backend types agree
→ templatecentral:standards (full-stack-pairing)
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

Checks whether dependencies, patterns, and conventions still match current templateCentral standards — run it at the start of a session on an existing project.
