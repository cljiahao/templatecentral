<!-- ref: add/database/typescript/nestjs-mongoose.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Mongoose (MongoDB)

AWS IAM auth and auth-stub completion live in sibling add-ons (`nestjs-mongoose-iam.md`, `nestjs-mongoose-auth.md`) that the router loads alongside this guide only when needed.

#### C1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

#### C2. Create DatabaseModule

**`src/database/database.module.ts`** (uses `serviceConfig` from `src/config/env.config.ts` — external service connections belong in `serviceConfig`, not `appConfig`):

```typescript
import { Global, Module, type OnModuleInit } from '@nestjs/common';
import { InjectConnection, MongooseModule } from '@nestjs/mongoose';
import { type Connection } from 'mongoose';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    MongooseModule.forRoot(serviceConfig.MONGODB_URL),
  ],
})
export class DatabaseModule implements OnModuleInit {
  constructor(@InjectConnection() private readonly connection: Connection) {}

  // Mongoose builds schema indexes in the background: on a fresh database, inserts
  // made right after boot land before the unique index exists and duplicates get in.
  // Awaiting init() holds the boot until every forFeature model's indexes are built
  // (and fails it loudly if existing duplicates block a unique index).
  async onModuleInit() {
    await Promise.all(Object.values(this.connection.models).map((model) => model.init()));
  }
}
```

Add `MONGODB_URL` to `envSchema` in `src/config/env.config.ts` — validated at import time, so boot fails loudly if it's missing instead of surfacing as a runtime `undefined`:

```typescript
const envSchema = z.object({
  // ... existing fields ...
  MONGODB_URL: z.string().min(1),
});
```

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_URL: env.MONGODB_URL,
};
```

> **Alternative**: If the project uses `@nestjs/config` (`pnpm add @nestjs/config`), use `forRootAsync` with `ConfigService` instead of direct `serviceConfig` imports.

#### C3. Register in AppModule

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

#### C4. Create a Schema

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

#### C5. Register Schema in Feature Module

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

#### C6. Usage

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

#### C7. Configure Environment

Add to `.env` and `.env.example`:

```env
MONGODB_URL=mongodb://localhost:27017/mydb
```

#### C8. Keep Tests Runnable Without a Database

`env.config.ts` now throws at import without `MONGODB_URL`, and Vitest does not load `.env`. Add it to the `test.env` object in **both** `vitest.config.ts` and `vitest.config.e2e.ts` (create the object if `add (auth)` has not):

```typescript
    // `test.env` overwrites the shell/CI value, so fall back only when none is set.
    env: { MONGODB_URL: process.env.MONGODB_URL ?? 'mongodb://127.0.0.1:1/test' },
```

`MongooseModule.forRoot` connects (and retries) during boot, so every e2e suite that boots `AppModule` without MongoDB swaps `DatabaseModule` for an empty module and stubs each `forFeature` model it would otherwise resolve:

```typescript
import { Module } from '@nestjs/common';
import { getModelToken } from '@nestjs/mongoose';
import { DatabaseModule } from '../src/database/database.module';
import { User } from '../src/modules/auth/schemas/user.schema';

@Module({})
class NoDatabaseModule {}

    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] })
      .overrideModule(DatabaseModule)
      .useModule(NoDatabaseModule)
      // One override per MongooseModule.forFeature model in the app.
      .overrideProvider(getModelToken(User.name))
      .useValue({})
      .compile();
```

Suites that exercise real queries boot `AppModule` without these overrides against a disposable MongoDB (CI service container) whose `MONGODB_URL` is set in the job env — the `??` fallback above keeps it. Vitest runs files in parallel, so give each such file its own database name (or run them with `--no-file-parallelism`); one file's `dropDatabase()` also drops the unique index another file relies on.

#### C9. Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
```

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use the IAM `DatabaseModule` from `nestjs-mongoose-iam.md` (`MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties`) — no schema or query code changes needed.
- **Auth integration** — if `templatecentral:add` (auth) ran first, `nestjs-mongoose-auth.md` replaces its 501 stubs; it is loaded alongside this guide, not from it.

---

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards