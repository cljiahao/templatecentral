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

### Step 7 — Migrate result handling pattern

Both leaf `migrate.ts` files share this result-processing block (place after `migrator.migrateToLatest()`):

```typescript
  results?.forEach((r) => {
    if (r.status === 'Success') console.log(`Migration "${r.migrationName}" executed successfully`);
    else if (r.status === 'Error') console.error(`Migration "${r.migrationName}" failed`);
  });

  if (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }

  await db.destroy();
```

### Step 8 — Write first Kysely migration for existing tables

The migration file path and content differ slightly per stack (see leaf file), but the pattern is the same. Example `up` body:

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
```

> Use `.ifNotExists()` to make the migration idempotent — the table already exists in the database from the Drizzle setup.

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

Replace `DATABASE_URL` with IAM fields in your env file and `.env.example`:

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

### Step 11 — Validate

```bash
pnpm build
```

Build must succeed with zero TypeScript errors. NestJS also runs `pnpm test` — all tests must pass.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards
