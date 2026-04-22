# templateCentral

A repository of production-ready project templates and Claude skills for scaffolding new projects using AI agents and subagents.

**Testing workflow:** For optional **tiered** use of separate AI sessions (test author vs selective test review) after scaffold or features — without changing the rule that tests ship in the same PR — see **`AGENTS.md` → Independent test workflow**.

## Repository Structure

```
templateCentral/
├── AGENTS.md                       # Agent orchestration guide
├── README.md
├── claude-skills/                  # Claude skills (organized by stack)
│   ├── nextjs/                     # All Next.js skills (11)
│   │   ├── scaffold/               #   Scaffold a new project
│   │   ├── code-standards/         #   Coding standards & conventions
│   │   ├── add-feature/            #   Add a feature module
│   │   ├── add-page/               #   Add a page/route
│   │   ├── add-api-route/          #   Add an API route handler
│   │   ├── add-component/          #   Add a component
│   │   ├── add-integration/        #   Add a third-party integration
│   │   ├── add-auth/               #   Add/configure authentication
│   │   ├── add-test/               #   Add API route tests (Vitest)
│   │   ├── add-form/               #   Add a validated form
│   │   └── add-database/           #   Add Prisma (SQL) or Mongoose (MongoDB)
│   ├── fastapi/                    # All FastAPI skills (7)
│   │   ├── scaffold/               #   Scaffold a new project
│   │   ├── code-standards/         #   Python/FastAPI coding standards
│   │   ├── add-endpoint/           #   Add a FastAPI endpoint
│   │   ├── add-test/               #   Add pytest tests
│   │   ├── add-auth/               #   Add JWT authentication
│   │   ├── add-database/           #   Add SQLAlchemy (SQL) or Beanie (MongoDB)
│   │   └── add-integration/        #   Add an external API integration
│   ├── vite-react/                 # All Vite + React skills (9)
│   │   ├── scaffold/               #   Scaffold a new project
│   │   ├── code-standards/         #   Coding standards & conventions
│   │   ├── add-feature/            #   Add a feature module
│   │   ├── add-page/               #   Add a page/route
│   │   ├── add-component/          #   Add a component
│   │   ├── add-integration/        #   Add an external API integration
│   │   ├── add-auth/               #   Add/configure authentication
│   │   ├── add-test/               #   Add component/hook/service tests
│   │   └── add-form/               #   Add a validated form
│   ├── nestjs/                     # All NestJS skills (7)
│   │   ├── scaffold/               #   Scaffold a new project
│   │   ├── code-standards/         #   Coding standards & conventions
│   │   ├── add-module/             #   Add a feature module with CRUD
│   │   ├── add-test/               #   Add unit/e2e tests
│   │   ├── add-auth/               #   Add JWT authentication
│   │   ├── add-database/           #   Add Prisma (SQL) or Mongoose (MongoDB)
│   │   └── add-integration/        #   Add an external API integration
│   └── shared/                     # Cross-stack skills
│       ├── task-management/        #   Opt-in structured task management
│       ├── full-stack-pairing/     #   Connect frontend to backend (proxy, CORS, env vars)
│       ├── remove-example/         #   Remove example/demo code from scaffolded project
│       ├── validation-patterns/    #   OWASP/CWE-compliant Zod/Pydantic validation patterns
│       ├── add-error-handling/     #   Consistent error responses and security boundaries
│       └── add-pagination/         #   Offset or cursor-based pagination for APIs and list UIs
└── templates/                      # Project templates
    ├── nextjs/                     # Next.js 16 + React 19 + shadcn/ui + Tailwind
    ├── fastapi/                    # FastAPI + layered architecture + Pydantic v2
    ├── vite-react/                 # Vite 8 + React 19 + React Router + TanStack Query
    └── nestjs/                     # NestJS 11 + Fastify + Zod + Swagger
```

## Available Templates

| Template | Stack | Status |
|----------|-------|--------|
| **nextjs** | Next.js 16, React 19, shadcn/ui, Tailwind CSS 4, React Query, React Hook Form, Framer Motion, Docker | Ready |
| **fastapi** | FastAPI 0.116, Pydantic v2 (camelCase schemas), layered architecture, Ruff, pytest, Docker | Ready |
| **vite-react** | Vite 8, React 19, React Router 7, TanStack Query, shadcn/ui, Tailwind CSS 4, React Hook Form, Framer Motion, Docker | Ready |
| **nestjs** | NestJS 11, Fastify, Zod + nestjs-zod, Swagger, TypeScript 6, Jest, Docker | Ready |

## Available Skills

Skills are organized by stack. Each skill has YAML frontmatter (`name`, `description`) per the [Agent Skills spec](https://agentskills.io/specification). See each stack's `AGENT.md` for the skill routing table.

- **Next.js** — 11 skills (scaffold, code-standards, add-feature, add-page, add-api-route, add-component, add-integration, add-auth, add-test, add-form, add-database)
- **FastAPI** — 7 skills (scaffold, code-standards, add-endpoint, add-test, add-auth, add-database, add-integration)
- **Vite + React** — 9 skills (scaffold, code-standards, add-feature, add-page, add-component, add-integration, add-auth, add-test, add-form)
- **NestJS** — 7 skills (scaffold, code-standards, add-module, add-test, add-auth, add-database, add-integration)
- **Shared** — 6 skills (task-management, full-stack-pairing, remove-example, validation-patterns, add-error-handling, add-pagination)

## Getting Started

### With Cursor

1. Open the `templateCentral` folder in Cursor
2. Open the agent (Cmd+L or Ctrl+L) and describe what you want:
   > "Scaffold a new Next.js project at ~/Desktop/my-app called MyApp"
3. The agent reads `AGENTS.md`, detects the stack, and delegates to the right subagent
4. The subagent copies the template, renames it, installs dependencies, and verifies the dev server — all automatically

This works the same way for any stack — just describe what you need and the orchestrator handles routing.

### With Claude Code (CLI)

1. `cd` into the `templateCentral` directory
2. Run `claude` — it automatically picks up `AGENTS.md`
3. Describe what you want:
   > "Create a FastAPI project at ~/projects/my-api"
4. The agent follows the same orchestration flow as Cursor

### With Other AI Tools

Any AI tool that reads `AGENTS.md` (Codex, Copilot, Windsurf, etc.) can use templateCentral. Open or point the tool at this repository and give it a natural language instruction. The orchestrator in `AGENTS.md` handles the rest.

### Manual (No AI)

Copy a template directory to your target location and customize:

```bash
# Next.js
cp -r templates/nextjs /path/to/my-new-project
cd /path/to/my-new-project
pnpm install && pnpm dev

# Vite + React
cp -r templates/vite-react /path/to/my-new-project
cd /path/to/my-new-project
pnpm install && pnpm dev

# NestJS
cp -r templates/nestjs /path/to/my-new-project
cd /path/to/my-new-project
pnpm install && pnpm start:dev

# FastAPI
cp -r templates/fastapi /path/to/my-new-project
cd /path/to/my-new-project
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cd src && python main.py
```

## Adding a New Template

To add a new stack:

1. Create `templates/<stack>/` with all project files and a `README.md`
2. Create `claude-skills/<stack>/` with `AGENT.md`, `code-standards/SKILL.md`, `scaffold/SKILL.md`, and additional skills
3. Create `.claude/rules/<stack>.md` with path-scoped boundaries and architecture summary
4. Add the stack to the detection table in `AGENTS.md`
5. Update this README
