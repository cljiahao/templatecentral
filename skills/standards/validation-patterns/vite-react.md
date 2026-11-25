<!-- ref: standards/validation-patterns/vite-react.md
     loaded-by: standards/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### Vite + React (TypeScript + React Hook Form + Zod)

**1. Forms and uploads**

Schemas live in `src/features/<name>/schemas/`, never in the component file, and are shared by the service, the test and the form (`zodResolver`). Cross-feature schemas (`passwordSchema`, `emailSchema`, `fileUploadSchema`, `paginationSchema`) are defined once in `src/lib/validation/schemas.ts` (`patterns.md`); import them, never copy them into a feature.

Use `CustomFormField` (`src/components/widgets/custom-form-field.tsx`: `name`, `label`, optional `description`, one input child); it wires the Controller, label and error message via `useFormContext()`. Do not wrap it in `FormField`/`FormControl`/`FormItem` or spread `{...field}` onto it. Show a fixed message on `APIError` and `logError` the backend text.

Upload forms: derive the `accept` attribute from `ALLOWED_UPLOAD_EXTENSIONS` so picker and validator agree, and read the first message from `z.flattenError(result.error).fieldErrors`. Client checks are fast feedback only; the server repeats them and adds the size cap, magic-byte sniff and server-generated storage key (see the backend stack's `validation-patterns` file).

**2. Service through `ApiClient`, with Response Validation**

Every call goes through `ApiClient` (`src/lib/clients/api-client.ts`, defined in `templatecentral:standards (full-stack-pairing)`): it maps non-2xx to `APIError`, passes `FormData` through, and — with `templatecentral:add (auth)` — sends the session cookie plus `X-CSRF-Token` on POSTs. These examples need a paired backend.

`id` from `useParams` is user input: validate it, then `encodeURIComponent` it so a `/` or `?` cannot rewrite the URL.

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

// Lazy: ApiClient throws when VITE_API_BASE_URL is unset, and at module scope that aborts bundle evaluation and blanks the page.
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
    // APIError, never a generic Error: error handling is keyed on it, and field detail goes to the log, not the message.
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

- Call the backend through an `ApiClient` subclass, not raw `fetch` or a hardcoded `/api/...` path (it maps non-2xx to `APIError` and adds the CSRF header)
- Validate route params and query values with Zod, and `encodeURIComponent` any value interpolated into a path (`../` or `?` rewrites the URL)
- Throw `APIError`, never a generic `Error`, and keep validation field detail out of the message (error handling is keyed on `APIError`)
- Never render a backend error string; log it, show a fixed message (it can carry stack traces or SQL)

Verify: submit the form with invalid values (field errors render before any request); `pnpm test`.

## After Writing Code

Dispatch in order:
1. build utility (`cat "<skill-dir>/../build/SKILL.md"`) — validate compilation
2. review utility (`cat "<skill-dir>/../review/SKILL.md"`) — check code standards