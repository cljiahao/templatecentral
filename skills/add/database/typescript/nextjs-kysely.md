<!-- ref: add/database/typescript/nextjs-kysely.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Kysely (SQL, supports standard + AWS IAM auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
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
    "migrate": "tsx --env-file=.env.local src/integrations/database/migrate.ts"
  }
}
```

#### B2. Create Database Client

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nextjs-kysely bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nextjs-kysely/template/` (listed in `<skill-dir>/database/typescript/nextjs-kysely/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/integrations/database/kysely-client.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-kysely/template/src/integrations/database/kysely-client.ts` by the copy step; do not re-type it.

> **Why the singleton**: Next.js hot-reloads modules in development; caching the Kysely instance (and the pool created inside it) on `globalThis` prevents connection exhaustion.

> **TLS**: the `ssl` option above is the enforcement point. If your managed provider expects TLS to be negotiated from the connection string instead, append `?sslmode=require` (or `?sslmode=verify-full`, which also checks the hostname) to `DATABASE_URL` — same requirement as the IAM variant's `ssl: { rejectUnauthorized: true, ca }` below. Plaintext connections are acceptable only against a local database.

##### IAM Auth Variant

For AWS IAM auth, also install:

```bash
pnpm add @aws-sdk/rds-signer
```

Download the AWS global RDS CA bundle — the Amazon RDS root CA is not in Node's default trust store, so `rejectUnauthorized: true` without `ca` fails with `SELF_SIGNED_CERT_IN_CHAIN` (and `rejectUnauthorized: false` is never the fix). Commit it (public certificate, not a secret) or bake it into the image:

```bash
mkdir -p certs
curl -fsSL -o certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Replace the pool creation in `kysely-client.ts` with:

```ts
import { readFileSync } from 'node:fs';
import { Kysely, PostgresDialect } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import type { Database } from './types';

const signer = new Signer({
  hostname: process.env.DATABASE_HOST!,
  port: Number(process.env.DATABASE_PORT ?? '5432'),
  username: process.env.DATABASE_USER!,
});

function createPool() {
  return new Pool({
    host: process.env.DATABASE_HOST,
    port: Number(process.env.DATABASE_PORT ?? '5432'),
    user: process.env.DATABASE_USER,
    database: process.env.DATABASE_NAME,
    // Called per new connection, so each one gets a fresh 15-minute IAM token.
    password: () => signer.getAuthToken(),
    ssl: { rejectUnauthorized: true, ca: readFileSync(process.env.RDS_CA_BUNDLE_PATH!, 'utf8') },
    max: 10,
  });
}

const globalForKysely = globalThis as unknown as { db?: Kysely<Database> };

export const db =
  globalForKysely.db ?? new Kysely<Database>({ dialect: new PostgresDialect({ pool: createPool() }) });

if (process.env.NODE_ENV !== 'production') globalForKysely.db = db;
```

IAM environment variables (add to `.env.local` and `.env.example`):

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
RDS_CA_BUNDLE_PATH=certs/rds-global-bundle.pem
```

> **IAM fields replace `DATABASE_URL`** — remove `DATABASE_URL` from `.env` when using IAM auth. `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

#### B3. Define Database Types

**`src/integrations/database/types.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-kysely/template/src/integrations/database/types.ts` by the copy step; do not re-type it.

> **Tip**: After the database exists, run `pnpm exec kysely-codegen` to auto-generate types from the live schema instead of maintaining them manually.

#### B4. Create Barrel Export

**`src/integrations/database/index.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-kysely/template/src/integrations/database/index.ts` by the copy step; do not re-type it.

#### B5. Create First Migration

**`src/integrations/database/migrations/001_initial.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-kysely/template/src/integrations/database/migrations/001_initial.ts` by the copy step; do not re-type it.

Create a migration runner script at **`src/integrations/database/migrate.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-kysely/template/src/integrations/database/migrate.ts` by the copy step; do not re-type it.

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
import { z } from 'zod';
import { db } from '@/integrations/database';
import { withLogging } from '@/lib/utils/with-logging';

export const GET = withLogging(async () => {
  // Explicit column list — never send full records to the browser.
  const users = await db.selectFrom('users')
    .select(['id', 'email', 'name'])
    .execute();
  return NextResponse.json(users);
});

const createUserSchema = z.object({
  email: z.email(),
  name: z.string().min(1),
});

export const POST = withLogging(async (request) => {
  const result = createUserSchema.safeParse(await request.json());
  if (!result.success) {
    return NextResponse.json(
      { error: 'Validation failed', details: z.flattenError(result.error) },
      { status: 400 }
    );
  }
  const body = result.data;
  const user = await db
    .insertInto('users')
    .values({ email: body.email, name: body.name })
    .returning(['id', 'email', 'name'])
    .executeTakeFirstOrThrow();
  return NextResponse.json(user, { status: 201 });
});
```

**In Server Components**:

```tsx
// src/app/dashboard/users/page.tsx
import { db } from '@/integrations/database';

export default async function UsersPage() {
  // Explicit column list — never send full records to the browser.
  const users = await db.selectFrom('users').select(['id', 'email', 'name']).execute();
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

- **Opt-in only** — add a database only on request.
- **Default to password auth** — use AWS SDK packages and IAM variants only when the user requires AWS IAM.
- Client and schemas live in `src/integrations/database/`.
- Keep the cached singleton — it prevents connection exhaustion on hot reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — server-only (`'use server'`, API routes, Server Components).
- **Kysely**: Write manual `up`/`down` migration files in `src/integrations/database/migrations/`, named `NNN_<description>.ts` with the next unused number — Kysely runs them in name order and fails on a file that sorts before an executed one. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant pool config; query code is unchanged.

---

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.