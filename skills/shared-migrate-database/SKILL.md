---
name: shared-migrate-database
description: Upgrade an existing database setup from low to high compliance — Drizzle → Kysely + AWS IAM (NestJS/Next.js) or SQLAlchemy basic → SQLAlchemy + AWS IAM (FastAPI). Invoked internally by shared-add-database-python and shared-add-database-typescript.
disable-model-invocation: true
---

# Migrate Database to High Compliance

Upgrades an existing low-compliance database setup to use AWS IAM authentication.

**Out of scope:** SQL ↔ MongoDB, version upgrades, schema data migrations, and any migration not listed below.

## Step 0 — Verify existing setup

Detect the project stack and current library:

1. Check `AGENTS.md` line 1 for the stack marker.
2. Check which database files exist:

| Marker | Files present | Migration path |
|---|---|---|
| `fastapi@` | `src/database/session.py` with `create_engine` | [FastAPI: SQLAlchemy → IAM](#fastapi-sqlalchemy--aws-iam) |
| `nestjs@` | `src/database/drizzle.service.ts` | [NestJS: Drizzle → Kysely + IAM](#nestjs-drizzle--kysely--aws-iam) |
| `nextjs@` | `src/integrations/database/db-client.ts` | [Next.js: Drizzle → Kysely + IAM](#nextjs-drizzle--kysely--aws-iam) |

If no database setup is found → exit. Tell the user: *"I don't see an existing database setup. Run `shared-add-database` first, then request the migration."*

---

## FastAPI: SQLAlchemy → AWS IAM

This is a **config-only change** — no schema or query code changes needed.

### Step 1 — Install boto3

Add to `requirements.txt`:

```
boto3
```

### Step 2 — Replace `src/database/session.py`

Replace the file contents with:

```python
from collections.abc import Generator

import boto3
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from core.config import api_settings


def _get_iam_token() -> str:
    client = boto3.client("rds", region_name=api_settings.AWS_REGION)
    return client.generate_db_auth_token(
        DBHostname=api_settings.DATABASE_HOST,
        Port=api_settings.DATABASE_PORT,
        DBUsername=api_settings.DATABASE_USER,
    )


engine = create_engine(
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}",
    connect_args={"sslmode": "require"},
)


@event.listens_for(engine, "do_connect")
def provide_token(dialect, conn_rec, cargs, cparams):
    cparams["password"] = _get_iam_token()


SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### Step 3 — Update `src/core/config.py`

Remove `DATABASE_URL` from `APISettings` and replace with IAM fields:

```python
class APISettings(BaseSettings):
    # ... existing fields (keep all non-database fields) ...
    DATABASE_HOST: str = Field(description="RDS instance hostname")
    DATABASE_PORT: int = Field(default=5432, description="RDS port")
    DATABASE_USER: str = Field(description="IAM database user")
    DATABASE_NAME: str = Field(description="Database name")
    AWS_REGION: str = Field(default="us-east-1", description="AWS region for RDS signer")
```

### Step 4 — Update `alembic/env.py`

Replace the `set_main_option` call:

```python
from core.config import api_settings

sqlalchemy_url = (
    f"postgresql+psycopg2://{api_settings.DATABASE_USER}@"
    f"{api_settings.DATABASE_HOST}:{api_settings.DATABASE_PORT}/{api_settings.DATABASE_NAME}"
)
config.set_main_option("sqlalchemy.url", sqlalchemy_url)
```

### Step 5 — Update `.env` and `.env.default`

Remove `DATABASE_URL`. Add:

```
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
AWS_REGION=us-east-1
```

### Step 6 — Validate

```bash
pytest test/
```

All tests should pass. If the app starts and connects, the migration is complete.

---

## NestJS: Drizzle → Kysely + AWS IAM

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

---

## Next.js: Drizzle → Kysely + AWS IAM

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

Drizzle → Kysely query translation (same table as NestJS section above).

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
