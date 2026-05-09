---
name: shared-add-database-typescript
description: NestJS and Next.js database setup — Drizzle (SQL low compliance), Kysely (SQL high compliance + AWS IAM), or Mongoose (MongoDB). Invoked by shared-add-database.
disable-model-invocation: true
---

# Add Database to NestJS / Next.js

Add a database to a NestJS or Next.js project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Choose Your Database and Compliance Level

### Step 0 — Detect intent and sub-stack

If the user's request includes "migrate database to compliance", "upgrade database to IAM", "switch to IAM auth", or similar upgrade intent → invoke `Skill("templatecentral:shared-migrate-database")` and stop.

Otherwise, check line 1 of `AGENTS.md` for the sub-stack:
- `<!-- templateCentral: nestjs@` → you are on **NestJS**. Follow the `### NestJS` variant in each section.
- `<!-- templateCentral: nextjs@` → you are on **Next.js**. Follow the `### Next.js` variant in each section.

### Step 1 — Database type

Ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

If the user explicitly names a library (`Drizzle`, `Kysely`, `Mongoose`) → skip the compliance question and go to that section directly.

### Step 2 — Compliance level (SQL only, skip for MongoDB)

> **SQLite note:** SQLite is always standard auth — it is file-based and does not support network IAM auth. If the user needs SQLite, go directly to Section A (Drizzle).

Scan the conversation for compliance signals:

**High-compliance signals:** `HIPAA`, `PCI`, `PCI-DSS`, `SOC 2`, `fintech`, `healthcare`, `government`, `AWS IAM`, `regulated`, `enterprise`, `compliance requirement`

- Signals found → use Kysely (high compliance)
- No signals → ask: *"Is this project for a regulated industry (e.g. healthcare, finance, government) or does it need to connect to AWS RDS using IAM authentication rather than a password?"*
  - **Yes** → use Kysely (high compliance)
  - **No** → use Drizzle (standard)
  - **Not sure** → use Drizzle (standard) — a migration path is available later

---

### Step 3 — Load implementation

Based on sub-stack (Step 0) and library (Step 1–2), run the matching `cat` command and follow the loaded guide exactly.

**NestJS + Drizzle (low compliance):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nestjs-drizzle.md"
```
Follow the loaded guide exactly.

**Next.js + Drizzle (low compliance):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nextjs-drizzle.md"
```
Follow the loaded guide exactly.

**NestJS + Kysely (high compliance / AWS IAM):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nestjs-kysely.md"
```
Follow the loaded guide exactly.

**Next.js + Kysely (high compliance / AWS IAM):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nextjs-kysely.md"
```
Follow the loaded guide exactly.

**NestJS + Mongoose (MongoDB):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nestjs-mongoose.md"
```
Follow the loaded guide exactly.

**Next.js + Mongoose (MongoDB):**
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-database-typescript/nextjs-mongoose.md"
```
Follow the loaded guide exactly.
