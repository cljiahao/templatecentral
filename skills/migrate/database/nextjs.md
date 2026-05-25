<!-- ref: migrate/database/nextjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## Next.js Database Migration

Migrates an existing Drizzle ORM setup to Kysely + AWS IAM authentication.

This is a **library swap** — schema syntax differs, so existing queries must be rewritten.

### Step 1 — Swap packages

```bash
pnpm remove drizzle-orm drizzle-kit
pnpm add kysely pg @aws-sdk/rds-signer
pnpm add -D kysely-codegen @types/pg tsx
```

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

Match your existing schema. Example for a `users` table:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
  // add more tables here as needed
}

export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}

export type User = Selectable<UsersTable>;
export type NewUser = Insertable<UsersTable>;
export type UserUpdate = Updateable<UsersTable>;
```

### Step 6 — Create `src/integrations/database/migrate.ts`

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { FileMigrationProvider, Migrator } from 'kysely';

import { db } from './kysely-client';

async function migrate() {
  const migrator = new Migrator({
    db,
    provider: new FileMigrationProvider({
      fs,
      path,
      migrationFolder: path.join(__dirname, 'migrations'),
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

migrate();
```

### Step 7 — Update `src/integrations/database/index.ts`

```typescript
export { db } from './kysely-client';
export type { Database, User, NewUser, UserUpdate } from './types';
```

### Step 8 — Write first Kysely migration for existing tables

Create `src/integrations/database/migrations/001_initial.ts`:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('users')
    .ifNotExists()
    .addColumn('id', 'text', (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn('email', 'text', (col) => col.notNull().unique())
    .addColumn('name', 'text', (col) => col.notNull())
    .addColumn('created_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .addColumn('updated_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('users').execute();
}
```

### Step 9 — Update query code in API routes and Server Components

Drizzle → Kysely query translation reference:

| Drizzle | Kysely |
|---|---|
| `drizzle.db.select().from(users)` | `db.selectFrom('users').selectAll().execute()` |
| `drizzle.db.select().from(users).where(eq(users.id, id))` | `db.selectFrom('users').selectAll().where('id', '=', id).executeTakeFirst()` |
| `drizzle.db.insert(users).values(data).returning()` | `db.insertInto('users').values(data).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.update(users).set(data).where(eq(users.id, id))` | `db.updateTable('users').set(data).where('id', '=', id).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.delete(users).where(eq(users.id, id))` | `db.deleteFrom('users').where('id', '=', id).executeTakeFirst()` |

Also update `src/integrations/factories.ts` if it exports a `DB()` function:

```typescript
import { db } from './database/kysely-client';

export function DB() {
  return db;
}
```

### Step 10 — Update `.env.local` and `.env.example`

Replace `DATABASE_URL` with:

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

### Step 11 — Validate

```bash
pnpm build
```

Build must succeed with zero TypeScript errors.

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards