---
name: add-database
description: Use when the user wants to add a database to a Next.js project — Prisma for SQL databases (PostgreSQL, MySQL, SQLite) or Mongoose for MongoDB.
---

# Add Database to Next.js

Add a database to a Next.js project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The base template is intentionally database-free.

## Choose Your Database

Ask the user which database they need, then follow the corresponding section:

| Database type | ORM/ODM | Section |
|--------------|---------|---------|
| PostgreSQL, MySQL, SQLite | Prisma (ORM) | [Section A](#section-a-prisma-sql) |
| MongoDB | Mongoose (ODM) | [Section B](#section-b-mongoose-mongodb) |

If the user says "database" without specifying, ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

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
DATABASE_URL="postgresql://user:password@localhost:5432/mydb"
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

---

## Section B: Mongoose (MongoDB)

### B1. Install Dependencies

```bash
pnpm add mongoose
```

### B2. Create Mongoose Client Singleton

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

### B3. Create a Schema

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

### B4. Create Barrel Export

**`src/integrations/database/index.ts`**:

```ts
export { connectDB } from './mongoose-client';
```

### B5. Configure Environment

Add to `.env.local` (or `.env`) and `.env.example`:

```env
MONGODB_URL="mongodb://localhost:27017/mydb"
```

### B6. Usage

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

### B7. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors.

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- Keep `DATABASE_URL` in `.env` (Prisma CLI reads `.env` by default); keep `MONGODB_URL` in `.env.local` or `.env` — NEVER hardcode credentials.
- Update `.env.example` with placeholder values so other developers know what to configure.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- For Prisma: always run `prisma generate` after schema changes; use `prisma migrate dev` for development migrations.
- For Mongoose: always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors.
- Add `*.db` to `.gitignore` for SQLite — NEVER ignore the `prisma/` directory itself (it contains `schema.prisma` and migrations that must be tracked).
