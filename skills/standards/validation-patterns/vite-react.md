<!-- ref: standards/validation-patterns/vite-react.md
     loaded-by: standards/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### Vite + React (TypeScript + React Hook Form + Zod)

**1. Schemas live in `schemas/`, never in the component file**

Keeping the schema in its own module lets a service, a test, and a form validate against one definition:

```ts
// src/features/projects/schemas/create-project.schema.ts
import { z } from 'zod';

export const createProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name must be under 100 characters'),
  description: z.string().max(500, 'Description must be under 500 characters').optional(),
});

export type CreateProjectData = z.input<typeof createProjectSchema>;
```

Cross-feature schemas (`passwordSchema`, `emailSchema`, `fileUploadSchema`, `paginationSchema`) are defined once in `src/lib/validation/schemas.ts` (`patterns.md`) — import them, never copy them into a feature.

**2. Form Component with Validation**

```tsx
// src/features/projects/components/create-project-form.tsx
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '@/components/ui/button';
import { Form } from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { CustomFormField } from '@/components/widgets';
import { APIError, logError } from '@/lib/errors';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { createProject } from '../api/project-service';
import { createProjectSchema, type CreateProjectData } from '../schemas/create-project.schema';

export function CreateProjectForm() {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const form = useForm<CreateProjectData>({
    resolver: zodResolver(createProjectSchema),
    defaultValues: { name: '', description: '' },
  });

  const onSubmit = async (data: CreateProjectData) => {
    try {
      setSubmitError(null);
      await createProject(data);
      form.reset();
    } catch (error) {
      if (error instanceof APIError) {
        // The backend's error text is for engineers, not users — it can carry stack
        // traces, SQL fragments, or internal identifiers. Log it, show a fixed string.
        logError('CreateProjectForm: create failed', error);
        setSubmitError('Failed to create project. Please try again.');
        return;
      }
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

        {submitError && <p role="alert" className="text-sm text-destructive">{submitError}</p>}

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

**3. File Upload with Server-Side Validation (Critical)**

Client checks are fast feedback only — the server must repeat them and add the size cap, magic-byte sniff, and server-generated storage key (see the backend stack's `validation-patterns` file).

```tsx
// src/features/projects/components/file-upload-form.tsx
import { APIError, logError } from '@/lib/errors';
import {
  ALLOWED_UPLOAD_EXTENSIONS,
  fileUploadSchema,
} from '@/lib/validation/schemas';
import { type ChangeEvent, useState } from 'react';
import { z } from 'zod';
import { uploadProjectFile } from '../api/project-service';

// Derived from the same whitelist the schema checks, so picker and validator never disagree
const ACCEPT_ATTRIBUTE = ALLOWED_UPLOAD_EXTENSIONS.map((ext) => `.${ext}`).join(',');

export function FileUploadForm() {
  const [error, setError] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  const handleFileChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.currentTarget.files?.[0];
    if (!file) return;

    try {
      setError(null);
      setIsUploading(true);

      // Fast feedback only — the server repeats every one of these checks
      const validation = fileUploadSchema.safeParse({
        name: file.name,
        size: file.size,
        type: file.type,
      });

      if (!validation.success) {
        const firstError = Object.values(z.flattenError(validation.error).fieldErrors)[0]?.[0];
        setError(firstError || 'Invalid file');
        return;
      }

      const formData = new FormData();
      formData.append('file', file);
      await uploadProjectFile(formData);
    } catch (error) {
      if (error instanceof APIError) {
        // The backend's error text is for engineers, not users — log it, show a fixed string.
        logError('FileUploadForm: upload failed', error);
        setError('Upload failed. Please try again.');
        return;
      }
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
          accept={ACCEPT_ATTRIBUTE}
          onChange={handleFileChange}
          disabled={isUploading}
          aria-invalid={Boolean(error)}
          aria-describedby={error ? 'file-error' : undefined}
          className="w-full"
        />
        {error && (
          <p id="file-error" role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}
        <p aria-live="polite" className="text-sm text-primary">
          {isUploading ? 'Uploading...' : ''}
        </p>
      </div>
    </div>
  );
}
```

**4. Service through `ApiClient`, with Response Validation**

Both forms above and the read below call the backend through `ApiClient` (`src/lib/clients/api-client.ts` — the SPA's one backend client, defined in `templatecentral:standards (full-stack-pairing)`). It maps non-2xx to `APIError`, passes `FormData` through with the browser's multipart boundary, and — with `templatecentral:add (auth)` applied — sends the session cookie plus `X-CSRF-Token` on the POSTs. No paired backend means no `ApiClient`: these examples need one.

`id` arrives from `useParams` — it is user input, so it is validated before it is used and encoded before it is interpolated into a path. Validation rejects the wrong *kind* of value; `encodeURIComponent` stops a `/` or `?` in the value from rewriting the URL.

```ts
// src/features/projects/api/project-service.ts
import { ApiClient } from '@/lib/clients/api-client';
import { APIError, logError } from '@/lib/errors';
import { z } from 'zod';
import type { CreateProjectData } from '../schemas/create-project.schema';

const projectIdSchema = z.uuid();

const projectSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().optional(),
  createdAt: z.iso.datetime(),
});

type Project = z.infer<typeof projectSchema>;

class ProjectClient extends ApiClient {
  create(data: CreateProjectData): Promise<unknown> {
    return this.request('projects', 'POST', data);
  }

  upload(formData: FormData): Promise<unknown> {
    return this.request('projects/upload', 'POST', formData);
  }

  get(id: string): Promise<unknown> {
    return this.request(`projects/${encodeURIComponent(id)}`);
  }
}

// Lazy: ApiClient's constructor throws when VITE_API_BASE_URL is unset — at module scope
// that aborts bundle evaluation before createRoot() runs and renders a blank page.
let client: ProjectClient | undefined;
const projects = (): ProjectClient => (client ??= new ProjectClient());

export async function createProject(data: CreateProjectData): Promise<void> {
  await projects().create(data);
}

export async function uploadProjectFile(formData: FormData): Promise<void> {
  await projects().upload(formData);
}

export async function fetchProject(id: string): Promise<Project> {
  const parsedId = projectIdSchema.safeParse(id);
  if (!parsedId.success) {
    throw new APIError({ statusCode: 400, data: { message: 'Invalid project id.' } });
  }

  const parsed = projectSchema.safeParse(await projects().get(parsedId.data));
  if (!parsed.success) {
    // APIError, never a generic Error — the app's error handling is keyed on it.
    // Field detail goes to the log; the thrown message stays user-safe.
    logError(
      'fetchProject: response failed schema validation',
      new Error(JSON.stringify(z.flattenError(parsed.error).fieldErrors))
    );
    throw new APIError({
      statusCode: 502,
      data: { message: 'Received an unexpected response from the server.' },
    });
  }

  return parsed.data;
}
```

## Rules

- Schemas live in `schemas/` — NEVER define or export a schema from a component file
- Call the backend through an `ApiClient` subclass — NEVER raw `fetch` or a hardcoded `/api/...` path
- Always validate route params / query values with Zod before use, and `encodeURIComponent` any value interpolated into a path
- Throw `APIError`, never a generic `Error` — and never embed validation field detail in the thrown message
- NEVER render a backend error string to the user — log it, show a fixed generic message

## Testing / Verification

```bash
pnpm dev   # submit the form with invalid values — field errors render before any request
pnpm test
```

## See Also

- `templatecentral:add` (error-handling) — Transform validation errors to consistent response format
- `templatecentral:add` (logging) — Log validation failures with context
- Stack-specific `code-standards` — Type annotation and schema standards
- `templatecentral:add (endpoint)` / `templatecentral:add (form)` — Use validation patterns in new routes/forms

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards