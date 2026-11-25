<!-- ref: add/test/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = Vite + React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React

Apply the test-value rule (`docs/CONSTITUTION.md` §4).

### Steps

**Context check:** Confirm `src/features/` or `src/components/` contains at least
one `.tsx` file. If not, stop and tell the user: "No components or features found. Add some
using `templatecentral:add` (feature) or `templatecentral:add` (component)
first, then return here."

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

Vitest has `globals: true` — `describe`, `it`, `expect` need no import (explicit imports also work).

### Component Tests

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

  it('renders the project name and description', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('Alpha')).toBeInTheDocument();
    expect(screen.getByText('First project')).toBeInTheDocument();
  });
});
```

### Component Tests with User Interaction

Use `userEvent.setup()` with `await user.*`, not `fireEvent`. The scaffold does not ship `@testing-library/user-event`:

```bash
pnpm add -D @testing-library/user-event
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
    // Bare array body, no `{ data }` envelope, with every required projectItemSchema field since getAll() parses it.
    const projects = [{ id: '1', name: 'Alpha', description: null }];
    // Response.json sets application/json; a bare `new Response(JSON.stringify(...))` is text/plain and fails .parse().
    mockFetch.mockResolvedValue(Response.json(projects));

    const result = await ProjectService.getAll();
    expect(result).toEqual(projects);
  });
});
```

### React Query Hook Tests

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

Integration services (`src/integrations/services/`) take their client by constructor injection — test them with a stub client, no module mocking. Stub the client as an object of `vi.fn()` methods cast to the client type, pass it to the constructor, and assert the client was called.

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

- Reset in `afterEach`: `vi.resetAllMocks()` when the file uses `vi.fn()` / `vi.mock` (`vi.restoreAllMocks()` only undoes `vi.spyOn`, so queued values leak), `vi.restoreAllMocks()` for `vi.spyOn`, plus `vi.unstubAllGlobals()` after `vi.stubGlobal`
- Query by role or text, not `querySelector`; create a fresh `QueryClient` per test
