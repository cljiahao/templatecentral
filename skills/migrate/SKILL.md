---
name: templatecentral:migrate
description: Use when adopting or upgrading a project, switching its DB access layer, or extracting a Next.js backend — FastAPI, NestJS, Next.js, Vite + React.
---

**Step 1** — Identify the migration type → path (base: `<skill-dir>/`):

| Type | Path |
|---|---|
| **Adopt / upgrade** — retrofit the harness into a project built without templateCentral, or upgrade a templateCentral project's conventions | `general/implementation.md` |
| **Database access layer** — fastapi: SQLAlchemy password auth → AWS IAM auth; nestjs/nextjs: Drizzle → Kysely | `database/<fastapi\|nestjs\|nextjs>.md` |
| **Backend extraction** — Next.js API routes → NestJS or FastAPI service | `nextjs-backend-extraction.md` |

**Step 2** — Run:
> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

`cat "<skill-dir>/<path>"`

**Step 3** — Follow the loaded guide exactly.
