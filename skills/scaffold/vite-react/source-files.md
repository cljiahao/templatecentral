<!-- ref: scaffold/vite-react/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part C — Verbatim Source Files

### `src/main.tsx`

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from '@/app';
import '@/styles/globals.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

### `src/app.tsx`

```tsx
import { ErrorBoundary, Providers } from '@/components/layout';
import { AppRouter } from '@/router';

export function App() {
  return (
    <ErrorBoundary>
      <Providers>
        <AppRouter />
      </Providers>
    </ErrorBoundary>
  );
}
```

### `src/router.tsx`

```tsx
import { RootLayout } from '@/components/layout';
import { ProtectedRoute } from '@/features/auth';
import { DashboardPage } from '@/pages/dashboard';
import { HomePage } from '@/pages/home';
import { LoginPage } from '@/pages/login';
import { NotFoundPage } from '@/pages/not-found';
import { BrowserRouter, Route, Routes } from 'react-router';

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<RootLayout />}>
          {/* Public routes */}
          <Route index element={<HomePage />} />
          <Route path="login" element={<LoginPage />} />

          {/* Protected routes */}
          <Route element={<ProtectedRoute />}>
            <Route path="dashboard" element={<DashboardPage />} />
          </Route>

          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
```

### `src/styles/globals.css`

```css
@import 'tailwindcss';
@plugin '@tailwindcss/typography';
@import 'tw-animate-css';

@theme inline {
  /* Fonts & radius */
  --font-sans: 'Inter', ui-sans-serif, system-ui, sans-serif;
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);

  /* App colors */
  --color-black: var(--black);
  --color-white: var(--white);

  /* Surface */
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-popover: var(--popover);
  --color-popover-foreground: var(--popover-foreground);

  /* Actions */
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-primary-hover: var(--primary-hover);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-secondary-hover: var(--secondary-hover);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-accent-hover: var(--accent-hover);

  /* Feedback */
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-destructive: var(--destructive);
  --color-destructive-foreground: var(--destructive-foreground);

  /* Borders & inputs */
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);

  /* Max content width */
  --max-w-site: 1280px;
}

:root {
  --radius: 0.625rem;

  /* Core palette — neutral */
  --black: oklch(0 0 0);
  --white: oklch(1 0 0);

  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);

  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --primary-hover: oklch(0.3 0 0);

  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --secondary-hover: oklch(0.92 0 0);

  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --accent-hover: oklch(0.92 0 0);

  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);

  --destructive: oklch(0.577 0.245 27.325);
  --destructive-foreground: oklch(0.577 0.245 27.325);

  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
}

* {
  border-color: var(--border);
}

body {
  background-color: var(--background);
  color: var(--foreground);
  font-family: var(--font-sans);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Utility classes */
@utility max-w-site {
  max-width: var(--max-w-site);
}

@utility max-w-content {
  max-width: 1000px;
}

@utility flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

@utility flex-between {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

@utility flex-start {
  display: flex;
  align-items: flex-start;
  justify-content: flex-start;
}

@utility flex-end {
  display: flex;
  justify-content: flex-end;
}

@utility hw-full {
  height: 100%;
  width: 100%;
}

@utility bg-brand-gradient {
  background-image: linear-gradient(to right, var(--primary), var(--primary), var(--primary));
}

@utility text-brand-gradient {
  background-image: linear-gradient(to right, var(--primary), var(--primary), var(--primary));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* Scrollbar */
.no-scrollbar::-webkit-scrollbar {
  display: none;
}

.no-scrollbar {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
```

### `src/test/setup.ts`

```ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

### `src/hooks/index.ts`

```ts
// Shared hooks (used by shadcn/ui components that auto-generate hook dependencies).
// Feature-specific hooks live in src/features/<name>/hooks/.
```

### `src/pages/index.ts`

```ts
export { DashboardPage } from './dashboard';
export { HomePage } from './home';
export { LoginPage } from './login';
export { NotFoundPage } from './not-found';
```

### `src/pages/home.tsx`

Update `"Vite + React Template"` to the project name during scaffolding.

```tsx
import { Link } from 'react-router';
import { PAGE_ROUTES } from '@/lib/constants/routes';

export function HomePage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-16">
      <div className="flex flex-col items-center gap-6 text-center">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">Vite + React Template</h1>
        <p className="max-w-xl text-lg text-muted-foreground">
          A production-ready starter with React Router, TanStack Query, Tailwind CSS, and a
          feature-driven folder structure.
        </p>
        <Link
          to={PAGE_ROUTES.DASHBOARD}
          className="rounded-lg bg-primary px-6 py-3 font-semibold text-primary-foreground transition-colors hover:bg-primary-hover"
        >
          Go to Dashboard
        </Link>
      </div>
    </div>
  );
}
```

### `src/pages/login.tsx`

```tsx
import { LoginCard } from '@/features/auth';

export function LoginPage() {
  return (
    <div className="flex-center min-h-screen">
      <LoginCard />
    </div>
  );
}
```

### `src/pages/dashboard.tsx`

```tsx
import { ExampleList } from '@/features/example';

export function DashboardPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-muted-foreground">
        This page demonstrates the feature module pattern with TanStack Query.
      </p>

      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```

### `src/pages/not-found.tsx`

```tsx
import { Link } from 'react-router';
import { PAGE_ROUTES } from '@/lib/constants/routes';

export function NotFoundPage() {
  return (
    <div className="flex-center min-h-[60vh] flex-col gap-4">
      <h1 className="text-6xl font-bold">404</h1>
      <p className="text-lg text-muted-foreground">Page not found</p>
      <Link
        to={PAGE_ROUTES.HOME}
        className="mt-2 text-sm font-medium text-primary underline underline-offset-4 hover:text-primary-hover"
      >
        Go back home
      </Link>
    </div>
  );
}
```

### `src/features/auth/index.ts`

```ts
export { AuthProvider, LoginCard, ProtectedRoute } from './components';
export { useAuth } from './hooks';
export type { AuthState, AuthUser } from './types';
```

### `src/features/auth/types.ts`

```ts
export interface AuthUser {
  id: string;
  name: string;
  email: string;
  image?: string | null;
}

export interface AuthState {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}
```

### `src/features/auth/components/index.ts`

```ts
export { AuthProvider } from './auth-provider';
export { LoginCard } from './login-card';
export { ProtectedRoute } from './protected-route';
```

### `src/features/auth/components/auth-provider.tsx`

```tsx
import { ENV } from '@/lib/constants/env';
import { createContext, useCallback, useMemo, useState, type ReactNode } from 'react';
import type { AuthUser } from '../types';

const DEV_USER: AuthUser = {
  id: 'dev',
  name: 'Dev User',
  email: 'dev@local',
};

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (user: AuthUser) => void;
  logout: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<AuthUser | null>(
    // Dev bypass: in development, skip the API call and use a mock user.
    // Remove this block before going to production.
    ENV.IS_DEV ? DEV_USER : null
  );
  const [isLoading] = useState(false);

  const login = useCallback((authUser: AuthUser) => {
    setUser(authUser);
  }, []);

  const logout = useCallback(async () => {
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({
      user,
      isAuthenticated: !!user,
      isLoading,
      login,
      logout,
    }),
    [user, isLoading, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

### `src/features/auth/components/login-card.tsx`

```tsx
import { CustomCard } from '@/components/widgets';
import { ENV } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useNavigate } from 'react-router';
import { useAuth } from '../hooks/use-auth';

export function LoginCard() {
  const { login } = useAuth();
  const navigate = useNavigate();

  const handleDevLogin = () => {
    login({ id: 'dev', name: 'Dev User', email: 'dev@local' });
    navigate(PAGE_ROUTES.DASHBOARD);
  };

  return (
    <CustomCard
      header="Sign In"
      description="Choose a sign-in method to continue."
      className="w-full max-w-md shadow-lg"
    >
      <div className="flex flex-col gap-4">
        {/* Add your SSO / OAuth login button here */}
        {ENV.IS_DEV && (
          <button
            type="button"
            className="rounded-md border-2 bg-white px-4 py-3 text-sm text-gray-500 hover:bg-gray-100"
            onClick={handleDevLogin}
          >
            Dev login (bypass auth)
          </button>
        )}
      </div>
    </CustomCard>
  );
}
```

### `src/features/auth/components/protected-route.tsx`

```tsx
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { Navigate, Outlet } from 'react-router';
import { useAuth } from '../hooks/use-auth';

export function ProtectedRoute() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex-center min-h-screen">
        <p className="text-muted-foreground">Loading...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to={PAGE_ROUTES.LOGIN} replace />;
  }

  return <Outlet />;
}
```

### `src/features/auth/hooks/index.ts`

```ts
export { useAuth } from './use-auth';
```

### `src/features/auth/hooks/use-auth.ts`

```ts
import { useContext } from 'react';
import { AuthContext } from '../components/auth-provider';

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
```

### `src/features/example/index.ts`

```ts
export * from './components';
export * from './hooks';
export * from './constants';
export type { ExampleItem } from './types';
```

### `src/features/example/types.ts`

```ts
export interface ExampleItem {
  id: string;
  title: string;
  description: string;
}
```

### `src/features/example/constants.ts`

```ts
export const EXAMPLE_ITEMS = [
  { id: 'item-1', title: 'First Item', description: 'Description for the first item' },
  { id: 'item-2', title: 'Second Item', description: 'Description for the second item' },
  { id: 'item-3', title: 'Third Item', description: 'Description for the third item' },
] as const;
```

### `src/features/example/api/index.ts`

```ts
export { ExampleService } from './example-service';
```

### `src/features/example/api/example-service.ts`

```ts
import { EXAMPLE_ITEMS } from '../constants';
import type { ExampleItem } from '../types';

export const ExampleService = {
  getAll: (): ExampleItem[] => {
    return [...EXAMPLE_ITEMS];
  },

  getById: (id: string): ExampleItem | undefined => {
    return EXAMPLE_ITEMS.find((item) => item.id === id);
  },
};
```

### `src/features/example/api/example-service.test.ts`

```ts
import { describe, expect, it } from 'vitest';
import { ExampleService } from './example-service';

describe('ExampleService', () => {
  it('returns all example items', () => {
    const items = ExampleService.getAll();
    expect(items).toHaveLength(3);
    expect(items[0]).toHaveProperty('id');
    expect(items[0]).toHaveProperty('title');
  });

  it('returns a copy, not the original array', () => {
    const a = ExampleService.getAll();
    const b = ExampleService.getAll();
    expect(a).not.toBe(b);
    expect(a).toEqual(b);
  });

  it('finds an item by id', () => {
    const item = ExampleService.getById('item-1');
    expect(item).toBeDefined();
    expect(item?.title).toBe('First Item');
  });

  it('returns undefined for unknown id', () => {
    const item = ExampleService.getById('nonexistent');
    expect(item).toBeUndefined();
  });
});
```

### `src/features/example/components/index.ts`

```ts
export { ExampleCard } from './example-card';
export { ExampleList } from './example-list';
```

### `src/features/example/components/example-card.tsx`

```tsx
import { CustomCard } from '@/components/widgets';
import type { ExampleItem } from '../types';

interface ExampleCardProps {
  item: ExampleItem;
}

export function ExampleCard({ item }: ExampleCardProps) {
  return <CustomCard header={item.title} description={item.description} />;
}
```

### `src/features/example/components/example-card.test.tsx`

```tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ExampleCard } from './example-card';

describe('ExampleCard', () => {
  const mockItem = {
    id: 'test-1',
    title: 'Test Title',
    description: 'Test description text',
  };

  it('renders the item title and description', () => {
    render(<ExampleCard item={mockItem} />);
    expect(screen.getByText('Test Title')).toBeInTheDocument();
    expect(screen.getByText('Test description text')).toBeInTheDocument();
  });
});
```

### `src/features/example/components/example-list.tsx`

```tsx
import { useExampleItems } from '../hooks';
import { ExampleCard } from './example-card';

export function ExampleList() {
  const { data: items, isPending, error } = useExampleItems();

  if (isPending) {
    return <p className="text-muted-foreground">Loading...</p>;
  }

  if (error) {
    return <p className="text-destructive">Failed to load items.</p>;
  }

  if (!items?.length) {
    return <p className="text-muted-foreground">No items found.</p>;
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <ExampleCard key={item.id} item={item} />
      ))}
    </div>
  );
}
```

### `src/features/example/hooks/index.ts`

```ts
export { useExampleItems } from './use-example-items.query';
```

### `src/features/example/hooks/use-example-items.query.ts`

```ts
import { useQuery } from '@tanstack/react-query';
import { ExampleService } from '../api';

export const useExampleItems = () => {
  return useQuery({
    queryKey: ['example-items'],
    queryFn: () => ExampleService.getAll(),
  });
};
```

### `src/features/example/schemas/index.ts`

Empty file — placeholder for Zod schemas added by the `templatecentral:add` (feature) skill.

### `src/components/layout/index.ts`

```ts
export { Navbar } from './navbar';
export { Providers } from './providers';
export { RootLayout } from './root-layout';
export { SiteFooter } from './site-footer';
export { ErrorBoundary } from './error-boundary';
```

### `src/components/layout/error-boundary.tsx`

```tsx
import { Component, type ErrorInfo, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    if (import.meta.env.DEV) {
      console.error('ErrorBoundary caught an error:', error, errorInfo);
    }
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-2xl font-bold">Something went wrong</h1>
          <p className="text-muted-foreground max-w-md text-sm">
            {import.meta.env.DEV
              ? (this.state.error?.message ?? 'An unexpected error occurred.')
              : 'An unexpected error occurred.'}
          </p>
          <button
            type="button"
            onClick={this.handleRetry}
            className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-4 py-2 text-sm font-medium transition-colors"
          >
            Try again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

### `src/components/layout/navbar.tsx`

Replace `templateCentral` with the project name during scaffolding.

```tsx
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';
import { Link, useLocation } from 'react-router';

const NAV_LINKS = [
  { label: 'Home', href: PAGE_ROUTES.HOME },
  { label: 'Dashboard', href: PAGE_ROUTES.DASHBOARD },
] as const;

export function Navbar() {
  const { pathname } = useLocation();

  return (
    <nav className="sticky top-0 z-50 w-full border-b bg-white">
      <div className="max-w-site flex-between mx-auto px-6 py-4">
        <Link to={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          templateCentral
        </Link>

        <div className="flex gap-6">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              to={link.href}
              className={cn(
                'text-sm font-medium transition-colors hover:text-primary',
                pathname === link.href ? 'text-primary' : 'text-muted-foreground'
              )}
            >
              {link.label}
            </Link>
          ))}
        </div>
      </div>
    </nav>
  );
}
```

### `src/components/layout/providers.tsx`

```tsx
import { AuthProvider } from '@/features/auth';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { Toaster } from 'sonner';

interface ProvidersProps {
  children: ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            refetchOnWindowFocus: false,
          },
        },
      })
  );

  return (
    <AuthProvider>
      <QueryClientProvider client={queryClient}>
        {children}
        <Toaster position="top-right" />
      </QueryClientProvider>
    </AuthProvider>
  );
}
```

### `src/components/layout/root-layout.tsx`

```tsx
import { Outlet } from 'react-router';
import { Navbar } from './navbar';
import { SiteFooter } from './site-footer';

export function RootLayout() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        <Outlet />
      </main>
      <SiteFooter />
    </div>
  );
}
```

### `src/components/layout/site-footer.tsx`

Update `creditText` default to project name during scaffolding.

```tsx
interface SiteFooterProps {
  creditText?: string;
}

export function SiteFooter({ creditText = 'Built with templateCentral' }: SiteFooterProps) {
  return (
    <footer className="w-full border-t bg-black">
      <div className="max-w-site mx-auto px-6 py-6">
        <p className="text-sm text-white">{creditText}</p>
      </div>
    </footer>
  );
}
```

### `src/components/widgets/index.ts`

```ts
export { BrandText } from './brand-text';
export { CustomCard } from './custom-card';
export { CustomDialog } from './custom-dialog';
export { CustomFormField } from './custom-form-field';
export { LinkList, type LinkItem } from './link-list';
export { MediaCard } from './media-card';
export { Pill } from './pill';
```

### `src/components/widgets/brand-text.tsx`

```tsx
import { cn } from '@/lib/utils';

interface BrandTextProps {
  className?: string;
}

export function BrandText({ className }: BrandTextProps) {
  return (
    <>
      <span className="text-brand-gradient">template</span>
      <span className={cn('text-white', className)}>Central</span>
    </>
  );
}
```

### `src/components/widgets/custom-card.tsx`

```tsx
import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';

interface CustomCardProps {
  header: string;
  description?: string;
  children?: ReactNode;
  className?: string;
}

export function CustomCard({ header, description, children, className }: CustomCardProps) {
  return (
    <div className={cn('rounded-lg border bg-white p-6 shadow-xs', className)}>
      <h3 className="text-lg font-semibold">{header}</h3>
      {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}
```

### `src/components/widgets/custom-dialog.tsx`

```tsx
import type { ComponentProps, ReactNode } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';

interface CustomDialogProps extends Omit<
  ComponentProps<typeof Dialog>,
  'children'
> {
  className?: string;
  children: ReactNode;
  trigger?: ReactNode;
  title?: ReactNode;
  description?: ReactNode;
}

export function CustomDialog({
  className,
  trigger,
  title,
  description,
  children,
  ...dialogProps
}: CustomDialogProps) {
  return (
    <Dialog {...dialogProps}>
      {trigger && <DialogTrigger asChild>{trigger}</DialogTrigger>}
      <DialogContent className={cn('flex h-full w-full flex-col', className)}>
        <DialogHeader>
          {title ? (
            <DialogTitle>{title}</DialogTitle>
          ) : (
            <DialogTitle className="sr-only">Dialog</DialogTitle>
          )}
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
      </DialogContent>
    </Dialog>
  );
}
```

### `src/components/widgets/custom-form-field.tsx`

```tsx
import { cloneElement, type ReactElement } from 'react';
import { Controller, useFormContext } from 'react-hook-form';

import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from '@/components/ui/field';

interface CustomFormFieldProps {
  name: string;
  label: string;
  description?: string;
  children: ReactElement<Record<string, unknown>>;
}

export function CustomFormField({
  name,
  label,
  description,
  children,
}: CustomFormFieldProps) {
  const { control } = useFormContext();

  return (
    <Controller
      name={name}
      control={control}
      render={({ field: { ref, ...field }, fieldState }) => (
        <Field data-invalid={fieldState.invalid}>
          <FieldLabel
            htmlFor={name}
            className="text-foreground text-lg leading-tight font-semibold tracking-tight"
          >
            {label}
          </FieldLabel>
          {cloneElement(children, {
            id: name,
            ref,
            'aria-invalid': fieldState.invalid,
            ...field,
          })}
          {description && <FieldDescription>{description}</FieldDescription>}
          {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
        </Field>
      )}
    />
  );
}
```

### `src/components/widgets/link-list.tsx`

```tsx
import { cn } from '@/lib/utils';

export interface LinkItem {
  label: string;
  href: string;
  target?: string;
}

interface LinkListProps {
  links: LinkItem[];
  className?: string;
}

export function LinkList({ links, className }: LinkListProps) {
  return (
    <div className="flex items-center gap-6">
      {links.map((link) => (
        <a
          key={link.label}
          href={link.href}
          target={link.target}
          rel={link.target === '_blank' ? 'noopener noreferrer' : undefined}
          className={cn(
            'hover:text-primary font-semibold transition-colors',
            className
          )}
        >
          {link.label}
        </a>
      ))}
    </div>
  );
}
```

### `src/components/widgets/media-card.tsx`

```tsx
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';

type MediaPosition = 'top' | 'bottom' | 'left' | 'right';

interface MediaCardProps {
  className?: string;
  children?: ReactNode;
  title: string;
  description?: string;
  descClassName?: string;
  /** Where the media (children) is placed relative to the text. @default "top" */
  mediaPosition?: MediaPosition;
}

interface LayoutStyles {
  card: string;
  content: string;
  header: string;
  text: string;
}

const VERTICAL: Omit<LayoutStyles, 'card'> = {
  content: 'hw-full',
  header: 'flex-center hw-full',
  text: 'text-center',
};

const HORIZONTAL: Omit<LayoutStyles, 'card'> = {
  content: 'flex-1',
  header: 'flex-1',
  text: 'text-left',
};

const LAYOUT: Record<MediaPosition, LayoutStyles> = {
  top: { card: 'flex-col', ...VERTICAL },
  bottom: { card: 'flex-col-reverse', ...VERTICAL },
  left: { card: 'flex-row items-center gap-8', ...HORIZONTAL },
  right: { card: 'flex-row-reverse items-center gap-8', ...HORIZONTAL },
};

export function MediaCard({
  className,
  children,
  title,
  description,
  descClassName,
  mediaPosition = 'top',
}: MediaCardProps) {
  const { card, content, header, text } = LAYOUT[mediaPosition];

  return (
    <div className="bg-brand-gradient rounded-lg p-px">
      <Card className={cn('flex h-full w-full p-2', card, className)}>
        {children && (
          <CardContent className={cn('flex-center', content)}>
            {children}
          </CardContent>
        )}
        <CardHeader
          className={cn('flex-col gap-3', header, !children && 'flex-center')}
        >
          <CardTitle className={text}>{title}</CardTitle>
          {description && (
            <CardDescription className={cn('text-wrap', text, descClassName)}>
              {description}
            </CardDescription>
          )}
        </CardHeader>
      </Card>
    </div>
  );
}
```

### `src/components/widgets/pill.tsx`

```tsx
import type { ReactNode } from 'react';

import { cn } from '@/lib/utils';

interface PillProps {
  children: ReactNode;
  variant?: 'outline' | 'solid';
}

export function Pill({ children, variant = 'outline' }: PillProps) {
  return (
    <div className="bg-brand-gradient inline-block rounded-full p-px">
      <span
        className={cn(
          'inline-block rounded-full px-4 py-1.5 text-sm font-medium',
          variant === 'solid'
            ? 'text-background'
            : 'bg-card text-muted-foreground'
        )}
      >
        {children}
      </span>
    </div>
  );
}
```

### `src/components/ui/button-group.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import type { ComponentProps } from 'react';

import { cva, type VariantProps } from 'class-variance-authority';
import { Slot } from '@radix-ui/react-slot';

import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils/index';

const buttonGroupVariants = cva(
  "flex w-fit items-stretch [&>*]:focus-visible:z-10 [&>*]:focus-visible:relative [&>[data-slot=select-trigger]:not([class*='w-'])]:w-fit [&>input]:flex-1 has-[select[aria-hidden=true]:last-child]:[&>[data-slot=select-trigger]:last-of-type]:rounded-r-md has-[>[data-slot=button-group]]:gap-2",
  {
    variants: {
      orientation: {
        horizontal:
          '[&>*:not(:first-child)]:rounded-l-none [&>*:not(:first-child)]:border-l-0 [&>*:not(:last-child)]:rounded-r-none',
        vertical:
          'flex-col [&>*:not(:first-child)]:rounded-t-none [&>*:not(:first-child)]:border-t-0 [&>*:not(:last-child)]:rounded-b-none',
      },
    },
    defaultVariants: {
      orientation: 'horizontal',
    },
  }
);

function ButtonGroup({
  className,
  orientation,
  ...props
}: ComponentProps<'div'> & VariantProps<typeof buttonGroupVariants>) {
  return (
    <div
      role="group"
      data-slot="button-group"
      data-orientation={orientation}
      className={cn(buttonGroupVariants({ orientation }), className)}
      {...props}
    />
  );
}

function ButtonGroupText({
  className,
  asChild = false,
  ...props
}: ComponentProps<'div'> & {
  asChild?: boolean;
}) {
  const Comp = asChild ? Slot.Root : 'div';

  return (
    <Comp
      className={cn(
        "bg-muted flex items-center gap-2 rounded-md border px-4 text-sm font-medium shadow-xs [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    />
  );
}

function ButtonGroupSeparator({
  className,
  orientation = 'vertical',
  ...props
}: ComponentProps<typeof Separator>) {
  return (
    <Separator
      data-slot="button-group-separator"
      orientation={orientation}
      className={cn(
        'bg-input relative !m-0 self-stretch data-[orientation=vertical]:h-auto',
        className
      )}
      {...props}
    />
  );
}

export {
  ButtonGroup,
  ButtonGroupSeparator,
  ButtonGroupText,
  buttonGroupVariants,
};
```

### `src/components/ui/field.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import type { ComponentProps, ReactNode } from 'react';
import { useMemo } from 'react';

import { cva, type VariantProps } from 'class-variance-authority';

import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';

function FieldSet({ className, ...props }: ComponentProps<'fieldset'>) {
  return (
    <fieldset
      data-slot="field-set"
      className={cn(
        'flex flex-col gap-6',
        'has-[>[data-slot=checkbox-group]]:gap-3 has-[>[data-slot=radio-group]]:gap-3',
        className
      )}
      {...props}
    />
  );
}

function FieldLegend({
  className,
  variant = 'legend',
  ...props
}: ComponentProps<'legend'> & { variant?: 'legend' | 'label' }) {
  return (
    <legend
      data-slot="field-legend"
      data-variant={variant}
      className={cn(
        'mb-3 font-medium',
        'data-[variant=legend]:text-base',
        'data-[variant=label]:text-sm',
        className
      )}
      {...props}
    />
  );
}

function FieldGroup({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-group"
      className={cn(
        'group/field-group @container/field-group flex w-full flex-col gap-7 data-[slot=checkbox-group]:gap-3 [&>[data-slot=field-group]]:gap-4',
        className
      )}
      {...props}
    />
  );
}

const fieldVariants = cva(
  'group/field flex w-full gap-3 data-[invalid=true]:text-destructive',
  {
    variants: {
      orientation: {
        vertical: ['flex-col [&>*]:w-full [&>.sr-only]:w-auto'],
        horizontal: [
          'flex-row items-center',
          '[&>[data-slot=field-label]]:flex-auto',
          'has-[>[data-slot=field-content]]:items-start has-[>[data-slot=field-content]]:[&>[role=checkbox],[role=radio]]:mt-px',
        ],
        responsive: [
          'flex-col [&>*]:w-full [&>.sr-only]:w-auto @md/field-group:flex-row @md/field-group:items-center @md/field-group:[&>*]:w-auto',
          '@md/field-group:[&>[data-slot=field-label]]:flex-auto',
          '@md/field-group:has-[>[data-slot=field-content]]:items-start @md/field-group:has-[>[data-slot=field-content]]:[&>[role=checkbox],[role=radio]]:mt-px',
        ],
      },
    },
    defaultVariants: {
      orientation: 'vertical',
    },
  }
);

function Field({
  className,
  orientation = 'vertical',
  ...props
}: ComponentProps<'div'> & VariantProps<typeof fieldVariants>) {
  return (
    <div
      role="group"
      data-slot="field"
      data-orientation={orientation}
      className={cn(fieldVariants({ orientation }), className)}
      {...props}
    />
  );
}

function FieldContent({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-content"
      className={cn(
        'group/field-content flex flex-1 flex-col gap-1.5 leading-snug',
        className
      )}
      {...props}
    />
  );
}

function FieldLabel({
  className,
  ...props
}: ComponentProps<typeof Label>) {
  return (
    <Label
      data-slot="field-label"
      className={cn(
        'group/field-label peer/field-label flex w-fit gap-2 leading-snug group-data-[disabled=true]/field:opacity-50',
        'has-[>[data-slot=field]]:w-full has-[>[data-slot=field]]:flex-col has-[>[data-slot=field]]:rounded-md has-[>[data-slot=field]]:border [&>*]:data-[slot=field]:p-4',
        'has-data-[state=checked]:bg-primary/5 has-data-[state=checked]:border-primary',
        className
      )}
      {...props}
    />
  );
}

function FieldTitle({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-label"
      className={cn(
        'flex w-fit items-center gap-2 text-sm leading-snug font-medium group-data-[disabled=true]/field:opacity-50',
        className
      )}
      {...props}
    />
  );
}

function FieldDescription({ className, ...props }: ComponentProps<'p'>) {
  return (
    <p
      data-slot="field-description"
      className={cn(
        'text-muted-foreground text-sm leading-normal font-normal group-has-[[data-orientation=horizontal]]/field:text-balance',
        'last:mt-0 nth-last-2:-mt-1 [[data-variant=legend]+&]:-mt-1.5',
        '[&>a:hover]:text-primary [&>a]:underline [&>a]:underline-offset-4',
        className
      )}
      {...props}
    />
  );
}

function FieldSeparator({
  children,
  className,
  ...props
}: ComponentProps<'div'> & {
  children?: ReactNode;
}) {
  return (
    <div
      data-slot="field-separator"
      data-content={!!children}
      className={cn(
        'relative -my-2 h-5 text-sm group-data-[variant=outline]/field-group:-mb-2',
        className
      )}
      {...props}
    >
      <Separator className="absolute inset-0 top-1/2" />
      {children && (
        <span
          className="bg-background text-muted-foreground relative mx-auto block w-fit px-2"
          data-slot="field-separator-content"
        >
          {children}
        </span>
      )}
    </div>
  );
}

function FieldError({
  className,
  children,
  errors,
  ...props
}: ComponentProps<'div'> & {
  errors?: Array<{ message?: string } | undefined>;
}) {
  const content = useMemo(() => {
    if (children) {
      return children;
    }

    if (!errors?.length) {
      return null;
    }

    if (errors?.length == 1) {
      return errors[0]?.message;
    }

    return (
      <ul className="ml-4 flex list-disc flex-col gap-1">
        {errors.map(
          (error, index) =>
            error?.message && <li key={index}>{error.message}</li>
        )}
      </ul>
    );
  }, [children, errors]);

  if (!content) {
    return null;
  }

  return (
    <div
      role="alert"
      data-slot="field-error"
      className={cn('text-destructive text-sm font-normal', className)}
      {...props}
    >
      {content}
    </div>
  );
}

export {
  Field,
  FieldContent,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldLegend,
  FieldSeparator,
  FieldSet,
  FieldTitle,
};
```

### `src/components/ui/input-group.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import * as React from 'react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils/index';

function InputGroup({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="input-group"
      role="group"
      className={cn(
        'group/input-group border-input relative flex w-full items-center rounded-md border shadow-xs transition-[color,box-shadow] outline-hidden',
        'h-9 min-w-0 has-[>textarea]:h-auto',
        'has-[>[data-align=inline-start]]:[&>input]:pl-2',
        'has-[>[data-align=inline-end]]:[&>input]:pr-2',
        'has-[>[data-align=block-start]]:h-auto has-[>[data-align=block-start]]:flex-col has-[>[data-align=block-start]]:[&>input]:pb-3',
        'has-[>[data-align=block-end]]:h-auto has-[>[data-align=block-end]]:flex-col has-[>[data-align=block-end]]:[&>input]:pt-3',
        'has-[[data-slot=input-group-control]:focus-visible]:border-ring has-[[data-slot=input-group-control]:focus-visible]:ring-ring/50 has-[[data-slot=input-group-control]:focus-visible]:ring-[3px]',
        'has-[[data-slot][aria-invalid=true]]:ring-destructive/20 has-[[data-slot][aria-invalid=true]]:border-destructive',
        className
      )}
      {...props}
    />
  );
}

const inputGroupAddonVariants = cva(
  "text-muted-foreground flex h-auto cursor-text items-center justify-center gap-2 py-1.5 text-sm font-medium select-none [&>svg:not([class*='size-'])]:size-4 [&>kbd]:rounded-[calc(var(--radius)-5px)] group-data-[disabled=true]/input-group:opacity-50",
  {
    variants: {
      align: {
        'inline-start':
          'order-first pl-3 has-[>button]:ml-[-0.45rem] has-[>kbd]:ml-[-0.35rem]',
        'inline-end':
          'order-last pr-3 has-[>button]:mr-[-0.45rem] has-[>kbd]:mr-[-0.35rem]',
        'block-start':
          'order-first w-full justify-start px-3 pt-3 [.border-b]:pb-3 group-has-[>input]/input-group:pt-2.5',
        'block-end':
          'order-last w-full justify-start px-3 pb-3 [.border-t]:pt-3 group-has-[>input]/input-group:pb-2.5',
      },
    },
    defaultVariants: {
      align: 'inline-start',
    },
  }
);

function InputGroupAddon({
  className,
  align = 'inline-start',
  ...props
}: React.ComponentProps<'div'> & VariantProps<typeof inputGroupAddonVariants>) {
  return (
    <div
      role="group"
      data-slot="input-group-addon"
      data-align={align}
      className={cn(inputGroupAddonVariants({ align }), className)}
      onClick={(e) => {
        if ((e.target as HTMLElement).closest('button')) {
          return;
        }
        e.currentTarget.parentElement?.querySelector('input')?.focus();
      }}
      {...props}
    />
  );
}

const inputGroupButtonVariants = cva(
  'text-sm shadow-none flex gap-2 items-center',
  {
    variants: {
      size: {
        xs: "h-6 gap-1 px-2 rounded-[calc(var(--radius)-5px)] [&>svg:not([class*='size-'])]:size-3.5 has-[>svg]:px-2",
        sm: 'h-8 px-2.5 gap-1.5 rounded-md has-[>svg]:px-2.5',
        'icon-xs':
          'size-6 rounded-[calc(var(--radius)-5px)] p-0 has-[>svg]:p-0',
        'icon-sm': 'size-8 p-0 has-[>svg]:p-0',
      },
    },
    defaultVariants: {
      size: 'xs',
    },
  }
);

function InputGroupButton({
  className,
  type = 'button',
  variant = 'ghost',
  size = 'xs',
  ...props
}: Omit<React.ComponentProps<typeof Button>, 'size'> &
  VariantProps<typeof inputGroupButtonVariants>) {
  return (
    <Button
      type={type}
      data-size={size}
      variant={variant}
      className={cn(inputGroupButtonVariants({ size }), className)}
      {...props}
    />
  );
}

function InputGroupText({ className, ...props }: React.ComponentProps<'span'>) {
  return (
    <span
      className={cn(
        "text-muted-foreground flex items-center gap-2 text-sm [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    />
  );
}

function InputGroupInput({
  className,
  ...props
}: React.ComponentProps<'input'>) {
  return (
    <Input
      data-slot="input-group-control"
      className={cn(
        'flex-1 rounded-none border-0 bg-transparent shadow-none focus-visible:ring-0',
        className
      )}
      {...props}
    />
  );
}

function InputGroupTextarea({
  className,
  ...props
}: React.ComponentProps<'textarea'>) {
  return (
    <Textarea
      data-slot="input-group-control"
      className={cn(
        'flex-1 resize-none rounded-none border-0 bg-transparent py-3 shadow-none focus-visible:ring-0',
        className
      )}
      {...props}
    />
  );
}

export {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput,
  InputGroupText,
  InputGroupTextarea,
};
```

### `src/lib/clients/fetch-client.ts`

```ts
import { APIError } from '@/lib/errors';

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';

const BINARY_CONTENT_TYPES = [
  'application/zip',
  'application/octet-stream',
  'application/gzip',
  'application/pdf',
  'image/',
  'video/',
  'audio/',
];

const TEXT_CONTENT_TYPES = [
  'text/plain',
  'text/html',
  'text/csv',
  'text/xml',
  'application/xml',
];

export abstract class FetchClient {
  constructor(
    protected baseUrl: string,
    protected headers: Record<string, string>
  ) {}

  // ── Core Request ──────────────────────────────────────────────────

  protected async request<T>(
    path: string,
    method: HttpMethod = 'GET',
    body?: unknown,
    query: Record<string, string | number | boolean | undefined> = {}
  ): Promise<T> {
    const url = new URL(`${this.baseUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`, window.location.origin);

    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v));
    }

    const headers: Record<string, string> = { ...this.headers };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    const res = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (!res.ok) {
      const data = await this.parseErrorBody(res);
      if (import.meta.env.DEV) {
        console.error(`${res.status} ${res.statusText}:`, data);
      }
      throw new APIError({ statusCode: res.status, data });
    }

    return this.parseResponse<T>(res);
  }

  // ── Response Parsing ──────────────────────────────────────────────

  private async parseResponse<T>(res: Response): Promise<T> {
    if (res.status === 204) return undefined as T;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('application/json'))
      return (await res.json()) as T;
    if (this.matchesContentType(contentType, BINARY_CONTENT_TYPES))
      return (await res.arrayBuffer()) as T;
    if (this.matchesContentType(contentType, TEXT_CONTENT_TYPES))
      return (await res.text()) as T;
    if (contentType.includes('multipart/form-data'))
      return (await res.formData()) as T;

    return this.fallbackParse<T>(res);
  }

  private async parseErrorBody(res: Response): Promise<unknown> {
    if (res.status === 204) return undefined;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('json') || contentType.includes('+json')) {
      try {
        return await res.json();
      } catch {
        /* not valid JSON — fall through */
      }
    }

    const text = await res.text().catch(() => '');
    if (!text) return { message: res.statusText };

    try {
      return JSON.parse(text);
    } catch {
      if (
        contentType.includes('text/html') ||
        text.trimStart().startsWith('<')
      ) {
        console.error(
          `[HTTP ${res.status}] Received HTML error response from ${res.url}`
        );
        return { message: res.statusText };
      }
      return { message: text };
    }
  }

  private async fallbackParse<T>(res: Response): Promise<T> {
    try {
      return (await res.json()) as T;
    } catch {
      return (await res.text()) as T;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  private matchesContentType(contentType: string, patterns: string[]): boolean {
    return patterns.some((p) => contentType.includes(p));
  }
}
```

### `src/lib/constants/env.ts`

IMPORTANT: All env vars use `import.meta.env.VITE_*` — NEVER `process.env`.

```ts
export const ENV = {
  API_BASE_URL: import.meta.env.VITE_API_BASE_URL as string | undefined,
  IS_DEV: import.meta.env.DEV,
  IS_PROD: import.meta.env.PROD,
} as const;

export const getApiBaseUrl = (): string => {
  if (!ENV.API_BASE_URL) throw new Error('VITE_API_BASE_URL is not set');
  return ENV.API_BASE_URL;
};
```

### `src/lib/constants/index.ts`

```ts
export { API_ROUTES, PAGE_ROUTES } from './routes';
export { ENV } from './env';
```

### `src/lib/constants/routes.ts`

```ts
export const PAGE_ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  DASHBOARD: '/dashboard',
} as const;

export const API_ROUTES = {
  HEALTH: '/api/health',
} as const;
```

### `src/lib/errors/index.ts`

```ts
export { APIError } from './api-error';
export { logError } from './error-log-handler';
```

### `src/lib/errors/api-error.ts`

```ts
const isRecord = (x: unknown): x is Record<string, unknown> =>
  typeof x === 'object' && x !== null;

function safeStringify(x: unknown): string {
  try {
    return JSON.stringify(x);
  } catch {
    return '[unserializable]';
  }
}

function extractMessage(data: unknown): string {
  if (typeof data === 'string') {
    const trimmed = data.trim();
    if (trimmed) return trimmed;
  }

  if (data instanceof Error) return data.message;

  if (isRecord(data)) {
    for (const key of ['message', 'error'] as const) {
      const val = data[key];
      if (typeof val === 'string') {
        const trimmed = val.trim();
        if (trimmed) return trimmed;
      }
    }

    return safeStringify(data);
  }

  return String(data);
}

export interface ApiErrorResponse {
  statusCode?: number;
  data?: unknown;
}

export class APIError extends Error {
  public readonly name = 'APIError' as const;
  public readonly statusCode: number;
  public readonly data: unknown;

  constructor({ statusCode = 500, data }: ApiErrorResponse = {}) {
    const message = extractMessage(data);
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);

    this.statusCode = statusCode;
    this.data = data;

    if (Error.captureStackTrace) Error.captureStackTrace(this, APIError);
  }
}
```

### `src/lib/errors/error-log-handler.ts`

```ts
import { APIError } from './api-error';

export const logError = (label: string, error: unknown): void => {
  if (error instanceof APIError) {
    console.error(`${label}:`, {
      message: error.message,
      statusCode: error.statusCode,
      data: error.data,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  if (error instanceof Error) {
    console.error(`${label}:`, {
      message: error.message,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  console.error(`${label}:`, {
    message: String(error),
    timestamp: new Date().toISOString(),
  });
};
```

### `src/lib/utils/index.ts`

```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function mergeHandlers<Args extends readonly unknown[]>(
  ...handlers: (((...args: Args) => void) | undefined)[]
): (...args: Args) => void {
  return (...args: Args) => {
    handlers.forEach((fn) => fn?.(...args));
  };
}
```

---

## Scaffold Steps

### 1. Create directory and write all files

Create the target directory, then write all Part B and Part C files verbatim, plus every file in `config-files.md` (including `package.json` and `eslint.config.mjs`) — substituting only the project `"name"` in `package.json`.

### 2. Update project name and branding

- `package.json`: set `"name"` to the project name (lowercase kebab-case)
- `index.html`: update `<title>` to the project name
- `src/components/layout/navbar.tsx`: replace `templateCentral` with the project name
- `src/components/layout/site-footer.tsx`: replace `'Built with templateCentral'` default with project-appropriate text
- `src/pages/home.tsx`: replace `"Vite + React Template"` heading with the project name

### 3. Copy `.env.example` to `.env`

```bash
cp .env.example .env
```

### 4. Initialize git and install dependencies

```bash
git init
pnpm install
```

`pnpm install` automatically runs `prepare: husky`, activating pre-commit and pre-push hooks. Verify installation completed without errors.

### 5. Install shadcn components

```bash
npx shadcn@latest add accordion avatar button card checkbox dialog dropdown-menu form input label select separator skeleton sonner tabs textarea
```

After shadcn installs, write the custom UI components verbatim (they are NOT managed by shadcn CLI):
- `src/components/ui/button-group.tsx`
- `src/components/ui/field.tsx`
- `src/components/ui/input-group.tsx`

### 6. Verification gate

Do NOT generate `AGENTS.md` until ALL of these pass:

```bash
pnpm build        # zero errors
pnpm check        # format + lint + typecheck — zero errors
pnpm test         # all tests pass
```

If any check fails, diagnose and fix before proceeding.

### 7. Write project `AGENTS.md`

Only after the verification gate passes. Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

````markdown
<!-- templateCentral: vite-react@5.0.0 -->
# AGENTS.md — [Project Name]

## Stack
Vite 8 · React 19 · TypeScript strict · shadcn/ui · Tailwind CSS 4 · React Router 7
TanStack React Query 5 · React Hook Form + Zod · Vitest · pnpm · Node ≥24
Client-side SPA — no SSR, no API route handlers.

## Commands
```bash
pnpm dev          # dev server
pnpm build        # production build (tsc -b && vite build)
pnpm test         # run tests
pnpm check        # format + lint + typecheck
```

## File Layout
src/features/<name>/    — feature modules (api/, components/, hooks/, types.ts)
src/components/ui/      — shadcn primitives (CLI-managed, do not edit directly)
src/components/widgets/ — reusable composed components (project-owned)
src/router.tsx          — route definitions (not filesystem convention)
src/lib/constants/env.ts — centralized VITE_* env access

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/vite-verify` | typecheck + lint + test in one pass |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (feature)` | full feature: page + query hook + components (includes components) |
| `templatecentral:add (page)` | new route + page component |
| `templatecentral:add (form)` | React Hook Form + Zod form |
| `templatecentral:add (auth)` | auth flow integration |
| `templatecentral:standards` | drift check, validation patterns |
| `templatecentral:audit` | full ecosystem + accuracy audit |

## Rules (always)
- `VITE_*` env vars are shipped to the browser — never API keys, tokens, or secrets
- All user input / API responses validated with Zod at every boundary
- Named exports only (except tooling configs); `function` declarations for components
- No secrets in code or `VITE_*` vars — use server-side proxy for sensitive calls

## AI Harness
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`; a second Bash guard blocks `--no-verify` and force-pushes to protected branches. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/clear/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: `pnpm exec tsc --noEmit --incremental 2>&1 | tail -5` after every Edit/Write. Feedback-only.
Stop hook: runs full test suite; exit 2 feeds failures to Claude via stderr; exit 0 on pass.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
````

### 7b. Seed the agent harness (shared kit)

Load the shared harness kit using the **vite-react** row of its delta table:

```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/shared/harness-kit.md"
```

Execute kit Steps **A through D** now (settings.json, hook scripts, FUTURE.md, CONSTITUTION.md). Then continue with step 7c below to create the verify skill. After step 7c, execute kit Steps **E through H** (harness.json requires the verify skill to exist first — Step E's prerequisites note explains this).

### 7c. Create project skill files (`.claude/skills/`)

Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Run `mkdir -p .claude/skills/vite-verify`, then create `.claude/skills/vite-verify/SKILL.md`:

````markdown
---
name: vite-verify
description: Run typecheck, lint, and tests for this Vite+React project in one pass
allowed-tools: Bash(pnpm *)
---

Run all quality checks in sequence:

```bash
pnpm exec tsc --noEmit --incremental && pnpm check && pnpm test --run
```

Report failures with the exact error output. Fix before proceeding.
````

CONSTITUTION.md was created in kit Step D. Do not run kit Step E yet — the verify skill below must exist first.

### 7d. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `vite-feature` — scaffold a new feature module (components + query hook + page)
- `vite-component` — scaffold a reusable widget component with props + story

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

Now execute kit Steps **E through H** using the **vite-react** row: harness.json (Step E — includes the `vite-verify` skill hash), `.agents` symlink (Step F), AGENTS.md tail check (Step G — append the shared tail; vite-react does NOT embed it), and plugin install (Step H).

---

### 8. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

After creating it, add a `CLAUDE.md` entry to `seeded_files` in `.claude/harness.json` with its SHA-256 hash (see 7e).

### 9. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from "Scaffold: optional Task Management" in repository root `AGENTS.md`. If no, skip.

### 10. Optional: Remove example code

Once the project is verified and the user confirms it runs, optionally remove example code:

- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/pages/dashboard.tsx`
- Update `src/pages/index.ts` if needed

Or use the cleanup utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/cleanup/SKILL.md"`.

---

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — NEVER commit `.env` or paste secrets into `AGENTS.md` / `CLAUDE.md`
- Always update `index.html` title — it is the browser tab name (NEVER skip)
- Routes are defined in `src/router.tsx`, not by filesystem convention
- NEVER use `process.env` — all env access goes through `import.meta.env.VITE_*` in `src/lib/constants/env.ts`
- Verify `pnpm build`, `pnpm typecheck`, and `pnpm test` all pass before generating `AGENTS.md`
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/` or `dist/` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off