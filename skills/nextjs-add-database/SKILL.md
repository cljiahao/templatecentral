---
name: nextjs-add-database
description: Use when the user wants to add a database to a Next.js project — Drizzle (SQL), Kysely (SQL), or Mongoose (MongoDB). Supports optional AWS IAM authentication for compliance environments (Kysely).
---

# Add Database to Next.js

Add a database to a Next.js project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The base template is intentionally database-free.

## Choose Your Database

Ask the user which database they need, then follow the corresponding section:

| Database type | ORM/ODM | Section |
|--------------|---------|---------|
| PostgreSQL, MySQL, SQLite | Drizzle | [Section A](#section-a-drizzle-sql) |
| PostgreSQL, MySQL | Kysely | [Section B](#section-b-kysely-sql) |
| MongoDB | Mongoose | [Section C](#section-c-mongoose-mongodb) |

> **How to choose SQL ORM**: Use **Drizzle** (Section A) for new projects — lightweight, zero-dependency, full TypeScript inference, excellent edge support. Use **Kysely** (Section B) if you need AWS IAM authentication or strict compliance requiring full SQL control. If unsure, use Drizzle.

If the user says "database" without specifying, ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

> **AWS IAM authentication**: Only Kysely (Section B) and Mongoose (Section C) include IAM Auth Variants. If AWS IAM database authentication is required for compliance, use Kysely. Do NOT install IAM packages unless the user requests it.

---

## Section A: Drizzle (SQL)

### A1. Install Dependencies

```bash
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit
```

> **Security**: drizzle-orm 0.45.2 fixed a SQL injection vulnerability in `sql.identifier()` and `sql.as()`. Use `>=0.45.2`.

### A2. Add Database Scripts

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

### A3. Create Drizzle Config

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

### A4. Define Schema

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

### A5. Create Database Client

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

### A6. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { db } from './db-client';
export * from './schema';
```

### A7. Add Factory Function

Add to **`src/integrations/factories.ts`**:

```ts
import { db } from './database/db-client';

export function DB() {
  return db;
}
```

### A8. Configure Environment

Add to `.env.local` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

### A9. Generate & Run Migrations

```bash
pnpm db:generate  # generate SQL migration files from schema
pnpm db:migrate   # apply pending migrations to the database
```

For rapid local iteration, `pnpm db:push` applies the schema directly without migration files (dev only — never use against production).

### A10. Usage

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

### A11. Validate

```bash
pnpm db:generate && pnpm build
```

Confirm the migration file was generated and the build succeeds with no type errors. Skip to [Rules](#rules).

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (Section B) instead.

---

## Section B: Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. If the user requires AWS IAM auth, see the IAM variant below.

### B1. Install Dependencies

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

### B2. Create Database Client

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

#### IAM Auth Variant

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

### B3. Define Database Types

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

### B4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { db } from './kysely-client';
export type { Database, User, NewUser, UserUpdate } from './types';
```

### B5. Create First Migration

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

Run migrations with: `npx tsx src/integrations/database/migrate.ts`

### B6. Configure Environment

Add to `.env.local` and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

### B7. Usage

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

### B8. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors. Skip to [Rules](#rules).

---

## Section C: Mongoose (MongoDB)

### C1. Install Dependencies

```bash
pnpm add mongoose
```

### C2. Create Mongoose Client Singleton

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

#### IAM Auth Variant

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

### C3. Create a Schema

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

### C4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { connectDB } from './mongoose-client';
```

### C5. Configure Environment

Add to `.env.local` (or `.env`) and `.env.example`:

```env
MONGODB_URL="mongodb://localhost:27017/mydb"
```

### C6. Usage

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

### C7. Validate

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
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Add `*.db` and `*.db-journal` to `.gitignore` for SQLite. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.
- **Kysely**: Write manual `up`/`down` migration files in `src/integrations/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant pool config — no query code changes needed.
- **Mongoose**: Always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors. For IAM auth, install `@aws-sdk/credential-providers` and use the `MONGODB-AWS` auth mechanism — no schema or query code changes needed.
