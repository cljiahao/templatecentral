<!-- ref: add/database/typescript/nestjs-kysely-auth.md
     loaded-by: add/database/typescript.md → add/SKILL.md
     prereq: Stack = NestJS, ORM = Kysely, auth stubs from templatecentral:add (auth) present (`src/modules/auth/auth.service.ts` exists). Loaded alongside nestjs-kysely.md (B3 types + B6 migrations must exist). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Completing Auth Integration

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

**Step A — Update `src/database/types.ts` and add migration**

Add `hashed_password` to `UsersTable`:

```typescript
import type { Generated, Insertable, Selectable, Updateable } from 'kysely';

export interface Database {
  users: UsersTable;
}

export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  hashed_password: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}

export type User = Selectable<UsersTable>;
export type NewUser = Insertable<UsersTable>;
export type UserUpdate = Updateable<UsersTable>;
```

**If `001_initial.ts` has not been applied yet:** add `hashed_password text NOT NULL` directly to the `createTable` call in `001_initial.ts`.

**If `001_initial.ts` was already applied** (users table exists in the DB), create `src/database/migrations/NNN_add_auth.ts`, where `NNN` is the next unused number in that directory (e.g. `002` if only `001_initial.ts` exists, `003` if `002_projects.ts` is already there) — Kysely runs migrations in name order and, by default, fails when a new file sorts before one already executed, so never reuse or back-fill a number:

```typescript
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .alterTable('users')
    .addColumn('hashed_password', 'text', (col) => col.notNull().defaultTo(''))
    .execute();
  // Remove the temporary default — hashed_password must not have a default in production
  await sql`ALTER TABLE users ALTER COLUMN hashed_password DROP DEFAULT`.execute(db);
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.alterTable('users').dropColumn('hashed_password').execute();
}
```

Run: `pnpm migrate`

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';

import { KyselyService } from '../../database/kysely.service';
import type { LoginDto, RegisterDto } from './auth.dto';

// Verified on the miss path so an unknown email costs the same as a wrong
// password — without it, response timing leaks which accounts exist. Hashed at
// startup with the same defaults as real passwords so the cost matches exactly.
const DUMMY_HASH = argon2.hash(randomUUID());

const PG_UNIQUE_VIOLATION = '23505';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly db: KyselyService,
  ) {}

  async register(dto: RegisterDto) {
    // argon2id by default
    const hashedPassword = await argon2.hash(dto.password);
    try {
      return await this.db
        .insertInto('users')
        .values({ email: dto.email, name: dto.name, hashed_password: hashedPassword })
        .returning(['id', 'email', 'name'])
        .executeTakeFirstOrThrow();
    } catch (error) {
      // The unique index, not a SELECT-then-INSERT pre-check, is race-free under concurrent sign-ups.
      if ((error as { code?: string }).code === PG_UNIQUE_VIOLATION) {
        throw new ConflictException('Email already registered.');
      }
      throw error;
    }
  }

  async login(dto: LoginDto) {
    const user = await this.db
      .selectFrom('users')
      .selectAll()
      .where('email', '=', dto.email)
      .executeTakeFirst();
    const passwordOk = await argon2.verify(
      // `||`, not `??`: rows backfilled by the NNN_add_auth migration hold '' — argon2.verify throws on it.
      user?.hashed_password || (await DUMMY_HASH),
      dto.password,
    );
    if (!user || !passwordOk) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`KyselyService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`.

Then run the **After Writing Code** steps of `nestjs-kysely.md` (build, then review).
