<!-- ref: add/database/typescript.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as NestJS or Next.js (TypeScript). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# TypeScript Database Stack Router

Migration intent ("migrate/upgrade to IAM") → stop and say "Run `templatecentral:migrate`."

Stack from `AGENTS.md` line 1 (`nestjs@` or `nextjs@`). Ask *"SQL (PostgreSQL) or MongoDB?"* unless the user named a library.

Detect high-security signals (`regulated`, `iam`, `no-password`, `audit-logging`, etc.) or ask. Drizzle and Kysely guides are PostgreSQL-only; for MySQL or SQLite, say so and adapt driver, dialect and schema imports.

| Stack | Library | Load |
|---|---|---|
| NestJS | Drizzle | `cat "<skill-dir>/database/typescript/nestjs-drizzle.md"` |
| NestJS | Kysely | `cat "<skill-dir>/database/typescript/nestjs-kysely.md"` |
| NestJS | Mongoose | `cat "<skill-dir>/database/typescript/nestjs-mongoose.md"` |
| Next.js | Drizzle | `cat "<skill-dir>/database/typescript/nextjs-drizzle.md"` |
| Next.js | Kysely | `cat "<skill-dir>/database/typescript/nextjs-kysely.md"` |
| Next.js | Mongoose | `cat "<skill-dir>/database/typescript/nextjs-mongoose.md"` |

**NestJS + Kysely add-ons** — load with `nestjs-kysely.md` only when they apply (never skip the base guide):

| Condition | Also load |
|---|---|
| AWS IAM auth required | `cat "<skill-dir>/database/typescript/nestjs-kysely-iam.md"` |
| `src/modules/auth/auth.service.ts` exists | `cat "<skill-dir>/database/typescript/nestjs-kysely-auth.md"` |

**NestJS + Mongoose add-ons** — same rule, with `nestjs-mongoose.md`:

| Condition | Also load |
|---|---|
| AWS IAM auth required (DocumentDB / Atlas) | `cat "<skill-dir>/database/typescript/nestjs-mongoose-iam.md"` |
| `src/modules/auth/auth.service.ts` exists | `cat "<skill-dir>/database/typescript/nestjs-mongoose-auth.md"` |

Run the chosen `cat`(s); follow the guide(s) exactly.
