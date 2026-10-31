<!-- ref: add/database/typescript/nextjs-drizzle.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = Next.js, ORM = Drizzle (SQL, standard auth). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js + Drizzle (SQL)

> **Pre-release notice**: Drizzle ORM v1 is still pre-release — pin the RC exactly. `drizzle-zod` is merged into `drizzle-orm/zod` — import from there, not the old `drizzle-zod` package.

#### A1. Install Dependencies

Read the exact RC from the plugin's version SSOT — `cat "<skill-dir>/../../.claude/rules/nextjs.md"` (the scaffolded project has no copy) — and install it exactly; never the floating `@rc` tag, which resolves to a different RC on every install:

```bash
pnpm add --save-exact drizzle-orm@<exact-rc-from-rules> postgres
pnpm add -D --save-exact drizzle-kit@<exact-rc-from-rules>
```

Both packages must be on the same RC — a `drizzle-kit` that disagrees with `drizzle-orm` generates migrations the runtime cannot read.

`drizzle-kit` pulls in `esbuild`, whose install script pnpm 12 blocks — `pnpm install` fails with `ERR_PNPM_IGNORED_BUILDS` until you record a decision. Its platform binary ships as an optional dependency, so the script is not needed; add under `allowBuilds:` in `pnpm-workspace.yaml`:

```yaml
  esbuild: false
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

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nextjs-drizzle bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nextjs-drizzle/template/` (listed in `<skill-dir>/database/typescript/nextjs-drizzle/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`drizzle.config.ts`** (project root):

Copied verbatim from `<skill-dir>/database/typescript/nextjs-drizzle/template/drizzle.config.ts` by the copy step; do not re-type it.

#### A4. Define Schema

**`src/integrations/database/schema.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-drizzle/template/src/integrations/database/schema.ts` by the copy step; do not re-type it.

#### A5. Create Database Client

**`src/integrations/database/db-client.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-drizzle/template/src/integrations/database/db-client.ts` by the copy step; do not re-type it.

> **TLS**: the `ssl` option is the enforcement point for the app (`next build`/`next start` run with `NODE_ENV=production`). `drizzle.config.ts` runs as a standalone CLI outside Next.js and uses only the URL — against any non-local database, end that `DATABASE_URL` with `?sslmode=verify-full` so `drizzle-kit migrate` verifies the server certificate (`require` encrypts without verifying identity).

> **Why the singleton**: Next.js hot-reloads in development, which creates new connection pools on every reload. The `globalThis` cache prevents connection exhaustion.

#### A6. Create Barrel Export

**`src/integrations/database/index.ts`**:

Copied verbatim from `<skill-dir>/database/typescript/nextjs-drizzle/template/src/integrations/database/index.ts` by the copy step; do not re-type it.

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
pnpm db:generate
pnpm db:migrate
```

For rapid local iteration, `pnpm db:push` applies the schema directly without migration files (dev only — never use against production).

#### A9b. Persist better-auth sessions (only if `src/lib/auth.ts` exists)

Without this, `templatecentral:add (auth)` keeps users and sessions in process memory. Drizzle v1 has no `relations()` export, so use the adapter's Relations v2 entry point (the default `better-auth/adapters/drizzle` entry generates v0.x `relations()` code that fails `tsc` and the build):

```bash
pnpm add @better-auth/drizzle-adapter
```

Keep it on the same version as `better-auth` — the two release in lockstep.

Export the schema namespace from `src/integrations/database/index.ts`:

```ts
export * as schema from './schema';
```

In `src/lib/auth.ts`, import `drizzleAdapter` from `@better-auth/drizzle-adapter/relations-v2` and `{ db, schema }` from `@/integrations/database`, then add `database: drizzleAdapter(db, { provider: 'pg', schema }),` after `secret`. Generate the auth tables with the CLI matching the installed `better-auth` version — it imports `src/lib/auth.ts`, so run it with `BETTER_AUTH_SECRET` exported (any `openssl rand -base64 32` value) — then re-export them and create the migration:

```bash
npx auth@<installed-better-auth-version> generate --output src/integrations/database/auth-schema.ts --yes
echo "export * from './auth-schema';" >> src/integrations/database/schema.ts
pnpm db:generate
```

`auth-schema.ts` is CLI-owned — regenerate it after every better-auth upgrade instead of editing it. Its exported `authRelations` only needs passing to `drizzle({ relations })` if you enable `advanced.database.joins`.

#### A10. Usage

**In API routes** (for client-side fetching via React Query):

```ts
// src/app/api/users/route.ts
import { NextResponse } from 'next/server';
import { db, users } from '@/integrations/database';
import { withLogging } from '@/lib/utils/with-logging';

export const GET = withLogging(async () => {
  // Explicit column list — never send full records to the browser.
  const all = await db
    .select({ id: users.id, email: users.email, name: users.name })
    .from(users);
  return NextResponse.json(all);
});
```

**In Server Components** (direct DB access, no API hop):

```tsx
// src/app/dashboard/users/page.tsx
import { db, users } from '@/integrations/database';

export default async function UsersPage() {
  const all = await db.select({ id: users.id, name: users.name }).from(users);
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

> **Need to upgrade to high compliance later?** Tell me *"migrate database to compliance"* and I'll handle the switch to Kysely + AWS IAM.

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- Database client and schemas live in `src/integrations/database/` — consistent with the integration layer pattern.
- Always use the singleton/cached pattern to prevent connection exhaustion during hot-reload.
- NEVER hardcode credentials — keep connection config in `.env` / `.env.local` and document in `.env.example`.
- NEVER import database code in client components — database access is server-only (`'use server'`, API routes, Server Components).
- **Drizzle**: Run `pnpm db:generate` after schema changes; run `pnpm db:migrate` to apply. Use `pnpm db:push` in development only — never against production. Migration files live in `drizzle/` at the project root; commit them to version control. Does not include a native IAM token-fetching variant — use Kysely if IAM auth is required.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards