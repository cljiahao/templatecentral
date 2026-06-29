<!-- ref: migrate/database/nextjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## Next.js Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5, 8 up-body, 9 translation table, 10 env block, After Writing Code) live there.

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

```bash
rm src/integrations/database/db-client.ts
rm src/integrations/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

### Step 4 — Create `src/integrations/database/kysely-client.ts` (IAM variant)

```typescript
import { Kysely, PostgresDialect } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import type { Database } from './types';

const signer = new Signer({
  hostname: process.env.DATABASE_HOST!,
  port: Number(process.env.DATABASE_PORT ?? '5432'),
  username: process.env.DATABASE_USER!,
});

const pool = new Pool({
  host: process.env.DATABASE_HOST,
  port: Number(process.env.DATABASE_PORT ?? '5432'),
  user: process.env.DATABASE_USER,
  database: process.env.DATABASE_NAME,
  password: () => signer.getAuthToken(),
  ssl: { rejectUnauthorized: true },
  max: 10,
});

const globalForKysely = globalThis as unknown as { db: Kysely<Database> };

export const db = globalForKysely.db ?? new Kysely<Database>({
  dialect: new PostgresDialect({ pool }),
});

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
      // ESM project ("type": "module") — __dirname does not exist
      migrationFolder: path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations'),
    }),
  });

  const { results, error } = await migrator.migrateToLatest();
  // result-handling block: see drizzle-to-kysely.md Step 7
}

migrate();
```

### Step 7 — Update `src/integrations/database/index.ts`

```typescript
export { db } from './kysely-client';
export type { Database, User, NewUser, UserUpdate } from './types';
```

### Step 8 — Write first Kysely migration

Create `src/integrations/database/migrations/001_initial.ts`. Use the `up` body from `drizzle-to-kysely.md` Step 8.

Next.js `down` drops the table:

```typescript
export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('users').execute();
}
```

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
