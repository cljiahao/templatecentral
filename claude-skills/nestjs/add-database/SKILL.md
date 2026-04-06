---
name: add-database
description: Use when the user wants to add a database to a NestJS project — Prisma for SQL databases (PostgreSQL, MySQL, SQLite) or Mongoose for MongoDB.
---

# Add Database to NestJS

Add a database to a NestJS project scaffolded from templateCentral.

> **Opt-in only**: Do not add database support unless the user explicitly requests it. The template has an empty `src/database/` directory ready for database modules.

## Choose Your Database

Ask the user which database they need, then follow the corresponding section:

| Database type | ORM/ODM | Section |
|--------------|---------|---------|
| PostgreSQL, MySQL, SQLite | Prisma (ORM) | [Section A](#section-a-prisma-sql) |
| MongoDB | Mongoose (ODM) | [Section B](#section-b-mongoose-mongodb) |

If the user says "database" without specifying, ask: *"Do you need a SQL database (PostgreSQL, MySQL, SQLite) or MongoDB?"*

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

### A7. Generate Client & Migrate

```bash
npx prisma generate
npx prisma migrate dev --name init
```

### A8. Usage

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

### A9. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass. Skip to [Rules](#rules).

---

## Section B: Mongoose (MongoDB)

### B1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

### B2. Create DatabaseModule

**`src/database/database.module.ts`** (uses `appConfig` from `src/config/env.config.ts`, which is the template's config pattern):

```typescript
import { Global, Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { appConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    MongooseModule.forRoot(appConfig.MONGODB_URL),
  ],
})
export class DatabaseModule {}
```

Add `MONGODB_URL` to `appConfig` in `src/config/env.config.ts`:

```typescript
export const appConfig = {
  // ... existing fields ...
  MONGODB_URL: process.env.MONGODB_URL!,
};
```

> **Alternative**: If the project uses `@nestjs/config` (`pnpm add @nestjs/config`), use `forRootAsync` with `ConfigService` instead of direct `appConfig` imports.

### B3. Register in AppModule

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

### B4. Create a Schema

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

  @Prop({ required: true })
  hashedPassword: string;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

### B5. Register Schema in Feature Module

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

### B6. Usage

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

### B7. Configure Environment

Add to `.env` and `.env.example`:

```env
MONGODB_URL=mongodb://localhost:27017/mydb
```

### B8. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `PrismaService` or `DatabaseModule` in `src/database/`.
- **Prisma**: Always use `prisma migrate dev` for schema changes. Run `prisma generate` after every schema change. Create `<feature>.repository.ts` in feature modules for complex query logic.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally.
- Keep `DATABASE_URL` / `MONGODB_URL` in `.env` — NEVER hardcode production credentials.
- Always add `.env.example` placeholders so other developers know what to configure.
