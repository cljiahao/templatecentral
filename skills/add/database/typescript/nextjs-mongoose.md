<!-- ref: add/database/typescript/nextjs-mongoose.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Mongoose (MongoDB). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js + Mongoose (MongoDB)

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
    cached.promise = mongoose.connect(MONGODB_URL, {
      // Fail fast instead of holding a serverless invocation open for the 30s default
      serverSelectionTimeoutMS: 5_000,
      // Each serverless instance keeps its own pool — a small cap avoids exhausting
      // the cluster's connection limit as instances scale out
      maxPoolSize: 10,
    });
  }

  try {
    const conn = await cached.promise;
    // Mongoose builds indexes in the background; wait so unique constraints exist before the first write.
    await Promise.all(conn.modelNames().map((name) => conn.model(name).init()));
    cached.conn = conn;
  } catch (error) {
    // Drop the rejected promise so the next request retries instead of failing forever.
    cached.promise = null;
    throw error;
  }
  return cached.conn;
}
```

> **Why the cached pattern**: Next.js hot-reloads modules in development. The `globalThis` cache prevents opening duplicate MongoDB connections.

> **TLS in transit is required for any non-local cluster** — the localhost `MONGODB_URL` below is a development default only. Append `?tls=true` to `MONGODB_URL` for a self-hosted or DocumentDB cluster (the IAM variant below does exactly this); `mongodb+srv://` URLs, as used by Atlas, enable TLS implicitly. Never disable certificate validation (`tlsAllowInvalidCertificates`) to work around a handshake failure — install the cluster's CA instead.

##### IAM Auth Variant

If the user requires AWS IAM authentication (e.g., connecting to Amazon DocumentDB or MongoDB Atlas with AWS IAM), install the additional package:

```bash
pnpm add @aws-sdk/credential-providers
```

In `mongoose-client.ts`, replace the `MONGODB_URL` guard with the one below and the `mongoose.connect(...)` assignment inside `connectDB()` with the IAM connect (the cache and retry logic stay unchanged):

```ts
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';

const MONGODB_HOST = process.env.MONGODB_HOST;
const MONGODB_DB_NAME = process.env.MONGODB_DB_NAME;

if (!MONGODB_HOST || !MONGODB_DB_NAME) {
  throw new Error('MONGODB_HOST and MONGODB_DB_NAME environment variables are required');
}

// Inside connectDB():
cached.promise = mongoose.connect(
  `mongodb://${MONGODB_HOST}:27017/${MONGODB_DB_NAME}?authSource=%24external&authMechanism=MONGODB-AWS&tls=true`,
  {
    serverSelectionTimeoutMS: 5_000,
    maxPoolSize: 10,
    authMechanismProperties: { AWS_CREDENTIAL_PROVIDER: fromNodeProviderChain() },
  },
);
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
import mongoose, { type Model } from 'mongoose';

// Plain interface — Mongoose discourages extending `Document` for schema types.
export interface IUser {
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

export const User =
  (mongoose.models.User as Model<IUser> | undefined) ?? mongoose.model<IUser>('User', userSchema);
```

> **Why `mongoose.models.User ??`**: Prevents the "Cannot overwrite model once compiled" error during hot-reload in development.
>
> Import the model module before the first `connectDB()` call (route handlers import `User`, then connect) so `connectDB()` waits for its unique index.

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
import { withLogging } from '@/lib/utils/with-logging';

export const GET = withLogging(async () => {
  await connectDB();
  // Explicit projection — never send full documents to the browser.
  const users = await User.find().select('name email -_id').lean();
  return NextResponse.json(users);
});
```

**In Server Components**:

```tsx
// src/app/dashboard/users/page.tsx
import { connectDB } from '@/integrations/database';
import { User } from '@/integrations/database/schemas/user';

export default async function UsersPage() {
  await connectDB();
  // Explicit projection — never send full documents to the browser.
  const users = await User.find().select('name email -_id').lean();
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

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- **Mongoose**: Always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors. For IAM auth, install `@aws-sdk/credential-providers` and use the `MONGODB-AWS` auth mechanism — no schema or query code changes needed.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards