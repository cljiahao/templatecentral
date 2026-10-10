<!-- ref: add/test/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = Vite + React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React

Guide for writing tests in a Vite + React project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/features/` or `src/components/` contains at least
one `.tsx` file.

If not found → ⛔ STOP. Tell the user: "No components or features found. Add some
using `templatecentral:add` (feature) or `templatecentral:add` (component)
first, then return here."

If found → proceed to the sections below.

### Test Structure

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

### Test Setup

The template has a setup file at `src/test/setup.ts` that:
- Imports `@testing-library/jest-dom/vitest` (adds DOM matchers like `toBeInTheDocument`)
- Runs `cleanup()` after each test (unmounts rendered components)

Vitest is configured with `globals: true` — `describe`, `it`, `expect` are available without imports, but explicit imports are also fine.

### Component Tests

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
    description: 'First project',
  };

  it('renders the project name', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('Alpha')).toBeInTheDocument();
  });

  it('renders the project description', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('First project')).toBeInTheDocument();
  });
});
```

### Component Tests with User Interaction

Use `@testing-library/user-event` for interactions. The scaffold does not ship it:

```bash
pnpm add -D @testing-library/user-event
```

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

### Service Tests

In-memory services (like the scaffold's `ExampleService`) are tested by calling them directly — `src/features/example/api/example-service.test.ts` is the model. For services that call `fetch`, stub `fetch` at the boundary (`vite.config.ts` pins `VITE_API_BASE_URL` for tests, so `getApiBaseUrl()` resolves in CI):

```ts
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { ProjectService } from './project-service';

const mockFetch = vi.fn();

describe('ProjectService (API-backed)', () => {
  beforeEach(() => { vi.stubGlobal('fetch', mockFetch); });
  afterEach(() => { vi.resetAllMocks(); vi.unstubAllGlobals(); });

  it('fetches projects from API', async () => {
    // FastAPI/NestJS return a bare body (no `{ data }` envelope), so the fixture is the array
    // itself. It must carry every required projectItemSchema field — ProjectService.getAll()
    // runs it through .parse(), so a short fixture throws first.
    const projects = [{ id: '1', name: 'Alpha', description: null }];
    // Response.json sets application/json — FetchClient parses by content-type, so a bare
    // `new Response(JSON.stringify(...))` (text/plain) comes back as a string and fails .parse().
    mockFetch.mockResolvedValue(Response.json(projects));

    const result = await ProjectService.getAll();
    expect(result).toEqual(projects);
  });
});
```

### React Query Hook Tests

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
    vi.resetAllMocks();
  });

  it('returns projects on success', async () => {
    const projects = [{ id: '1', name: 'Alpha', description: null }];
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

### Integration Service Tests (External APIs)

If you've added external API integrations via the `templatecentral:add (integration)` skill, services live under `src/integrations/services/` and receive their client via constructor injection — test them by instantiating the service with a stub client object (no module mocking needed):

```ts
// src/integrations/services/github-service.test.ts
import { describe, expect, it, vi } from 'vitest';
import type { GithubClient } from '../clients/github-client';
import { GithubService } from './github-service';

describe('GithubService', () => {
  it('fetches and returns repos', async () => {
    const mockRepos = [{ id: 1, name: 'alpha', full_name: 'me/alpha', private: false }];
    const client = {
      getRepos: vi.fn().mockResolvedValue(mockRepos),
    } as unknown as GithubClient;

    const service = new GithubService(client);

    const result = await service.getRepos();
    expect(result).toEqual(mockRepos);
    expect(client.getRepos).toHaveBeenCalledOnce();
  });
});
```

### Running Tests

```bash
pnpm test                  # Run all tests once (vitest --run)
pnpm test:watch            # Watch mode (re-runs on change)
pnpm test:ci               # Run once with the dot reporter (used by the lefthook pre-push hook)
```

### Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

### Rules

- One concept per test — test a single behavior in each `it()` block
- Mock at boundaries — mock `fetch`, service modules, or integration clients; NEVER mock internal utilities or React internals
- Use Testing Library queries by role/text — `getByRole`, `getByText`, `getByLabelText`; NEVER use `querySelector` or test IDs unless no semantic alternative exists
- Use `userEvent` over `fireEvent` — `userEvent.setup()` simulates real user behavior
- Always clear mocks and globals in `afterEach` — but pick the right reset. `vi.restoreAllMocks()` only undoes `vi.spyOn` spies; it does **nothing** to a standalone `vi.fn()` or to the `vi.fn()`s inside a `vi.mock` factory, so queued `mockResolvedValue`s leak into the next test. Use `vi.resetAllMocks()` whenever the file uses `vi.fn()` / `vi.mock`, `vi.restoreAllMocks()` when it uses `vi.spyOn`, and always pair with `vi.unstubAllGlobals()` if you called `vi.stubGlobal`
- Create a fresh `QueryClient` per test — NEVER share a client across tests (stale cache causes flakes)
- NEVER test implementation details — test what the user sees (components) or what the caller gets (services)
- NEVER test third-party library behavior — test YOUR code's usage of it
- NEVER share mutable state between tests — each test sets up its own data

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards