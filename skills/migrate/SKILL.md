---
name: templatecentral:migrate
description: Use when adopting or upgrading a project, switching its DB access layer, or extracting a Next.js backend — FastAPI, NestJS, Next.js, Vite + React.
---

**Step 1** — Pick the path (under `<skill-dir>/`):

| Type | Path |
|---|---|
| **Harness refresh** — `.claude/harness.json` exists in the project (seeded by any plugin version): bring its harness files to the current templates without losing edits. Pick this row first whenever that file exists | `general/harness-refresh.md` |
| **Adopt / upgrade** — no `.claude/harness.json` yet (retrofit the harness into a project built without templateCentral) | `general/implementation.md` |
| **DB access layer** — fastapi: SQLAlchemy password → AWS IAM auth; nestjs/nextjs: Drizzle → Kysely (vite-react has no database layer: tell the user and stop) | `database/<fastapi\|nestjs\|nextjs>.md` |
| **Backend extraction** — Next.js API routes → NestJS or FastAPI service | `nextjs-backend-extraction.md` |
| **Portal framing** — pre-6.2.0 app framed only by its appCentral portal (`APPCENTRAL_PORTAL_ORIGIN`) | `portal-frame-ancestors.md` |

**Step 2** — Run:
> `<skill-dir>` = this skill's directory ("Base directory for this skill"); substitute the absolute path — it is **not** a shell variable.

`cat "<skill-dir>/<path>"`

**Step 3** — Follow the loaded guide exactly.
