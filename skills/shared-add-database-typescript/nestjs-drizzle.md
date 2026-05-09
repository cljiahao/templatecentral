## Section A: Drizzle (SQL)

> **Drizzle ORM v1**: v1.0 is stable (released mid-2025). The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.

### NestJS

#### A1. Install Dependencies

```bash
pnpm add drizzle-orm postgres
pnpm add -D drizzle-kit
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

**`drizzle.config.ts`** (project root):

```ts
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/database/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
});
```

> `drizzle.config.ts` reads `process.env` directly — it runs as a standalone CLI command outside NestJS, so it cannot use `serviceConfig`.

#### A4. Define Schema

**`src/database/schema.ts`**:

```typescript
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

#### A5. Create DrizzleService

**`src/database/drizzle.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { drizzle } from 'drizzle-orm/postgres-js';
import { sql } from 'drizzle-orm';
import postgres from 'postgres';

import { serviceConfig } from '../config/env.config';
import * as schema from './schema';

@Injectable()
export class DrizzleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DrizzleService.name);
  private readonly client: ReturnType<typeof postgres>;
  readonly db: ReturnType<typeof drizzle<typeof schema>>;

  constructor() {
    this.client = postgres(serviceConfig.DATABASE_URL);
    this.db = drizzle(this.client, { schema });
  }

  async onModuleInit() {
    try {
      await this.db.execute(sql`SELECT 1`);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.client.end();
  }
}
```

#### A6. Create DatabaseModule

**`src/database/database.module.ts`**:

```typescript
import { Global, Module } from '@nestjs/common';

import { DrizzleService } from './drizzle.service';

@Global()
@Module({
  providers: [DrizzleService],
  exports: [DrizzleService],
})
export class DatabaseModule {}
```

#### A7. Register in AppModule

Import `DatabaseModule` in `src/app.module.ts`:

```typescript
import { DatabaseModule } from './database/database.module';

@Module({
  imports: [
    DatabaseModule,
    // ...existing modules
  ],
})
export class AppModule {}
```

#### A8. Configure Environment

Add `DATABASE_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_URL: process.env.DATABASE_URL!,
};
```

Add to `.env` and `.env.example`:

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

Inject `DrizzleService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';

@Injectable()
export class UserService {
  constructor(private readonly drizzle: DrizzleService) {}

  findAll() {
    return this.drizzle.db.select().from(users);
  }

  findById(id: string) {
    return this.drizzle.db.select().from(users).where(eq(users.id, id)).then((r) => r[0] ?? null);
  }

  create(data: { email: string; name: string }) {
    return this.drizzle.db.insert(users).values(data).returning();
  }
}
```

> Import `eq` from `drizzle-orm`: `import { eq } from 'drizzle-orm';`

#### A11. Validate

```bash
pnpm db:generate && pnpm build && pnpm test
```

Confirm the migration file was generated, build succeeds, and all tests pass.

> **AWS IAM auth**: Drizzle does not include a native IAM token-fetching variant. If AWS IAM database authentication is required, use **Kysely** (Section B) instead.
