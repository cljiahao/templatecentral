# templateCentral Audit 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate agent-invention risk in nextjs-scaffold by converting 6 [generate] files to verbatim, and close the NestJS auth completion gap in nestjs-add-database.

**Architecture:** Task 1 makes surgical text replacements in `skills/nextjs-scaffold/SKILL.md` — 6 annotation changes in the directory tree + 6 new verbatim blocks appended to Part C. Task 2 appends a "Completing Auth Integration" section to `skills/nestjs-add-database/SKILL.md` covering Drizzle, Kysely, and Mongoose paths. Both tasks are fully independent and touch different files.

**Tech Stack:** Markdown SKILL.md files only — no runnable code. Verification is via `grep` commands.

---

### Task 1: nextjs-scaffold — convert 6 [generate] entries to verbatim

**Goal:** Replace 6 `[generate — ...]` tree annotations with `[verbatim — Part C]` and append the exact file content as new Part C blocks.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md`

**Acceptance Criteria:**
- [ ] `src/app/globals.css` annotation reads `[verbatim — Part C]`
- [ ] `src/app/(public)/layout.tsx` annotation reads `[verbatim — Part C]`
- [ ] `src/app/(public)/page.tsx` annotation reads `[verbatim — Part C, update branding in Step 2]`
- [ ] `src/components/layout/navbar.tsx` annotation reads `[verbatim — Part C, update branding in Step 2]`
- [ ] `src/components/layout/site-footer.tsx` annotation reads `[verbatim — Part C, update branding in Step 2]`
- [ ] `test/api/health.test.ts` annotation reads `[verbatim — Part C]`
- [ ] Part C contains verbatim blocks for all 6 files
- [ ] `grep '[generate' skills/nextjs-scaffold/SKILL.md | grep -E 'globals|public.*layout|public.*page|navbar|site-footer|health.test'` → 0 matches

**Verify:** `grep '\[generate' skills/nextjs-scaffold/SKILL.md | grep -cE 'globals\.css|public.*layout|public.*page|navbar\.tsx|site-footer|health\.test'` → `0`

**Steps:**

- [ ] **Step 1: Update the 6 tree annotations**

Read `skills/nextjs-scaffold/SKILL.md` first. Then make these 6 exact replacements using the Edit tool:

**Replace 1** — globals.css:
```
Old: │   ├── globals.css                 [generate — Tailwind 4 directives + CSS vars + animate-float keyframe]
New: │   ├── globals.css                 [verbatim — Part C]
```

**Replace 2** — (public)/layout.tsx:
```
Old: │   │   ├── layout.tsx              [generate — public layout with Navbar + Footer]
New: │   │   ├── layout.tsx              [verbatim — Part C]
```

**Replace 3** — (public)/page.tsx:
```
Old: │   │   └── page.tsx                [generate — landing page using widgets]
New: │   │   └── page.tsx                [verbatim — Part C, update branding in Step 2]
```

**Replace 4** — navbar.tsx:
```
Old: │   │   ├── navbar.tsx              [generate — uses BrandLogo, BrandText, LinkList, ThemeToggleButton]
New: │   │   ├── navbar.tsx              [verbatim — Part C, update branding in Step 2]
```

**Replace 5** — site-footer.tsx:
```
Old: │   │   ├── site-footer.tsx         [generate — simple footer with credit text]
New: │   │   ├── site-footer.tsx         [verbatim — Part C, update branding in Step 2]
```

**Replace 6** — health.test.ts:
```
Old: │       └── health.test.ts          [generate — tests GET /api and GET /api/health]
New: │       └── health.test.ts          [verbatim — Part C]
```

- [ ] **Step 2: Verify annotation replacements**

Run: `grep '\[generate' skills/nextjs-scaffold/SKILL.md | grep -E 'globals\.css|public.*layout|public.*page|navbar\.tsx|site-footer|health\.test'`

Expected: no output (0 matches). If any match appears, fix it before continuing.

- [ ] **Step 3: Append 6 verbatim blocks to Part C**

The current last block in Part C ends at the closing ` ``` ` of `src/app/dashboard/(overview)/page.tsx`, just before the `---` separator that precedes `## Scaffold Steps`. Insert the following content between that closing ` ``` ` and the `---`.

Find this anchor in the file (it is the unique end of Part C):
```
    </div>
  );
}
```

immediately followed by the closing triple-backtick and then the `---`. Use the Edit tool to replace the closing of the dashboard page block with the same closing block PLUS the 6 new verbatim sections:

The exact text to find (unique anchor — the last ~5 lines of the dashboard page block + separator):
```
      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```

Replace it with the same content PLUS the new sections appended before the `---`:

```
      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```

Then append the following new verbatim blocks as a new Edit, inserting BEFORE the `---` that precedes `## Scaffold Steps`. The anchor to find is:

```
}
```

followed immediately by:

```

---

## Scaffold Steps
```

Replace with:

````markdown
}
```

### `src/app/globals.css`

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

### `src/app/(public)/layout.tsx`

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

### `src/app/(public)/page.tsx`

> Update brand text (`template`/`Central` spans and the description paragraph) in Step 2.

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

### `src/components/layout/navbar.tsx`

> Update the two brand `<span>` elements and the Dashboard button text in Step 2.

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

### `src/components/layout/site-footer.tsx`

> Update `creditText` default in Step 2.

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

### `test/api/health.test.ts`

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

## Scaffold Steps
````

**IMPORTANT:** The above is the replacement text for the Edit tool — it replaces the `---\n\n## Scaffold Steps` separator + heading with the 6 new verbatim blocks followed by the restored `---\n\n## Scaffold Steps`. Use Edit with `old_string` = the exact anchor text and `new_string` = the full replacement above.

The exact `old_string` to match (unique in the file):
```
---

## Scaffold Steps
```

The `new_string` starts with the 6 new verbatim section blocks and ends with `---\n\n## Scaffold Steps`.

- [ ] **Step 4: Verify all 6 verbatim blocks are present**

```bash
grep -c '### `src/app/globals.css`' skills/nextjs-scaffold/SKILL.md
grep -c '### `src/app/(public)/layout.tsx`' skills/nextjs-scaffold/SKILL.md
grep -c '### `src/app/(public)/page.tsx`' skills/nextjs-scaffold/SKILL.md
grep -c '### `src/components/layout/navbar.tsx`' skills/nextjs-scaffold/SKILL.md
grep -c '### `src/components/layout/site-footer.tsx`' skills/nextjs-scaffold/SKILL.md
grep -c '### `test/api/health.test.ts`' skills/nextjs-scaffold/SKILL.md
```

Each command must output `1`.

- [ ] **Step 5: Verify no rogue [generate] annotations remain for these 6 files**

```bash
grep '\[generate' skills/nextjs-scaffold/SKILL.md | grep -E 'globals\.css|public.*layout|public.*page|navbar\.tsx|site-footer|health\.test'
```

Expected: no output. If any match appears, the annotation replacement from Step 1 was incomplete — fix it.

- [ ] **Step 6: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "feat(nextjs-scaffold): convert 6 [generate] layout/test files to verbatim

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

```json:metadata
{"files": ["skills/nextjs-scaffold/SKILL.md"], "verifyCommand": "grep '\\[generate' skills/nextjs-scaffold/SKILL.md | grep -cE 'globals\\.css|public.*layout|public.*page|navbar\\.tsx|site-footer|health\\.test'", "acceptanceCriteria": ["globals.css annotation is [verbatim — Part C]", "(public)/layout.tsx annotation is [verbatim — Part C]", "(public)/page.tsx annotation is [verbatim — Part C, update branding in Step 2]", "navbar.tsx annotation is [verbatim — Part C, update branding in Step 2]", "site-footer.tsx annotation is [verbatim — Part C, update branding in Step 2]", "health.test.ts annotation is [verbatim — Part C]", "Part C contains verbatim blocks for all 6 files", "verify command returns 0"]}
```

---

### Task 2: nestjs-add-database — add Completing Auth Integration section

**Goal:** Append a "Completing Auth Integration" section to `skills/nestjs-add-database/SKILL.md` covering Drizzle, Kysely, and Mongoose — the same pattern used in `skills/fastapi-add-database/SKILL.md`.

**Files:**
- Modify: `skills/nestjs-add-database/SKILL.md`

**Acceptance Criteria:**
- [ ] `grep 'Completing Auth Integration' skills/nestjs-add-database/SKILL.md` → 1 match
- [ ] Section has conditional notice (only apply if `nestjs-add-auth` was run first)
- [ ] Drizzle path: schema update + AuthService replacement + AuthModule note (3 steps)
- [ ] Kysely path: types + migration + AuthService replacement + AuthModule note (3 steps)
- [ ] Mongoose path: schema creation + AuthService replacement + AuthModule update (3 steps)
- [ ] No `UnauthorizedException('Database integration required')` stub in any AuthService block
- [ ] All 3 `login()` methods return `{ accessToken, tokenType: 'bearer' as const }`

**Verify:** `grep 'Completing Auth Integration' skills/nestjs-add-database/SKILL.md | wc -l` → `1`

**Steps:**

- [ ] **Step 1: Read the end of the file to confirm the insertion point**

Read `skills/nestjs-add-database/SKILL.md` — the file ends with the `## Rules` section. The new section goes at the very end of the file (after the last Rules bullet).

- [ ] **Step 2: Append the Completing Auth Integration section**

Use Edit to append the following to the end of `skills/nestjs-add-database/SKILL.md`. The `old_string` is the final Rules bullet (unique anchor at the end of file):

`old_string`:
```
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use `MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties` — no schema or query code changes needed.
```

`new_string` (the same bullet plus the new section appended):
```markdown
- **Mongoose**: Schemas live inside feature modules at `src/modules/<feature>/schemas/`. Register schemas with `MongooseModule.forFeature()` in the feature module — not globally. For IAM auth, install `@aws-sdk/credential-providers` and use `MongooseModule.forRoot` with `AWS_CREDENTIAL_PROVIDER` in `authMechanismProperties` — no schema or query code changes needed.

---

## Completing Auth Integration

> **Only apply this section if `nestjs-add-auth` was run before this skill.**
> It replaces the in-memory stubs with real database-backed implementations.
> Follow only the sub-section that matches your chosen database.

### Drizzle path

**Step A — Add `hashedPassword` to `src/database/schema.ts`**

Add the `hashedPassword` column to the `users` table and regenerate + apply the migration:

```typescript
import { pgTable, text, timestamp } from 'drizzle-orm/pg-core';

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
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`DrizzleService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`. Confirm `DatabaseModule` is registered in `AppModule` (the scaffold handles this).

---

### Kysely path

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

**If `001_initial.ts` was already applied** (users table exists in the DB), create `src/database/migrations/002_add_auth.ts`:

```typescript
import { type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .alterTable('users')
    .addColumn('hashed_password', 'text', (col) => col.notNull().defaultTo(''))
    .execute();
  // Remove the temporary default — hashed_password must not have a default in production
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
    return {
      accessToken: this.jwtService.sign({ sub: user.id, email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
```

**Step C — `src/modules/auth/auth.module.ts` requires no changes**

`KyselyService` is exported by the `@Global()` `DatabaseModule` and is injectable throughout the application without listing it in `AuthModule.providers`.

---

### Mongoose path

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
    const user = await this.userModel.create({
      email: dto.email,
      name: dto.name,
      hashedPassword,
    });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    const user = await this.userModel.findOne({ email: dto.email }).exec();
    if (!user || !(await bcrypt.compare(dto.password, user.hashedPassword))) {
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
```

- [ ] **Step 3: Verify the section was appended correctly**

```bash
grep 'Completing Auth Integration' skills/nestjs-add-database/SKILL.md | wc -l
```
Expected: `1`

```bash
grep -c 'Database integration required' skills/nestjs-add-database/SKILL.md
```
Expected: `0` — the stub error message must not appear in any of the three AuthService replacements.

```bash
grep "tokenType: 'bearer'" skills/nestjs-add-database/SKILL.md | wc -l
```
Expected: `3` — one per DB option.

- [ ] **Step 4: Commit**

```bash
git add skills/nestjs-add-database/SKILL.md
git commit -m "feat(nestjs-add-database): add Completing Auth Integration section for Drizzle, Kysely, Mongoose

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

```json:metadata
{"files": ["skills/nestjs-add-database/SKILL.md"], "verifyCommand": "grep 'Completing Auth Integration' skills/nestjs-add-database/SKILL.md | wc -l", "acceptanceCriteria": ["Completing Auth Integration section exists (1 match)", "Conditional notice present", "Drizzle path has schema + AuthService + AuthModule note (3 steps)", "Kysely path has types + migration + AuthService + AuthModule note (3 steps)", "Mongoose path has schema + AuthService + AuthModule update (3 steps)", "No 'Database integration required' stub text", "3 occurrences of tokenType: 'bearer'"]}
```
