---
name: add-form
description: Use when adding a form with validation to a Vite + React project — covers React Hook Form setup, Zod schema definition, CustomFormField usage, and toast notifications.
---

# Add a Form to Vite + React

Create a validated form in a Vite + React SPA scaffolded from templateCentral using React Hook Form, Zod, and the `CustomFormField` widget.

## What the Template Provides

| Dependency / Component | Location |
|------------------------|----------|
| `react-hook-form` | `package.json` |
| `@hookform/resolvers` | `package.json` |
| `zod` | `package.json` |
| `Form` (FormProvider) | `src/components/ui/form.tsx` |
| `CustomFormField` | `src/components/widgets/custom-form-field.tsx` |
| `Input`, `Textarea`, `Select` | `src/components/ui/` |
| `Toaster` (Sonner) | Already in Providers |

## Inputs

- **Form name** — e.g., `contact`, `create-project`, `settings`
- **Fields** — List of field names, types, and validation rules

## Steps

### 1. Define the Zod Schema

**`src/features/<feature>/schemas/<form-name>.schema.ts`**:

```typescript
import { z } from 'zod';

export const contactFormSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email address'),
  message: z.string().min(10, 'Message must be at least 10 characters'),
});

export type ContactFormValues = z.input<typeof contactFormSchema>;
```

> **Zod v4 note**: Use `z.input` (not `z.infer`) for form value types. `z.input` gives the **input** type (what the user types), while `z.infer` gives the **output** type (after transforms like `.default()`, `.coerce`). `useForm` works with input types.

### 2. Create the Form Component

**`src/features/<feature>/components/<form-name>-form.tsx`**:

```tsx
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

  const onSubmit = async (values: ContactFormValues) => {
    // TODO: replace with actual API call
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

Add to `src/features/<feature>/components/index.ts`:

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

export function ContactPage() {
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

- Always define the Zod schema in a separate file under `schemas/` — not inline.
- Use `CustomFormField` for all fields — it handles label, error display, and Controller wiring.
- Use `Form` from `@/components/ui/form` to wrap the form — it re-exports `FormProvider` and `CustomFormField` uses `useFormContext()`.
- Set `defaultValues` for all fields.
- Use `toast.success()` / `toast.error()` from Sonner for feedback.
- For complex validation (file uploads, password rules, OWASP/CWE compliance): use `shared/validation-patterns/SKILL.md`.
