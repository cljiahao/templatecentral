<!-- ref: standards/validation-patterns/vite-react.md
     loaded-by: standards/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### Vite + React (TypeScript + React Hook Form + Zod)

**1. Form Component with Validation**

```tsx
// src/features/projects/components/create-project-form.tsx
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Form } from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { CustomFormField } from '@/components/widgets';
import { Button } from '@/components/ui/button';

const createProjectSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be under 100 characters'),
  description: z
    .string()
    .max(500, 'Description must be under 500 characters')
    .optional(),
});

// Password fields: enforce length first (≥ 12 characters), then basic complexity.
// Length matters more than exotic character rules — long passphrases beat short complex strings.
export const passwordSchema = z
  .string()
  .min(12, 'Password must be at least 12 characters')
  .regex(/[a-z]/, 'Must contain a lowercase letter')
  .regex(/[A-Z]/, 'Must contain an uppercase letter')
  .regex(/[0-9]/, 'Must contain a number');

type CreateProjectData = z.input<typeof createProjectSchema>;

export function CreateProjectForm() {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const form = useForm<CreateProjectData>({
    resolver: zodResolver(createProjectSchema),
    defaultValues: { name: '', description: '' },
  });

  const onSubmit = async (data: CreateProjectData) => {
    try {
      setSubmitError(null);
      const response = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
        credentials: 'include',
      });

      if (!response.ok) {
        const body = await response.json();
        setSubmitError(body.error || 'Failed to create project');
        return;
      }

      // Success
    } catch {
      setSubmitError('An unexpected error occurred');
    }
  };

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <CustomFormField name="name" label="Name">
          <Input placeholder="Project name" />
        </CustomFormField>

        <CustomFormField name="description" label="Description">
          <Input placeholder="Project description (optional)" />
        </CustomFormField>

        {submitError && <p className="text-sm text-red-600">{submitError}</p>}

        <Button
          type="submit"
          disabled={form.formState.isSubmitting}
          className="w-full"
        >
          {form.formState.isSubmitting ? 'Creating...' : 'Create Project'}
        </Button>
      </form>
    </Form>
  );
}
```

`CustomFormField` (`src/components/widgets/custom-form-field.tsx`) takes `name`, `label`, optional `description`, and a single input child — it wires the Controller, label, and error message internally via `useFormContext()`. Do NOT wrap it in `FormField`/`FormControl`/`FormItem` or spread `{...field}` onto it.

**2. File Upload with Server-Side Validation (Critical)**

⚠️ **Important:** Client validation can be bypassed. Server-side validation is MANDATORY.

```tsx
// src/features/projects/components/file-upload-form.tsx
import { type ChangeEvent, useState } from 'react';
import { z } from 'zod';

const fileUploadSchema = z.object({
  filename: z
    .string()
    .min(1, 'Filename is required')
    .refine((name) => !name.includes('..'), 'Invalid filename')
    .refine((name) => !name.startsWith('/'), 'Invalid filename')
    .refine((name) => !name.includes('\x00'), 'Invalid filename'),
  size: z.number().max(10 * 1024 * 1024, 'File must be under 10MB'),
  type: z.enum(['image/jpeg', 'image/png', 'application/pdf'], {
    error: 'Only JPEG, PNG, and PDF files allowed',
  }),
});

export function FileUploadForm() {
  const [error, setError] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  const handleFileChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.currentTarget.files?.[0];
    if (!file) return;

    try {
      setError(null);
      setIsUploading(true);

      // Client-side validation (user feedback only)
      const validation = fileUploadSchema.safeParse({
        filename: file.name,
        size: file.size,
        type: file.type,
      });

      if (!validation.success) {
        const firstError = Object.values(z.flattenError(validation.error).fieldErrors)[0]?.[0];
        setError(firstError || 'Invalid file');
        return;
      }

      // Upload to server
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch('/api/projects/upload', {
        method: 'POST',
        body: formData,
        // Note: Don't set Content-Type; browser handles multipart
      });

      if (!response.ok) {
        const data = await response.json();
        setError(data.error || 'Upload failed');
        return;
      }

      // Success - file is uploaded and server-validated
    } catch {
      setError('An error occurred during upload');
    } finally {
      setIsUploading(false);
    }
  };

  return (
    <div className="space-y-4">
      <div>
        <label htmlFor="file">Upload File</label>
        <input
          id="file"
          type="file"
          accept=".jpg,.jpeg,.png,.pdf"
          onChange={handleFileChange}
          disabled={isUploading}
          className="w-full"
        />
        {error && <p className="text-sm text-red-600">{error}</p>}
        {isUploading && <p className="text-sm text-blue-600">Uploading...</p>}
      </div>
    </div>
  );
}
```

**3. API Client with Response Validation**

```ts
// src/lib/clients/api-client.ts
import { z } from 'zod';
import { APIError } from '@/lib/errors';

const projectSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().optional(),
  createdAt: z.iso.datetime(),
});

type Project = z.infer<typeof projectSchema>;

export async function fetchProject(id: string): Promise<Project> {
  const response = await fetch(`/api/projects/${id}`);

  if (!response.ok) {
    throw new APIError({ statusCode: response.status, data: await response.json().catch(() => ({ message: 'Failed to fetch project' })) });
  }

  const data = await response.json();

  // Validate response shape
  const parsed = projectSchema.safeParse(data);

  if (!parsed.success) {
    throw new Error('Invalid API response');
  }

  return parsed.data;
}
```

## Testing / Verification

```bash
pnpm dev

# Test form validation (client shows error)
# Submit invalid form, verify errors appear

# Test API response validation (if API changes, error caught)
pnpm test
```

## See Also

- `templatecentral:add` (error-handling) — Transform validation errors to consistent response format
- `templatecentral:add` (logging) — Log validation failures with context
- Stack-specific `code-standards` — Type annotation and schema standards
- Stack-specific `add-api-route`, `add-endpoint`, `add-form` — Use validation patterns in new routes/forms

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards