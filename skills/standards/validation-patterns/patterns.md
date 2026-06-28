<!-- ref: standards/validation-patterns/patterns.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Zod Pattern Library (Reusable)

Common schemas for TypeScript/Next.js projects:

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

// Basic types
export const emailSchema = z
  .email({ error: 'Invalid email address' })
  .transform(v => v.toLowerCase());

// Modern authenticator guidance: require length and screen against breached-password lists —
// do NOT impose character-composition rules. Long passphrases beat short complex strings.
export const passwordSchema = z
  .string()
  .min(12, 'Password must be at least 12 characters')
  .max(128, 'Password must be at most 128 characters');

export const uuidSchema = z
  .uuid();

export const urlSchema = z
  .url();

export const dateSchema = z
  .iso.datetime()
  .transform((val) => new Date(val));

// File validation
export const fileUploadSchema = z.object({
  name: z
    .string()
    .refine(
      (name) => {
        try {
          const decoded = decodeURIComponent(name);
          return (
            !decoded.includes('..') &&
            !decoded.startsWith('/') &&
            !decoded.startsWith('./') &&
            !decoded.includes('\x00')
          );
        } catch {
          return false;
        }
      },
      'Invalid filename'
    )
    .refine(
      (name) => {
        try {
          const decoded = decodeURIComponent(name);
          const ext = decoded.split('.').pop()?.toLowerCase();
          // Whitelist (Rule 5) — must stay in sync with the MIME whitelist below
          const allowed = ['jpg', 'jpeg', 'png', 'pdf'];
          return allowed.includes(ext || '');
        } catch {
          return false;
        }
      },
      'File type not allowed'
    ),
  size: z
    .number()
    .max(10 * 1024 * 1024, 'File must be under 10MB'),
  type: z
    .string()
    .refine(
      (type) => ['image/jpeg', 'image/png', 'application/pdf'].includes(type),
      'File type must be JPEG, PNG, or PDF'
    ),
});

// Forms
export const loginFormSchema = z.object({
  email: emailSchema,
  password: z.string().min(1, 'Password is required'),
  rememberMe: z.boolean().optional(),
});

export const signupFormSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
  confirmPassword: z.string(),
  termsAccepted: z.boolean().refine(
    (val) => val === true,
    'You must accept the terms'
  ),
}).refine(
  (data) => data.password === data.confirmPassword,
  {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  }
);

// API requests
export const createProjectSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be under 100 characters'),
  description: z
    .string()
    .max(500, 'Description must be under 500 characters')
    .optional(),
});

export const updateProjectSchema = createProjectSchema.partial();

// Query parameters
export const paginationSchema = z.object({
  page: z
    .string()
    .default('1')
    .pipe(z.coerce.number().int().positive()),
  limit: z
    .string()
    .default('10')
    .pipe(z.coerce.number().int().min(1).max(100)),
  sort: z
    .string()
    .regex(/^(asc|desc)_\w+$/, 'Invalid sort format')
    .optional(),
});

// External API response
export const externalApiUserSchema = z.looseObject({
  id: z.number().or(z.string()),
  email: emailSchema,
  name: z.string().optional(),
  createdAt: z.string().optional(),
}); // z.looseObject allows extra fields — new v4 shorthand; z.object(...).passthrough() also still works
```

**Schema Composition:**

```ts
// Combine schemas
const projectWithAuthor = createProjectSchema.extend({
  authorId: uuidSchema,
});

// Pick fields
const projectUpdate = createProjectSchema.pick({ name: true });

// Omit fields
const projectPublic = createProjectSchema.omit({ description: true });

// Discriminated unions (for polymorphic types)
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

## Rules

1. **All user input must be validated** — Forms (client + server), API body, query params, path params, file uploads
2. **Validation error must be field-level** — Map to form field names, not schema paths
3. **Server always validates independently** — Never trust client validation
4. **Never trust `request.json()`, `form.data`, or query params** — Always parse with Zod/Pydantic first
5. **File uploads must validate type, size, and filename** — Whitelist, reject `../` and suspicious extensions
6. **External API responses must be validated** — Use Zod `safeParse()` to handle API changes
7. **Validation happens before business logic** — Parse at route/controller entry point
8. **Errors are user-friendly** — Field-level messages, no raw validation paths or user input echoed back
9. **ORM queries use parameterization** — Never concatenate user input into SQL
10. **JSX auto-escapes** — React JSX prevents XSS; only use `dangerouslySetInnerHTML` for trusted content