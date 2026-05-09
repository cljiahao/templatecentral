<!-- ref: shared-add-database/typescript.md
     loaded-by: shared-add-database/SKILL.md
     prereq: Stack identified as NestJS or Next.js (TypeScript). Do not invoke this file directly — it is loaded at runtime by the shared-add-database skill. -->

# Add Database to NestJS / Next.js

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Step 0 — Detect intent and sub-stack

If the user's request includes "migrate database to compliance", "upgrade database to IAM", or "switch to IAM auth" → stop and say: "Run `shared-migrate-database` to handle that upgrade."

Check line 1 of `AGENTS.md`:
- `<!-- templateCentral: nestjs@` → **NestJS**. Use NestJS paths in Step 3.
- `<!-- templateCentral: nextjs@` → **Next.js**. Use Next.js paths in Step 3.

## Step 1 — Database type

Ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

If the user explicitly names a library (`Drizzle`, `Kysely`, `Mongoose`) → skip the compliance question.

## Step 2 — Compliance level (SQL only, skip for MongoDB)

> **SQLite note:** SQLite is always standard auth — file-based, no network IAM. Go directly to Drizzle.

Scan the conversation for compliance signals: `HIPAA`, `PCI`, `PCI-DSS`, `SOC 2`, `fintech`, `healthcare`, `government`, `AWS IAM`, `regulated`, `enterprise`, `compliance requirement`

- Signals found → use Kysely (high compliance)
- No signals → ask: *"Is this for a regulated industry or does it require AWS RDS IAM authentication?"*
  - **Yes** → Kysely (high compliance)
  - **No** → Drizzle (standard)
  - **Not sure** → Drizzle (standard) — migration path available later

## Step 3 — Load implementation

**NestJS + Drizzle:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-drizzle.md"
```

**Next.js + Drizzle:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-drizzle.md"
```

**NestJS + Kysely:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-kysely.md"
```

**Next.js + Kysely:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-kysely.md"
```

**NestJS + Mongoose:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nestjs-mongoose.md"
```

**Next.js + Mongoose:**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database/typescript/nextjs-mongoose.md"
```

Follow the loaded guide exactly.
