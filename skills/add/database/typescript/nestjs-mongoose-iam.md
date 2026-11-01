<!-- ref: add/database/typescript/nestjs-mongoose-iam.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB), compliance = AWS IAM (Amazon DocumentDB or MongoDB Atlas with AWS IAM). Loaded alongside nestjs-mongoose.md — overrides its C2 DatabaseModule and env fields and its C7 env. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Mongoose — IAM Auth Variant

> **Add-on to `nestjs-mongoose.md`** (the router loads both). Work through that guide's C1–C9, but use the `DatabaseModule` below instead of its standard C2 module, and the IAM env fields below instead of its `MONGODB_URL` (C2 `envSchema`/`serviceConfig`, C7 `.env`, and C8 `test.env` — `MONGODB_HOST: process.env.MONGODB_HOST ?? '127.0.0.1', MONGODB_DB_NAME: process.env.MONGODB_DB_NAME ?? 'test'`); then run its **After Writing Code** steps.

For AWS IAM auth (DocumentDB, Atlas), also install:

```bash
pnpm add @aws-sdk/credential-providers
```

Replace the `DatabaseModule` with:

```typescript
import { Global, Module, type OnModuleInit } from '@nestjs/common';
import { InjectConnection, MongooseModule } from '@nestjs/mongoose';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import { type Connection } from 'mongoose';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
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
export class DatabaseModule implements OnModuleInit {
  constructor(@InjectConnection() private readonly connection: Connection) {}

  // Same as the standard C2 module: hold the boot until schema indexes (the unique
  // email index) exist, so early inserts cannot slip duplicates past them.
  async onModuleInit() {
    await Promise.all(Object.values(this.connection.models).map((model) => model.init()));
  }
}
```

Add IAM fields to `envSchema` in `src/config/env.config.ts` — validated at import, so boot fails when a field is missing:

```typescript
const envSchema = z.object({
  // ... existing fields ...
  MONGODB_HOST: z.string().min(1),
  MONGODB_DB_NAME: z.string().min(1),
});
```

```typescript
export const serviceConfig = {
  // ... existing fields ...
  MONGODB_HOST: env.MONGODB_HOST,
  MONGODB_DB_NAME: env.MONGODB_DB_NAME,
};
```

IAM environment variables (add to `.env` and `.env.example`):

```env
MONGODB_HOST=your-cluster.region.docdb.amazonaws.com
MONGODB_DB_NAME=mydb
```

> With `AWS_CREDENTIAL_PROVIDER` the driver resolves credentials (instance role, env vars or SSO profile via `@aws-sdk/credential-providers`) and rotates tokens on reconnect. For Atlas, use `mongodb+srv://` without the port and `&tls=true`.
