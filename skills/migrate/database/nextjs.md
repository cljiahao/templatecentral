<!-- ref: migrate/database/nextjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## Next.js Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5 types, 8 migration body, 9 translation table, 10 env block, After Writing Code) live there.

```bash
cat "<skill-dir>/database/drizzle-to-kysely.md"
```

**Before Step 1**, create a migration branch so every change below (packages, scripts, deletions) is reviewable and revertible as one unit:

`git checkout -b migrate/drizzle-to-kysely`

---

### Step 2 — Update `package.json` scripts

Remove `db:generate`, `db:migrate`, `db:push`, `db:studio`. Add:

```json
{
  "scripts": {
    "migrate": "tsx src/integrations/database/migrate.ts"
  }
}
```

### Step 3 — Delete Drizzle files

> **Confirm with the user before running any of these deletions.** `drizzle/` holds the applied-migration journal and generated SQL; deleting it is irreversible and destroys the record of what has already run against every environment's database. Do not proceed until:
> 1. The working tree is committed (or `drizzle/` is archived outside the repo), so the migration history is recoverable from git.
> 2. The user has explicitly confirmed these paths should be removed.
>
> If the user declines or is unsure, leave the files in place — Kysely migrations live in a different directory and coexist with them fine.

```bash
rm src/integrations/database/db-client.ts
rm src/integrations/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

If the user declined, `db-client.ts`, `schema.ts` and `drizzle.config.ts` stay as dead code once Steps 7 and 9 switch every import to Kysely; tell the user they can be removed later.

### Step 4 — Create `src/integrations/database/kysely-client.ts` (IAM variant)

Download the CA bundle first — the Amazon RDS root CA is not in Node's default trust store, so `rejectUnauthorized: true` without `ca` fails with `SELF_SIGNED_CERT_IN_CHAIN` (and `rejectUnauthorized: false` is never the fix). Commit it (public certificate) or bake it into the image:

```bash
mkdir -p certs
curl -fsSL -o certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Run `TC_PART=leaf TC_LEAF=migrate/database/nextjs bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/nextjs/template/` (listed in `<skill-dir>/database/nextjs/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

Copied verbatim from `<skill-dir>/database/nextjs/template/src/integrations/database/kysely-client.ts` by the copy step; do not re-type it.

### Step 5 — Create `src/integrations/database/types.ts`

Use the shared types template from `drizzle-to-kysely.md` Step 5.

### Step 6 — Create `src/integrations/database/migrate.ts`

Copied verbatim from `<skill-dir>/database/nextjs/template/src/integrations/database/migrate.ts` by the copy step; do not re-type it.

### Step 7 — Update `src/integrations/database/index.ts`

```typescript
export { db } from './kysely-client';
export type { Database, User, NewUser, UserUpdate } from './types';
```

### Step 8 — Write first Kysely migration

Create `src/integrations/database/migrations/001_initial.ts` with the `up`/`down` pair from `drizzle-to-kysely.md` Step 8.

### Step 9 — Update query code in API routes and Server Components

Use the translation table from `drizzle-to-kysely.md` Step 9.

Also update `src/integrations/factories.ts` if it exports a `DB()` function:

```typescript
import { db } from './database/kysely-client';

export function DB() {
  return db;
}
```

### Step 10 — Update `.env.local` and `.env.example`

Use the env block from `drizzle-to-kysely.md` Step 10.

### Step 11 — Validate

See `drizzle-to-kysely.md` Step 11 (Next.js runs only `pnpm build`). Then follow After Writing Code.
