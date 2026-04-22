# Next.js Template

A production-ready Next.js application template with shadcn/ui, Tailwind CSS, and Docker support.

## Stack

- **Next.js 16** with Turbopack dev server
- **React 19** with Server Components (RSC)
- **TypeScript 6**
- **Tailwind CSS 4** with `@tailwindcss/typography` and `tw-animate-css`
- **shadcn/ui** (new-york style, neutral base, Lucide icons)
- **Radix UI** primitives (Dialog, Accordion, Tabs, Select, Avatar, etc.)
- **React Hook Form** + **Zod** for form validation
- **TanStack React Query** for server state management
- **Framer Motion** for animations
- **Sonner** for toast notifications
- **next-themes** for dark/light mode
- **Axios** for HTTP requests
- **Docker** multi-stage build with standalone output

## Project Structure

```
├── test/api/                    # API route handler tests (Vitest)
├── src/proxy.ts                 # Next.js 16 proxy — route protection (auth redirects, 401 for API)
├── .trivyignore.yaml            # Trivy CVE suppressions for Node.js base image
├── Dockerfile                   # Multi-stage build (base → prisma → deps → builder → dev/prod)
├── docker-entrypoint.sh         # Package manager auto-detection (pnpm/yarn/npm)
├── .dockerignore                # Production-optimized Docker ignore
└── src/
    ├── app/                          # Next.js App Router
    │   ├── globals.css               # Tailwind config, CSS variables, utility classes
    │   ├── layout.tsx                # Root layout (Lato + Geist Mono, ThemeProvider, Providers, Toaster)
    │   ├── (public)/                 # Public route group
    │   │   ├── layout.tsx            # Navbar + Footer shell
    │   │   └── page.tsx              # Home page
    │   ├── dashboard/                # Dashboard route group
    │   │   ├── layout.tsx            # Navbar + Footer shell
    │   │   ├── (overview)/           # Overview sub-group
    │   │   │   ├── page.tsx          # Dashboard page
    │   │   │   ├── loading.tsx       # Loading skeleton
    │   │   │   └── error.tsx         # Error boundary with retry
    │   │   └── [id]/                 # Dynamic detail route
    │   │       ├── page.tsx          # Detail page
    │   │       ├── loading.tsx       # Loading skeleton
    │   │       └── not-found.tsx     # 404 page
    │   └── api/
    │       ├── route.ts              # Health check endpoint
    │       └── auth/[...nextauth]/   # NextAuth API handler
    ├── auth.ts                       # NextAuth config (providers, JWT callbacks)
    ├── components/                   # Shared components
    │   ├── layout/                   # Navbar, SiteFooter, Providers, ThemeProvider
    │   ├── ui/                       # shadcn/ui components (20+ components)
    │   └── widgets/                  # Reusable widgets (see below)
    ├── features/                     # Domain-specific feature modules
    │   ├── auth/                     # Auth feature (LoginCard, LoginButton, SignOutButton)
    │   └── example/                  # Example feature (reference implementation)
    │       ├── api/                  # Client-side data access (fetch calls to /api/*)
    │       ├── components/           # Feature-specific UI
    │       ├── hooks/                # React hooks (queries, mutations)
    │       ├── schemas/              # Zod validation schemas
    │       ├── constants.ts          # Static data
    │       ├── types.ts              # TypeScript types
    │       └── index.ts              # Barrel export
    ├── integrations/                 # External service clients
    │   ├── error.ts                  # APIError class
    │   ├── factories.ts              # Service factory functions
    │   ├── clients/                  # Thin HTTP clients
    │   ├── schemas/                  # Zod schemas for external responses
    │   └── services/                 # Business logic wrapping clients
    └── lib/                          # Shared utilities
        ├── utils/                    # cn(), mergeHandlers()
        ├── constants/                # Routes, env, avatar colors
        └── errors/                   # Error logging and API error handler
```

## Getting Started

```bash
pnpm install
pnpm dev
```

The dev server starts at `http://localhost:3000` with Turbopack.

## Testing

```bash
pnpm test                  # Run all tests once
pnpm test:watch            # Watch mode (re-runs on change)
pnpm test:coverage         # Run with coverage report
```

Tests live in `test/api/` and cover API route handlers (backend only). See `claude-skills/nextjs/add-test/SKILL.md` for conventions.

## Docker

```bash
# Development (hot reload)
docker build --target dev -t my-app:dev .
docker run -p 3000:3000 -v $(pwd):/app my-app:dev

# Production (standalone)
docker build --target prod -t my-app:prod .
docker run -p 3000:3000 my-app:prod
```

The Dockerfile supports optional Prisma — if a `prisma/` directory exists, it's automatically included in the build.

## Included Components

### Layout
- `Navbar` — Responsive navigation with brand text and link list
- `SiteFooter` — Footer with credit text and links
- `Providers` — SessionProvider + React Query provider wrapper
- `ThemeProvider` — next-themes wrapper

### UI (shadcn/ui)
Accordion, Avatar, Button, ButtonGroup, Card, Checkbox, Dialog, DropdownMenu, Field, Form, Input, InputGroup, Label, Select, Separator, Skeleton, Sonner, Tabs, Textarea, Dropzone

### Widgets
- `BrandLogo` — Logo image component (uses `next/image`)
- `BrandText` — Brand text with gradient styling
- `CustomCard` — Card with configurable header/description
- `CustomDialog` — Dialog with trigger/title/description
- `CustomFormField` — React Hook Form field with validation
- `FloatingShape` — Animated floating image with Framer Motion
- `LinkList` — Reusable link list component
- `MediaCard` — Card with configurable media position (top/bottom/left/right)
- `Pill` — Gradient pill badge (outline or solid variant)
- `ThemeToggleButton` — Animated dark/light toggle

## Quality Scripts

```bash
pnpm format          # Format with Prettier
pnpm format:check    # Check formatting
pnpm lint            # ESLint
pnpm lint:fix        # ESLint autofix
pnpm typecheck       # TypeScript check
pnpm check           # Run all checks
```

## Customization Points

- `globals.css` — Theme colors (neutral palette by default), CSS custom properties
- `layout.tsx` — Fonts, metadata, default theme
- `src/proxy.ts` — Next.js 16 proxy for route protection (`export const proxy = auth(...)`)
- `lib/constants/routes.ts` — Page and API routes
- `components.json` — shadcn/ui style and color preferences
- `Dockerfile` — Port, Node version, timezone
- `.env.example` — Environment variables
- `.trivyignore.yaml` — Trivy CVE suppressions
