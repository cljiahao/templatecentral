---
name: nextjs-add-component
description: Use when creating a new React component and unsure whether it belongs in features/, widgets/, layout/, or ui/, or when adding a shared component with barrel exports.
---

# Add a Component

Create a new component in a Next.js project scaffolded from templateCentral.

## Inputs

- **Component name** — PascalCase name (e.g., `StatusBadge`, `UserAvatar`)
- **Component type** — Where it belongs (feature, widget, layout, UI)

## Decision Guide

First, determine where the component belongs:

| Scenario | Location | Example |
|----------|----------|---------|
| Used by one feature only | `src/features/<name>/components/` | `ProjectCard` in `features/project` |
| Used by 2+ features | `src/components/widgets/` | `StatusBadge` used by project + dashboard |
| Low-level primitive | `src/components/ui/` (use shadcn CLI) | `Button`, `Input`, `Dialog` |
| App shell | `src/components/layout/` | `Navbar`, `SiteFooter` |

## Steps

### 1. Create the Component File

Use kebab-case for the filename, PascalCase for the export:

```tsx
// src/components/widgets/status-badge.tsx
import { cn } from '@/lib/utils';

interface StatusBadgeProps {
  status: 'active' | 'inactive' | 'pending';
  className?: string;
}

export function StatusBadge({ status, className }: StatusBadgeProps) {
  return (
    <span className={cn(
      'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
      status === 'active' && 'bg-emerald-100 text-emerald-800',
      status === 'inactive' && 'bg-gray-100 text-gray-800',
      status === 'pending' && 'bg-yellow-100 text-yellow-800',
      className
    )}>
      {status}
    </span>
  );
}
```

### 2. Export from Barrel

Add the export to the folder's `index.ts`:

```ts
// src/components/widgets/index.ts
export { StatusBadge } from './status-badge';
```

### 3. Adding a shadcn/ui Component

For low-level UI primitives, use the shadcn CLI:

```bash
npx shadcn@latest add <component-name>
```

This installs into `src/components/ui/`. Do not manually create UI primitives.

> For component patterns (`function` vs `const`, `React.memo`, composition over configuration, static data in constants), see `code-standards/SKILL.md`.

### 4. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors.

## Rules

- Don't prematurely extract — keep inline until a second consumer needs it. NEVER extract to `widgets/` until it has a second consumer
- NEVER add boolean flag props to configure variants — prefer composition with children

## Validate

```bash
pnpm build    # zero errors
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
