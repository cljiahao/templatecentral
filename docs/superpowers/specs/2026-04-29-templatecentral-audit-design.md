# templateCentral Audit — Design Spec

**Date:** 2026-04-29
**Scope:** Three targeted fixes to the templateCentral plugin following a clean-eyes audit.

---

## Problem Summary

Three gaps were found across the plugin. All affect the accuracy of generated projects.

### Gap 1 — Next.js scaffold has a broken example feature flow

- `src/features/example/` is `[generate]` in the scaffold with no verbatim spec — agents invent its contents unpredictably.
- No `src/app/dashboard/` exists in the scaffold tree, so the example feature has no consumer page.
- `nextjs-add-auth` creates `src/app/dashboard/` (layout + overview page), but its dashboard page is a blank "Dashboard" heading — it never imports the example feature.
- `shared-remove-example` correctly references `src/app/dashboard/(overview)/page.tsx`, but that file doesn't exist until auth is added — which is backwards.

**Result:** The example feature floats unconnected; users can't see the architectural pattern it demonstrates; remove-example removes something that was never wired up.

### Gap 2 — FastAPI auth has no completion path after `fastapi-add-database`

- `fastapi-add-auth` creates an auth service where `login_user` raises `HTTP 501` and `register_user` writes to nowhere.
- The stub notice says "run `fastapi-add-database` to complete" but `fastapi-add-database` has no corresponding instructions.
- Users who run both skills in order end up with a deployed app returning 501 on every login attempt.

### Gap 3 — FastAPI auth route handlers use `async def`

- `get_current_user`, `register`, `login`, `get_me` are all `async def`.
- All four are sync (JWT decode is CPU-only; the service calls are sync; `get_me` raises an exception).
- Inconsistent with the `fastapi-add-database` convention: use `def` for sync SQLAlchemy handlers so FastAPI runs them in a thread pool.

---

## Architecture

### Proxy-based route protection (Next.js 16 + better-auth)

`proxy.ts` uses an allowlist: only `HOME` (`/`) and `LOGIN` (`/login`) are explicitly public. Every other route — including `/dashboard` — is protected automatically once auth is added. Route groups like `(protected)/` are purely organizational; they do not enforce protection.

This means the scaffold can create `src/app/dashboard/` without any auth dependency. When `nextjs-add-auth` is run, `proxy.ts` protects `/dashboard` automatically.

### Ownership boundaries after these changes

| Asset | Owner |
|---|---|
| `src/features/example/` (all 11 files) | `nextjs-scaffold` (verbatim) |
| `src/app/dashboard/layout.tsx` | `nextjs-scaffold` (verbatim); `nextjs-add-auth` skips if present |
| `src/app/dashboard/(overview)/page.tsx` | `nextjs-scaffold` (verbatim, uses ExampleList); `nextjs-add-auth` skips if present |
| `src/lib/constants/routes.ts` — `HOME`, `DASHBOARD` | `nextjs-scaffold` (generated) |
| `src/lib/constants/routes.ts` — `LOGIN` | `nextjs-add-auth` (additive) |
| FastAPI `User` model + repository + real auth service | `fastapi-add-database` "Completing Auth Integration" section |

---

## Section 1 — Next.js Scaffold

**File:** `skills/nextjs-scaffold/SKILL.md`

### 1.1 Add dashboard to directory tree

Add to the Part A directory tree under `src/app/`:

```
src/app/
├── dashboard/
│   ├── layout.tsx              [verbatim — Part C]
│   └── (overview)/
│       └── page.tsx            [verbatim — Part C]
```

### 1.2 Replace `[generate]` example feature with verbatim spec

Replace the single-line `[generate]` entry:

```
    ├── features/
    │   └── example/                   [generate — minimal example with types, service, hook, component]
```

With the full verbatim tree:

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

### 1.3 Verbatim content for Part C additions

**`src/features/example/types.ts`**
```ts
export interface ExampleItem {
  id: string;
  title: string;
  description: string;
  status: 'active' | 'inactive';
}
```

**`src/features/example/constants.ts`**
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

**`src/features/example/api/example-service.ts`**
```ts
import { EXAMPLE_ITEMS } from '../constants';
import type { ExampleItem } from '../types';

export function getExampleItems(): Promise<ExampleItem[]> {
  return Promise.resolve(EXAMPLE_ITEMS);
}
```

**`src/features/example/api/index.ts`**
```ts
export { getExampleItems } from './example-service';
```

**`src/features/example/hooks/use-example-items.query.ts`**
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

**`src/features/example/hooks/index.ts`**
```ts
export { useExampleItems } from './use-example-items.query';
```

**`src/features/example/components/example-card.tsx`**
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

**`src/features/example/components/example-list.tsx`**
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

**`src/features/example/components/index.ts`**
```ts
export { ExampleCard } from './example-card';
export { ExampleList } from './example-list';
```

**`src/features/example/schemas/index.ts`**
```ts
export {};
```

**`src/features/example/index.ts`**
```ts
export * from './components';
export * from './hooks';
export type { ExampleItem } from './types';
```

**`src/app/dashboard/layout.tsx`**
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

**`src/app/dashboard/(overview)/page.tsx`**
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

### 1.4 Add `DASHBOARD` to `routes.ts` generation spec

Update the generation convention note for `routes.ts`:

> Generate with `HOME: '/'` and `DASHBOARD: '/dashboard'`. `nextjs-add-auth` appends `LOGIN: '/login'` on top — do not add it here.

### 1.5 Update `AGENTS.md` template — add dashboard route

In the "Architecture Decisions" section of the generated `AGENTS.md`, add:

> - Route groups: `(public)/` for public pages; `dashboard/` for authenticated pages (protected by `proxy.ts` once `nextjs-add-auth` is run)

---

## Section 2 — `nextjs-add-auth` Coordination

**File:** `skills/nextjs-add-auth/SKILL.md`

### 2.1 Step 6 — routes additive only

Change the instruction for Step 6 from creating the full `PAGE_ROUTES` object to:

> Add `LOGIN: '/login'` to the existing `PAGE_ROUTES` object in `src/lib/constants/routes.ts`. `HOME` and `DASHBOARD` are already present from the scaffold — do not duplicate them.

### 2.2 Steps 8 + 9 — conditional on scaffold

Prepend to Step 8 (dashboard layout) and Step 9 (overview page):

> **Skip if `src/app/dashboard/layout.tsx` already exists** — present when the project was scaffolded with templateCentral. The proxy protects `/dashboard` automatically via the allowlist in `proxy.ts`; no structural change is needed.

---

## Section 3 — FastAPI Auth Fixes

### 3.1 `async def` → `def` in `skills/fastapi-add-auth/SKILL.md`

Change all four function signatures:

| Location | Before | After |
|---|---|---|
| `src/api/dependencies/auth.py` | `async def get_current_user(...)` | `def get_current_user(...)` |
| `src/api/routers/auth.py` | `async def register(...)` | `def register(...)` |
| `src/api/routers/auth.py` | `async def login(...)` | `def login(...)` |
| `src/api/routers/auth.py` (Step 9 example) | `async def get_me(...)` | `def get_me(...)` |

FastAPI runs `def` handlers in a thread pool — no blocking risk.

### 3.2 Add "Completing Auth Integration" section to `skills/fastapi-add-database/SKILL.md`

New optional section appended after all other steps. Only applies when `fastapi-add-auth` was run first. Contains four steps:

**Step A — Create `src/models/user.py`**
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

**Step B — Create `src/api/repositories/user_repository.py`**
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

**Step C — Replace stubs in `src/api/services/auth_service.py`**
```python
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from api.repositories.user_repository import create_user, get_user_by_email
from core.security import create_access_token, hash_password, verify_password


def register_user(db: Session, email: str, password: str, name: str) -> dict:
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
    user = get_user_by_email(db, email)
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=str(user.id))
```

**Step D — Inject `db` into auth router handlers**

Replace the entire `src/api/routers/auth.py` (all three handlers — `register`, `login`, and `get_me`):

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

---

## Files Changed

| File | Change |
|---|---|
| `skills/nextjs-scaffold/SKILL.md` | Add dashboard tree + 13 verbatim files + routes.ts spec + AGENTS.md note |
| `skills/nextjs-add-auth/SKILL.md` | Step 6 additive-only; Steps 8+9 conditional |
| `skills/fastapi-add-auth/SKILL.md` | 4× `async def` → `def` |
| `skills/fastapi-add-database/SKILL.md` | Add "Completing Auth Integration" section (4 steps) |

No other files change.

---

## Out of Scope

- Vite+React scaffold — already has full verbatim example feature and dashboard page; no changes needed.
- NestJS scaffold — no example feature consumer gap; no changes needed.
- `shared-remove-example` — already references the correct Next.js paths (`src/app/dashboard/(overview)/page.tsx`); will become accurate once Section 1 is implemented.
- All other skills — clean as of previous audit session (Drizzle, FastAPI 0.136+, better-auth ≥1.6.6 security).
