---
name: add-form
description: Use when adding a form with validation to a Next.js project — covers React Hook Form setup, Zod schema definition, CustomFormField usage, and toast notifications.
---

# Add a Form to Next.js

Create a validated form in a Next.js project scaffolded from templateCentral using React Hook Form, Zod, and the existing `CustomFormField` widget.

## What the Template Already Provides

| Dependency / Component | Location |
|------------------------|----------|
| `react-hook-form` | `package.json` |
| `@hookform/resolvers` | `package.json` |
| `zod` | `package.json` |
| `Form` (FormProvider) | `src/components/ui/form.tsx` |
| `CustomFormField` | `src/components/widgets/custom-form-field.tsx` |
| `Input`, `Textarea`, `Select` | `src/components/ui/` |
| `Toaster` (Sonner) | Already in root layout |

## Inputs

- **Form name** — e.g., `contact`, `create-project`, `settings`
- **Fields** — List of field names, types, and validation rules

## Steps

### 1. Define the Zod Schema

Create the schema in the feature's `schemas/` directory:

**`src/features/<feature>/schemas/<form-name>.schema.ts`**:

```typescript
import { z } from 'zod';

export const contactFormSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email address'),
  message: z.string().min(10, 'Message must be at least 10 characters'),
});

export type ContactFormValues = z.infer<typeof contactFormSchema>;
```

### 2. Create the Form Component

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
    // TODO: replace with actual submission logic
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

### 3. Export from Feature Barrel

Add the form component to `src/features/<feature>/components/index.ts`:

```typescript
export { ContactForm } from './contact-form';
```

Ensure the feature root barrel (`src/features/<feature>/index.ts`) re-exports components:

```typescript
export * from './components';
```

### 4. Use in a Page

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
- Use `toast.success()` / `toast.error()` from Sonner for user feedback — the `Toaster` is already in the root layout.
- For server actions (Next.js), handle submission in an async `onSubmit` that calls the server action directly.
- Add `'use client'` directive — forms are inherently interactive.
