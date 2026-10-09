<!-- ref: add/database/typescript/nestjs-mongoose-auth.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Mongoose (MongoDB), auth stubs from templatecentral:add (auth) present (`src/modules/auth/auth.service.ts` exists). Loaded alongside nestjs-mongoose.md (C2 DatabaseModule must exist). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Completing Auth Integration

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

**Step A — Create `src/modules/auth/schemas/user.schema.ts`**

> If the C4 example `src/modules/user/schemas/user.schema.ts` exists, add `hashedPassword` there and import it instead — two `User` schemas registered on one connection collide (`OverwriteModelError`).

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

  // `select: false` keeps the hash out of every query result by default — without it
  // any `findOne`/`find` that serializes a user document leaks the password hash.
  // Opt back in explicitly with `.select('+hashedPassword')` where it is actually needed.
  @Prop({ required: true, select: false })
  hashedPassword: string;
}

export const UserSchema = SchemaFactory.createForClass(User);
```

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';
import type { LoginDto, RegisterDto } from './auth.dto';

// Verified on the miss path so an unknown email costs the same as a wrong
// password — without it, response timing leaks which accounts exist. Hashed at
// startup with the same defaults as real passwords so the cost matches exactly.
const DUMMY_HASH = argon2.hash(randomUUID());

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.userModel.findOne({ email: dto.email }).exec();
    if (existing) throw new ConflictException('Email already registered.');

    // argon2id by default
    const hashedPassword = await argon2.hash(dto.password);
    const user = await this.userModel.create({
      email: dto.email,
      name: dto.name,
      hashedPassword,
    });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    // `hashedPassword` is `select: false` on the schema — opt in only here.
    const user = await this.userModel
      .findOne({ email: dto.email })
      .select('+hashedPassword')
      .exec();
    const passwordOk = await argon2.verify(
      user?.hashedPassword ?? (await DUMMY_HASH),
      dto.password,
    );
    if (!user || !passwordOk) {
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
      signOptions: { algorithm: 'HS256', expiresIn: appConfig.JWT_EXPIRES_IN_SECONDS },
    }),
    MongooseModule.forFeature([{ name: User.name, schema: UserSchema }]),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

Then run the **After Writing Code** steps of `nestjs-mongoose.md` (build, then review).
