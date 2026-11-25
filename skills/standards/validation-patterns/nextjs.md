<!-- ref: standards/validation-patterns/nextjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### Next.js (TypeScript + React + Zod)

Import shared schemas (`emailSchema`, `paginationSchema`, `fileUploadSchema`, …) from `src/lib/validation/schemas.ts` (`patterns.md`). The routes rely on `handleApiError`'s `ZodError` branch (400 + `fieldErrors` + `VALIDATION_ERROR`) from `templatecentral:add (error-handling)`; the scaffold default maps a `ZodError` to 500.

**1. Forms**

Form schemas live in `src/features/<name>/schemas/`, never in the component file, and are shared by the client resolver (`zodResolver`), the server action and the route. Type form data `z.input<typeof Schema>`, not `z.infer`: `.default()` and `.optional()` differ between input and output under `zodResolver`. Re-validate with `const parsed = Schema.safeParse(formData)` in the server action; it returns a plain serializable value, not an HTTP response, so it does not use `handleApiError`:

`return { error: 'Validation failed', details: { fieldErrors: z.flattenError(parsed.error).fieldErrors, code: 'VALIDATION_ERROR' } }`

Hand-rolled inputs need `aria-invalid` plus `aria-describedby` pointing at a `role="alert"` error node. Client error text: log the backend's message, show a fixed string; navigate with `router.push`, never `window.location.href`.

**2. API Route with Request Body Validation**

> **Never name a route segment under `/api/auth/`.** better-auth (`templatecentral:add (auth)`) owns the catch-all `src/app/api/auth/[...all]/route.ts`; a static sibling there would bypass its handling and rate limiting. Hence `/api/sessions`.

Routes call `schema.safeParse(await request.json())` and return `handleApiError(msg, parsed.error)` on failure; its `ZodError` branch emits the 400 + `fieldErrors` + `VALIDATION_ERROR` shape. Wrap handlers in `withLogging`.

**3. Query Parameter Validation**

`searchParams.get()` returns `null` for a missing param and `z.coerce.number()` turns `null` into `0`, so coalesce each value with `?? undefined` before `paginationSchema.safeParse` for `.default()` to apply. Check `sort` against a field whitelist before it reaches an ORM `orderBy` (`templatecentral:add (pagination)` provides `parseSortParam`).

**4. File Upload Validation**

`file.name` and `file.type` are attacker-controlled; validating them is a usability filter, not the security control. The schema cannot:

- **Cap size before buffering.** `await request.formData()` buffers the whole body, so a later `file.size` check cannot stop a memory DoS. Reject on `Content-Length` first and set the same ceiling at the platform edge (`next.config.ts` body limit / CDN / reverse proxy).
- **Verify content.** Sniff the buffer's magic bytes and match them to the allowed type before storing or serving.
- **Make the filename safe.** Do not derive a storage key or path from `file.name` (`../`, null bytes, collisions). Generate the key (e.g. a UUID); keep the name as metadata only.

```ts
// src/app/api/upload/route.ts
import { APIError } from '@/integrations/error';
import { handleApiError } from '@/lib/errors';
import { withLogging } from '@/lib/utils/with-logging';
import {
  ALLOWED_UPLOAD_TYPES,
  fileUploadSchema,
  MAX_UPLOAD_BYTES,
} from '@/lib/validation/schemas';
import { storeUpload } from '@/features/uploads/api/store-upload';
import { NextResponse } from 'next/server';

type AllowedType = (typeof ALLOWED_UPLOAD_TYPES)[number];

// Leading signature bytes per allowed type; for other formats use a maintained detector such as file-type.
const MAGIC_BYTES: Record<AllowedType, number[]> = {
  'image/png': [0x89, 0x50, 0x4e, 0x47],
  'image/jpeg': [0xff, 0xd8, 0xff],
  'application/pdf': [0x25, 0x50, 0x44, 0x46],
};

function matchesDeclaredType(buffer: ArrayBuffer, type: AllowedType): boolean {
  const signature = MAGIC_BYTES[type];
  if (buffer.byteLength < signature.length) return false;
  const head = new Uint8Array(buffer, 0, signature.length);
  return signature.every((byte, i) => head[i] === byte);
}

export const POST = withLogging(async (request) => {
  try {
    // Reject oversized bodies BEFORE formData() buffers them into memory
    const declaredLength = Number(request.headers.get('content-length') ?? 0);
    if (declaredLength > MAX_UPLOAD_BYTES) {
      return handleApiError('File too large', new APIError({ statusCode: 413 }));
    }

    const formData = await request.formData();
    const file = formData.get('file');

    // get() returns a string for a non-file field — narrow instead of casting
    if (!(file instanceof File)) {
      return handleApiError('File is required', new APIError({ statusCode: 400 }));
    }

    const parsed = fileUploadSchema.safeParse({
      name: file.name,
      size: file.size,
      type: file.type,
    });

    if (!parsed.success) {
      return handleApiError('Invalid file', parsed.error);
    }

    const buffer = await file.arrayBuffer();

    if (!matchesDeclaredType(buffer, parsed.data.type)) {
      return handleApiError('File content does not match its type', new APIError({ statusCode: 400 }));
    }

    // Never build a path from parsed.data.name
    const storageKey = crypto.randomUUID();
    await storeUpload(storageKey, buffer);

    return NextResponse.json({ data: { storageKey } }, { status: 201 });
  } catch (error) {
    return handleApiError('Upload failed', error);
  }
});
```

**5. External API Response Validation**

Shape only; `templatecentral:add (integration)` owns the real layer (`src/integrations/services/github-service.ts`). Encode every interpolated path segment (`encodeURIComponent`), throw `APIError` on a non-ok status, then `safeParse` the JSON. On a parse failure log `z.flattenError(parsed.error).fieldErrors` through `logError` and throw a generic `APIError` with status 502; never put the field detail in the thrown message.

## Rules

- Validate route params and query values with Zod, and `encodeURIComponent` any value interpolated into a path (`../` or `?` rewrites the URL)
- Throw `APIError`, never a generic `Error`, and keep validation field detail out of the message (error handling is keyed on `APIError`)

Verify: `POST /api/sessions` with `{"email":"not-an-email","password":"x"}` returns 400 with `fieldErrors.email`; `pnpm test`.

## After Writing Code

Dispatch in order:
1. the project's check command (`pnpm build && pnpm check`) — validate compilation
2. review utility (`cat "<skill-dir>/../review/SKILL.md"`) — check code standards