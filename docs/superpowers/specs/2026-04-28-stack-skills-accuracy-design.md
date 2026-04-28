# Stack Skills Accuracy Fixes — Design Spec

**Date:** 2026-04-28
**Scope:** Fix 3 confirmed accuracy/security gaps across 3 stack-specific skills after full-project audit.

---

## Background

Full audit of all 34 stack-specific skills identified 3 targeted fixes. Scaffolds, auth patterns, and 26 other skills are clean. Shared skills were already audited and fixed earlier in this session.

---

## Fix 1 — `nextjs-add-auth`: Explicit cookie security attributes

**File:** `skills/nextjs-add-auth/SKILL.md`

**Problem:** The generated `src/auth.ts` does not explicitly configure `SameSite`, `HttpOnly`, or `Secure` on better-auth session cookies. While better-auth internally defaults to `sameSite: 'lax'` and `httpOnly: true` (confirmed from package source at v1.2.9), and sets `Secure` in production automatically, these defaults are invisible in the generated code. An explicit `advanced.defaultCookieAttributes` block makes the security posture auditable and immune to future library version changes.

**Fix:** Add `advanced.defaultCookieAttributes` to the `betterAuth({})` config in the generated `src/auth.ts`, inserted after the `session` block and before `plugins`.

**Before (lines 97–108 of the generated auth.ts block):**
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

**After:**
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

Note: `secure: process.env.NODE_ENV === 'production'` mirrors better-auth's own default behaviour, making the intent explicit rather than relying on undocumented internal logic.

---

## Fix 2 — `nextjs-add-database`: Prisma 6 not-found handling

**File:** `skills/nextjs-add-database/SKILL.md`

**Problem:** The skill's Prisma section shows `findMany()` and `create()` patterns but has no "not found" handling. In Prisma 5, developers could import `NotFoundError` from `@prisma/client` and catch it. Prisma 6 (current) removed `NotFoundError` entirely — that import throws at runtime. The skill gives no guidance, leaving developers to discover this at runtime.

**Fix:** Extend the existing `**Prisma**:` bullet in the `## Rules` section with a Prisma 6 not-found callout, and add a concrete code example below it.

**Insertion point:** After the existing Prisma rule bullet in `## Rules`, add:

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

---

## Fix 3 — `nestjs-add-database`: Prisma 6 not-found handling

**File:** `skills/nestjs-add-database/SKILL.md`

**Problem:** Same as Fix 2. The NestJS Prisma example at line 167 shows `findUnique({ where: { id } })` returning the result directly with no null/not-found handling. `NotFoundError` is removed in Prisma 6.

**Fix:** Extend the existing `**Prisma**:` bullet in the `## Rules` section with the same Prisma 6 not-found callout, adapted for NestJS (service layer, `NotFoundException`).

**Insertion point:** After the existing Prisma rule bullet in `## Rules`, add:

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

---

## Non-goals

- No changes to scaffold skills (all clean)
- No changes to FastAPI/Vite-React skills (not affected by Prisma)
- No changes to auth skills beyond nextjs-add-auth cookie config
- No changes to the 26 other stack-specific skills (clean)

---

## Acceptance Criteria

- [ ] `nextjs-add-auth`: `betterAuth({})` config includes `advanced.defaultCookieAttributes` with `sameSite`, `httpOnly`, `secure`
- [ ] `nextjs-add-database` Rules: Prisma 6 not-found callout present with both Option A and Option B patterns and transaction note
- [ ] `nestjs-add-database` Rules: Same callout with NestJS-specific patterns (`NotFoundException`)
- [ ] No other lines changed in any of the 3 files
