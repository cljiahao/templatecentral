<!-- ref: scaffold/nextjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part C — Verbatim Custom Components

Write these files exactly as shown. Do not modify.

### `src/components/ui/field.tsx`

```tsx
'use client';

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
        'has-data-[state=checked]:bg-primary/5 has-data-[state=checked]:border-primary dark:has-data-[state=checked]:bg-primary/10',
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
}: ComponentProps<'div'> & { children?: ReactNode }) {
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
    if (children) return children;
    if (!errors?.length) return null;
    if (errors?.length == 1) return errors[0]?.message;
    return (
      <ul className="ml-4 flex list-disc flex-col gap-1">
        {errors.map(
          (error, index) =>
            error?.message && <li key={index}>{error.message}</li>
        )}
      </ul>
    );
  }, [children, errors]);

  if (!content) return null;

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

### `src/components/widgets/custom-form-field.tsx`

```tsx
'use client';

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

### `src/components/widgets/custom-card.tsx`

```tsx
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import React from 'react';

type CardProps = React.ComponentProps<typeof Card>;

interface CustomCardProps extends Omit<CardProps, 'children'> {
  className?: string;
  children?: React.ReactNode;
  header?: React.ReactNode;
  description?: React.ReactNode;
  contentClassName?: string;
}

export function CustomCard({
  className,
  contentClassName,
  children,
  header,
  description,
  ...cardProps
}: CustomCardProps) {
  return (
    <Card {...cardProps} className={className}>
      {(header || description) && (
        <CardHeader>
          {header && (
            <CardTitle className="text-xl leading-tight font-bold">
              {header}
            </CardTitle>
          )}
          {description && <CardDescription>{description}</CardDescription>}
        </CardHeader>
      )}
      <CardContent className={contentClassName}>{children}</CardContent>
    </Card>
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

### `src/components/widgets/floating-shape.tsx`

```tsx
import { cn } from '@/lib/utils';
import Image from 'next/image';

interface FloatingShapeProps {
  src?: string;
  alt?: string;
  imageClassName?: string;
  className?: string;
}

export function FloatingShape({
  src = '/image_assets/default-square.svg',
  alt = 'default-square',
  imageClassName,
  className,
}: FloatingShapeProps) {
  return (
    <div
      className={cn(
        className,
        'pointer-events-none absolute hidden opacity-80 xl:block animate-float'
      )}
    >
      <Image
        src={src}
        alt={alt}
        fill
        className={cn(imageClassName, 'object-contain')}
      />
    </div>
  );
}
```

### `src/components/widgets/brand-logo.tsx`

```tsx
import { cn } from '@/lib/utils';
import Image from 'next/image';

interface BrandLogoProps {
  className?: string;
}

export function BrandLogo({ className }: BrandLogoProps) {
  return (
    <div className={cn('relative h-full w-full', className)}>
      <Image
        src="/image_assets/logo.svg"
        alt="Logo"
        fill
        className="object-contain"
        priority
      />
    </div>
  );
}
```

### `src/components/widgets/brand-text.tsx`

> **Note:** After writing this file, update the text content to match the actual project name. Replace `template` and `Central` with the project's brand name split appropriately, or simplify to a single `<span>` if no gradient split is needed.

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

### `src/components/widgets/link-list.tsx`

```tsx
import { cn } from '@/lib/utils';
import Link from 'next/link';

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
        <Link
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
        </Link>
      ))}
    </div>
  );
}
```

### `src/components/widgets/theme-toggle-button.tsx`

```tsx
'use client';

import { Moon, Sun } from 'lucide-react';
import { useTheme } from 'next-themes';

export function ThemeToggleButton() {
  const { theme, setTheme } = useTheme();
  const isDark = theme === 'dark';

  return (
    <button
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      className="relative overflow-hidden rounded-full bg-gray-200 p-5 transition-colors duration-100 dark:bg-gray-800 dark:text-gray-200"
      aria-label="Toggle theme"
    >
      <span
        className="flex-center absolute inset-0 transition-all duration-200"
        style={{
          opacity: isDark ? 1 : 0,
          transform: isDark ? 'translateY(0)' : 'translateY(-50%)',
        }}
      >
        <Sun className="h-5 w-5" fill="currentColor" />
      </span>
      <span
        className="flex-center absolute inset-0 transition-all duration-200"
        style={{
          opacity: isDark ? 0 : 1,
          transform: isDark ? 'translateY(50%)' : 'translateY(0)',
        }}
      >
        <Moon className="h-5 w-5" fill="currentColor" />
      </span>
    </button>
  );
}
```

### `src/components/widgets/index.ts`

```ts
export { BrandLogo } from './brand-logo';
export { BrandText } from './brand-text';
export { CustomCard } from './custom-card';
export { CustomDialog } from './custom-dialog';
export { CustomFormField } from './custom-form-field';
export { FloatingShape } from './floating-shape';
export { LinkList } from './link-list';
export { MediaCard } from './media-card';
export { Pill } from './pill';
export { ThemeToggleButton } from './theme-toggle-button';
```

### `src/components/layout/providers.tsx`

```tsx
'use client';

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
    <QueryClientProvider client={queryClient}>
      {children}
      <Toaster position="top-right" />
    </QueryClientProvider>
  );
}
```

### `src/components/layout/theme-provider.tsx`

```tsx
'use client';

import { ThemeProvider as NextThemesProvider } from 'next-themes';
import * as React from 'react';

export function ThemeProvider({
  children,
  ...props
}: React.ComponentProps<typeof NextThemesProvider>) {
  return <NextThemesProvider {...props}>{children}</NextThemesProvider>;
}
```

### `src/components/layout/index.ts`

```ts
export { Navbar } from './navbar';
export { SiteFooter } from './site-footer';
export { Providers } from './providers';
export { ThemeProvider } from './theme-provider';
```

### `src/integrations/error.ts`

```ts
export const isRecord = (x: unknown): x is Record<string, unknown> =>
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

### `src/integrations/clients/base/https-agent.ts`

```ts
import https from 'https';

export interface HttpsAgentOptions {
  cert?: string | Buffer;
  key?: string | Buffer;
  ca?: string | Buffer | Array<string | Buffer>;
  rejectUnauthorized?: boolean;
  keepAlive?: boolean;
  maxSockets?: number;
  passphrase?: string;
}

// Respect explicit opt-out (NODE_TLS_REJECT_UNAUTHORIZED=0) but default to true in all envs.
// Never use NODE_ENV to disable TLS — staging/UAT servers have valid certs and should be verified.
const DEFAULT_AGENT_OPTIONS: HttpsAgentOptions = {
  rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0',
  keepAlive: true,
  maxSockets: 50,
};

export function createHttpsAgent(options?: HttpsAgentOptions): https.Agent {
  return new https.Agent({ ...DEFAULT_AGENT_OPTIONS, ...options });
}

export function normalizePem(pem: string): string {
  if (pem.trim().startsWith('{')) {
    try {
      const parsed = JSON.parse(pem);
      if (typeof parsed === 'string')
        return parsed.replace(/\\n/g, '\n').trim();
      if (parsed.cert) return String(parsed.cert).replace(/\\n/g, '\n').trim();
    } catch {
      // fall through to string normalization
    }
  }

  return pem.replace(/\\n/g, '\n').replace(/^"|"$/g, '').trim();
}
```

### `src/integrations/clients/base/fetch-client.ts`

```ts
import { APIError } from '@/integrations/error';

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

  protected async request<T>(
    path: string,
    method: HttpMethod = 'GET',
    body?: unknown,
    query: Record<string, string | number | boolean | undefined> = {}
  ): Promise<T> {
    const url = new URL(`${this.baseUrl}/${path}`);

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
      // Log status/URL only — never the error body (may contain PII)
      console.error(`[HTTP ${res.status}] ${res.statusText} from ${res.url}`);
      throw new APIError({ statusCode: res.status, data });
    }

    return this.parseResponse<T>(res);
  }

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
        /* not valid JSON */
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

  private matchesContentType(contentType: string, patterns: string[]): boolean {
    return patterns.some((p) => contentType.includes(p));
  }
}
```

### `src/integrations/clients/base/axios-client.ts`

```ts
import { APIError } from '@/integrations/error';
import axios, {
  type AxiosError,
  type AxiosInstance,
  type InternalAxiosRequestConfig,
} from 'axios';
import { createHttpsAgent, type HttpsAgentOptions } from './https-agent';

interface AxiosClientOptions {
  baseURL: string;
  timeout?: number;
  httpsAgentOptions?: HttpsAgentOptions;
  apiKey?: Record<string, string>;
  additionalHeaders?: Record<string, string>;
  enableLogging?: boolean;
}

interface AxiosErrorResponse {
  message?: string;
  error?: string;
  statusCode?: number;
  details?: unknown;
}

export function createAxiosClient(options: AxiosClientOptions): AxiosInstance {
  const {
    baseURL,
    timeout = 30_000,
    httpsAgentOptions,
    apiKey,
    additionalHeaders = {},
    enableLogging = process.env.NODE_ENV === 'development',
  } = options;

  const client = axios.create({
    baseURL,
    timeout,
    headers: { 'Content-Type': 'application/json', ...additionalHeaders },
  });

  if (httpsAgentOptions) {
    client.defaults.httpsAgent = createHttpsAgent(httpsAgentOptions);
  }

  client.interceptors.request.use(
    (config: InternalAxiosRequestConfig) => {
      if (apiKey) {
        for (const [key, value] of Object.entries(apiKey)) {
          config.headers[key] = value;
        }
      }

      if (enableLogging) {
        // Log method/URL only — never params or bodies (may contain PII)
        console.log(`[Request] ${config.method?.toUpperCase()} ${config.url}`);
      }

      return config;
    },
    (error: AxiosError) => {
      console.error('[Request Error]', error.message);
      return Promise.reject(error);
    }
  );

  client.interceptors.response.use(
    (response) => {
      if (enableLogging) {
        // Log status/URL only — never response bodies (may contain PII)
        console.log(`[Response] ${response.status} ${response.config.url}`);
      }
      return response;
    },
    (error: AxiosError<AxiosErrorResponse>) => {
      if (!error.response) {
        throw new APIError({
          statusCode: error.code === 'ECONNABORTED' ? 408 : 500,
          data: { message: `Request timeout after ${timeout}ms` },
        });
      }

      const statusCode = error.response.status || 500;
      let data: unknown = error.response.data;

      if (typeof data === 'string' && data.trimStart().startsWith('<')) {
        console.error(
          `[HTTP ${statusCode}] Received HTML error response from ${error.config?.url}`
        );
        data = { message: error.response.statusText || error.message };
      }

      if (enableLogging) {
        console.error(`[API Error ${statusCode}]`, {
          url: error.config?.url,
          message: error.message,
        });
      }

      throw new APIError({ statusCode, data });
    }
  );

  return client;
}
```

### `src/lib/errors/index.ts`

```ts
export { APIError } from '@/integrations/error';
export { handleApiError } from './handle-api-error';
export { logError } from './error-log-handler';
```

### `src/lib/errors/handle-api-error.ts`

```ts
import { APIError } from '@/integrations/error';
import { logError } from '@/lib/errors/error-log-handler';
import { NextResponse } from 'next/server';

const STATUS_MESSAGES: Record<number, string> = {
  400: 'Invalid request',
  401: 'Authentication required',
  403: 'Access denied',
  404: 'Resource not found',
  408: 'Request timed out',
  409: 'Conflict',
  429: 'Too many requests',
  500: 'Internal server error',
  502: 'Service temporarily unavailable',
  503: 'Service temporarily unavailable',
};

export const handleApiError = (label: string, error: unknown) => {
  logError(label, error);

  if (error instanceof APIError) {
    const status = error.statusCode;
    const message = STATUS_MESSAGES[status] ?? label;
    return NextResponse.json({ error: message }, { status });
  }

  return NextResponse.json({ error: label }, { status: 500 });
};
```

### `src/lib/errors/error-log-handler.ts`

```ts
import { APIError } from '@/integrations/error';
import { logger } from '@/lib/logger';

export const logError = (logLabel: string, error: unknown): void => {
  if (error instanceof APIError) {
    logger.error({
      label: logLabel,
      message: error.message,
      statusCode: error.statusCode,
    });
    return;
  }
  if (error instanceof Error) {
    logger.error({ label: logLabel, message: error.message });
    return;
  }
  logger.error({ label: logLabel, message: String(error) });
};
```

### `src/app/layout.tsx`

```tsx
import type { ReactNode } from 'react';

import { Providers, ThemeProvider } from '@/components/layout';
import type { Metadata } from 'next';
import { Geist_Mono, Lato } from 'next/font/google';
import './globals.css';

const lato = Lato({
  variable: '--font-lato',
  subsets: ['latin'],
  weight: ['100', '300', '400', '700', '900'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: '<project-name>',
  description: 'A Next.js application',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning className="no-scrollbar">
      <body className={`${lato.variable} ${geistMono.variable} relative antialiased`}>
        <ThemeProvider attribute="class" defaultTheme="light" disableTransitionOnChange>
          <Providers>{children}</Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
```

### `src/app/api/route.ts`

```ts
import { type NextRequest, NextResponse } from 'next/server';

export async function GET(_req: NextRequest): Promise<NextResponse> {
  return NextResponse.json(
    { status: 'ok', timestamp: new Date().toISOString() },
    { status: 200 },
  );
}
```

### `src/app/api/health/route.ts`

Identical to `src/app/api/route.ts` above — write the same content to both paths.

### `src/lib/logger.ts`

```ts
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  ...(process.env.NODE_ENV !== 'production' && {
    transport: {
      target: 'pino-pretty',
      options: { colorize: true, singleLine: true },
    },
  }),
});
```

### `src/lib/utils/with-logging.ts`

```ts
import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

import { logger } from '@/lib/logger';

type RouteHandler = (
  req: NextRequest,
  ctx?: { params?: Promise<Record<string, string>> }
) => Promise<NextResponse>;

export function withLogging(handler: RouteHandler): RouteHandler {
  return async (req, ctx) => {
    const start = Date.now();
    const { method } = req;
    const path = new URL(req.url).pathname;
    const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID();

    try {
      const res = await handler(req, ctx);
      logger.info({ requestId, method, path, status: res.status, duration_ms: Date.now() - start });
      return res;
    } catch (err) {
      logger.error({
        requestId,
        method,
        path,
        error: err instanceof Error ? err.message : String(err),
      });
      return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
    }
  };
}
```

### `src/lib/utils/index.ts`

```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### `src/lib/utils/request-origin.ts`

```ts
import { type NextRequest } from 'next/server';

// TRUST_PROXY: set to the number of trusted proxy hops in front of the app
// (1 = ALB → App, 2 = ALB → Traefik → App); empty/unset = X-Forwarded-*
// headers are not trusted. A hop count is truthy, so the checks below hold.
export function getAppOrigin(request: NextRequest): string {
  const trustProxy = process.env.TRUST_PROXY;
  const proto = (trustProxy
    ? request.headers.get('x-forwarded-proto')?.split(',')[0].trim()
    : undefined) ?? request.nextUrl.protocol.replace(/:$/, '');
  const host = (trustProxy
    ? (request.headers.get('x-forwarded-host') ?? request.headers.get('host'))
    : undefined) ?? request.nextUrl.host;
  return `${proto}://${host}`;
}
```

### `src/lib/constants/env.ts`

```ts
export const API_BASE =
  process.env.NEXT_PUBLIC_BASE_URL ?? 'http://localhost:3000';

export const isDev = process.env.NODE_ENV === 'development';
export const isProd = process.env.NODE_ENV === 'production';
```

### `src/lib/constants/routes.ts`

```ts
export const PAGE_ROUTES = {
  HOME: '/',
  DASHBOARD: '/dashboard',
} as const;

export const API_ROUTES = {
  HEALTH: '/api/health',
} as const;
```

### `src/hooks/index.ts`

```ts
export {};
```

### `src/lib/constants/index.ts`

```ts
export * from './env';
export * from './routes';
```

### `src/integrations/factories.ts`

```ts
/**
 * Factory functions for creating integration client instances.
 *
 * Pattern: Environment → factories.ts → clients/ → services/ → schemas/
 *
 * Default to FetchClient for simple REST APIs:
 *
 *   import { FetchClient } from '@/integrations/clients/base/fetch-client';
 *
 *   class MyClient extends FetchClient {
 *     async getItems() {
 *       return this.request<Item[]>('items');
 *     }
 *   }
 *
 *   export const myClient = new MyClient(
 *     process.env.MY_API_URL!,
 *     { Authorization: `Bearer ${process.env.MY_TOKEN}` }
 *   );
 *
 * Switch to createAxiosClient only when you need complex HTTPS requirements
 * (mutual TLS, certificate pinning, per-request interceptor chains):
 *
 *   import { createAxiosClient } from '@/integrations/clients/base/axios-client';
 *
 *   export const myApiClient = createAxiosClient({
 *     baseURL: process.env.MY_API_URL!,
 *     apiKey: { 'x-api-key': process.env.MY_API_KEY! },
 *   });
 */
```

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
  const { data: items, isPending } = useExampleItems();

  if (isPending) return <p className="text-sm text-muted-foreground">Loading…</p>;
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
        Example feature — remove with the <code>templatecentral:cleanup</code> skill after
        confirming the scaffold works.
      </p>
      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```

### `src/app/globals.css`

```css
@import 'tailwindcss';
@plugin '@tailwindcss/typography';
@import 'tw-animate-css';

@custom-variant dark (&:is(.dark *));

@theme inline {
  /* Fonts & radius */
  --font-sans: var(--font-lato);
  --font-mono: var(--font-geist-mono);
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

  /* Utility */
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-destructive: var(--destructive);

  /* Form */
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);
}

:root {
  --black: #101010;
  --white: #f9f9f9;
  --radius: 0.625rem;

  --background: var(--white);
  --foreground: var(--black);
  --card: var(--white);
  --card-foreground: var(--black);
  --popover: var(--white);
  --popover-foreground: var(--black);

  --primary: var(--color-neutral-900);
  --primary-foreground: var(--white);
  --primary-hover: var(--color-neutral-800);
  --secondary: var(--color-neutral-100);
  --secondary-foreground: var(--color-neutral-900);
  --secondary-hover: var(--color-neutral-200);
  --accent: var(--color-neutral-100);
  --accent-foreground: var(--color-neutral-900);
  --accent-hover: var(--color-neutral-200);

  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --destructive: oklch(0.577 0.245 27.325);

  --border: var(--color-neutral-300);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
}

.dark {
  --background: var(--black);
  --foreground: var(--white);
  --card: var(--black);
  --card-foreground: var(--white);
  --popover: var(--black);
  --popover-foreground: var(--white);

  --primary: var(--white);
  --primary-foreground: var(--color-neutral-900);
  --primary-hover: var(--color-neutral-200);
  --secondary: var(--color-neutral-800);
  --secondary-foreground: var(--color-neutral-100);
  --secondary-hover: var(--color-neutral-700);
  --accent: var(--color-neutral-800);
  --accent-foreground: var(--color-neutral-100);
  --accent-hover: var(--color-neutral-700);

  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --destructive: oklch(0.704 0.191 22.216);

  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
}

@layer base {
  * {
    @apply border-border outline-ring/50;
  }
  html {
    scroll-behavior: smooth;
    @apply bg-background;
  }
  body {
    @apply bg-background text-foreground;
  }
  button:not(:disabled),
  [role='button']:not(:disabled) {
    cursor: pointer;
  }
}

@layer utilities {
  .hw-full { @apply h-full w-full; }
  .flex-between { @apply flex items-center justify-between; }
  .flex-center { @apply flex items-center justify-center; }
  .flex-start { @apply flex items-start justify-start; }
  .flex-end { @apply flex justify-end; }
  .max-w-site { @apply max-w-[1184px]; }
  .max-w-content { @apply max-w-[1000px]; }
  .bg-brand-gradient { @apply from-primary via-primary to-primary bg-linear-to-r; }
  .text-brand-gradient { @apply from-primary via-primary to-primary bg-linear-to-r bg-clip-text text-transparent; }
}

.no-scrollbar::-webkit-scrollbar { display: none; }
.no-scrollbar { -ms-overflow-style: none; scrollbar-width: none; }

@keyframes float {
  0%, 100% { transform: translateY(0) rotate(0deg); }
  50% { transform: translateY(-15px) rotate(5deg); }
}
.animate-float { animation: float 10s ease-in-out infinite; }
```

### `src/app/(public)/layout.tsx`

```tsx
import type { ReactNode } from 'react';

import { Navbar, SiteFooter } from '@/components/layout';

export default function PublicLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex flex-1 flex-col">{children}</main>
      <SiteFooter />
    </div>
  );
}
```

### `src/app/(public)/page.tsx`

> Update brand text (`template`/`Central` spans and the description paragraph) in Step 2.

```tsx
export default function Home() {
  return (
    <div className="flex-center min-h-screen flex-col gap-6">
      <h1 className="text-4xl font-bold tracking-tight lg:text-6xl">
        <span className="text-brand-gradient">template</span>
        <span>Central</span>
      </h1>
      <p className="text-muted-foreground max-w-md text-center text-lg">
        A production-ready Next.js template with shadcn/ui, Tailwind CSS, and
        everything you need to build modern web applications.
      </p>
    </div>
  );
}
```

### `src/components/layout/navbar.tsx`

> Update the two brand `<span>` elements and the Dashboard button text in Step 2.

```tsx
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { LinkList, type LinkItem } from '@/components/widgets';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';

const defaultNavLinks: LinkItem[] = [];

export function Navbar() {
  const pathname = usePathname();
  const rootPath = `/${pathname.split('/')[1]}`;
  const isDashboard = rootPath === PAGE_ROUTES.DASHBOARD;

  return (
    <nav
      className={cn(
        isDashboard
          ? 'sticky top-0 z-50 w-full'
          : 'max-w-site fixed inset-x-0 top-0 z-50 mx-auto pt-10',
      )}
    >
      <div
        className={cn(
          'flex-between min-h-20 bg-white px-6 py-3 shadow-lg',
          isDashboard ? 'border-b' : 'rounded-2xl border',
        )}
      >
        <Link href={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          <span className="text-brand-gradient">template</span>
          <span>Central</span>
        </Link>

        <div className="flex items-center gap-4">
          {defaultNavLinks.length > 0 && (
            <LinkList links={defaultNavLinks} className="hover:text-primary transition-colors" />
          )}
          <Button
            asChild
            className="bg-primary hover:bg-primary-hover h-12 rounded-lg px-6 py-3 font-bold text-white"
          >
            <Link href={PAGE_ROUTES.DASHBOARD}>Dashboard</Link>
          </Button>
        </div>
      </div>
    </nav>
  );
}
```

### `src/components/layout/site-footer.tsx`

> Update `creditText` default in Step 2.

```tsx
import { LinkList, type LinkItem } from '@/components/widgets';

interface SiteFooterProps {
  creditText?: string;
  links?: LinkItem[];
}

const defaultLinks: LinkItem[] = [
  { label: 'Contact Us', href: '#' },
];

export function SiteFooter({
  creditText = 'Built with templateCentral',
  links = defaultLinks,
}: SiteFooterProps) {
  return (
    <footer className="w-full bg-black">
      <div className="flex-between px-6 py-6">
        <p className="text-sm text-white">{creditText}</p>
        <LinkList links={links} className="text-sm text-white" />
      </div>
    </footer>
  );
}
```

### `test/api/health.test.ts`

```ts
import { describe, expect, it } from 'vitest';
import { NextRequest } from 'next/server';

import { GET as getRootHealth } from '@/app/api/route';
import { GET as getHealthPath } from '@/app/api/health/route';

function makeRequest(url: string): NextRequest {
  return new NextRequest(url);
}

describe('GET /api (root health)', () => {
  it('returns ok with 200', async () => {
    const response = await getRootHealth(makeRequest('http://localhost/api'));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});

describe('GET /api/health (Docker / probe path)', () => {
  it('returns ok with 200', async () => {
    const response = await getHealthPath(makeRequest('http://localhost/api/health'));
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.status).toBe('ok');
    expect(data.timestamp).toBeDefined();
  });
});
```

---

## Scaffold Steps

### 1. Create directory and files

Create the target directory. Write every file verbatim from `config-files.md` (Dockerfiles, `package.json`, `eslint.config.mjs`, tsconfig, etc.) and from Parts B and C below — substituting only the project `"name"` in `package.json`.

### 2. Update project name and branding

- In `package.json`: set `"name"` to kebab-case project name
- In `src/app/layout.tsx`: update `metadata.title` and `metadata.description`
- In `src/components/layout/navbar.tsx`: replace brand text with project name
- In `src/components/layout/site-footer.tsx`: update credit text
- In `src/components/widgets/brand-text.tsx`: update the text spans to reflect the project name
- In `src/components/widgets/brand-logo.tsx`: logo path stays as `/image_assets/logo.svg` — user replaces the SVG file with their own logo

### 3. Initialise git and install dependencies

```bash
git init
pnpm install
```

`pnpm install` activates husky hooks via the `prepare` script.

### 4. Install shadcn components

`components.json` was written in Step 1 — no interactive init needed. Add primitives directly:

```bash
npx shadcn@latest add button card dialog form input label select separator sonner tabs textarea
```

### 5. Copy `.env.example` to `.env.local`

```bash
cp .env.example .env.local
```

Never commit `.env.local`.

### 5b. Run verification gate before generating AGENTS.md

Do not generate AGENTS.md until this passes:

```bash
pnpm build       # production build — zero errors
pnpm check       # format + lint + typecheck — zero errors
pnpm test        # all tests pass
```

If build fails with module-not-found errors, a `pnpm add` is missing.
If check fails, a generated file violates the eslint or prettier config.

### 6. Write project AGENTS.md

Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

```markdown
<!-- templateCentral: nextjs@4.0.0 -->
# AGENTS.md — [Project Name]

> STOP — Next.js 16 breaking changes: `cookies()`, `headers()`, `params`, `searchParams` are
> ALL async. `middleware.ts` is replaced by `proxy.ts`. Verify before writing route handlers.

## Stack
Next.js 16 · App Router · TypeScript strict · shadcn/ui · TanStack Query v5
React Hook Form · Zod v4 · Vitest · pnpm 11 · Node ≥24

## Commands
```bash
pnpm dev          # dev server — http://localhost:3000
pnpm build        # production build
pnpm test         # run test suite
pnpm check        # format + lint + typecheck
```

## File Layout
src/app/                — app router (pages, layouts, route handlers)
src/app/api/            — API route handlers
src/features/<name>/    — feature modules: api/, components/, hooks/, types.ts
src/components/ui/      — shadcn primitives (CLI-managed, do not edit directly)
src/components/widgets/ — reusable composed components (project-owned)
proxy.ts + src/lib/auth.ts — auth layer
src/integrations/database/ — database layer (after `templatecentral:add (database)`)
src/lib/constants/env.ts — environment constants

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/next-verify` | typecheck + lint + test in one pass |
| `/next-migrate` | Drizzle push/migrate with safety gate (once database is wired up) |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (feature)` | full feature: page + API route + hooks |
| `templatecentral:add (component)` | reusable UI component |
| `templatecentral:add (api-route)` | API route with auth guard |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |
| `templatecentral:audit` | full ecosystem + accuracy audit |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod at every boundary
- DB writes via repository layer only
- `z.input<typeof Schema>` for form types; `z.infer` for post-parse output
- No secrets in `NEXT_PUBLIC_*` variables

## AI Harness
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
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
```

### 6b. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (below). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present.

**`.claude/settings.json`**:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.local)",
      "Read(.env.*.local)",
      "Read(.env.development)",
      "Read(.env.development.*)",
      "Read(.env.dev)",
      "Read(.env.production)",
      "Read(.env.production.*)",
      "Read(.env.staging)",
      "Read(.env.staging.*)",
      "Read(.env.uat)",
      "Read(.env.test)",
      "Read(./secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/protect-files.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "node .claude/hooks/user-prompt-guard.js" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-edit-typecheck.sh" }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-tool-failure.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/stop-checks.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/subagent-stop.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-context.sh" }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

Hook logic lives in `.claude/hooks/` scripts (seeded below) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `.github/workflows/`, cert/credential files; warns on governance files (`AGENTS.md`, `CLAUDE.md`, `Dockerfile`). Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — blocks `git commit --no-verify`, direct commits/force-push to protected branches (`main`/`uat`/`develop`), and `rm -rf` on source dirs.
- `user-prompt-guard.js` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs).
- `post-edit-typecheck.sh` (PostToolUse) — incremental `tsc` feedback, filtered to TS edits in-script. Feedback-only; exit 0 always.
- `post-tool-failure.sh` (PostToolUseFailure) — surfaces tool error context for self-correction.
- `stop-checks.sh` (Stop) — runs the test suite; exit 2 forces a fix before the turn ends.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted TS changes so it can't hand back broken code.
- `session-context.sh` (SessionStart: startup/resume/compact) — re-injects AGENTS.md routing context + universal invariants. This is the working post-compaction recovery path; PostCompact is observability-only and cannot inject context, so it is not used.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**`.claude/hooks/protect-files.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block; exit 1 = warn (human approval expected); exit 0 = allow.
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$file" ] && exit 0
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || root="."
rel="${file#"$root"/}"

if [[ "$rel" == .github/workflows/* ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition — requires human review." >&2
  exit 2
elif [[ "$rel" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json) reason="harness config — editing it can silently disable every hook" ;;
  .claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  Dockerfile) reason="container image definition" ;;
esac
if [ -n "$reason" ]; then
  echo "PROTECTED FILE: $rel — $reason. Confirm human approval and note it in the PR." >&2
  exit 1
fi
exit 0
```

**`.claude/hooks/block-no-verify.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
input=$(cat)
cmd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(((JSON.parse(b||'{}').tool_input)||{}).command||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$cmd" ] && exit 0

if echo "$cmd" | grep -qE 'git[[:space:]]+commit' && echo "$cmd" | grep -qE '\-\-no-verify|[[:space:]]-[a-z]*n'; then
  echo "BLOCKED: --no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "uat" || "$branch" == "develop" ]]; then
    echo "BLOCKED: direct commit to protected branch '$branch'. Create a feature branch first." >&2
    exit 2
  fi
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+push' && { { echo "$cmd" | grep -qE '\-\-force([[:space:]=]|$)|[[:space:]]-[a-z]*f' && echo "$cmd" | grep -qE '\bmain\b|\buat\b|\bdevelop\b'; } || echo "$cmd" | grep -qE '[[:space:]]\+(main|uat|develop)\b'; }; then
  echo "BLOCKED: force-push to a protected branch (--force/-f or +refspec). Open a PR instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/])(src|app|lib|test|\.claude|\.husky|\.git|node_modules)([[:space:]/]|$)'; then
  echo "BLOCKED: recursive rm on a source directory. Confirm with a human first." >&2
  exit 2
fi
exit 0
```

**`.claude/hooks/user-prompt-guard.js`**:
```javascript
#!/usr/bin/env node
// UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
const input = require('fs').readFileSync(0, 'utf8');
let prompt = '';
try { prompt = (JSON.parse(input || '{}').prompt) || ''; } catch { process.exit(0); }
const lower = prompt.toLowerCase();

const injection = [
  'ignore previous instructions',
  'ignore all instructions',
  'disregard your',
  'forget your instructions',
  'override your',
  'new instructions:',
  'system prompt:',
  'your real instructions',
  'you are now a different ai',
  'you are no longer bound',
  'pretend you are not bound',
  'pretend you have no restrictions',
  'act as if you have no restrictions',
  'developer mode enabled',
];
for (const p of injection) {
  if (lower.includes(p)) {
    process.stderr.write(`Blocked: prompt matches an injection pattern (OWASP LLM01): "${p}"\n`);
    process.exit(2);
  }
}

const credentials = [
  [/AKIA[0-9A-Z]{16}/, 'AWS access key ID'],
  [/ghp_[A-Za-z0-9]{36}/, 'GitHub personal access token'],
  [/github_pat_[A-Za-z0-9_]{82}/, 'GitHub fine-grained PAT'],
  [/sk-ant-[A-Za-z0-9\-_]{90,}/, 'Anthropic API key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'PEM private key block'],
  [/mongodb(\+srv)?:\/\/[^:]+:[^@]+@/i, 'database URL with embedded credentials'],
];
for (const [re, label] of credentials) {
  if (re.test(prompt)) {
    process.stderr.write(`Blocked: prompt may contain a real credential — ${label} (OWASP LLM02). Do not paste secrets; use env vars.\n`);
    process.exit(2);
  }
}
process.exit(0);
```

**`.claude/hooks/post-edit-typecheck.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on TS edits only. Feedback-only (never blocks).
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx) ;; *) exit 0 ;; esac
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
pnpm exec tsc --noEmit --incremental 2>&1 | tail -5
exit 0
```

**`.claude/hooks/post-tool-failure.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUseFailure — surface tool error context for self-correction. Always exit 0.
input=$(cat)
printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const d=JSON.parse(b||'{}');process.stderr.write('Tool failure: '+(d.tool_name||'unknown')+(d.error?(' — '+d.error):'')+'\n')}catch(e){}})" 2>/dev/null
exit 0
```

**`.claude/hooks/stop-checks.sh`**:
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(String(JSON.parse(b||'{}').stop_hook_active||false))}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] || [ "$active" = "True" ] && exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm test --run 2>&1); EC=$?
echo "$OUTPUT" | tail -20 >&2
[ $EC -ne 0 ] && exit 2 || exit 0
```

**`.claude/hooks/subagent-stop.sh`**:
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted TS changes so it can't hand back broken code.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
if git diff --name-only HEAD 2>/dev/null | grep -qE '\.(ts|tsx)$' || \
   git diff --cached --name-only 2>/dev/null | grep -qE '\.(ts|tsx)$'; then
  OUTPUT=$(pnpm exec tsc --noEmit 2>&1); EC=$?
  if [ $EC -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
exit 0
```

**`.claude/hooks/session-context.sh`**:
```bash
#!/usr/bin/env bash
# SessionStart(startup|resume|compact) — re-inject routing context + universal invariants.
# Plain stdout is added to Claude's context (per Claude Code hooks docs); this is what survives compaction.
echo "=== templateCentral routing context ==="
head -30 AGENTS.md 2>/dev/null

# If a CONSTITUTION.md exists, re-inject it (project binding invariants survive compaction)
if [ -f docs/CONSTITUTION.md ]; then
  echo ""
  echo "=== Project invariants (docs/CONSTITUTION.md) ==="
  cat docs/CONSTITUTION.md
fi

cat <<'EOF'

## Always-on invariants (survive compaction)
1. Secrets are never read or written by the agent — .env* and secrets/** are guarded.
2. Run the quality gate (typecheck + tests) before declaring any task done.
3. Work on a feature branch — never commit directly to main/uat/develop.
4. Protected files — AGENTS.md, CLAUDE.md, Dockerfile, .claude/settings.json, .claude/hooks/*, docs/CONSTITUTION.md — require human approval.
5. Respect the architecture/dependency boundaries documented in AGENTS.md and docs/CONSTITUTION.md.
EOF
```

Make all hook scripts executable:
```bash
chmod +x .claude/hooks/*.sh
```

Also create `FUTURE.md` at the project root:

**`FUTURE.md`**:
```markdown
# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** The disabled trace hook placeholder in `.claude/settings.json`.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated.*
```

### 6c. Create project skill files (`.claude/skills/`)

Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Run `mkdir -p .claude/skills/next-migrate .claude/skills/next-verify`, then create `.claude/skills/next-migrate/SKILL.md`:

```markdown
---
name: next-migrate
description: Run Drizzle push/migrate for this project with a safety gate.
allowed-tools: Bash(pnpm *)
---

Check that `src/integrations/database/` exists before running — database must be wired up first (`templatecentral:add (database)`).

- `pnpm db:push` — dev only, no migration files generated (schema overwrite)
- `pnpm db:migrate` — production-safe, generates migration files

Before running against production: verify `DATABASE_URL` in `.env.local` points to the correct instance.
```

Create `.claude/skills/next-verify/SKILL.md`:

```markdown
---
name: next-verify
description: Run typecheck + lint + test suite for this project in one pass.
allowed-tools: Bash(pnpm *)
---

Run `pnpm check && pnpm test` and report any failures.

- If `pnpm check` fails: fix TypeScript or lint errors before marking work done.
- If `pnpm test` fails: investigate root cause — do not skip or disable tests.
```

### 6d. Create `.claude/hooks/verify.sh`

Create `.claude/hooks/verify.sh`:

```bash
#!/bin/bash
# Verification gate — run after scaffold is complete
set -e
echo "Running verification gate..."
pnpm build
pnpm check
pnpm test
echo "All checks passed."
```

Run `chmod +x .claude/hooks/verify.sh`.

### 6e. Seed `docs/CONSTITUTION.md`

Create `docs/CONSTITUTION.md` as the binding invariants document for this project.
It takes precedence over `AGENTS.md` and all skill guidance when there is a conflict.
Fill in the `[...]` placeholders with the actual project values.

**`docs/CONSTITUTION.md`**:
```markdown
# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **[Project Name]**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Define the load-bearing architectural rules: layering, module boundaries,
factory/composition-root patterns, forbidden cross-imports, etc.]

## 3. Security Invariants

- Secrets NEVER appear in code, git, logs, or build output — use environment
  variables loaded from a secrets manager.
- All API routes authenticate before executing business logic.
- All mutations write to an audit log.

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 401, 200, and at least one error path.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- Every PR to `uat` and `main` requires the PR template fully filled.

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval noted in the PR under
`## Protected File Changes`. Agents MUST NOT modify them without approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Add project-specific protected files here]

### Behavioural rules

- Run the quality gate (`pnpm check` / `python -m pytest`) before declaring any task done.
- Never use `--no-verify` on commits — this bypasses pre-commit hooks.
- Work on a feature branch — never commit directly to `main`, `uat`, or `develop`.
```

### 6f. Create `.claude/harness.json`

After all harness files are written, compute SHA-256 hashes and write `.claude/harness.json`:

```bash
sha256_agents=$(shasum -a 256 AGENTS.md | cut -d' ' -f1)
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/*; do shasum -a 256 "$h"; done
sha256_claude=$(shasum -a 256 CLAUDE.md | cut -d' ' -f1)
sha256_settings=$(shasum -a 256 .claude/settings.json | cut -d' ' -f1)
sha256_verify_sh=$(shasum -a 256 .claude/hooks/verify.sh | cut -d' ' -f1)
sha256_migrate=$(shasum -a 256 .claude/skills/next-migrate/SKILL.md | cut -d' ' -f1)
sha256_verify=$(shasum -a 256 .claude/skills/next-verify/SKILL.md | cut -d' ' -f1)
```

Write `.claude/harness.json` with the computed values, replacing `<sha256_*>` placeholders and `<ISO-date>` with today's date:

```json
{
  "templatecentral_version": "4.6.0",
  "stack": "nextjs",
  "seeded_at": "<ISO-date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/settings.json": { "origin_hash": "<sha256_settings>", "path": ".claude/settings.json" },
    ".claude/hooks/verify.sh": { "origin_hash": "<sha256_verify_sh>", "path": ".claude/hooks/verify.sh" },
    ".claude/skills/next-migrate/SKILL.md": { "origin_hash": "<sha256_migrate>", "path": ".claude/skills/next-migrate/SKILL.md" },
    ".claude/skills/next-verify/SKILL.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/next-verify/SKILL.md" },
    ".claude/hooks/protect-files.sh": { "origin_hash": "<sha256_hook_1>", "path": ".claude/hooks/protect-files.sh" },
    ".claude/hooks/block-no-verify.sh": { "origin_hash": "<sha256_hook_2>", "path": ".claude/hooks/block-no-verify.sh" },
    ".claude/hooks/user-prompt-guard.js": { "origin_hash": "<sha256_hook_3>", "path": ".claude/hooks/user-prompt-guard.js" },
    ".claude/hooks/post-edit-typecheck.sh": { "origin_hash": "<sha256_hook_4>", "path": ".claude/hooks/post-edit-typecheck.sh" },
    ".claude/hooks/post-tool-failure.sh": { "origin_hash": "<sha256_hook_5>", "path": ".claude/hooks/post-tool-failure.sh" },
    ".claude/hooks/stop-checks.sh": { "origin_hash": "<sha256_hook_6>", "path": ".claude/hooks/stop-checks.sh" },
    ".claude/hooks/subagent-stop.sh": { "origin_hash": "<sha256_hook_7>", "path": ".claude/hooks/subagent-stop.sh" },
    ".claude/hooks/session-context.sh": { "origin_hash": "<sha256_hook_8>", "path": ".claude/hooks/session-context.sh" }
  }
}
```

### 6g. Create `.agents` symlink

Create a `.agents` symlink pointing to `.claude` so the project works with any agent framework that resolves from `.agents/`:

```bash
ln -s .claude .agents
```

This makes `AGENTS.md`, `settings.json`, `rules/`, `skills/`, and `hooks/` discoverable by Claude Code (`.claude/`) and any other tool that looks in `.agents/` — one source of truth, zero duplication.

### 7. Dispatch agents

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `templatecentral:build` — verify the scaffold compiles clean (`pnpm build && pnpm check`)
2. `templatecentral:test` — verify all scaffold tests pass (`pnpm test`)
3. `templatecentral:review` (update operation) — freshen all dependencies to latest compatible versions
4. `templatecentral:review` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 7b. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install caveman@caveman
claude plugin install superpowers@superpowers-marketplace
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

### 7c. Seed additional project skills

After all dispatch agents complete, ask the user: "Do you want to create project-scoped skills for any workflows you'll run regularly in this project?"

If yes — or if the user ran any workflow more than once during the scaffold process — create skills in `.claude/skills/`. Common candidates for new projects:

| Workflow | Suggested skill name | Body |
|----------|---------------------|------|
| Start dev + open browser | `dev-start` | `pnpm dev` + describe URL |
| Reset DB to clean state | `db-reset` | `pnpm db:push --force-reset` (dev only) |
| Generate a new shadcn component | `add-component` | `pnpm dlx shadcn@latest add <name>` |

Each skill gets a SKILL.md with `name:` and `description:` frontmatter and a short body. Skills capture this-project specifics — not generic advice that templateCentral already provides.

### 8. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This makes Claude Code automatically load `AGENTS.md` on every session without duplicating its content.

### 8b. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append this to the project's `AGENTS.md`:

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`. Skip for single-file edits or quick fixes.
```

### 9. Remove example code (optional)

Once the project is verified and the user confirms it runs, use the `templatecentral:cleanup` skill.

Next.js-specific steps (the skill covers these):
- Delete `src/features/example/` directory
- Remove `ExampleList` import from `src/app/dashboard/(overview)/page.tsx`

The `templatecentral:cleanup` skill handles both steps automatically.

---

## Rules

- Always update `package.json` name before `pnpm install` — affects Docker image names and lockfiles
- Always copy `.env.example` to `.env.local` before first run — never commit `.env.local`
- Never put secrets in `NEXT_PUBLIC_*` — exposed to every browser
- Never skip AGENTS.md — scaffolding is not complete without it
- Never copy `node_modules/` or `.next/` — generated at install/build time
- Remove example code after user confirms the project runs — use the `templatecentral:cleanup` skill (handles both `src/features/example/` deletion and the `ExampleList` import in `src/app/dashboard/(overview)/page.tsx`)

---

## Changelog

### 1.0.0
- Initial plugin release — hybrid rules + verbatim scaffold approach
- Replaces MCP-based `scaffold_project` file copy
- `templatecentral:review` (update) replaces lockfile for dependency freshness