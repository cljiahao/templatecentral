# templateCentral Audit 2 — Design Spec

**Date:** 2026-04-29
**Scope:** Two targeted fixes following a second clean-eyes audit. Previous session fixed FastAPI async/def, FastAPI auth completion, Next.js dashboard verbatim, and nextjs-add-auth dashboard conditional.

---

## Problem Summary

### Gap 1 — nextjs-scaffold: 6 files are [generate] but should be verbatim

These files all existed as exact source files in the deleted `templates/nextjs/` directory but are currently left for agents to invent from brief annotations. Agents cannot reliably reproduce 190 lines of Tailwind 4 CSS tokens, a 53-line navbar with conditional routing logic, or a specific Vitest test structure — they will produce plausible-looking but incorrect output.

Files affected:

| File | Lines | Risk |
|---|---|---|
| `src/app/globals.css` | 190 | Critical — full Tailwind 4 theme token map, custom utilities, dark mode, keyframes |
| `src/components/layout/navbar.tsx` | 53 | High — widget composition, dashboard/public conditional styling, routing |
| `src/components/layout/site-footer.tsx` | 28 | Medium — specific props, LinkItem imports |
| `src/app/(public)/layout.tsx` | 15 | Medium — specific component imports |
| `src/app/(public)/page.tsx` | 14 | Medium — brand gradient structure |
| `test/api/health.test.ts` | 31 | Critical — must pass `pnpm test` verification gate; imports specific route handlers |

Files left as `[generate]` (well-specified, low risk):
- `.husky/pre-commit`, `.husky/pre-push` — exact commands in annotation
- `eslint.config.mjs`, `prettier.config.mjs` — config pattern is stable
- `public/image_assets/*.svg` — placeholder SVGs
- `src/lib/constants/routes.ts` — fully specified in annotation

### Gap 2 — nestjs-add-database: no "Completing Auth Integration" section

`nestjs-add-auth` creates an `AuthService` where `register()` stores nothing and `login()` throws `UnauthorizedException("Database integration required. Run nestjs-add-database to complete auth.")`. The database skill has no follow-up section. Users who run both skills in order have an app that returns 401 on every login attempt.

This is the identical pattern to the FastAPI gap fixed in the previous session.

---

## Architecture

### Gap 1 — Verbatim recovery strategy

Content is recovered verbatim from git history (commit `d8a3be2`, the last commit before `templates/` was deleted in `591ce19`). Files containing "templateCentral" brand text use the placeholder from the original template — Step 2 of nextjs-scaffold already instructs agents to replace brand text in navbar, page, and footer. Tree annotations change from `[generate — ...]` to `[verbatim — Part C]` (with "update branding in Step 2" note where applicable). New verbatim blocks are appended to Part C in file order matching the directory tree.

### Gap 2 — NestJS auth completion ownership

| Layer | Owner |
|---|---|
| `AuthController` | `nestjs-add-auth` — no changes needed |
| `JwtStrategy` | `nestjs-add-auth` — no changes needed |
| `AuthService` (stubs) | `nestjs-add-auth` — replaced by completion section |
| User schema / migration | `nestjs-add-database` completion section |
| `AuthService` (real) | `nestjs-add-database` completion section |
| `AuthModule` (updated providers) | `nestjs-add-database` completion section |

JWT payload shape (`{ sub: userId, email }`) and `JwtStrategy.validate()` are unchanged across all three DB options.

---

## Section 1 — nextjs-scaffold Verbatim Conversions

**File:** `skills/nextjs-scaffold/SKILL.md`

### 1.1 Tree annotation changes

In the Part A directory tree, replace the six `[generate — ...]` annotations:

```
src/app/globals.css                         [verbatim — Part C]
src/app/(public)/layout.tsx                 [verbatim — Part C]
src/app/(public)/page.tsx                   [verbatim — Part C, update branding in Step 2]
src/components/layout/navbar.tsx            [verbatim — Part C, update branding in Step 2]
src/components/layout/site-footer.tsx       [verbatim — Part C, update branding in Step 2]
test/api/health.test.ts                     [verbatim — Part C]
```

### 1.2 New Part C verbatim blocks

Append six blocks to Part C (after existing blocks, in directory-tree order):

**`src/app/globals.css`**
```css
@import 'tailwindcss';
@plugin '@tailwindcss/typography';
@import 'tw-animate-css';

@custom-variant dark (&:is(.dark *));

@theme inline {
  /* Fonts & radius */
  --font-sans: var(--font-lato);
  --font-mono: var(--font-geist-mono);
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);

  /* App colors */
  --color-black: var(--black);
  --color-white: var(--white);

  /* Surface */
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-popover: var(--popover);
  --color-popover-foreground: var(--popover-foreground);

  /* Actions */
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-primary-hover: var(--primary-hover);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-secondary-hover: var(--secondary-hover);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-accent-hover: var(--accent-hover);

  /* Utility */
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-destructive: var(--destructive);

  /* Form */
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);
}

:root {
  --black: #101010;
  --white: #f9f9f9;
  --radius: 0.625rem;

  --background: var(--white);
  --foreground: var(--black);
  --card: var(--white);
  --card-foreground: var(--black);
  --popover: var(--white);
  --popover-foreground: var(--black);

  --primary: var(--color-neutral-900);
  --primary-foreground: var(--white);
  --primary-hover: var(--color-neutral-800);
  --secondary: var(--color-neutral-100);
  --secondary-foreground: var(--color-neutral-900);
  --secondary-hover: var(--color-neutral-200);
  --accent: var(--color-neutral-100);
  --accent-foreground: var(--color-neutral-900);
  --accent-hover: var(--color-neutral-200);

  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --destructive: oklch(0.577 0.245 27.325);

  --border: var(--color-neutral-300);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
}

.dark {
  --background: var(--black);
  --foreground: var(--white);
  --card: var(--black);
  --card-foreground: var(--white);
  --popover: var(--black);
  --popover-foreground: var(--white);

  --primary: var(--white);
  --primary-foreground: var(--color-neutral-900);
  --primary-hover: var(--color-neutral-200);
  --secondary: var(--color-neutral-800);
  --secondary-foreground: var(--color-neutral-100);
  --secondary-hover: var(--color-neutral-700);
  --accent: var(--color-neutral-800);
  --accent-foreground: var(--color-neutral-100);
  --accent-hover: var(--color-neutral-700);

  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --destructive: oklch(0.704 0.191 22.216);

  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
}

@layer base {
  * {
    @apply border-border outline-ring/50;
  }
  html {
    scroll-behavior: smooth;
    @apply bg-background;
  }
  body {
    @apply bg-background text-foreground;
  }
  button:not(:disabled),
  [role='button']:not(:disabled) {
    cursor: pointer;
  }
}

@layer utilities {
  .hw-full { @apply h-full w-full; }
  .flex-between { @apply flex items-center justify-between; }
  .flex-center { @apply flex items-center justify-center; }
  .flex-start { @apply flex items-start justify-start; }
  .flex-end { @apply flex justify-end; }
  .max-w-site { @apply max-w-[1184px]; }
  .max-w-content { @apply max-w-[1000px]; }
  .bg-brand-gradient { @apply from-primary via-primary to-primary bg-linear-to-r; }
  .text-brand-gradient { @apply from-primary via-primary to-primary bg-linear-to-r bg-clip-text text-transparent; }
}

.no-scrollbar::-webkit-scrollbar { display: none; }
.no-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }

@keyframes float {
  0%, 100% { transform: translateY(0) rotate(0deg); }
  50% { transform: translateY(-15px) rotate(5deg); }
}
.animate-float { animation: float 10s ease-in-out infinite; }
```

**`src/app/(public)/layout.tsx`**
```tsx
import { Navbar, SiteFooter } from '@/components/layout';

export default function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex flex-1 flex-col">{children}</main>
      <SiteFooter />
    </div>
  );
}
```

**`src/app/(public)/page.tsx`** *(update brand text in Step 2)*
```tsx
export default function Home() {
  return (
    <div className="flex-center min-h-screen flex-col gap-6">
      <h1 className="text-4xl font-bold tracking-tight lg:text-6xl">
        <span className="text-brand-gradient">template</span>
        <span>Central</span>
      </h1>
      <p className="text-muted-foreground max-w-md text-center text-lg">
        A production-ready Next.js template with shadcn/ui, Tailwind CSS, and
        everything you need to build modern web applications.
      </p>
    </div>
  );
}
```

**`src/components/layout/navbar.tsx`** *(update brand text in Step 2)*
```tsx
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { LinkList, type LinkItem } from '@/components/widgets';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';

const defaultNavLinks: LinkItem[] = [];

export function Navbar() {
  const pathname = usePathname();
  const rootPath = `/${pathname.split('/')[1]}`;
  const isDashboard = rootPath === PAGE_ROUTES.DASHBOARD;

  return (
    <nav
      className={cn(
        isDashboard
          ? 'sticky top-0 z-50 w-full'
          : 'max-w-site fixed inset-x-0 top-0 z-50 mx-auto pt-10',
      )}
    >
      <div
        className={cn(
          'flex-between min-h-20 bg-white px-6 py-3 shadow-lg',
          isDashboard ? 'border-b' : 'rounded-2xl border',
        )}
      >
        <Link href={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          <span className="text-brand-gradient">template</span>
          <span>Central</span>
        </Link>

        <div className="flex items-center gap-4">
          {defaultNavLinks.length > 0 && (
            <LinkList links={defaultNavLinks} className="hover:text-primary transition-colors" />
          )}
          <Button
            asChild
            className="bg-primary hover:bg-primary-hover h-12 rounded-lg px-6 py-3 font-bold text-white"
          >
            <Link href={PAGE_ROUTES.DASHBOARD}>Dashboard</Link>
          </Button>
        </div>
      </div>
    </nav>
  );
}
```

**`src/components/layout/site-footer.tsx`** *(update credit text in Step 2)*
```tsx
import { LinkList, type LinkItem } from '@/components/widgets';

interface SiteFooterProps {
  creditText?: string;
  links?: LinkItem[];
}

const defaultLinks: LinkItem[] = [
  { label: 'Contact Us', href: '#' },
];

export function SiteFooter({
  creditText = 'Built with templateCentral',
  links = defaultLinks,
}: SiteFooterProps) {
  return (
    <footer className="w-full bg-black">
      <div className="flex-between px-6 py-6">
        <p className="text-sm text-white">{creditText}</p>
        <LinkList links={links} className="text-sm text-white" />
      </div>
    </footer>
  );
}
```

**`test/api/health.test.ts`**
```ts
import { describe, expect, it } from 'vitest';
import { NextRequest } from 'next/server';

import { GET as getRootHealth } from '@/app/api/route';
import { GET as getHealthPath } from '@/app/api/health/route';

function makeRequest(url: string): NextRequest {
  return new NextRequest(url);
}

describe('GET /api (root health)', () => {
  it('returns ok with 200', async () => {
    const response = await getRootHealth(makeRequest('http://localhost/api'));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

describe('GET /api/health (Docker / probe path)', () => {
  it('returns ok with 200', async () => {
    const response = await getHealthPath(makeRequest('http://localhost/api/health'));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});
```

---

## Section 2 — nestjs-add-database: Completing Auth Integration

**File:** `skills/nestjs-add-database/SKILL.md`

New optional section appended after all existing steps. Only applies when `nestjs-add-auth` was run first.

### 2.1 Section header and conditional notice

```
## Completing Auth Integration

> **Only apply this section if `nestjs-add-auth` was run before this skill.**
> It replaces the in-memory stubs with real database-backed implementations.
> Follow only the sub-section that matches your chosen database.
```

### 2.2 Drizzle path

**Step A — Add `hashedPassword` to schema**

In `src/database/schema.ts`, add `hashedPassword` to the `users` table:

```typescript
export const users = pgTable('users', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  email: text('email').notNull().unique(),
  name: text('name').notNull(),
  hashedPassword: text('hashed_password').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

Then generate and apply the migration:
```bash
pnpm db:generate
pnpm db:migrate
```

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { eq } from 'drizzle-orm';

import { DrizzleService } from '../../database/drizzle.service';
import { users } from '../../database/schema';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly drizzle: DrizzleService,
  ) {}

  async register(dto: RegisterDto) {
    const [existing] = await this.drizzle.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await bcrypt.hash(dto.password, 10);
    const [user] = await this.drizzle.db
      .insert(users)
      .values({ email: dto.email, name: dto.name, hashedPassword })
      .returning({ id: users.id, email: users.email, name: users.name });
    return user;
  }

  async login(dto: LoginDto) {
    const [user] = await this.drizzle.db
      .select()
      .from(users)
      .where(eq(users.email, dto.email))
      .limit(1);
    if (!user || !(await bcrypt.compare(dto.password, user.hashedPassword))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return { accessToken: this.jwtService.sign({ sub: user.id, email: user.email }), tokenType: 'bearer' as const };
  }
}
```

**Step C — Update `src/modules/auth/auth.module.ts`**

`DrizzleService` is globally exported by `DatabaseModule` (`@Global()`) so it is injectable without listing it in `AuthModule.providers`. No module-level change is required beyond confirming `DatabaseModule` is registered in `AppModule` (the scaffold handles this):

```typescript
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      signOptions: { expiresIn: appConfig.JWT_EXPIRES_IN },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

### 2.3 Kysely path

**Step A — Add `hashed_password` to types and migration**

In `src/database/types.ts`, add `hashed_password` to `UsersTable`:

```typescript
export interface UsersTable {
  id: Generated<string>;
  email: string;
  name: string;
  hashed_password: string;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}
```

**If `001_initial.ts` has not been applied yet:** add `hashed_password text NOT NULL` directly to the `createTable` call in `001_initial.ts`.

**If `001_initial.ts` was already applied** (users table exists): create `src/database/migrations/002_add_auth.ts`:

```typescript
import { type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .alterTable('users')
    .addColumn('hashed_password', 'text', (col) => col.notNull().defaultTo(''))
    .execute();
  // Remove the temporary default after adding the column
  await db.schema
    .alterTable('users')
    .alterColumn('hashed_password', (col) => col.dropDefault())
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.alterTable('users').dropColumn('hashed_password').execute();
}
```

Run: `pnpm db:migrate`

**Step B — Replace `src/modules/auth/auth.service.ts`**

```typescript
import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';

import { KyselyService } from '../../database/kysely.service';
import type { LoginDto, RegisterDto } from './auth.dto';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly db: KyselyService,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.db
      .selectFrom('users')
      .select('id')
      .where('email', '=', dto.email)
      .executeTakeFirst();
    if (existing) throw new ConflictException('Email already registered.');

    const hashedPassword = await bcrypt.hash(dto.password, 10);
    const user = await this.db
      .insertInto('users')
      .values({ email: dto.email, name: dto.name, hashed_password: hashedPassword })
      .returning(['id', 'email', 'name'])
      .executeTakeFirstOrThrow();
    return user;
  }

  async login(dto: LoginDto) {
    const user = await this.db
      .selectFrom('users')
      .selectAll()
      .where('email', '=', dto.email)
      .executeTakeFirst();
    if (!user || !(await bcrypt.compare(dto.password, user.hashed_password))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return { accessToken: this.jwtService.sign({ sub: user.id, email: user.email }), tokenType: 'bearer' as const };
  }
}
```

**Step C — Update `src/modules/auth/auth.module.ts`**

`KyselyService` is globally exported by `DatabaseModule` (`@Global()`) and injectable without listing it in `AuthModule.providers`:

```typescript
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      signOptions: { expiresIn: appConfig.JWT_EXPIRES_IN },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
```

### 2.4 Mongoose path

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
import * as bcrypt from 'bcrypt';
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

    const hashedPassword = await bcrypt.hash(dto.password, 10);
    const user = await this.userModel.create({ email: dto.email, name: dto.name, hashedPassword });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    const user = await this.userModel.findOne({ email: dto.email }).exec();
    if (!user || !(await bcrypt.compare(dto.password, user.hashedPassword))) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return { accessToken: this.jwtService.sign({ sub: user._id.toString(), email: user.email }), tokenType: 'bearer' as const };
  }
}
```

**Step C — Update `src/modules/auth/auth.module.ts`**

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

## Files Changed

| File | Change |
|---|---|
| `skills/nextjs-scaffold/SKILL.md` | 6× `[generate]` → `[verbatim — Part C]` in tree; 6 new verbatim blocks in Part C |
| `skills/nestjs-add-database/SKILL.md` | Append "Completing Auth Integration" section (Drizzle + Kysely + Mongoose, 3 steps each) |

No other files change.

---

## Out of Scope

- `.husky/`, `eslint.config.mjs`, `prettier.config.mjs`, SVGs, `routes.ts` in nextjs-scaffold — annotations are sufficient, agent-generation risk is low
- vite-react-scaffold — already 100% verbatim, no gaps found
- fastapi-scaffold, nestjs-scaffold — only appropriate [generate] entries (package.json, README.md)
- All shared-* skills — no TODOs, no gaps found
- AGENTS.md routing table — clean, no missing entries
- Rate limiting on auth endpoints — not in scope for this audit; no existing skill addresses it and adding it would be a new feature, not a fix
