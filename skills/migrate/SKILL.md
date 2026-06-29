---
name: templatecentral:migrate
description: Use when running database migrations, migrating conventions, or extracting a Next.js backend to a dedicated service — FastAPI or NestJS.
---

**Step 1** — Identify the migration type:
- **Database migration** (schema changes, Alembic/Drizzle runs): `database/<stack>.md`
- **Project migration** (framework upgrades, convention changes): `general/implementation.md`
- **Backend extraction** (Next.js API routes → NestJS or FastAPI): `nextjs-backend-extraction.md`

**Step 2** — For database migrations, identify the stack: `fastapi`, `nestjs`, or `nextjs`.

**Step 3** — Cat the reference file:
> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

`cat "<skill-dir>/<path>"`

**Step 4** — Follow the loaded guide exactly.
