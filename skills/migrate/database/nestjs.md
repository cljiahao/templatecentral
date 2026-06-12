<!-- ref: migrate/database/nestjs.md
     loaded-by: migrate/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->
## NestJS Database Migration

**Read `drizzle-to-kysely.md` first** — shared steps (1, 5, 8 up-body, 9 translation table, 10 env block, After Writing Code) live there.

```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/migrate/database/drizzle-to-kysely.md"
```

---

### Step 2 — Update `package.json` scripts

Remove `db:generate`, `db:migrate`, `db:push`, `db:studio`. Add:

```json
{
  "scripts": {
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

### Step 3 — Delete Drizzle files

> **Gate — these are user files.** Create a migration branch and get explicit user confirmation before running the deletions below; never delete user code without it.

```bash
git checkout -b migrate/drizzle-to-kysely   # then confirm with the user before the rm commands
rm src/database/drizzle.service.ts
rm src/database/schema.ts
rm drizzle.config.ts
rm -rf drizzle/
```

### Step 4 — Create `src/database/kysely.service.ts` (IAM variant)

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const signer = new Signer({
      hostname: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      username: serviceConfig.DATABASE_USER,
    });

    const pool = new Pool({
      host: serviceConfig.DATABASE_HOST,
      port: serviceConfig.DATABASE_PORT,
      user: serviceConfig.DATABASE_USER,
      database: serviceConfig.DATABASE_NAME,
      password: () => signer.getAuthToken(),
      ssl: { rejectUnauthorized: true },
      max: 10,
    });

    super({ dialect: new PostgresDialect({ pool }) });
  }

  async onModuleInit() {
    try {
      await sql`SELECT 1`.execute(this);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.destroy();
  }
}
```

### Step 5 — Create `src/database/types.ts`

Use the shared types template from `drizzle-to-kysely.md` Step 5.

### Step 6 — Update `src/database/database.module.ts`

Replace `DrizzleService` with `KyselyService`:

```typescript
import { Global, Module } from '@nestjs/common';
import { KyselyService } from './kysely.service';

@Global()
@Module({
  providers: [KyselyService],
  exports: [KyselyService],
})
export class DatabaseModule {}
```

### Step 7 — Create `src/database/migrate.ts`

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { FileMigrationProvider, Migrator, Kysely, PostgresDialect } from 'kysely';
import { Signer } from '@aws-sdk/rds-signer';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const signer = new Signer({
    hostname: serviceConfig.DATABASE_HOST,
    port: serviceConfig.DATABASE_PORT,
    username: serviceConfig.DATABASE_USER,
  });

  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({
        host: serviceConfig.DATABASE_HOST,
        port: serviceConfig.DATABASE_PORT,
        user: serviceConfig.DATABASE_USER,
        database: serviceConfig.DATABASE_NAME,
        password: () => signer.getAuthToken(),
        ssl: { rejectUnauthorized: true },
      }),
    }),
  });

  const migrator = new Migrator({
    db,
    provider: new FileMigrationProvider({
      fs,
      path,
      migrationFolder: path.join(__dirname, 'migrations'),
    }),
  });

  const { results, error } = await migrator.migrateToLatest();
  // result-handling block: see drizzle-to-kysely.md Step 7
}

migrate();
```

### Step 8 — Write first Kysely migration

Create `src/database/migrations/001_initial.ts`. Use the `up` body from `drizzle-to-kysely.md` Step 8.

NestJS `down` is a no-op (table pre-existed under Drizzle):

```typescript
export async function down(_db: Kysely<unknown>): Promise<void> {
  // No-op by design: the users table pre-existed this adoption migration.
  // Dropping it on rollback would destroy production data.
}
```

### Step 9 — Update query code in feature services

Use the translation table from `drizzle-to-kysely.md` Step 9.

Also update constructor injection: replace `private readonly drizzle: DrizzleService` → `private readonly db: KyselyService`.

### Step 10 — Update `src/config/env.config.ts`

Replace `DATABASE_URL` with IAM fields:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_HOST: process.env.DATABASE_HOST!,
  DATABASE_PORT: Number(process.env.DATABASE_PORT ?? '5432'),
  DATABASE_USER: process.env.DATABASE_USER!,
  DATABASE_NAME: process.env.DATABASE_NAME!,
};
```

Update `.env` and `.env.example` — use the env block from `drizzle-to-kysely.md` Step 10.

### Step 11 — Validate

See `drizzle-to-kysely.md` Step 11 (NestJS runs `pnpm build && pnpm test`). Then follow After Writing Code.
