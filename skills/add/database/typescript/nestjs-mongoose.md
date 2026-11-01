<!-- ref: add/database/typescript/nestjs-mongoose.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Mongoose (MongoDB)

IAM auth and auth-stub completion are sibling add-ons (`nestjs-mongoose-iam.md`, `nestjs-mongoose-auth.md`).

#### C1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

#### C2. Create DatabaseModule

Run `TC_PART=leaf TC_LEAF=add/database/typescript/nestjs-mongoose bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/typescript/nestjs-mongoose/template/` (listed in `<skill-dir>/database/typescript/nestjs-mongoose/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/database/database.module.ts`** (uses `serviceConfig` from `src/config/env.config.ts` — external service connections belong in `serviceConfig`, not `appConfig`):

Copied verbatim from `<skill-dir>/database/typescript/nestjs-mongoose/template/src/database/database.module.ts` by the copy step; do not re-type it.

Add `MONGODB_URL` to `envSchema` in `src/config/env.config.ts` — validated at import, so boot fails when it is missing:

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

Vitest does not load `.env`, and `env.config.ts` now throws without `MONGODB_URL` — add it to `test.env` in **both** `vitest.config.ts` and `vitest.config.e2e.ts` (create the object if needed):

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

- **Opt-in only** — add a database only on request.
- **Default to password auth** — use AWS SDK packages and IAM variants only when the user requires AWS IAM.
- `DatabaseModule` is `@Global()` so modules need not re-import it.
- Place `DatabaseModule` in `src/database/`.
- Do not hardcode credentials; keep connection config in `.env` and document in `.env.example`.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use the IAM `DatabaseModule` from `nestjs-mongoose-iam.md` (`MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties`); schema and query code are unchanged.
- **Auth integration** — if `templatecentral:add` (auth) ran first, `nestjs-mongoose-auth.md` replaces its 501 stubs; it is loaded alongside this guide, not from it.

---

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.