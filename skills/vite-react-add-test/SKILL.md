---
name: vite-react-add-test
description: Use when adding tests for components, hooks, or services in a Vite + React project — covers Vitest unit tests, Testing Library component tests, and React Query hook tests.
disable-model-invocation: true
---

# Add Tests (Vitest + Testing Library)

Guide for writing tests in a Vite + React project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:vite-react-scaffold`. See Step 0.

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/features/` or `src/components/` contains at least
one `.tsx` file.

If not found → ⛔ STOP. Tell the user: "No components or features found. Add some
using `templatecentral:vite-react-add-feature` or `templatecentral:vite-react-add-component`
first, then return here."

If found → proceed to Step 1.

## Test Structure

Tests are **co-located** next to the source file they test:

```
src/features/project/
├── api/
│   ├── project-service.ts
│   └── project-service.test.ts        # Service test
├── components/
│   ├── project-card.tsx
│   └── project-card.test.tsx          # Component test
├── hooks/
│   ├── use-projects.query.ts
│   └── use-projects.query.test.tsx    # Hook test
```

| Source file | Test file |
|-------------|-----------|
| `project-service.ts` | `project-service.test.ts` |
| `project-card.tsx` | `project-card.test.tsx` |
| `use-projects.query.ts` | `use-projects.query.test.tsx` |

Use `.test.ts` for pure logic, `.test.tsx` for anything that renders React.

## Test Setup

The template has a setup file at `src/test/setup.ts` that:
- Imports `@testing-library/jest-dom/vitest` (adds DOM matchers like `toBeInTheDocument`)
- Runs `cleanup()` after each test (unmounts rendered components)

Vitest is configured with `globals: true` — `describe`, `it`, `expect` are available without imports, but explicit imports are also fine.

## Steps

### 1. Component Tests

Use Testing Library to render and assert on DOM output:

```tsx
// src/features/project/components/project-card.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ProjectCard } from './project-card';

describe('ProjectCard', () => {
  const mockProject = {
    id: '1',
    name: 'Alpha',
    status: 'active' as const,
  };

  it('renders the project name', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('Alpha')).toBeInTheDocument();
  });

  it('renders the project status', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('active')).toBeInTheDocument();
  });
});
```

### 2. Component Tests with User Interaction

Use `@testing-library/user-event` for clicks, typing, and other interactions:

```tsx
// src/features/project/components/project-form.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ProjectForm } from './project-form';

describe('ProjectForm', () => {
  it('calls onSubmit with form data', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();

    render(<ProjectForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Name'), 'New Project');
    await user.click(screen.getByRole('button', { name: /submit/i }));

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'New Project' }),
    );
  });
});
```

### 3. Service Tests

Test services by calling their methods directly. The first example below is for **synchronous/in-memory services** (like the template's `ExampleService`). For **async services** that call `fetch` or an external API, see the second example with `mockFetch`:

```ts
// src/features/project/api/project-service.test.ts
import { describe, expect, it } from 'vitest';
import { ProjectService } from './project-service';

describe('ProjectService', () => {
  it('getAll returns all items', () => {
    const result = ProjectService.getAll();

    expect(Array.isArray(result)).toBe(true);
    expect(result.length).toBeGreaterThan(0);
    expect(result[0]).toHaveProperty('id');
  });

  it('getById returns matching item', () => {
    const result = ProjectService.getById('1');

    expect(result).toBeDefined();
    expect(result?.id).toBe('1');
  });

  it('getById returns undefined for unknown id', () => {
    expect(ProjectService.getById('nonexistent')).toBeUndefined();
  });
});
```

For services that call `fetch` or an external API, stub `fetch` at the boundary:

```ts
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { ProjectService } from './project-service';

const mockFetch = vi.fn();

describe('ProjectService (API-backed)', () => {
  beforeEach(() => { vi.stubGlobal('fetch', mockFetch); });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it('fetches projects from API', async () => {
    const projects = [{ id: '1', name: 'Alpha' }];
    mockFetch.mockResolvedValue(new Response(JSON.stringify(projects)));

    const result = await ProjectService.getAll();
    expect(result).toEqual(projects);
  });
});
```

### 4. React Query Hook Tests

Wrap hooks in a `QueryClientProvider` for testing:

```tsx
// src/features/project/hooks/use-projects.query.test.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi, afterEach } from 'vitest';
import type { ReactNode } from 'react';
import { useProjects } from './use-projects.query';
import { ProjectService } from '../api';

vi.mock('../api', () => ({
  ProjectService: {
    getAll: vi.fn(),
  },
}));

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };
}

describe('useProjects', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns projects on success', async () => {
    const projects = [{ id: '1', name: 'Alpha', status: 'active' }];
    vi.mocked(ProjectService.getAll).mockResolvedValue(projects);

    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toEqual(projects);
  });

  it('returns error on failure', async () => {
    vi.mocked(ProjectService.getAll).mockRejectedValue(new Error('Failed'));

    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

### 5. Integration Service Tests (External APIs)

If you've added external API integrations via the `add-integration` skill, test them by mocking the client:

```ts
// src/features/<name>/api/<name>-service.test.ts
import { describe, expect, it, vi, afterEach } from 'vitest';
import { NameService } from './<name>-service';

vi.mock('./<name>-client', () => ({
  nameClient: { getItems: vi.fn(), getItem: vi.fn() },
}));

import { nameClient } from './<name>-client';

describe('NameService', () => {
  afterEach(() => { vi.restoreAllMocks(); });

  it('fetches and returns items', async () => {
    const mockData = [{ id: '1', title: 'Item' }];
    vi.mocked(nameClient.getItems).mockResolvedValue(mockData);

    const result = await NameService.getItems();
    expect(result).toEqual(mockData);
  });
});
```

### 6. Run Tests

```bash
pnpm test                  # Run all tests once
pnpm test:watch            # Watch mode (re-runs on change)
pnpm test:coverage         # Run with coverage report
```

### 7. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

## Helper Patterns

### JSON Response Factory

```ts
function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
```

### React Query Wrapper

```tsx
function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };
}
```

## Rules

- One concept per test — test a single behavior in each `it()` block
- Mock at boundaries — mock `fetch`, service modules, or integration clients; NEVER mock internal utilities or React internals
- Use Testing Library queries by role/text — `getByRole`, `getByText`, `getByLabelText`; NEVER use `querySelector` or test IDs unless no semantic alternative exists
- Use `userEvent` over `fireEvent` — `userEvent.setup()` simulates real user behavior
- Always call `vi.restoreAllMocks()` and `vi.unstubAllGlobals()` in `afterEach` — prevent mock leakage between tests
- Create a fresh `QueryClient` per test — NEVER share a client across tests (stale cache causes flakes)
- NEVER test implementation details — test what the user sees (components) or what the caller gets (services)
- NEVER test third-party library behavior — test YOUR code's usage of it
- NEVER share mutable state between tests — each test sets up its own data
