<!-- ref: add/form/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Form to Next.js

Create a validated form in a Next.js project scaffolded from templateCentral using React Hook Form, Zod, and the existing `CustomFormField` widget.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## What the Template Already Provides

| Dependency / Component | Location |
|------------------------|----------|
| `react-hook-form` | `package.json` |
| `@hookform/resolvers` | `package.json` |
| `zod` | `package.json` |
| `Form` (FormProvider) | `src/components/ui/form.tsx` |
| `CustomFormField` | `src/components/widgets/custom-form-field.tsx` |
| `Input`, `Textarea`, `Select` | `src/components/ui/` |
| `sonner` (Toaster) | `package.json` + `<Toaster />` mounted in `src/components/layout/providers.tsx` |

## Inputs

- **Form name** — e.g., `contact`, `create-project`, `settings`
- **Fields** — List of field names, types, and validation rules

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Toast feedback — already wired

The scaffold pre-installs `sonner` and mounts `<Toaster />` in `src/components/layout/providers.tsx` — call `toast.success()` / `toast.error()` directly; no setup needed. **Skip this step** for scaffolded projects.

**Fallback (non-scaffold projects only):** if `sonner` is missing from `package.json`, run:

```bash
npx shadcn@latest add sonner
```

Then mount exactly one `<Toaster />` in a shared client provider (e.g. inside `Providers`):

```tsx
import { Toaster } from 'sonner';
// ...
<Providers>
  {children}
  <Toaster richColors />
</Providers>
```

Never mount more than one `<Toaster />` — duplicate toasts result.

### 2. Define the Zod Schema


Create the schema in the feature's `schemas/` directory:

**`src/features/<feature>/schemas/<form-name>.schema.ts`**:

```typescript
import { z } from 'zod';

export const contactFormSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.email({ error: 'Invalid email address' }),
  message: z.string().min(10, 'Message must be at least 10 characters'),
});

export type ContactFormValues = z.input<typeof contactFormSchema>;
```

> **Zod v4 note**: Use `z.input` (not `z.infer`) for form value types. `z.input` gives the **input** type (what the user types), while `z.infer` gives the **output** type (after transforms like `.default()`, `.coerce`). `useForm` works with input types.

### 3. Create the Form Component

**`src/features/<feature>/components/<form-name>-form.tsx`**:

```tsx
'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { Form } from '@/components/ui/form';
import { toast } from 'sonner';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { CustomFormField } from '@/components/widgets';

import {
  contactFormSchema,
  type ContactFormValues,
} from '../schemas/contact.schema';

export function ContactForm() {
  const form = useForm<ContactFormValues>({
    resolver: zodResolver(contactFormSchema),
    defaultValues: {
      name: '',
      email: '',
      message: '',
    },
  });

  const onSubmit = (values: ContactFormValues) => {
    // TODO: replace with a real submit (server action / API call) using `values`
    console.log(values);
    toast.success('Form submitted successfully!');
    form.reset();
  };

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
        <CustomFormField name="name" label="Name">
          <Input placeholder="Your name" />
        </CustomFormField>

        <CustomFormField name="email" label="Email">
          <Input type="email" placeholder="you@example.com" />
        </CustomFormField>

        <CustomFormField name="message" label="Message" description="Minimum 10 characters.">
          <Textarea placeholder="Your message..." />
        </CustomFormField>

        <Button type="submit" disabled={form.formState.isSubmitting}>
          {form.formState.isSubmitting ? 'Submitting...' : 'Submit'}
        </Button>
      </form>
    </Form>
  );
}
```

### 4. Export from Feature Barrel

Add the form component to `src/features/<feature>/components/index.ts`:

```typescript
export { ContactForm } from './contact-form';
```

Ensure the feature root barrel (`src/features/<feature>/index.ts`) re-exports components:

```typescript
export * from './components';
```

### 5. Use in a Page

```tsx
import { ContactForm } from '@/features/<feature>';

export default function ContactPage() {
  return (
    <div className="max-w-site mx-auto px-6 py-12">
      <h1 className="text-3xl font-bold">Contact Us</h1>
      <div className="mt-8 max-w-md">
        <ContactForm />
      </div>
    </div>
  );
}
```

## Rules

- Always define the Zod schema in a separate file under `schemas/` — not inline in the component.
- Use `CustomFormField` for all fields — it handles label, error display, and Controller wiring automatically.
- Use `Form` from `@/components/ui/form` to wrap the form — it re-exports `FormProvider` and `CustomFormField` uses `useFormContext()`.
- Set `defaultValues` for all fields to avoid uncontrolled-to-controlled warnings.
- Use `toast.success()` / `toast.error()` from Sonner for user feedback — install sonner and add `<Toaster />` to root layout first (see Step 1).
- For server actions (Next.js), handle submission in an async `onSubmit` that calls the server action directly.
- Add `'use client'` directive — forms are inherently interactive.
- For complex validation (file uploads, password rules, OWASP/CWE compliance): use `templatecentral:standards` (validation-patterns).

## Validate

```bash
pnpm build    # zero errors
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards