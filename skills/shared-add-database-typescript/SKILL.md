---
name: shared-add-database-typescript
description: NestJS and Next.js database setup — Drizzle (SQL low compliance), Kysely (SQL high compliance + AWS IAM), or Mongoose (MongoDB). Invoked by shared-add-database.
disable-model-invocation: true
---

# Add Database to NestJS / Next.js

Add a database to a NestJS or Next.js project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it.

## Choose Your Database and Compliance Level

### Step 0 — Detect sub-stack

Check line 1 of `AGENTS.md`:
- `<!-- templateCentral: nestjs@` → you are on **NestJS**. Follow the `### NestJS` variant in each section.
- `<!-- templateCentral: nextjs@` → you are on **Next.js**. Follow the `### Next.js` variant in each section.

### Step 1 — Database type

Ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

If the user explicitly names a library (`Drizzle`, `Kysely`, `Mongoose`) → skip the compliance question and go to that section directly.

### Step 2 — Compliance level (SQL only, skip for MongoDB)

> **SQLite note:** SQLite is always standard auth — it is file-based and does not support network IAM auth. If the user needs SQLite, go directly to Section A (Drizzle).

Scan the conversation for compliance signals:

**High-compliance signals:** `HIPAA`, `PCI`, `PCI-DSS`, `SOC 2`, `fintech`, `healthcare`, `government`, `AWS IAM`, `regulated`, `enterprise`, `compliance requirement`

- Signals found → go to [Section B: Kysely + AWS IAM](#section-b-kysely-sql)
- No signals → ask: *"Is this project for a regulated industry (e.g. healthcare, finance, government) or does it need to connect to AWS RDS using IAM authentication rather than a password?"*
  - **Yes** → [Section B: Kysely + AWS IAM](#section-b-kysely-sql)
  - **No** → [Section A: Drizzle (standard)](#section-a-drizzle-sql)
  - **Not sure** → [Section A: Drizzle (standard)](#section-a-drizzle-sql) — a migration path is available later

---

## Section A: Drizzle (SQL)

> **Drizzle ORM v1**: v1.0 is stable (released mid-2025). The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.

### NestJS

#### A1. Install Dependencies

```bash
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit
```

#### A2. Add Database Scripts

Add to `package.json`:

```json
{
  "scripts": {
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  }
}
```

#### A3. Create Drizzle Config

**`drizzle.config.ts`** (project root):

```ts
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

> `drizzle.config.ts` reads `process.env` directly — it runs as a standalone CLI command outside NestJS, so it cannot use `serviceConfig`.

#### A4. Define Schema

**`src/database/schema.ts`**:

```typescript
import { pgTable, text, timestamp } from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

#### A5. Create DrizzleService

**`src/database/drizzle.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { drizzle } from 'drizzle-orm/postgres-js';
import { sql } from 'drizzle-orm';
import postgres from 'postgres';

import { serviceConfig } from '../config/env.config';
import * as schema from './schema';

@Injectable()
export class DrizzleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DrizzleService.name);
  private readonly client: ReturnType<typeof postgres>;
  readonly db: ReturnType<typeof drizzle<typeof schema>>;

  constructor() {
    this.client = postgres(serviceConfig.DATABASE_URL);
    this.db = drizzle(this.client, { schema });
  }

  async onModuleInit() {
    try {
      await this.db.execute(sql`SELECT 1`);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.client.end();
  }
}
```

#### A6. Create DatabaseModule

**`src/database/database.module.ts`**:

```typescript
import { Global, Module } from '@nestjs/common';

import { DrizzleService } from './drizzle.service';

@Global()
@Module({
  providers: [DrizzleService],
  exports: [DrizzleService],
})
export class DatabaseModule {}
```

#### A7. Register in AppModule

Import `DatabaseModule` in `src/app.module.ts`:

```typescript
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [
    DatabaseModule,
    // ...existing modules
  ],
})
export class AppModule {}
```

#### A8. Configure Environment

Add `DATABASE_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_URL: process.env.DATABASE_URL!,
};
```

Add to `.env` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

#### A9. Generate & Run Migrations

```bash
pnpm db:generate  # generate SQL migration files from schema
pnpm db:migrate   # apply pending migrations to the database
```

For rapid local iteration, `pnpm db:push` applies the schema directly without migration files (dev only — never use against production).

#### A10. Usage

Inject `DrizzleService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';

@Injectable()
export class UserService {
  constructor(private readonly drizzle: DrizzleService) {}

  findAll() {
    return this.drizzle.db.select().from(users);
  }

  findById(id: string) {
    return this.drizzle.db.select().from(users).where(eq(users.id, id)).then((r) => r[0] ?? null);
  }

  create(data: { email: string; name: string }) {
    return this.drizzle.db.insert(users).values(data).returning();
  }
}
```

> Import `eq` from `drizzle-orm`: `import { eq } from 'drizzle-orm';`

#### A11. Validate

```bash
pnpm db:generate && pnpm build && pnpm test
```

Confirm the migration file was generated, build succeeds, and all tests pass.

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (Section B) instead.

---

### Next.js

#### A1. Install Dependencies

```bash
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit
```

#### A2. Add Database Scripts

Add to `package.json`:

```json
{
  "scripts": {
    "db:generate": "drizzle-kit generate",
    "db:migrate": "drizzle-kit migrate",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  }
}
```

#### A3. Create Drizzle Config

**`drizzle.config.ts`** (project root):

```ts
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/integrations/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

#### A4. Define Schema

**`src/integrations/database/schema.ts`**:

```ts
import { pgTable, text, timestamp } from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

#### A5. Create Database Client

**`src/integrations/database/db-client.ts`**:

```ts
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import * as schema from './schema';

const globalForDb = globalThis as unknown as { db: ReturnType<typeof drizzle> };

const client = postgres(process.env.DATABASE_URL!);

export const db = globalForDb.db ?? drizzle(client, { schema });

if (process.env.NODE_ENV !== 'production') globalForDb.db = db;
```

> **Why the singleton**: Next.js hot-reloads in development, which creates new connection pools on every reload. The `globalThis` cache prevents connection exhaustion.

#### A6. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { db } from './db-client';
export * from './schema';
```

#### A7. Add Factory Function

Add to **`src/integrations/factories.ts`**:

```ts
import { db } from './database/db-client';

export function DB() {
  return db;
}
```

#### A8. Configure Environment

Add to `.env.local` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

#### A9. Generate & Run Migrations

```bash
pnpm db:generate  # generate SQL migration files from schema
pnpm db:migrate   # apply pending migrations to the database
```

For rapid local iteration, `pnpm db:push` applies the schema directly without migration files (dev only — never use against production).

#### A10. Usage

**In API routes** (for client-side fetching via React Query):

```ts
// src/app/api/users/route.ts
import { NextResponse } from 'next/server';
import { db, users } from '@/integrations/database';

export async function GET() {
  const all = await db.select().from(users);
  return NextResponse.json(all);
}
```

**In Server Components** (direct DB access, no API hop):

```tsx
// src/app/dashboard/users/page.tsx
import { db, users } from '@/integrations/database';

export default async function UsersPage() {
  const all = await db.select().from(users);
  return <UserList users={all} />;
}
```

**Via factory** (in feature services):

```ts
import { DB } from '@/integrations/factories';
import { users } from '@/integrations/database';

const all = await DB().select().from(users);
```

#### A11. Validate

```bash
pnpm db:generate && pnpm build
```

Confirm the migration file was generated and the build succeeds with no type errors.

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (Section B) instead.

---

> **Need to upgrade to high compliance later?** Tell me *"migrate database to compliance"* and I'll handle the switch to Kysely + AWS IAM.

---

## Section B: Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. If the user requires AWS IAM auth, see the IAM variant below.

### NestJS

#### B1. Install Dependencies

```bash
pnpm add kysely pg
pnpm add -D kysely-codegen @types/pg tsx
```

Add a migration script to `package.json`:

```json
{
  "scripts": {
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

#### B2. Create KyselyService

> **Complete B7 (Configure Environment) before this step** — `serviceConfig.DATABASE_URL` must be defined before creating the service.

**`src/database/kysely.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const pool = new Pool({
      connectionString: serviceConfig.DATABASE_URL,
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

##### IAM Auth Variant

If the user requires AWS IAM authentication, install the additional package:

```bash
pnpm add @aws-sdk/rds-signer
```

Replace the entire contents of `kysely.service.ts` with:

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

> **IAM fields replace `DATABASE_URL`** — remove `DATABASE_URL` from `serviceConfig` when using IAM auth.

Add IAM fields to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_HOST: process.env.DATABASE_HOST!,
  DATABASE_PORT: Number(process.env.DATABASE_PORT ?? '5432'),
  DATABASE_USER: process.env.DATABASE_USER!,
  DATABASE_NAME: process.env.DATABASE_NAME!,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

> IAM auth does not use a password — `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

#### B3. Define Database Types

**`src/database/types.ts`**:

```typescript
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

#### B4. Create DatabaseModule

**`src/database/database.module.ts`**:

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

#### B5. Register in AppModule

Import `DatabaseModule` in `src/app.module.ts`:

```typescript
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [
    DatabaseModule,
    // ...existing modules
  ],
})
export class AppModule {}
```

#### B6. Create First Migration

**`src/database/migrations/001_initial.ts`**:

```typescript
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

Create a migration runner at **`src/database/migrate.ts`**:

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { FileMigrationProvider, Migrator, Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({ connectionString: serviceConfig.DATABASE_URL }),
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

Run migrations with: `pnpm migrate`

#### B7. Configure Environment

Add `DATABASE_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_URL: process.env.DATABASE_URL!,
};
```

Add to `.env` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

#### B8. Usage

Inject `KyselyService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';

import { KyselyService } from '../../database/kysely.service';

@Injectable()
export class UserService {
  constructor(private readonly db: KyselyService) {}

  findAll() {
    return this.db.selectFrom('users').selectAll().execute();
  }

  findById(id: string) {
    return this.db.selectFrom('users').selectAll().where('id', '=', id).executeTakeFirst();
  }

  create(data: { email: string; name: string }) {
    return this.db
      .insertInto('users')
      .values(data)
      .returningAll()
      .executeTakeFirstOrThrow();
  }
}
```

#### B9. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

### Next.js

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

## Section C: Mongoose (MongoDB)

### NestJS

#### C1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

#### C2. Create DatabaseModule

**`src/database/database.module.ts`** (uses `serviceConfig` from `src/config/env.config.ts` — external service connections belong in `serviceConfig`, not `appConfig`):

```typescript
import { Global, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    MongooseModule.forRoot(serviceConfig.MONGODB_URL),
  ],
})
export class DatabaseModule {}
```

Add `MONGODB_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_URL: process.env.MONGODB_URL!,
};
```

> **Alternative**: If the project uses `@nestjs/config` (`pnpm add @nestjs/config`), use `forRootAsync` with `ConfigService` instead of direct `serviceConfig` imports.

##### IAM Auth Variant

If the user requires AWS IAM authentication (e.g., connecting to Amazon DocumentDB or MongoDB Atlas with AWS IAM), install the additional package:

```bash
pnpm add @aws-sdk/credential-providers
```

Replace the `DatabaseModule` with:

```typescript
import { Global, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    // For DocumentDB: mongodb://${HOST}:27017/${DB}?authSource=...&tls=true
    // For Atlas:      mongodb+srv://${HOST}/${DB}?authSource=...
    MongooseModule.forRoot(
      `mongodb://${serviceConfig.MONGODB_HOST}:27017/${serviceConfig.MONGODB_DB_NAME}?authSource=%24external&authMechanism=MONGODB-AWS&tls=true`,
      {
        authMechanismProperties: {
          AWS_CREDENTIAL_PROVIDER: fromNodeProviderChain(),
        },
      },
    ),
  ],
})
export class DatabaseModule {}
```

Add IAM fields to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_HOST: process.env.MONGODB_HOST!,
  MONGODB_DB_NAME: process.env.MONGODB_DB_NAME!,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
MONGODB_HOST=your-cluster.region.docdb.amazonaws.com
MONGODB_DB_NAME=mydb
```

> The MongoDB driver's `AWS_CREDENTIAL_PROVIDER` delegates credential resolution to the driver itself, which handles automatic token rotation on reconnect. The `@aws-sdk/credential-providers` package resolves IAM credentials from the EC2/ECS instance role, environment variables, or SSO profile. For MongoDB Atlas, replace `mongodb://` with `mongodb+srv://` and remove the port and `&tls=true`.

#### C3. Register in AppModule

Import `DatabaseModule` in `src/app.module.ts`:

```typescript
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [
    DatabaseModule,
    // ...existing modules
  ],
})
export class AppModule {}
```

#### C4. Create a Schema

**`src/modules/user/schemas/user.schema.ts`** (example):

```typescript
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { type HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true })
  email: string;

  @Prop({ required: true })
  name: string;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

#### C5. Register Schema in Feature Module

**`src/modules/user/user.module.ts`**:

```typescript
import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { User, UserSchema } from './schemas/user.schema';
import { UserService } from './user.service';
import { UserController } from './user.controller';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: User.name, schema: UserSchema }]),
  ],
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
```

#### C6. Usage

Inject the model in the service:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';

@Injectable()
export class UserService {
  constructor(@InjectModel(User.name) private readonly userModel: Model<UserDocument>) {}

  findAll() {
    return this.userModel.find().exec();
  }

  findById(id: string) {
    return this.userModel.findById(id).exec();
  }

  create(data: { email: string; name: string }) {
    return this.userModel.create(data);
  }
}
```

#### C7. Configure Environment

Add to `.env` and `.env.example`:

```env
MONGODB_URL=mongodb://localhost:27017/mydb
```

#### C8. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

### Next.js

#### C1. Install Dependencies

```bash
pnpm add mongoose
```

#### C2. Create Mongoose Client Singleton

**`src/integrations/database/mongoose-client.ts`**:

```ts
import mongoose from 'mongoose';

const MONGODB_URL = process.env.MONGODB_URL;

if (!MONGODB_URL) {
  throw new Error('MONGODB_URL environment variable is not defined');
}

interface MongooseCache {
  conn: typeof mongoose | null;
  promise: Promise<typeof mongoose> | null;
}

const globalForMongoose = globalThis as unknown as { mongoose: MongooseCache };

const cached: MongooseCache = globalForMongoose.mongoose ?? { conn: null, promise: null };

if (!globalForMongoose.mongoose) {
  globalForMongoose.mongoose = cached;
}

export async function connectDB(): Promise<typeof mongoose> {
  if (cached.conn) return cached.conn;

  if (!cached.promise) {
    cached.promise = mongoose.connect(MONGODB_URL);
  }

  cached.conn = await cached.promise;
  return cached.conn;
}
```

> **Why the cached pattern**: Next.js hot-reloads modules in development. The `globalThis` cache prevents opening duplicate MongoDB connections.

##### IAM Auth Variant

If the user requires AWS IAM authentication (e.g., connecting to Amazon DocumentDB or MongoDB Atlas with AWS IAM), install the additional package:

```bash
pnpm add @aws-sdk/credential-providers
```

Replace the `mongoose.connect` call in `mongoose-client.ts` with:

```ts
import mongoose from 'mongoose';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';

const MONGODB_HOST = process.env.MONGODB_HOST;
const MONGODB_DB_NAME = process.env.MONGODB_DB_NAME;

if (!MONGODB_HOST || !MONGODB_DB_NAME) {
  throw new Error('MONGODB_HOST and MONGODB_DB_NAME environment variables are required');
}

interface MongooseCache {
  conn: typeof mongoose | null;
  promise: Promise<typeof mongoose> | null;
}

const globalForMongoose = globalThis as unknown as { mongoose: MongooseCache };

const cached: MongooseCache = globalForMongoose.mongoose ?? { conn: null, promise: null };

if (!globalForMongoose.mongoose) {
  globalForMongoose.mongoose = cached;
}

export async function connectDB(): Promise<typeof mongoose> {
  if (cached.conn) return cached.conn;

  if (!cached.promise) {
    // For DocumentDB: mongodb://${MONGODB_HOST}:27017/${MONGODB_DB_NAME}?authSource=...&tls=true
    // For Atlas:      mongodb+srv://${MONGODB_HOST}/${MONGODB_DB_NAME}?authSource=...
    const url = `mongodb://${MONGODB_HOST}:27017/${MONGODB_DB_NAME}?authSource=%24external&authMechanism=MONGODB-AWS&tls=true`;

    cached.promise = mongoose.connect(url, {
      authMechanismProperties: {
        AWS_CREDENTIAL_PROVIDER: fromNodeProviderChain(),
      },
    });
  }

  cached.conn = await cached.promise;
  return cached.conn;
}
```

IAM environment variables (add to `.env.local` and `.env.example`):

```env
MONGODB_HOST=your-cluster.region.docdb.amazonaws.com
MONGODB_DB_NAME=mydb
```

> The MongoDB driver's `AWS_CREDENTIAL_PROVIDER` delegates credential resolution to the driver itself, which handles automatic token rotation on reconnect. The `@aws-sdk/credential-providers` package resolves IAM credentials from the EC2/ECS instance role, environment variables, or SSO profile. For MongoDB Atlas, replace `mongodb://` with `mongodb+srv://` and remove the port and `&tls=true`.

#### C3. Create a Schema

**`src/integrations/database/schemas/user.ts`**:

```ts
import mongoose, { type Document } from 'mongoose';

export interface IUser extends Document {
  email: string;
  name: string;
  createdAt: Date;
  updatedAt: Date;
}

const userSchema = new mongoose.Schema<IUser>(
  {
    email: { type: String, required: true, unique: true },
    name: { type: String, required: true },
  },
  { timestamps: true },
);

export const User = mongoose.models.User ?? mongoose.model<IUser>('User', userSchema);
```

> **Why `mongoose.models.User ??`**: Prevents the "Cannot overwrite model once compiled" error during hot-reload in development.

#### C4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { connectDB } from './mongoose-client';
```

#### C5. Configure Environment

Add to `.env.local` (or `.env`) and `.env.example`:

```env
MONGODB_URL="mongodb://localhost:27017/mydb"
```

#### C6. Usage

**In API routes**:

```ts
// src/app/api/users/route.ts
import { NextResponse } from 'next/server';
import { connectDB } from '@/integrations/database';
import { User } from '@/integrations/database/schemas/user';

export async function GET() {
  await connectDB();
  const users = await User.find();
  return NextResponse.json(users);
}
```

**In Server Components**:

```tsx
// src/app/dashboard/users/page.tsx
import { connectDB } from '@/integrations/database';
import { User } from '@/integrations/database/schemas/user';

export default async function UsersPage() {
  await connectDB();
  const users = await User.find().lean();
  return <UserList users={users} />;
}
```

#### C7. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors.

---

## Rules

### NestJS

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place database services (`DrizzleService`, `KyselyService`) and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Add `*.db` and `*.db-journal` to `.gitignore` for SQLite. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.
- **Kysely**: Write manual `up`/`down` migration files in `src/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant constructor — no query code changes needed.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use `MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties` — no schema or query code changes needed.

### Next.js

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Add `*.db` and `*.db-journal` to `.gitignore` for SQLite. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.
- **Kysely**: Write manual `up`/`down` migration files in `src/integrations/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant pool config — no query code changes needed.
- **Mongoose**: Always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors. For IAM auth, install `@aws-sdk/credential-providers` and use the `MONGODB-AWS` auth mechanism — no schema or query code changes needed.

---

## Completing Auth Integration

> **Only apply this section if `nestjs-add-auth` was run before this skill.** It replaces the in-memory stubs with real database-backed implementations. Next.js does not have a corresponding auth integration section.

### NestJS

> Follow only the sub-section that matches your chosen database.

#### Drizzle path

**Step A — Add `hashedPassword` to `src/database/schema.ts`**

Add the `hashedPassword` column to the existing `users` table (add only the highlighted line — preserve any other tables in the file):

```typescript
export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  hashedPassword: text('hashed_password').notNull(), // add this line
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});
```

Then run:

```bash
pnpm db:generate
pnpm db:migrate
```

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly drizzle: DrizzleService,
  ) {}

  async register(dto: RegisterDto) {
    const [existing] = await this.drizzle.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const [user] = await this.drizzle.db
      .insert(users)
      .values({ email: dto.email, name: dto.name, hashedPassword })
      .returning({ id: users.id, email: users.email, name: users.name });
    return user;
  }

  async login(dto: LoginDto) {
    const [user] = await this.drizzle.db
      .select()
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (!user || !(await argon2.verify(user.hashedPassword, dto.password))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`DrizzleService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`. Confirm `DatabaseModule` is registered in `AppModule` (the scaffold handles this).

---

#### Kysely path

**Step A — Update `src/database/types.ts` and add migration**

Add `hashed_password` to `UsersTable`:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
}

export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  hashed_password: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}

export type User = Selectable<UsersTable>;
export type NewUser = Insertable<UsersTable>;
export type UserUpdate = Updateable<UsersTable>;
```

**If `001_initial.ts` has not been applied yet:** add `hashed_password text NOT NULL` directly to the `createTable` call in `001_initial.ts`.

**If `001_initial.ts` was already applied** (users table exists in the DB), create `src/database/migrations/002_add_auth.ts`:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .alterTable('users')
    .addColumn('hashed_password', 'text', (col) => col.notNull().defaultTo(''))
    .execute();
  // Remove the temporary default — hashed_password must not have a default in production
  await sql`ALTER TABLE users ALTER COLUMN hashed_password DROP DEFAULT`.execute(db);
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.alterTable('users').dropColumn('hashed_password').execute();
}
```

Run: `pnpm migrate`

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';

import { KyselyService } from '../../database/kysely.service';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly db: KyselyService,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.db
      .selectFrom('users')
      .select('id')
      .where('email', '=', dto.email)
      .executeTakeFirst();
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const user = await this.db
      .insertInto('users')
      .values({ email: dto.email, name: dto.name, hashed_password: hashedPassword })
      .returning(['id', 'email', 'name'])
      .executeTakeFirstOrThrow();
    return user;
  }

  async login(dto: LoginDto) {
    const user = await this.db
      .selectFrom('users')
      .selectAll()
      .where('email', '=', dto.email)
      .executeTakeFirst();
    if (!user || !(await argon2.verify(user.hashed_password, dto.password))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`KyselyService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`.

---

#### Mongoose path

**Step A — Create `src/modules/auth/schemas/user.schema.ts`**

```typescript
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { type HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true })
  email: string;

  @Prop({ required: true })
  name: string;

  @Prop({ required: true })
  hashedPassword: string;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import * as argon2 from 'argon2';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.userModel.findOne({ email: dto.email }).exec();
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const user = await this.userModel.create({
      email: dto.email,
      name: dto.name,
      hashedPassword,
    });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    const user = await this.userModel.findOne({ email: dto.email }).exec();
    if (!user || !(await argon2.verify(user.hashedPassword, dto.password))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user._id.toString(), email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — Update `src/modules/auth/auth.module.ts`**

Add `MongooseModule.forFeature` to `imports` and register the `User` schema:

```typescript
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { MongooseModule } from '@nestjs/mongoose';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { User, UserSchema } from './schemas/user.schema';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      signOptions: { expiresIn: appConfig.JWT_EXPIRES_IN },
    }),
    MongooseModule.forFeature([{ name: User.name, schema: UserSchema }]),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

---

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
