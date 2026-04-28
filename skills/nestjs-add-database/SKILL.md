---
name: nestjs-add-database
description: Use when the user wants to add a database to a NestJS project — Prisma (SQL), Kysely (SQL), or Mongoose (MongoDB). Supports optional AWS IAM authentication for compliance environments.
---

# Add Database to NestJS

Add a database to a NestJS project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The template has an empty `src/database/` directory ready for database modules.

## Choose Your Database

Ask the user which database they need, then follow the corresponding section:

| Database type | ORM/ODM | Section |
|--------------|---------|---------|
| PostgreSQL, MySQL, SQLite | Prisma | [Section A](#section-a-prisma-sql) |
| PostgreSQL, MySQL | Kysely | [Section B](#section-b-kysely-sql) |
| MongoDB | Mongoose | [Section C](#section-c-mongoose-mongodb) |

> **How to choose SQL ORM**: Use **Prisma** (Section A) for the best developer experience — auto-migrations, generated types, Prisma Studio. Use **Kysely** (Section B) if you need full SQL control and best performance. If unsure, start with Prisma.

If the user says "database" without specifying, ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

> **AWS IAM authentication**: If the user explicitly requires AWS IAM database authentication for compliance, each section includes an "IAM Auth Variant" with the additional packages and configuration needed. Do NOT install IAM packages unless the user requests it.

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

This creates:
- `prisma/schema.prisma` — schema definition
- `.env` — with a `DATABASE_URL` placeholder

### A3. Create PrismaService

**`src/database/prisma.service.ts`**:

```typescript
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

### A4. Create DatabaseModule

**`src/database/database.module.ts`**:

```typescript
import { Global, Module } from '@nestjs/common';

import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class DatabaseModule {}
```

### A5. Register in AppModule

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

Prisma reads `DATABASE_URL` from `.env` directly. For consistency with the NestJS template's config pattern, also register it in `serviceConfig` in `src/config/env.config.ts`:

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

### A8. Generate Client & Migrate

```bash
npx prisma generate
npx prisma migrate dev --name init
```

### A9. Usage

Inject `PrismaService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../database/prisma.service';

@Injectable()
export class UserService {
  constructor(private readonly prisma: PrismaService) {}

  findAll() {
    return this.prisma.user.findMany();
  }

  findById(id: string) {
    return this.prisma.user.findUnique({ where: { id } });
  }

  create(data: { email: string; name: string }) {
    return this.prisma.user.create({ data });
  }
}
```

### A10. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass. Skip to [Rules](#rules).

> **Note**: Prisma does not natively support AWS IAM database authentication. If compliance requires IAM auth, use **Kysely** (Section B) instead.

---

## Section B: Kysely (SQL)

Kysely is a type-safe SQL query builder with full SQL control and minimal overhead. It defaults to standard password authentication. If the user requires AWS IAM auth, see the IAM variant below.

### B1. Install Dependencies

```bash
pnpm add kysely pg
pnpm add -D kysely-codegen @types/pg tsx
```

Add a migration script to `package.json`:

```json
{
  "scripts": {
    "migrate": "tsx src/database/migrate.ts"
  }
}
```

### B2. Create KyselyService

**`src/database/kysely.service.ts`**:

```typescript
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { Kysely, PostgresDialect, sql } from 'kysely';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

@Injectable()
export class KyselyService extends Kysely<Database> implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KyselyService.name);

  constructor() {
    const pool = new Pool({
      connectionString: serviceConfig.DATABASE_URL,
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

#### IAM Auth Variant

If the user requires AWS IAM authentication, install the additional package:

```bash
pnpm add @aws-sdk/rds-signer
```

Replace the constructor in `kysely.service.ts` with:

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

> **IAM fields replace `DATABASE_URL`** — remove `DATABASE_URL` from `serviceConfig` when using IAM auth.

Add IAM fields to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  DATABASE_HOST: process.env.DATABASE_HOST!,
  DATABASE_PORT: Number(process.env.DATABASE_PORT ?? '5432'),
  DATABASE_USER: process.env.DATABASE_USER!,
  DATABASE_NAME: process.env.DATABASE_NAME!,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
DATABASE_HOST=your-rds-instance.region.rds.amazonaws.com
DATABASE_PORT=5432
DATABASE_USER=iam_db_user
DATABASE_NAME=mydb
```

> IAM auth does not use a password — `@aws-sdk/rds-signer` generates a short-lived token automatically from the instance's IAM role.

### B3. Define Database Types

**`src/database/types.ts`**:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
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

> **Tip**: After the database exists, run `npx kysely-codegen` to auto-generate types from the live schema instead of maintaining them manually.

### B4. Create DatabaseModule

**`src/database/database.module.ts`**:

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

### B5. Register in AppModule

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

### B6. Create First Migration

**`src/database/migrations/001_initial.ts`**:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('users')
    .addColumn('id', 'text', (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()`))
    .addColumn('email', 'text', (col) => col.notNull().unique())
    .addColumn('name', 'text', (col) => col.notNull())
    .addColumn('created_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .addColumn('updated_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('users').execute();
}
```

Create a migration runner at **`src/database/migrate.ts`**:

```typescript
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { FileMigrationProvider, Migrator, PostgresDialect, Kysely } from 'kysely';
import { Pool } from 'pg';

import { serviceConfig } from '../config/env.config';
import type { Database } from './types';

async function migrate() {
  const db = new Kysely<Database>({
    dialect: new PostgresDialect({
      pool: new Pool({ connectionString: serviceConfig.DATABASE_URL }),
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
  results?.forEach((r) => {
    if (r.status === 'Success') console.log(`Migration "${r.migrationName}" executed successfully`);
    else if (r.status === 'Error') console.error(`Migration "${r.migrationName}" failed`);
  });

  if (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }

  await db.destroy();
}

migrate();
```

Run migrations with: `npx tsx src/database/migrate.ts`

### B7. Configure Environment

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

### B8. Usage

Inject `KyselyService` in any module's service:

```typescript
import { Injectable } from '@nestjs/common';

import { KyselyService } from '../../database/kysely.service';

@Injectable()
export class UserService {
  constructor(private readonly db: KyselyService) {}

  findAll() {
    return this.db.selectFrom('users').selectAll().execute();
  }

  findById(id: string) {
    return this.db.selectFrom('users').selectAll().where('id', '=', id).executeTakeFirst();
  }

  create(data: { email: string; name: string }) {
    return this.db
      .insertInto('users')
      .values(data)
      .returningAll()
      .executeTakeFirstOrThrow();
  }
}
```

### B9. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass. Skip to [Rules](#rules).

---

## Section C: Mongoose (MongoDB)

### C1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

### C2. Create DatabaseModule

**`src/database/database.module.ts`** (uses `serviceConfig` from `src/config/env.config.ts` — external service connections belong in `serviceConfig`, not `appConfig`):

```typescript
import { Global, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    MongooseModule.forRoot(serviceConfig.MONGODB_URL),
  ],
})
export class DatabaseModule {}
```

Add `MONGODB_URL` to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_URL: process.env.MONGODB_URL!,
};
```

> **Alternative**: If the project uses `@nestjs/config` (`pnpm add @nestjs/config`), use `forRootAsync` with `ConfigService` instead of direct `serviceConfig` imports.

#### IAM Auth Variant

If the user requires AWS IAM authentication (e.g., connecting to Amazon DocumentDB or MongoDB Atlas with AWS IAM), install the additional package:

```bash
pnpm add @aws-sdk/credential-providers
```

Replace the `DatabaseModule` with:

```typescript
import { Global, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    // For DocumentDB: mongodb://${HOST}:27017/${DB}?authSource=...&tls=true
    // For Atlas:      mongodb+srv://${HOST}/${DB}?authSource=...
    MongooseModule.forRoot(
      `mongodb://${serviceConfig.MONGODB_HOST}:27017/${serviceConfig.MONGODB_DB_NAME}?authSource=%24external&authMechanism=MONGODB-AWS&tls=true`,
      {
        authMechanismProperties: {
          AWS_CREDENTIAL_PROVIDER: fromNodeProviderChain(),
        },
      },
    ),
  ],
})
export class DatabaseModule {}
```

Add IAM fields to `serviceConfig` in `src/config/env.config.ts`:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_HOST: process.env.MONGODB_HOST!,
  MONGODB_DB_NAME: process.env.MONGODB_DB_NAME!,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
MONGODB_HOST=your-cluster.region.docdb.amazonaws.com
MONGODB_DB_NAME=mydb
```

> The MongoDB driver's `AWS_CREDENTIAL_PROVIDER` delegates credential resolution to the driver itself, which handles automatic token rotation on reconnect. The `@aws-sdk/credential-providers` package resolves IAM credentials from the EC2/ECS instance role, environment variables, or SSO profile. For MongoDB Atlas, replace `mongodb://` with `mongodb+srv://` and remove the port and `&tls=true`.

### C3. Register in AppModule

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

### C4. Create a Schema

**`src/modules/user/schemas/user.schema.ts`** (example):

```typescript
import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { type HydratedDocument } from 'mongoose';

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true })
  email: string;

  @Prop({ required: true })
  name: string;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

### C5. Register Schema in Feature Module

**`src/modules/user/user.module.ts`**:

```typescript
import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { User, UserSchema } from './schemas/user.schema';
import { UserService } from './user.service';
import { UserController } from './user.controller';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: User.name, schema: UserSchema }]),
  ],
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
```

### C6. Usage

Inject the model in the service:

```typescript
import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';

@Injectable()
export class UserService {
  constructor(@InjectModel(User.name) private readonly userModel: Model<UserDocument>) {}

  findAll() {
    return this.userModel.find().exec();
  }

  findById(id: string) {
    return this.userModel.findById(id).exec();
  }

  create(data: { email: string; name: string }) {
    return this.userModel.create(data);
  }
}
```

### C7. Configure Environment

Add to `.env` and `.env.example`:

```env
MONGODB_URL=mongodb://localhost:27017/mydb
```

### C8. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place database services (`PrismaService`, `KyselyService`) and `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Prisma**: Always use `prisma migrate dev` for schema changes. Run `prisma generate` after every schema change. Does not support AWS IAM auth natively — use Kysely if IAM is required.
- **Prisma 6 — not found handling**: `NotFoundError` was removed in Prisma 6 — do NOT import it from `@prisma/client`. Use one of these patterns instead:

  **Option A — null check (preferred for simple cases):**
  ```ts
  const record = await this.prisma.model.findUnique({ where: { id } });
  if (!record) throw new NotFoundException(`Record ${id} not found`);
  ```

  **Option B — throw on not found (cleaner in service methods):**
  ```ts
  import { Prisma } from '@prisma/client';
  try {
    const record = await this.prisma.model.findUniqueOrThrow({ where: { id } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      throw new NotFoundException(`Record ${id} not found`);
    }
    throw error;
  }
  ```

  Note: `findUniqueOrThrow` is incompatible with sequential (array-style) `$transaction` — use interactive transactions (`$transaction(async (tx) => { ... })`) if rollback on not-found is needed.
- **Kysely**: Write manual `up`/`down` migration files in `src/database/migrations/`. Use `kysely-codegen` to regenerate types after schema changes. For IAM auth, install `@aws-sdk/rds-signer` and use the IAM variant constructor — no query code changes needed.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use `MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties` — no schema or query code changes needed.
