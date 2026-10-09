<!-- ref: migrate/database/drizzle-to-kysely.md
     loaded-by: migrate/database/nestjs.md + migrate/database/nextjs.md → migrate/SKILL.md
     prereq: Drizzle → Kysely migration shared steps. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

## Shared Steps — Drizzle to Kysely Migration

### Step 1 — Swap packages

```bash
pnpm remove drizzle-orm drizzle-kit
pnpm add kysely pg @aws-sdk/rds-signer
pnpm add -D kysely-codegen @types/pg tsx
```

### Step 2 — Update `package.json` scripts

Remove `db:generate`, `db:migrate`, `db:push`, `db:studio`. Add the `migrate` script — the path differs per stack (see the leaf file for the exact path).

### Step 5 — Create `types.ts`

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

> **Tip**: Run `npx kysely-codegen` after connecting to generate types automatically from the live schema. Note it connects via a `DATABASE_URL` with password auth — which this migration removes — so point it at a temporary password-auth connection string for the run (e.g. `DATABASE_URL=postgresql://user:pass@host:5432/db npx kysely-codegen`).

### Step 8 — Write first Kysely migration for existing tables

The file path differs per stack (see leaf file); the body is the same:

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

export async function down(_db: Kysely<unknown>): Promise<void> {
  // No-op by design: the table pre-existed this adoption migration, so dropping it on
  // rollback would destroy production data.
}
```

> `.ifNotExists()` makes `up` idempotent — the table already exists from the Drizzle setup.

### Step 9 — Query translation reference

Drizzle → Kysely query translation reference:

| Drizzle | Kysely |
|---|---|
| `drizzle.db.select().from(users)` | `db.selectFrom('users').selectAll().execute()` |
| `drizzle.db.select().from(users).where(eq(users.id, id))` | `db.selectFrom('users').selectAll().where('id', '=', id).executeTakeFirst()` |
| `drizzle.db.insert(users).values(data).returning()` | `db.insertInto('users').values(data).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.update(users).set(data).where(eq(users.id, id))` | `db.updateTable('users').set(data).where('id', '=', id).returningAll().executeTakeFirstOrThrow()` |
| `drizzle.db.delete(users).where(eq(users.id, id))` | `db.deleteFrom('users').where('id', '=', id).executeTakeFirst()` |

### Step 10 — Update env vars

Replace `DATABASE_URL` with the IAM fields in `.env.example` yourself; **ask the user** to make the same change in their real env file (agent edits to `.env*` files are hook-blocked by design).

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
# Region for the RDS token signer
AWS_REGION=us-east-1
# Amazon RDS CA bundle — not in Node's default trust store
RDS_CA_BUNDLE_PATH=certs/rds-global-bundle.pem
```

### Step 11 — Validate

```bash
pnpm build
```

Build must succeed with zero TypeScript errors. NestJS also runs `pnpm test` — all tests must pass.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
