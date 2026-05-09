<!-- ref: add/database/typescript/nextjs-kysely.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Kysely (SQL, supports standard + AWS IAM auth). Do not invoke this file directly. -->
## Next.js + Kysely (SQL)

#### B1. Install Dependencies

```bash
pnpm add kysely pg
pnpm add -D kysely-codegen @types/pg tsx
```

Add a migration script to `package.json`:

```json
{
  "scripts": {
    "migrate": "tsx src/integrations/database/migrate.ts"
  }
}
```

#### B2. Create Database Client

**`src/integrations/database/kysely-client.ts`**:

```ts
import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import type { Database } from './types';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
});

const globalForKysely = globalThis as unknown as { db: Kysely<Database> };

export const db = globalForKysely.db ?? new Kysely<Database>({
  dialect: new PostgresDialect({ pool }),
});

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;
```

> **Why the singleton**: Next.js hot-reloads modules in development. The `globalThis` cache prevents connection exhaustion.

##### IAM Auth Variant

If the user requires AWS IAM authentication, install the additional package:

```bash
pnpm add @aws-sdk/rds-signer
```

Replace the pool creation in `kysely-client.ts` with:

```ts
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

IAM environment variables (add to `.env.local` and `.env.example`):

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

> **IAM fields replace `DATABASE_URL`** — remove `DATABASE_URL` from `.env` when using IAM auth. `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

#### B3. Define Database Types

**`src/integrations/database/types.ts`**:

```ts
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
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

> **Tip**: After the database exists, run `npx kysely-codegen` to auto-generate types from the live schema instead of maintaining them manually.

#### B4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { db } from './kysely-client';
export type { Database, User, NewUser, UserUpdate } from './types';
```

#### B5. Create First Migration

**`src/integrations/database/migrations/001_initial.ts`**:

```ts
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('users')
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

Create a migration runner script at **`src/integrations/database/migrate.ts`**:

```ts
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

Run migrations with: `pnpm migrate`

#### B6. Configure Environment

Add to `.env.local` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

#### B7. Usage

**In API routes**:

```ts
// src/app/api/users/route.ts
import { NextResponse } from 'next/server';
import { db } from '@/integrations/database';

export async function GET() {
  const users = await db.selectFrom('users').selectAll().execute();
  return NextResponse.json(users);
}

export async function POST(request: Request) {
  const body = await request.json();
  const user = await db
    .insertInto('users')
    .values({ email: body.email, name: body.name })
    .returningAll()
    .executeTakeFirstOrThrow();
  return NextResponse.json(user, { status: 201 });
}
```

**In Server Components**:

```tsx
// src/app/dashboard/users/page.tsx
import { db } from '@/integrations/database';

export default async function UsersPage() {
  const users = await db.selectFrom('users').selectAll().execute();
  return <UserList users={users} />;
}
```

#### B8. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors.

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- **Kysely**: Write manual `up`/`down` migration files in `src/integrations/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant pool config — no query code changes needed.

---

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards