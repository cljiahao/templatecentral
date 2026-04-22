# Vite + React Template

A production-ready Vite + React SPA starter with TypeScript, Tailwind CSS 4, React Router, TanStack Query, and a feature-driven folder structure.

## Stack

| Feature | Value |
|---------|-------|
| Build | Vite 8 |
| UI | React 19, TypeScript 6 |
| Styling | Tailwind CSS 4, tw-animate-css, shadcn/ui (new-york) |
| Routing | React Router 7 |
| State | TanStack React Query 5 |
| UI Components | shadcn/ui primitives (Radix UI, CVA, Lucide icons) |
| Forms | React Hook Form, @hookform/resolvers, Zod |
| Animation | Framer Motion |
| Auth | AuthProvider context with dev bypass |
| Toasts | Sonner |
| Testing | Vitest, Testing Library |
| Linting | ESLint 9, Prettier (organize-imports + tailwind) |
| Docker | Multi-stage (Vite build → Nginx) |

## Getting Started

```bash
pnpm install
pnpm dev
```

Dev server starts at `http://localhost:3000`.

### Testing

```bash
pnpm test              # Run all tests once
pnpm test:watch        # Watch mode (re-runs on change)
pnpm test:coverage     # Run with coverage report
```

Tests use [Vitest](https://vitest.dev/) + [Testing Library](https://testing-library.com/). Place test files next to source: `example-service.test.ts`, `example-card.test.tsx`.

## Folder Structure

```
src/
├── main.tsx                     # Entry point — renders <App />
├── app.tsx                      # App shell — wraps Providers + Router
├── router.tsx                   # React Router route definitions
├── styles/
│   └── globals.css              # Tailwind config, CSS custom properties, utilities
├── components/
│   ├── layout/                  # App shell: Navbar, Footer, RootLayout, Providers, ErrorBoundary
│   │   └── index.ts
│   ├── ui/                      # shadcn/ui primitives (managed via CLI or manual)
│   └── widgets/                 # Reusable composed components (used by 2+ features)
│       └── index.ts
├── features/                    # Feature modules (self-contained domain areas)
│   ├── auth/                    # Auth feature (AuthProvider, ProtectedRoute, LoginCard, useAuth)
│   └── example/
│       ├── api/                 # Data access services
│       ├── components/          # Feature-specific UI
│       ├── hooks/               # React Query hooks (.query.ts, .mutation.ts)
│       ├── constants.ts         # Static data
│       ├── types.ts             # TypeScript interfaces
│       └── index.ts             # Barrel export
├── lib/                         # Shared infrastructure
│   ├── clients/                 # Base HTTP clients (FetchClient)
│   ├── constants/               # Routes, env vars, app-wide constants
│   ├── errors/                  # APIError class, error logging
│   └── utils/                   # cn() and other pure utilities
├── pages/                       # Page components (thin — compose from features)
│   ├── home.tsx
│   ├── login.tsx
│   ├── dashboard.tsx
│   ├── not-found.tsx
│   └── index.ts
└── test/                        # Vitest setup (setup.ts)
```

### Architecture Principles

- **Feature-driven**: Each domain area lives in `src/features/<name>/` with its own components, hooks, API services, types, and constants.
- **Separation of concerns**: Pages are thin (compose from features), components handle rendering, hooks manage state, services handle data access.
- **Barrel exports**: `index.ts` in every shared folder. Import from barrel outside the feature: `import { X } from '@/features/example'`.
- **Shared infrastructure**: `src/lib/` holds utilities, constants, and error handling used across the app.
- **Component placement**: Feature-only → `features/<name>/components/`; shared by 2+ features → `components/widgets/`; app shell → `components/layout/`.

## UI Component Library

The template includes a full set of shadcn/ui-compatible components in `src/components/ui/`. These are the same components used in the Next.js template, adapted for client-only usage (no `'use client'` directives, no `next-themes`).

### Adding Components via CLI

A `components.json` is included at the project root with `rsc: false` for shadcn CLI compatibility:

```bash
npx shadcn@latest add [component-name]
```

### Included Components

**UI Primitives** (`src/components/ui/`): accordion, avatar, button, button-group, card, checkbox, dialog, dropdown-menu, field, form, input, input-group, label, select, separator, skeleton, sonner, tabs, textarea

**Widgets** (`src/components/widgets/`): brand-text, custom-card, custom-dialog, custom-form-field, link-list, media-card, pill

## Customization

| File | What to Change |
|------|----------------|
| `package.json` | `name`, `version`, add dependencies |
| `index.html` | `<title>`, favicon |
| `src/styles/globals.css` | Theme colors (CSS custom properties) |
| `src/router.tsx` | Add/remove routes |
| `src/components/layout/navbar.tsx` | Brand text, navigation links |
| `src/components/layout/site-footer.tsx` | Credit text |
| `src/lib/constants/routes.ts` | Page and API route definitions |
| `src/lib/constants/env.ts` | Environment variable accessors |
| `.env.example` / `.env` | Environment variables |
| `Dockerfile` | Port, Node version |

## Docker

```bash
# Development
docker build --target dev -t vite-dev .
docker run -p 3000:3000 -v $(pwd):/app vite-dev

# Production (static assets served by Nginx)
docker build --target prod -t vite-prod .
docker run -p 3000:3000 vite-prod
```

Production features: Nginx with security headers, SPA fallback, gzip compression, non-root container user.
