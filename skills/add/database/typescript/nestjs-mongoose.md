<!-- ref: add/database/typescript/nestjs-mongoose.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB). Do not invoke this file directly. -->
## NestJS + Mongoose (MongoDB)

#### C1. Install Dependencies

```bash
pnpm add @nestjs/mongoose mongoose
```

#### C2. Create DatabaseModule

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

##### IAM Auth Variant

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

#### C8. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

---

## Rules

- **Opt-in only** — the base template has no real database connection. Only add when explicitly requested.
- **Default to standard (password) auth** — only install AWS SDK packages and use IAM auth variants when the user explicitly requires AWS IAM authentication for compliance.
- `DatabaseModule` must be `@Global()` so database access is available everywhere without re-importing.
- Place `DatabaseModule` in `src/database/`.
- NEVER hardcode credentials — keep connection config in `.env` and document in `.env.example`.
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use `MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties` — no schema or query code changes needed.

---

## Completing Auth Integration

> **Only apply this section if `nestjs-add-auth` was run before this skill.** It replaces the in-memory stubs with real database-backed implementations.

**Step A — Create `src/modules/auth/schemas/user.schema.ts`**

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

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import * as argon2 from 'argon2';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.userModel.findOne({ email: dto.email }).exec();
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
    const user = await this.userModel.create({
      email: dto.email,
      name: dto.name,
      hashedPassword,
    });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    const user = await this.userModel.findOne({ email: dto.email }).exec();
    if (!user || !(await argon2.verify(user.hashedPassword, dto.password))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user._id.toString(), email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — Update `src/modules/auth/auth.module.ts`**

Add `MongooseModule.forFeature` to `imports` and register the `User` schema:

```typescript
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { MongooseModule } from '@nestjs/mongoose';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { User, UserSchema } from './schemas/user.schema';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      signOptions: { expiresIn: appConfig.JWT_EXPIRES_IN },
    }),
    MongooseModule.forFeature([{ name: User.name, schema: UserSchema }]),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

---

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards