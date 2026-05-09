<!-- ref: migrate/database/nestjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## NestJS Database Migration

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
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

### Step 3 — Delete Drizzle files

```bash
rm src/database/drizzle.service.ts
rm src/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

### Step 4 — Create `src/database/kysely.service.ts` (IAM variant)

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const signer = new Signer({
      hostname: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      username: serviceConfig.DATABASE_USER,
    });

    const pool = new Pool({
      host: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      user: serviceConfig.DATABASE_USER,
      database: serviceConfig.DATABASE_NAME,
      password: () => signer.getAuthToken(),
      ssl: { rejectUnauthorized: true },
      max: 10,
    });

    super({ dialect: new PostgresDialect({ pool }) });
  }

  async onModuleInit() {
    try {
      await sql`SELECT 1`.execute(this);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.destroy();
  }
}
```

### Step 5 — Create `src/database/types.ts`

Create Kysely type interfaces to match your existing schema. Example for a `users` table:

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

> **Tip**: Run `npx kysely-codegen` after connecting to generate types automatically from the live schema.

### Step 6 — Update `src/database/database.module.ts`

Replace `DrizzleService` with `KyselyService`:

```typescript
import { Global, Module } from '@nestjs/common';
import { KyselyService } from './kysely.service';

@Global()
@Module({
  providers: [KyselyService],
  exports: [KyselyService],
})
export class DatabaseModule {}
```

### Step 7 — Create `src/database/migrate.ts`

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { FileMigrationProvider, Migrator, Kysely, PostgresDialect } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const signer = new Signer({
    hostname: serviceConfig.DATABASE_HOST,
    port: serviceConfig.DATABASE_PORT,
    username: serviceConfig.DATABASE_USER,
  });

  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({
        host: serviceConfig.DATABASE_HOST,
        port: serviceConfig.DATABASE_PORT,
        user: serviceConfig.DATABASE_USER,
        database: serviceConfig.DATABASE_NAME,
        password: () => signer.getAuthToken(),
        ssl: { rejectUnauthorized: true },
      }),
    }),
  });

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

### Step 8 — Write first Kysely migration for existing tables

Create `src/database/migrations/001_initial.ts` reflecting your current schema. Example:

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

> Use `.ifNotExists()` to make the migration idempotent — the table already exists in the database from the Drizzle setup.

### Step 9 — Update query code in feature services

Drizzle → Kysely query translation reference:

| Drizzle | Kysely |
|---|---|
| `drizzle.db.select().from(users)` | `db.selectFrom('users').selectAll().execute()` |
| `drizzle.db.select().from(users).where(eq(users.id, id))` | `db.selectFrom('users').selectAll().where('id', '=', id).executeTakeFirst()` |
| `drizzle.db.insert(users).values(data).returning()` | `db.insertInto('users').values(data).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.update(users).set(data).where(eq(users.id, id))` | `db.updateTable('users').set(data).where('id', '=', id).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.delete(users).where(eq(users.id, id))` | `db.deleteFrom('users').where('id', '=', id).executeTakeFirst()` |

Also update constructor injection in services:
- Replace `private readonly drizzle: DrizzleService` → `private readonly db: KyselyService`

### Step 10 — Update `src/config/env.config.ts`

Replace `DATABASE_URL` with IAM fields:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_HOST: process.env.DATABASE_HOST!,
  DATABASE_PORT: Number(process.env.DATABASE_PORT ?? '5432'),
  DATABASE_USER: process.env.DATABASE_USER!,
  DATABASE_NAME: process.env.DATABASE_NAME!,
};
```

Update `.env` and `.env.example` — replace `DATABASE_URL` with:

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

### Step 11 — Validate

```bash
pnpm build && pnpm test
```

Build must succeed with zero TypeScript errors. All tests must pass.

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards