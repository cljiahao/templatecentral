<!-- ref: add/database/typescript/nextjs-mongoose.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Mongoose (MongoDB). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js + Mongoose (MongoDB)

#### C1. Install Dependencies

```bash
pnpm add mongoose
```

#### C2. Create Mongoose Client Singleton

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nextjs-mongoose bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nextjs-mongoose/template/` (listed in `<skill-dir>/database/typescript/nextjs-mongoose/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/integrations/database/mongoose-client.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts` by the copy step; do not re-type it.

> **Why the cached pattern**: Next.js hot-reloads modules in development. The `globalThis` cache prevents opening duplicate MongoDB connections.

> **TLS in transit is required for any non-local cluster** — the localhost `MONGODB_URL` below is a development default only. Append `?tls=true` to `MONGODB_URL` for a self-hosted or DocumentDB cluster (the IAM variant below does exactly this); `mongodb+srv://` URLs, as used by Atlas, enable TLS implicitly. Never disable certificate validation (`tlsAllowInvalidCertificates`) to work around a handshake failure — install the cluster's CA instead.

##### IAM Auth Variant

For AWS IAM auth (DocumentDB, Atlas), also install:

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

> With `AWS_CREDENTIAL_PROVIDER` the driver resolves credentials (instance role, env vars or SSO profile via `@aws-sdk/credential-providers`) and rotates tokens on reconnect. For Atlas, use `mongodb+srv://` without the port and `&tls=true`.

#### C3. Create a Schema

**`src/integrations/database/schemas/user.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-mongoose/template/src/integrations/database/schemas/user.ts` by the copy step; do not re-type it.

> **Why `mongoose.models.User ??`**: Prevents the "Cannot overwrite model once compiled" error during hot-reload in development.
>
> Import the model module before the first `connectDB()` call (route handlers import `User`, then connect) so `connectDB()` waits for its unique index.

#### C4. Create Barrel Export

**`src/integrations/database/index.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-mongoose/template/src/integrations/database/index.ts` by the copy step; do not re-type it.

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

- **Opt-in only** — add a database only on request.
- **Default to password auth** — use AWS SDK packages and IAM variants only when the user requires AWS IAM.
- Client and schemas live in `src/integrations/database/`.
- Keep the cached singleton — it prevents connection exhaustion on hot reload.
- Do not hardcode credentials; keep connection config in `.env` / `.env.local` and document in `.env.example`.
- Import database code only on the server, never in client components (`'use server'`, API routes, Server Components).
- **Mongoose**: Always use `mongoose.models.X ?? mongoose.model()` to prevent model recompilation errors. For IAM auth, install `@aws-sdk/credential-providers` and use the `MONGODB-AWS` auth mechanism; schema and query code are unchanged.

---

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.