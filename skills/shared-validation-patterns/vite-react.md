### Vite + React (TypeScript + React Hook Form + Zod)

**1. Form Component with Validation**

```tsx
// src/features/projects/components/create-project-form.tsx
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

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

type CreateProjectData = z.infer<typeof createProjectSchema>;

export function CreateProjectForm() {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<CreateProjectData>({
    resolver: zodResolver(createProjectSchema),
  });

  const onSubmit = async (data: CreateProjectData) => {
    try {
      setSubmitError(null);
      const response = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        const body = await response.json();
        setSubmitError(body.error || 'Failed to create project');
        return;
      }

      // Success
    } catch (err) {
      setSubmitError('An unexpected error occurred');
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label htmlFor="name">Name</label>
        <input
          id="name"
          type="text"
          placeholder="Project name"
          {...register('name')}
          className="w-full rounded border px-3 py-2"
        />
        {errors.name && (
          <p className="text-sm text-red-600">{errors.name.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="description">Description</label>
        <textarea
          id="description"
          placeholder="Project description (optional)"
          {...register('description')}
          className="w-full rounded border px-3 py-2"
        />
        {errors.description && (
          <p className="text-sm text-red-600">{errors.description.message}</p>
        )}
      </div>

      {submitError && <p className="text-sm text-red-600">{submitError}</p>}

      <button
        type="submit"
        disabled={isSubmitting}
        className="w-full rounded bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
      >
        {isSubmitting ? 'Creating...' : 'Create Project'}
      </button>
    </form>
  );
}
```

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
    error: () => ({ message: 'Only JPEG, PNG, and PDF files allowed' }),
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
    } catch (err) {
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
    throw new Error(`Failed to fetch project: ${response.status}`);
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

- `shared-add-error-handling` — Transform validation errors to consistent response format
- `shared-add-logging` — Log validation failures with context
- Stack-specific `code-standards` — Type annotation and schema standards
- Stack-specific `add-api-route`, `add-endpoint`, `add-form` — Use validation patterns in new routes/forms

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
