<!-- ref: migrate/database/nextjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## Next.js Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5 types, 8 migration body, 9 translation table, 10 env block, After Writing Code) live there.

```bash
cat "<skill-dir>/database/drizzle-to-kysely.md"
```

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

> **STOP — confirm with the user before running any of these deletions.** `drizzle/` holds the applied-migration journal and generated SQL; deleting it is irreversible and destroys the record of what has already run against every environment's database. Do not proceed until:
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

### Step 4 — Create `src/integrations/database/kysely-client.ts` (IAM variant)

Download the CA bundle first — the Amazon RDS root CA is not in Node's default trust store, so `rejectUnauthorized: true` without `ca` fails with `SELF_SIGNED_CERT_IN_CHAIN` (and `rejectUnauthorized: false` is never the fix). Commit it (public certificate) or bake it into the image:

```bash
mkdir -p certs
curl -fsSL -o certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

```typescript
import { readFileSync } from 'node:fs';
import { Signer } from '@aws-sdk/rds-signer';
import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import type { Database } from './types';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function createDb(): Kysely<Database> {
  const host = requireEnv('DATABASE_HOST');
  const port = Number(process.env.DATABASE_PORT ?? '5432');
  const user = requireEnv('DATABASE_USER');
  const signer = new Signer({ hostname: host, port, username: user });

  const pool = new Pool({
    host,
    port,
    user,
    database: requireEnv('DATABASE_NAME'),
    password: () => signer.getAuthToken(),
    ssl: { rejectUnauthorized: true, ca: readFileSync(requireEnv('RDS_CA_BUNDLE_PATH'), 'utf8') },
    max: 10,
  });

  return new Kysely<Database>({ dialect: new PostgresDialect({ pool }) });
}

// Reuse one pool across dev hot reloads instead of leaking a new one per reload
const globalForKysely = globalThis as unknown as { db?: Kysely<Database> };

export const db = globalForKysely.db ?? createDb();

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;
```

### Step 5 — Create `src/integrations/database/types.ts`

Use the shared types template from `drizzle-to-kysely.md` Step 5.

### Step 6 — Create `src/integrations/database/migrate.ts`

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { FileMigrationProvider, Migrator } from 'kysely';

import { db } from './kysely-client';

async function migrate() {
  const migrator = new Migrator({
    db,
    provider: new FileMigrationProvider({
      fs,
      path,
      // The Next.js scaffold is ESM ("type": "module") — __dirname does not exist
      migrationFolder: path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations'),
    }),
  });

  const { results, error } = await migrator.migrateToLatest();
  results?.forEach((r) => {
    if (r.status === 'Success') console.log(`Migration "${r.migrationName}" executed successfully`);
    else if (r.status === 'Error') console.error(`Migration "${r.migrationName}" failed`);
  });

  if (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }

  await db.destroy();
}

migrate().catch((e) => {
  console.error(e);
  process.exit(1);
});
```

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
