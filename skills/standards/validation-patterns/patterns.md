<!-- ref: standards/validation-patterns/patterns.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Zod Pattern Library (Reusable)

Shared Zod 4 schemas for the TS stacks (NestJS wraps them with `createZodDto`); FastAPI's Pydantic equivalents are in `fastapi.md`. The **Rules** apply to every stack.

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

export const emailSchema = z.email({ error: 'Invalid email address' }).toLowerCase();

// Require length and screen against breached-password lists; do NOT impose composition rules, since long passphrases beat short complex strings.
export const passwordSchema = z
  .string()
  .min(12, 'Password must be at least 12 characters')
  .max(128, 'Password must be at most 128 characters');

export const uuidSchema = z.uuid();
export const urlSchema = z.url();
export const dateSchema = z.iso.datetime().transform((val) => new Date(val));

// File metadata is client-claimed, so this schema is a usability filter: the server must still cap the body, verify magic bytes and generate its own storage key.
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

// Query values arrive as strings or null: coalesce to undefined so defaults apply; the limit ceiling stops a client requesting the whole table.
export const paginationSchema = z.object({
  // Capped: OFFSET cost grows with page, so an unbounded page is a cheap DoS lever.
  page: z.coerce.number().int().min(1, 'Page must be 1 or greater').max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(100, 'Limit must be 100 or less').default(10),
  sort: z.string().max(64).regex(/^(asc|desc)_\w+$/, 'Invalid sort format').optional(),
});

// External API responses: z.looseObject keeps unknown fields, z.object strips them
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

1. **Parse at the entry point** — body, query, path params, form data and uploads go through Zod/Pydantic before business logic; `request.json()` is `unknown` until parsed
2. **Server validates independently** — client validation is UX only; a crafted request skips it
3. **Field-level errors** — map to form field names (`z.flattenError`), not schema paths
4. **No echo** — error responses carry neither raw validation paths nor user input
5. **File uploads: cap, whitelist, sniff, rename** — cap body size before buffering, whitelist type/extension, verify magic bytes (the claimed type is attacker-controlled), generate the storage key server-side (a client filename can carry `../`). Untrusted uploaders: also scan for malware before storing or serving
6. **Validate external API responses** — Zod `safeParse()`; an upstream contract break must fail loudly, not flow through as typed data
