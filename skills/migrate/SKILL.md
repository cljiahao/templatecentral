---
name: templatecentral:migrate
description: Use when running database migrations or migrating a project to updated conventions, dependencies, or patterns.
---

**Step 1** — Identify the migration type:
- **Database migration** (schema changes, Alembic/Drizzle runs): `database/<stack>.md`
- **Project migration** (framework upgrades, convention changes): `general/implementation.md`

**Step 2** — For database migrations, identify the stack: `fastapi`, `nestjs`, or `nextjs`.

**Step 3** — Cat the reference file:
`cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/migrate/<path>"`

**Step 4** — Follow the loaded guide exactly.
