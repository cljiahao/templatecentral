<!-- ref: standards/validation-patterns/patterns.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Zod Pattern Library (Reusable)

Shared Zod 4 schemas for the TypeScript stacks (Next.js, Vite+React; NestJS wraps them with `createZodDto`). FastAPI uses the Pydantic equivalents in `fastapi.md`; the **Rules** at the bottom apply to every stack.

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

export const emailSchema = z.email({ error: 'Invalid email address' }).toLowerCase();

// Modern authenticator guidance: require length and screen against breached-password lists —
// do NOT impose character-composition rules. Long passphrases beat short complex strings.
export const passwordSchema = z
  .string()
  .min(12, 'Password must be at least 12 characters')
  .max(128, 'Password must be at most 128 characters');

export const uuidSchema = z.uuid();
export const urlSchema = z.url();
export const dateSchema = z.iso.datetime().transform((val) => new Date(val));

// File metadata (name/size/type) is client-claimed — this schema is a usability filter.
// The server must still cap the body before buffering, verify magic bytes, and generate
// its own storage key (never a path from `name`). See the per-stack upload examples.
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
export const ALLOWED_UPLOAD_EXTENSIONS = ['jpg', 'jpeg', 'png', 'pdf'] as const;
export const ALLOWED_UPLOAD_TYPES = ['image/jpeg', 'image/png', 'application/pdf'] as const;

export const fileUploadSchema = z.object({
  name: z
    .string()
    .min(1)
    .max(255)
    .refine(
      (name) => (ALLOWED_UPLOAD_EXTENSIONS as readonly string[]).includes(
        name.split('.').pop()?.toLowerCase() ?? ''
      ),
      'File type not allowed'
    ),
  size: z.number().int().positive().max(MAX_UPLOAD_BYTES, 'File must be under 10MB'),
  type: z.enum(ALLOWED_UPLOAD_TYPES, { error: 'File type must be JPEG, PNG, or PDF' }),
});

export const loginFormSchema = z.object({
  email: emailSchema,
  // Login only checks presence — the length policy is a signup/reset rule
  password: z.string().min(1, 'Password is required'),
  rememberMe: z.boolean().default(false),
});

export const signupFormSchema = z
  .object({
    email: emailSchema,
    password: passwordSchema,
    confirmPassword: z.string(),
    termsAccepted: z.literal(true, { error: 'You must accept the terms' }),
  })
  .refine((data) => data.password === data.confirmPassword, {
    error: 'Passwords do not match',
    path: ['confirmPassword'],
  });

export const createProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name must be under 100 characters'),
  description: z.string().max(500, 'Description must be under 500 characters').optional(),
});

export const updateProjectSchema = createProjectSchema.partial();

// Query values arrive as strings (or null from URLSearchParams.get — coalesce to undefined
// so the defaults apply). The `limit` ceiling is what stops a client requesting the whole table.
export const paginationSchema = z.object({
  // Capped: OFFSET cost grows with page, so an unbounded page is a cheap DoS lever.
  page: z.coerce.number().int().min(1, 'Page must be 1 or greater').max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(100, 'Limit must be 100 or less').default(10),
  sort: z.string().max(64).regex(/^(asc|desc)_\w+$/, 'Invalid sort format').optional(),
});

// External API responses: z.looseObject keeps unknown fields (z.object strips them)
export const externalApiUserSchema = z.looseObject({
  id: z.union([z.number(), z.string()]),
  email: emailSchema,
  name: z.string().optional(),
  createdAt: z.string().optional(),
});
```

**Schema Composition:**

```ts
const projectWithAuthor = createProjectSchema.extend({
  authorId: uuidSchema,
});

const projectUpdate = createProjectSchema.pick({ name: true });

const projectPublic = createProjectSchema.omit({ description: true });

const eventSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('user-created'),
    userId: uuidSchema,
  }),
  z.object({
    type: z.literal('project-updated'),
    projectId: uuidSchema,
  }),
]);
```

### Field-level error formatting

```ts
const result = schema.safeParse(input);
if (!result.success) {
  const { fieldErrors } = z.flattenError(result.error);
  // { fieldName: ["message"] } — maps straight onto form fields
  return { errors: fieldErrors };
}
```

Zod 4: use top-level `z.flattenError(err)` for field errors and `err.issues` for the raw list — the v3 instance helpers are gone.

## Rules

1. **All user input must be validated** — Forms (client + server), API body, query params, path params, file uploads
2. **Validation error must be field-level** — Map to form field names, not schema paths
3. **Server always validates independently** — Never trust client validation
4. **Never trust `request.json()`, `form.data`, or query params** — Always parse with Zod/Pydantic first
5. **File uploads: cap, whitelist, sniff, rename** — Cap body size before buffering, whitelist type/extension, verify magic bytes, and generate the storage key server-side (never a path from the client filename)
6. **External API responses must be validated** — Use Zod `safeParse()` to handle API changes
7. **Validation happens before business logic** — Parse at route/controller entry point
8. **Errors are user-friendly** — Field-level messages, no raw validation paths or user input echoed back
9. **ORM queries use parameterization** — Never concatenate user input into SQL
10. **JSX auto-escapes** — React JSX prevents XSS; only use `dangerouslySetInnerHTML` for trusted content