# Stack Skills Accuracy Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 confirmed accuracy/security gaps: explicit cookie security attributes in nextjs-add-auth, and Prisma 6 not-found handling docs in both database skills.

**Architecture:** Three independent single-file edits. All tasks can run in parallel.

**Tech Stack:** Markdown skill files only.

**Spec:** `docs/superpowers/specs/2026-04-28-stack-skills-accuracy-design.md`

---

### Task 1: Add explicit cookie security attributes to nextjs-add-auth

**Goal:** Insert `advanced.defaultCookieAttributes` into the generated `betterAuth({})` config so cookie security posture is explicit and auditable.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md`

**Acceptance Criteria:**
- [ ] `betterAuth({})` config includes `advanced` block with `defaultCookieAttributes`
- [ ] `defaultCookieAttributes` sets `sameSite: 'lax'`, `httpOnly: true`, `secure: process.env.NODE_ENV === 'production'`
- [ ] Block is inserted after the `session` block and before `plugins: [nextCookies()]`
- [ ] No other lines changed

**Verify:**
```bash
grep -n "defaultCookieAttributes\|sameSite\|advanced" skills/nextjs-add-auth/SKILL.md
```
→ Shows the three new lines inside the advanced block.

**Steps:**

- [ ] **Step 1: Read the file to find exact line numbers**

Run:
```bash
grep -n "plugins: \[nextCookies\|session:" skills/nextjs-add-auth/SKILL.md
```
Note the line number of `plugins: [nextCookies()]` — the insertion goes immediately before it.

- [ ] **Step 2: Insert the advanced block**

Find this block (the closing of the session config + plugins line):
```ts
  session: {
    expiresIn: 30 * 24 * 60 * 60,
    updateAge: 24 * 60 * 60,
    cookieCache: {
      enabled: true,
      maxAge: 5 * 60,
    },
  },

  plugins: [nextCookies()],
});
```

Replace with:
```ts
  session: {
    expiresIn: 30 * 24 * 60 * 60,
    updateAge: 24 * 60 * 60,
    cookieCache: {
      enabled: true,
      maxAge: 5 * 60,
    },
  },

  advanced: {
    defaultCookieAttributes: {
      sameSite: 'lax',
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
    },
  },

  plugins: [nextCookies()],
});
```

- [ ] **Step 3: Verify**

```bash
grep -n "defaultCookieAttributes\|sameSite\|advanced" skills/nextjs-add-auth/SKILL.md
```
Expected: 4 lines — `advanced:`, `defaultCookieAttributes:`, `sameSite:`, `httpOnly:`, `secure:`.

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md
git commit -m "fix(nextjs-add-auth): add explicit cookie security attributes to betterAuth config"
```

---

### Task 2: Add Prisma 6 not-found handling to nextjs-add-database

**Goal:** Add a Prisma 6 callout to the Rules section documenting that `NotFoundError` is removed and showing the correct patterns.

**Files:**
- Modify: `skills/nextjs-add-database/SKILL.md`

**Acceptance Criteria:**
- [ ] Rules section has a `**Prisma 6 — not found handling**:` bullet
- [ ] Bullet documents `NotFoundError` removal
- [ ] Option A (null check) pattern present
- [ ] Option B (`findUniqueOrThrow` + P2025) pattern present
- [ ] Transaction note present
- [ ] No other lines changed

**Verify:**
```bash
grep -n "Prisma 6\|NotFoundError\|P2025\|findUniqueOrThrow" skills/nextjs-add-database/SKILL.md
```
→ Shows all four terms.

**Steps:**

- [ ] **Step 1: Find the exact Prisma rule line**

```bash
grep -n "\*\*Prisma\*\*:" skills/nextjs-add-database/SKILL.md
```
Note the line number. The new bullet goes on the next line after the existing Prisma bullet ends.

- [ ] **Step 2: Find the end of the Prisma bullet**

Read around that line to find where the Prisma bullet ends and the next bullet begins (likely `**Kysely**:`). The new bullet inserts between them.

- [ ] **Step 3: Insert the Prisma 6 bullet**

Find the existing Prisma bullet (it ends before `**Kysely**:`). Insert this new bullet immediately after it:

```markdown
- **Prisma 6 — not found handling**: `NotFoundError` was removed in Prisma 6 — do NOT import it from `@prisma/client`. Use one of these patterns instead:

  **Option A — null check (preferred for simple cases):**
  ```ts
  const record = await prisma.model.findUnique({ where: { id } });
  if (!record) return NextResponse.json({ error: 'Not found' }, { status: 404 });
  ```

  **Option B — throw on not found (useful inside service layers):**
  ```ts
  import { Prisma } from '@prisma/client';
  try {
    const record = await prisma.model.findUniqueOrThrow({ where: { id } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }
    throw error;
  }
  ```

  Note: `findUniqueOrThrow` is incompatible with sequential (array-style) `$transaction` — use interactive transactions (`$transaction(async (tx) => { ... })`) if rollback on not-found is needed.
```

- [ ] **Step 4: Verify**

```bash
grep -n "Prisma 6\|NotFoundError\|P2025\|findUniqueOrThrow" skills/nextjs-add-database/SKILL.md
```
Expected: all four terms appear.

- [ ] **Step 5: Commit**

```bash
git add skills/nextjs-add-database/SKILL.md
git commit -m "fix(nextjs-add-database): document Prisma 6 not-found handling — NotFoundError removed"
```

---

### Task 3: Add Prisma 6 not-found handling to nestjs-add-database

**Goal:** Same as Task 2 but adapted for NestJS (`NotFoundException` instead of `NextResponse.json`).

**Files:**
- Modify: `skills/nestjs-add-database/SKILL.md`

**Acceptance Criteria:**
- [ ] Rules section has a `**Prisma 6 — not found handling**:` bullet
- [ ] Bullet documents `NotFoundError` removal
- [ ] Option A uses `throw new NotFoundException(...)`
- [ ] Option B uses `findUniqueOrThrow` + P2025 + `throw new NotFoundException(...)`
- [ ] Transaction note present
- [ ] No other lines changed

**Verify:**
```bash
grep -n "Prisma 6\|NotFoundError\|P2025\|findUniqueOrThrow\|NotFoundException" skills/nestjs-add-database/SKILL.md
```
→ Shows all five terms.

**Steps:**

- [ ] **Step 1: Find the exact Prisma rule line**

```bash
grep -n "\*\*Prisma\*\*:" skills/nestjs-add-database/SKILL.md
```

- [ ] **Step 2: Insert the Prisma 6 bullet after the existing Prisma rule**

Find the existing Prisma bullet (ends before `**Kysely**:`). Insert immediately after:

```markdown
- **Prisma 6 — not found handling**: `NotFoundError` was removed in Prisma 6 — do NOT import it from `@prisma/client`. Use one of these patterns instead:

  **Option A — null check (preferred for simple cases):**
  ```ts
  const record = await this.prisma.model.findUnique({ where: { id } });
  if (!record) throw new NotFoundException(`Record ${id} not found`);
  ```

  **Option B — throw on not found (cleaner in service methods):**
  ```ts
  import { Prisma } from '@prisma/client';
  try {
    const record = await this.prisma.model.findUniqueOrThrow({ where: { id } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      throw new NotFoundException(`Record ${id} not found`);
    }
    throw error;
  }
  ```

  Note: `findUniqueOrThrow` is incompatible with sequential (array-style) `$transaction` — use interactive transactions (`$transaction(async (tx) => { ... })`) if rollback on not-found is needed.
```

- [ ] **Step 3: Verify**

```bash
grep -n "Prisma 6\|NotFoundError\|P2025\|findUniqueOrThrow\|NotFoundException" skills/nestjs-add-database/SKILL.md
```
Expected: all five terms appear.

- [ ] **Step 4: Commit**

```bash
git add skills/nestjs-add-database/SKILL.md
git commit -m "fix(nestjs-add-database): document Prisma 6 not-found handling — NotFoundError removed"
```
