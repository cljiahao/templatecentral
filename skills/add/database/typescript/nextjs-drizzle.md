<!-- ref: add/database/typescript/nextjs-drizzle.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Drizzle (SQL, standard auth). Do not invoke this file directly. -->
## Next.js + Drizzle (SQL)

> **Pre-release notice**: Drizzle ORM v1 is still pre-release — pin a specific RC in `package.json` (current RC tracked in `.claude/rules/nextjs.md`). The `drizzle-zod` integration is now merged into `drizzle-orm/zod`. Import from `drizzle-orm/zod`, not the old `drizzle-zod` package.

#### A1. Install Dependencies

```bash
pnpm add drizzle-orm@rc postgres
pnpm add -D drizzle-kit
```

`drizzle-orm@rc` resolves the latest v1 RC — pin the exact RC in `package.json` afterwards (see `.claude/rules/nextjs.md`).

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

// drizzle-kit does not load .env.local (Next.js convention) — load it explicitly.
// NOTE: process.loadEnvFile() throws if the file does not exist — make sure
// .env.local is created (step A8) before running any db:* script.
process.loadEnvFile('.env.local');

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

const globalForDb = globalThis as unknown as { db: ReturnType<typeof drizzle<typeof schema>> };

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
  // Select only fields needed — never send full records to the browser
  const all = await db
    .select({ id: users.id, email: users.email, name: users.name })
    .from(users);
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

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (select Kysely when prompted) instead.

---

> **Need to upgrade to high compliance later?** Tell me *"migrate database to compliance"* and I'll handle the switch to Kysely + AWS IAM.

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Add `*.db` and `*.db-journal` to `.gitignore` for SQLite. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards