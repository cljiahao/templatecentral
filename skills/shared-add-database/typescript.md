<!-- ref: shared-add-database/typescript.md
     loaded-by: shared-add-database/SKILL.md
     prereq: Stack identified as NestJS or Next.js (TypeScript). Do not invoke this file directly — it is loaded at runtime by the shared-add-database skill. -->

# TypeScript Database Stack Router

Detect intent and ask for database type. If migration intent detected ("migrate/upgrade to IAM"), exit and say "Run `shared-migrate-database`."

Identify stack from `AGENTS.md` line 1 (`nestjs@` or `nextjs@`). Ask: *"SQL (PostgreSQL, MySQL, SQLite) or MongoDB?"* — skip if user named a library.

For SQL, detect compliance signals (`HIPAA`, `PCI`, `regulated`, etc.) or ask about IAM. SQLite always uses standard auth (Drizzle).

| Stack | Library | Load |
|-------|---------|------|
| NestJS | Drizzle | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-drizzle.md"` |
| NestJS | Kysely | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-kysely.md"` |
| NestJS | Mongoose | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-mongoose.md"` |
| Next.js | Drizzle | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-drizzle.md"` |
| Next.js | Kysely | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-kysely.md"` |
| Next.js | Mongoose | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-mongoose.md"` |

Run the chosen command and follow the loaded guide exactly.
