---
name: nextjs-add-database
description: Use when the user wants to add a database to a Next.js project — Prisma (SQL), Kysely (SQL), or Mongoose (MongoDB). Supports optional AWS IAM authentication for compliance environments.
---

# Add Database to Next.js

Add a database to a Next.js project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The base template is intentionally database-free.

## Choose Your Database

Ask the user which database they need, then follow the corresponding section:

| Database type | ORM/ODM | Section |
|--------------|---------|---------|
| PostgreSQL, MySQL, SQLite | Prisma | [Section A](#section-a-prisma-sql) |
| PostgreSQL, MySQL | Kysely | [Section B](#section-b-kysely-sql) |
| MongoDB | Mongoose | [Section C](#section-c-mongoose-mongodb) |

> **How to choose SQL ORM**: Use **Prisma** (Section A) for the best developer experience — auto-migrations, generated types, Prisma Studio. Use **Kysely** (Section B) if you need full SQL control and best serverless performance. If unsure, start with Prisma.

If the user says "database" without specifying, ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

> **AWS IAM authentication**: If the user explicitly requires AWS IAM database authentication for compliance, each section includes an "IAM Auth Variant" with the additional packages and configuration needed. Do NOT install IAM packages unless the user requests it.

---

## Section A: Prisma (SQL)

### A1. Install Dependencies

```bash
pnpm add @prisma/client
pnpm add -D prisma
```

### A2. Initialize Prisma

```bash
npx prisma init
```

This creates `prisma/schema.prisma` and adds `DATABASE_URL` to `.env`. Keep it in `.env` — Prisma CLI (`npx prisma generate`, `npx prisma migrate`) reads `.env` by default, not `.env.local`. Add a placeholder to `.env.example` and add `.env` to `.gitignore` if not already present.

### A3. Create Prisma Client Singleton

**`src/integrations/database/prisma-client.ts`**:

```ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
```

> **Why the singleton**: Next.js hot-reloads in development, which creates new `PrismaClient` instances on every reload. The `globalThis` cache prevents connection exhaustion.

### A4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { prisma } from './prisma-client';
```

### A5. Add Factory Function

Add to **`src/integrations/factories.ts`**:

```ts
import { prisma } from './database/prisma-client';

export function DB() {
  return prisma;
}
```

### A6. Define Schema

Edit `prisma/schema.prisma`:

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"  // or "sqlite", "mysql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
}
```

### A7. Configure Environment

Add to `.env` (Prisma CLI reads this) and `.env.example`:

```env
DATABASE_URL="postgresql://DBUSER:DBPASSWORD@localhost:5432/DBNAME"
```

For SQLite, use:
```env
DATABASE_URL="file:./dev.db"
```

### A8. Generate Client & Migrate

```bash
npx prisma generate
npx prisma migrate dev --name init
```

### A9. Usage

**In API routes** (for client-side fetching via React Query):

```ts
// src/app/api/users/route.ts
import { NextResponse } from 'next/server';
import { prisma } from '@/integrations/database';

export async function GET() {
  const users = await prisma.user.findMany();
  return NextResponse.json(users);
}
```

**In Server Components** (direct DB access, no API hop):

```tsx
// src/app/dashboard/users/page.tsx
import { prisma } from '@/integrations/database';

export default async function UsersPage() {
  const users = await prisma.user.findMany();
  return <UserList users={users} />;
}
```

**Via factory** (in feature services):

```ts
import { DB } from '@/integrations/factories';

const users = await DB().user.findMany();
```

### A10. Validate

```bash
npx prisma generate && pnpm build
```

Confirm the build succeeds with no type errors. Skip to [Rules](#rules).

> **Note**: Prisma does not natively support AWS IAM database authentication. If compliance requires IAM auth, use **Kysely** (Section B) instead.

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

> **Why the singleton**: Same as Prisma — Next.js hot-reloads in development. The `globalThis` cache prevents connection exhaustion.

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

IAM environment variables (add to `.env` and `.env.example`):

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

Add to `.env` and `.env.example`:

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

> **Why the cached pattern**: Same reason as Prisma — Next.js hot-reloads in development. The `globalThis` cache prevents opening duplicate MongoDB connections.

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
- **Prisma**: Always run `prisma generate` after schema changes; use `prisma migrate dev` for development migrations. Keep `DATABASE_URL` in `.env` (Prisma CLI reads `.env` by default). Add `*.db` to `.gitignore` for SQLite — NEVER ignore the `prisma/` directory itself. Does not support AWS IAM auth natively — use Kysely if IAM is required.
- **Prisma 6 — not found handling**: `NotFoundError` was removed in Prisma 6 — do NOT import it from `@prisma/client`. Use one of these patterns instead:

  **Option A — null check (preferred for simple cases):**
  ```ts
  const record = await prisma.model.findUnique({ where: { id } });
  if (!record) return NextResponse.json({ error: 'Not found' }, { status: 404 });
  ```

  **Option B — throw on not found (useful inside service layers):**
  ```ts
  import { Prisma } from '@prisma/client';
  try {
    const record = await prisma.model.findUniqueOrThrow({ where: { id } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }
    throw error;
  }
  ```

  Note: `findUniqueOrThrow` is incompatible with sequential (array-style) `$transaction` — use interactive transactions (`$transaction(async (tx) => { ... })`) if rollback on not-found is needed.
- **Kysely**: Write manual `up`/`down` migration files in `src/integrations/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant pool config — no query code changes needed.
- **Mongoose**: Always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors. For IAM auth, install `@aws-sdk/credential-providers` and use the `MONGODB-AWS` auth mechanism — no schema or query code changes needed.
