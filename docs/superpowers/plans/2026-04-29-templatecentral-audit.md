# templateCentral Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three accuracy gaps in the templateCentral plugin: add a verbatim example feature + dashboard to the Next.js scaffold, make `nextjs-add-auth` conditional on scaffold state, and complete the FastAPI auth → database integration path.

**Architecture:** Four targeted edits across four SKILL.md files — one commit per file. No new files are created; only existing skill files are modified. All changes are documentation (markdown + code blocks inside skill files).

**Tech Stack:** Markdown, templateCentral plugin conventions, Next.js 16, FastAPI 0.136+

---

### Task 1: nextjs-scaffold — dashboard tree + verbatim example feature

**Goal:** Add `src/app/dashboard/` to the scaffold tree, replace the `[generate]` example feature with 13 verbatim files, sharpen the `routes.ts` generation spec, and update the AGENTS.md template route-groups note.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md`

**Acceptance Criteria:**
- [ ] Directory tree shows `dashboard/layout.tsx` and `dashboard/(overview)/page.tsx` as `[verbatim — Part C]`
- [ ] `src/features/example/` in the tree lists all 13 files as `[verbatim — Part C]`
- [ ] `routes.ts` tree annotation specifies exact keys: `HOME:'/'`, `DASHBOARD:'/dashboard'`, `HEALTH:'/api/health'`
- [ ] AGENTS.md template mentions `dashboard/` as authenticated route group
- [ ] Part C contains verbatim blocks for all 13 example feature files plus 2 dashboard files
- [ ] Step 9 remove-example note references `dashboard/(overview)/page.tsx` and removes the stale "if present" qualifier

**Verify:**
```bash
grep -c "\[verbatim — Part C\]" skills/nextjs-scaffold/SKILL.md
# Before: count N; After: count N+15 (13 example + 2 dashboard)

grep "dashboard/layout.tsx" skills/nextjs-scaffold/SKILL.md
# Must appear in the tree section AND in Part C

grep "generate.*example\|example.*generate" skills/nextjs-scaffold/SKILL.md
# Must return 0 matches (old [generate] entry gone)

grep "ExampleList" skills/nextjs-scaffold/SKILL.md
# Must appear in dashboard/(overview)/page.tsx Part C block AND step 9 note
```

**Steps:**

- [ ] **Step 1: Add `dashboard/` to the Part A directory tree**

In `skills/nextjs-scaffold/SKILL.md`, find the tree block. Replace:

```
    │   ├── (public)/
    │   │   ├── layout.tsx              [generate — public layout with Navbar + Footer]
    │   │   └── page.tsx                [generate — landing page using widgets]
    │   ├── api/
```

With:

```
    │   ├── (public)/
    │   │   ├── layout.tsx              [generate — public layout with Navbar + Footer]
    │   │   └── page.tsx                [generate — landing page using widgets]
    │   ├── dashboard/
    │   │   ├── layout.tsx              [verbatim — Part C]
    │   │   └── (overview)/
    │   │       └── page.tsx            [verbatim — Part C]
    │   ├── api/
```

- [ ] **Step 2: Replace `[generate]` example feature with full verbatim tree**

Find and replace:

```
    ├── features/
    │   └── example/                   [generate — minimal example with types, service, hook, component]
```

With:

```
    ├── features/
    │   └── example/
    │       ├── index.ts                [verbatim — Part C]
    │       ├── types.ts                [verbatim — Part C]
    │       ├── constants.ts            [verbatim — Part C]
    │       ├── api/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   └── example-service.ts  [verbatim — Part C]
    │       ├── components/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   ├── example-card.tsx    [verbatim — Part C]
    │       │   └── example-list.tsx    [verbatim — Part C]
    │       ├── hooks/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   └── use-example-items.query.ts  [verbatim — Part C]
    │       └── schemas/
    │           └── index.ts            [verbatim — Part C]
```

- [ ] **Step 3: Sharpen the `routes.ts` generation annotation**

Find and replace:

```
        │   └── routes.ts               [generate — PAGE_ROUTES + API_ROUTES]
```

With:

```
        │   └── routes.ts               [generate — PAGE_ROUTES (HOME:'/', DASHBOARD:'/dashboard') + API_ROUTES (HEALTH:'/api/health'); nextjs-add-auth appends LOGIN:'/login' — do not add it here]
```

- [ ] **Step 4: Update AGENTS.md template route-groups note**

In the `### 6. Write project AGENTS.md` section, find and replace:

```
- Route groups: `(public)/` for public pages
```

With:

```
- Route groups: `(public)/` for public pages; `dashboard/` for authenticated pages (protected by `proxy.ts` once `nextjs-add-auth` is run)
```

- [ ] **Step 5: Add 15 verbatim Part C blocks (example feature + dashboard)**

In the Part C section, find the final entry (just before the `---` separator that precedes `## Scaffold Steps`):

```
### `src/integrations/factories.ts`

```ts
// Integration factory functions.
// Each factory returns a configured service instance.
// Added by nextjs-add-integration — one export per integration.
```

---

## Scaffold Steps
```

Insert all 15 new verbatim blocks between the closing triple-backtick of `factories.ts` and the `---` separator. Add them in this exact order:

````markdown
### `src/features/example/types.ts`

```ts
export interface ExampleItem {
  id: string;
  title: string;
  description: string;
  status: 'active' | 'inactive';
}
```

### `src/features/example/constants.ts`

```ts
import type { ExampleItem } from './types';

export const EXAMPLE_ITEMS: ExampleItem[] = [
  {
    id: '1',
    title: 'Feature Pattern',
    description: 'Add features under src/features/<name>/ with api/, components/, hooks/, schemas/.',
    status: 'active',
  },
  {
    id: '2',
    title: 'React Query',
    description: 'Data-fetching hooks live in features/hooks/ and wrap TanStack Query.',
    status: 'active',
  },
  {
    id: '3',
    title: 'shadcn/ui',
    description: 'Add UI primitives with: npx shadcn@latest add <component>',
    status: 'inactive',
  },
];
```

### `src/features/example/api/example-service.ts`

```ts
import { EXAMPLE_ITEMS } from '../constants';
import type { ExampleItem } from '../types';

export function getExampleItems(): Promise<ExampleItem[]> {
  return Promise.resolve(EXAMPLE_ITEMS);
}
```

### `src/features/example/api/index.ts`

```ts
export { getExampleItems } from './example-service';
```

### `src/features/example/hooks/use-example-items.query.ts`

```ts
import { useQuery } from '@tanstack/react-query';

import { getExampleItems } from '../api/example-service';

export function useExampleItems() {
  return useQuery({
    queryKey: ['example-items'],
    queryFn: getExampleItems,
  });
}
```

### `src/features/example/hooks/index.ts`

```ts
export { useExampleItems } from './use-example-items.query';
```

### `src/features/example/components/example-card.tsx`

```tsx
import { CustomCard } from '@/components/widgets';

import type { ExampleItem } from '../types';

interface ExampleCardProps {
  item: ExampleItem;
}

export function ExampleCard({ item }: ExampleCardProps) {
  return (
    <CustomCard>
      <div className="flex items-start justify-between gap-2">
        <div>
          <h3 className="font-semibold">{item.title}</h3>
          <p className="mt-1 text-sm text-muted-foreground">{item.description}</p>
        </div>
        <span
          className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${
            item.status === 'active'
              ? 'bg-green-100 text-green-700'
              : 'bg-gray-100 text-gray-500'
          }`}
        >
          {item.status}
        </span>
      </div>
    </CustomCard>
  );
}
```

### `src/features/example/components/example-list.tsx`

```tsx
'use client';

import { useExampleItems } from '../hooks/use-example-items.query';
import { ExampleCard } from './example-card';

export function ExampleList() {
  const { data: items, isLoading } = useExampleItems();

  if (isLoading) return <p className="text-sm text-muted-foreground">Loading…</p>;
  if (!items?.length) return <p className="text-sm text-muted-foreground">No items found.</p>;

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <ExampleCard key={item.id} item={item} />
      ))}
    </div>
  );
}
```

### `src/features/example/components/index.ts`

```ts
export { ExampleCard } from './example-card';
export { ExampleList } from './example-list';
```

### `src/features/example/schemas/index.ts`

```ts
export {};
```

### `src/features/example/index.ts`

```ts
export * from './components';
export * from './hooks';
export type { ExampleItem } from './types';
```

### `src/app/dashboard/layout.tsx`

```tsx
import { Navbar } from '@/components/layout/navbar';
import { SiteFooter } from '@/components/layout/site-footer';
import type { ReactNode } from 'react';

export default function DashboardLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}
```

### `src/app/dashboard/(overview)/page.tsx`

```tsx
import { ExampleList } from '@/features/example';

export default function DashboardPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-muted-foreground">
        Example feature — remove with the <code>shared-remove-example</code> skill after
        confirming the scaffold works.
      </p>
      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```
````

- [ ] **Step 6: Fix Step 9 remove-example note**

Find and replace in the `### 9. Remove example code (optional)` section:

```
Next.js-specific steps (the skill covers these):
- Delete `src/features/example/` directory
- Remove the example route import from `src/app/` if present
```

With:

```
Next.js-specific steps (the skill covers these):
- Delete `src/features/example/` directory
- Remove `ExampleList` import from `src/app/dashboard/(overview)/page.tsx`

The `shared-remove-example` skill handles both steps automatically.
```

- [ ] **Step 7: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "feat(nextjs-scaffold): add verbatim dashboard + example feature; fix routes.ts spec"
```

---

### Task 2: nextjs-add-auth — conditional dashboard + additive routes step

**Goal:** Make Step 6 additive-only (don't duplicate `HOME`/`DASHBOARD`), and Steps 8+9 conditional (skip if scaffold already created them). Update the file-list header to show dashboard as conditional.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md`

**Acceptance Criteria:**
- [ ] Step 6 heading says "Add `PAGE_ROUTES.LOGIN`" (not `LOGIN` and `DASHBOARD`)
- [ ] Step 6 code block shows only `LOGIN: '/login'` being added, with comment noting `HOME` and `DASHBOARD` already exist
- [ ] Step 8 has a skip notice at the top
- [ ] Step 9 has a skip notice at the top
- [ ] File-list header marks `dashboard/` as conditional

**Verify:**
```bash
grep "PAGE_ROUTES.LOGIN and PAGE_ROUTES.DASHBOARD" skills/nextjs-add-auth/SKILL.md
# Must return 0 (old heading gone)

grep "Skip this step" skills/nextjs-add-auth/SKILL.md
# Must return 2 matches (one for step 8, one for step 9)

grep "HOME.*already present\|DASHBOARD.*already present" skills/nextjs-add-auth/SKILL.md
# Must return 1 match
```

**Steps:**

- [ ] **Step 1: Update file-list header — mark dashboard as conditional**

Find and replace in the `## Files this skill creates` block:

```
    └── dashboard/
        ├── layout.tsx
        └── (overview)/
            └── page.tsx
```

With:

```
    └── dashboard/           ← only if not already created by scaffold
        ├── layout.tsx
        └── (overview)/
            └── page.tsx
```

- [ ] **Step 2: Update Step 6 heading and code block**

Find and replace:

```
### 6. Add `PAGE_ROUTES.LOGIN` and `PAGE_ROUTES.DASHBOARD` to `src/lib/constants/routes.ts`

Open the file and add the two routes to the `PAGE_ROUTES` object:

```ts
export const PAGE_ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  DASHBOARD: '/dashboard',
  // ... existing routes
} as const;
```
```

With:

```
### 6. Add `PAGE_ROUTES.LOGIN` to `src/lib/constants/routes.ts`

Add `LOGIN` to the existing `PAGE_ROUTES` object. `HOME` and `DASHBOARD` are already present from the scaffold — do not add them again:

```ts
export const PAGE_ROUTES = {
  // ... existing HOME: '/' and DASHBOARD: '/dashboard' entries
  LOGIN: '/login',
} as const;
```
```

- [ ] **Step 3: Add skip notice to Step 8**

Find and replace:

```
### 8. Create `src/app/dashboard/layout.tsx`
```

With:

```
### 8. Create `src/app/dashboard/layout.tsx` (skip if already exists)

> **Skip this step** if `src/app/dashboard/layout.tsx` already exists — present when the project was scaffolded with templateCentral. The `proxy.ts` allowlist protects `/dashboard` automatically once this skill completes; no structural change is needed.
```

- [ ] **Step 4: Add skip notice to Step 9**

Find and replace:

```
### 9. Create `src/app/dashboard/(overview)/page.tsx`

```tsx
export default function DashboardPage() {
  return (
    <div className="container py-8">
      <h1 className="text-2xl font-bold">Dashboard</h1>
    </div>
  );
}
```
```

With:

```
### 9. Create `src/app/dashboard/(overview)/page.tsx` (skip if already exists)

> **Skip this step** if `src/app/dashboard/(overview)/page.tsx` already exists — present when the project was scaffolded with templateCentral. The existing page shows the `ExampleList` component; `shared-remove-example` cleans it up when the user is ready.

If creating fresh (non-scaffold project):

```tsx
export default function DashboardPage() {
  return (
    <div className="container py-8">
      <h1 className="text-2xl font-bold">Dashboard</h1>
    </div>
  );
}
```
```

- [ ] **Step 5: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md
git commit -m "fix(nextjs-add-auth): make dashboard creation conditional on scaffold; routes step additive-only"
```

---

### Task 3: fastapi-add-auth — async def → def for all route handlers

**Goal:** Change all four `async def` function signatures to `def` for consistency with the FastAPI project convention (sync handlers run in thread pool; no I/O in these functions).

**Files:**
- Modify: `skills/fastapi-add-auth/SKILL.md`

**Acceptance Criteria:**
- [ ] `get_current_user` in `src/api/dependencies/auth.py` is `def`, not `async def`
- [ ] `register` in `src/api/routers/auth.py` is `def`, not `async def`
- [ ] `login` in `src/api/routers/auth.py` is `def`, not `async def`
- [ ] `get_me` example in Step 9 is `def`, not `async def`
- [ ] Zero remaining `async def` in this file

**Verify:**
```bash
grep "async def" skills/fastapi-add-auth/SKILL.md
# Must return 0 matches
```

**Steps:**

- [ ] **Step 1: Fix `get_current_user` dependency**

Find and replace:

```python
async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
```

With:

```python
def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
```

- [ ] **Step 2: Fix `register` handler**

Find and replace:

```python
@router.post("/register", response_model=UserResponse)
async def register(body: RegisterRequest) -> UserResponse:
```

With:

```python
@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest) -> UserResponse:
```

- [ ] **Step 3: Fix `login` handler**

Find and replace:

```python
@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest) -> TokenResponse:
```

With:

```python
@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
```

- [ ] **Step 4: Fix `get_me` example in Step 9**

Find and replace:

```python
@router.get("/me", response_model=UserResponse)
async def get_me(user_id: str = Depends(get_current_user)) -> UserResponse:
```

With:

```python
@router.get("/me", response_model=UserResponse)
def get_me(user_id: str = Depends(get_current_user)) -> UserResponse:
```

- [ ] **Step 5: Commit**

```bash
git add skills/fastapi-add-auth/SKILL.md
git commit -m "fix(fastapi-add-auth): use def (not async def) for all route handlers and dependencies"
```

---

### Task 4: fastapi-add-database — add Completing Auth Integration section

**Goal:** Append a new optional section to `fastapi-add-database` that completes the auth stubs created by `fastapi-add-auth`. Covers: User model, user repository, real auth service, and updated router with `db` injection.

**Files:**
- Modify: `skills/fastapi-add-database/SKILL.md`

**Acceptance Criteria:**
- [ ] New `## Completing Auth Integration` section exists at end of file
- [ ] Section has a clear opt-in notice ("only apply if `fastapi-add-auth` was run first")
- [ ] `src/models/user.py` verbatim block present with all five columns
- [ ] `src/api/repositories/user_repository.py` verbatim block present with `get_user_by_email`, `get_user_by_id`, `create_user`
- [ ] `src/api/services/auth_service.py` replacement block present — no more `501` responses
- [ ] `src/api/routers/auth.py` replacement block present with `db: Session = Depends(get_db)` in all three handlers
- [ ] `get_me` handler uses `get_user_by_id` (JWT subject is user ID, not email)

**Verify:**
```bash
grep "Completing Auth Integration" skills/fastapi-add-database/SKILL.md
# Must return 1 match

grep "HTTP_501_NOT_IMPLEMENTED" skills/fastapi-add-database/SKILL.md
# Must return 0 matches (501 belongs only in fastapi-add-auth stub)

grep "get_user_by_id\|get_user_by_email" skills/fastapi-add-database/SKILL.md
# Must return at least 2 matches (repository + get_me handler)
```

**Steps:**

- [ ] **Step 1: Append the new section**

At the very end of `skills/fastapi-add-database/SKILL.md` (after the final closing backtick on the last code block), append:

````markdown

---

## Completing Auth Integration

> **Only apply these steps if you previously ran `fastapi-add-auth`.** The auth service stubs (`register_user` raises HTTP 501 and `login_user` raises HTTP 501) are incomplete until a database is available. Complete the integration now in four steps.

### Step A — Create `src/models/user.py`

```python
from uuid import uuid4

from sqlalchemy import Column, DateTime, String
from sqlalchemy.sql import func

from database.base import Base


class User(Base):
    __tablename__ = "users"

    id: str = Column(String, primary_key=True, default=lambda: str(uuid4()))
    email: str = Column(String, unique=True, nullable=False, index=True)
    hashed_password: str = Column(String, nullable=False)
    name: str = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

### Step B — Create `src/api/repositories/user_repository.py`

Create the `src/api/repositories/` directory (does not exist yet), then add `__init__.py` (empty) and `user_repository.py`:

```python
from sqlalchemy.orm import Session

from models.user import User


def get_user_by_email(db: Session, email: str) -> User | None:
    return db.query(User).filter(User.email == email).first()


def get_user_by_id(db: Session, user_id: str) -> User | None:
    return db.query(User).filter(User.id == user_id).first()


def create_user(db: Session, email: str, hashed_password: str, name: str) -> User:
    user = User(email=email, hashed_password=hashed_password, name=name)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
```

### Step C — Replace stubs in `src/api/services/auth_service.py`

Replace the entire file:

```python
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from api.repositories.user_repository import create_user, get_user_by_email
from core.security import create_access_token, hash_password, verify_password


def register_user(db: Session, email: str, password: str, name: str) -> dict:
    """Register a new user. Raises 409 if email already exists."""
    if get_user_by_email(db, email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )
    user = create_user(
        db=db,
        email=email,
        hashed_password=hash_password(password),
        name=name,
    )
    return {"id": str(user.id), "email": user.email, "name": user.name}


def login_user(db: Session, email: str, password: str) -> str:
    """Authenticate user and return JWT access token."""
    user = get_user_by_email(db, email)
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=str(user.id))
```

### Step D — Replace `src/api/routers/auth.py`

Replace the entire file (adds `db` injection to all three handlers; `get_me` now fetches from DB using the JWT subject as user ID):

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from api.dependencies.auth import get_current_user
from api.repositories.user_repository import get_user_by_id
from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import login_user, register_user
from api.tags import APITags
from database.session import get_db

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest, db: Session = Depends(get_db)) -> UserResponse:
    """Register a new user account."""
    user = register_user(db=db, email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = login_user(db=db, email=body.email, password=body.password)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
def get_me(user_id: str = Depends(get_current_user), db: Session = Depends(get_db)) -> UserResponse:
    """Get the current authenticated user."""
    user = get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    return UserResponse(id=str(user.id), email=user.email, name=user.name)
```
````

- [ ] **Step 2: Commit**

```bash
git add skills/fastapi-add-database/SKILL.md
git commit -m "feat(fastapi-add-database): add Completing Auth Integration section for post-auth stub replacement"
```
