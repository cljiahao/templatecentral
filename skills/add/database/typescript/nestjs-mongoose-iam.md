<!-- ref: add/database/typescript/nestjs-mongoose-iam.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB), compliance = AWS IAM (Amazon DocumentDB or MongoDB Atlas with AWS IAM). Loaded alongside nestjs-mongoose.md — overrides its C2 DatabaseModule and env fields and its C7 env. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS + Mongoose — IAM Auth Variant

> **Add-on to `nestjs-mongoose.md`** (the router loads both). Work through that guide's C1–C9, but use the `DatabaseModule` below instead of its standard C2 module, and the IAM env fields below instead of its `MONGODB_URL` (C2 `envSchema`/`serviceConfig`, C7 `.env`, and C8 `test.env` — `MONGODB_HOST: '127.0.0.1', MONGODB_DB_NAME: 'test'`); then run its **After Writing Code** steps.

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

Add IAM fields to `envSchema` in `src/config/env.config.ts` — validated at import time, so boot fails loudly if a required field is missing instead of surfacing as a runtime `undefined`:

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

> The MongoDB driver's `AWS_CREDENTIAL_PROVIDER` delegates credential resolution to the driver itself, which handles automatic token rotation on reconnect. The `@aws-sdk/credential-providers` package resolves IAM credentials from the EC2/ECS instance role, environment variables, or SSO profile. For MongoDB Atlas, replace `mongodb://` with `mongodb+srv://` and remove the port and `&tls=true`.
