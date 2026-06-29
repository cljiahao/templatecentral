<!-- ref: add/database/typescript.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as NestJS or Next.js (TypeScript). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# TypeScript Database Stack Router

Detect intent and ask for database type. If migration intent detected ("migrate/upgrade to IAM"), exit and say "Run `templatecentral:migrate`."

Identify stack from `AGENTS.md` line 1 (`nestjs@` or `nextjs@`). Ask: *"SQL (PostgreSQL) or MongoDB?"* — skip if user named a library.

For SQL, detect high-security signals (`regulated`, `iam`, `no-password`, `audit-logging`, etc.) or ask. The Drizzle and Kysely leaf guides are PostgreSQL-only — if the user needs MySQL or SQLite, say so and adapt the guide's driver/dialect and schema imports manually.

| Stack | Library | Load |
|-------|---------|------|
> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

| NestJS | Drizzle | `cat "<skill-dir>/database/typescript/nestjs-drizzle.md"` |
| NestJS | Kysely | `cat "<skill-dir>/database/typescript/nestjs-kysely.md"` |
| NestJS | Mongoose | `cat "<skill-dir>/database/typescript/nestjs-mongoose.md"` |
| Next.js | Drizzle | `cat "<skill-dir>/database/typescript/nextjs-drizzle.md"` |
| Next.js | Kysely | `cat "<skill-dir>/database/typescript/nextjs-kysely.md"` |
| Next.js | Mongoose | `cat "<skill-dir>/database/typescript/nextjs-mongoose.md"` |

Run the chosen command and follow the loaded guide exactly.
