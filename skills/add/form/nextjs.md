<!-- ref: add/form/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Form to Next.js

## Inputs

- **Form name** — e.g., `contact`, `create-project`, `settings`
- **Fields** — List of field names, types, and validation rules

## Steps

### 1. Define the Zod Schema

`sonner` and one `<Toaster />` are already mounted in `providers.tsx` — call `toast.*` directly (otherwise `npx shadcn@latest add sonner` and mount exactly one `<Toaster />`).

**`src/features/<feature>/schemas/<form-name>.schema.ts`**:

```typescript
import { z } from 'zod';

// One source of truth for the constraint, its error copy and the hint.
export const MESSAGE_MIN_LENGTH = 10;

export const contactFormSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  email: z.email({ error: 'Invalid email address' }),
  message: z
    .string()
    .min(MESSAGE_MIN_LENGTH, `Message must be at least ${MESSAGE_MIN_LENGTH} characters`)
    .max(2000),
});

export type ContactFormValues = z.input<typeof contactFormSchema>;
```

> **Zod v4 note**: type form values with `z.input` (what the user types), not `z.infer` (the post-transform output); `useForm` works with input types.

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
  MESSAGE_MIN_LENGTH,
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

  // Async so formState.isSubmitting tracks the returned promise.
  const onSubmit = async (_values: ContactFormValues) => {
    // TODO: call the server action; never echo `values` into a toast or Error.
    toast.error('Submit handler not wired yet');
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

        <CustomFormField
          name="message"
          label="Message"
          description={`Minimum ${MESSAGE_MIN_LENGTH} characters.`}
        >
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

Create the route with `templatecentral:add (page)` — it covers placement and, once auth is installed, the `PUBLIC_PATHS` entry a public form page needs.

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

- **Client-side validation is not a security boundary** — any client can skip `zodResolver`. The server action / route handler re-parses the same schema (`contactFormSchema.safeParse(values)`) and reject on failure before any side effect.
- Complex validation (files, passwords, OWASP/CWE): `templatecentral:standards` (validation-patterns).
