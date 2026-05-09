### Next.js (TypeScript + React + Zod)

**1. Form Schema with Client & Server Validation**

```ts
// src/features/auth/schemas/login-form.ts
import { z } from 'zod';

export const LoginFormSchema = z.object({
  email: z
    .email('Invalid email address')
    .toLowerCase(),
  password: z
    .string()
    .min(1, 'Password is required'),
  rememberMe: z.boolean().optional().default(false),
});

export type LoginFormData = z.infer<typeof LoginFormSchema>;
```

**2. React Hook Form + Client Validation**

```tsx
// src/features/auth/components/login-form.tsx
'use client';

import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { LoginFormSchema, type LoginFormData } from '../schemas/login-form';

export function LoginForm() {
  const [error, setError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormData>({
    resolver: zodResolver(LoginFormSchema),
  });

  const onSubmit = async (data: LoginFormData) => {
    try {
      setError(null);
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      });

      if (!response.ok) {
        const body = await response.json();
        setError(body.error || 'Login failed');
        return;
      }

      // Redirect on success
      window.location.href = '/dashboard';
    } catch (err) {
      setError('An unexpected error occurred');
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label htmlFor="email">Email</label>
        <input
          id="email"
          type="email"
          placeholder="user@example.com"
          {...register('email')}
          className="w-full rounded border px-3 py-2"
        />
        {errors.email && (
          <p className="text-sm text-red-600">{errors.email.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="password">Password</label>
        <input
          id="password"
          type="password"
          {...register('password')}
          className="w-full rounded border px-3 py-2"
        />
        {errors.password && (
          <p className="text-sm text-red-600">{errors.password.message}</p>
        )}
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <button
        type="submit"
        disabled={isSubmitting}
        className="w-full rounded bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
      >
        {isSubmitting ? 'Logging in...' : 'Login'}
      </button>
    </form>
  );
}
```

**3. Server Action with Zod Validation**

```ts
// src/features/auth/actions/login.ts
'use server';

import { z } from 'zod';
import { LoginFormSchema } from '../schemas/login-form';

export async function loginAction(formData: unknown) {
  // Validate on server
  const parsed = LoginFormSchema.safeParse(formData);

  if (!parsed.success) {
    return {
      error: 'Validation failed',
      fieldErrors: z.flattenError(parsed.error).fieldErrors,
    };
  }

  // Call your auth logic here using parsed.data

  return { success: true };
}
```

**4. API Route with Request Body Validation**

```ts
// src/app/api/auth/login/route.ts
import { z } from 'zod';
import { handleApiError } from '@/lib/errors';
import { LoginFormSchema } from '@/features/auth/schemas/login-form';
import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const parsed = LoginFormSchema.safeParse(body);

    if (!parsed.success) {
      return NextResponse.json(
        {
          error: 'Validation failed',
          details: {
            fieldErrors: z.flattenError(parsed.error).fieldErrors,
            code: 'VALIDATION_ERROR',
          },
        },
        { status: 400 }
      );
    }

    // Call your auth logic here using parsed.data

    return NextResponse.json({ data: { success: true } }, { status: 200 });
  } catch (error) {
    return handleApiError('Login failed', error);
  }
}
```

**5. Query Parameter Validation**

```ts
// src/app/api/projects/route.ts
import { z } from 'zod';
import { paginationSchema } from '@/lib/validation/schemas';
import { NextResponse } from 'next/server';

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const queryObj = {
      page: searchParams.get('page'),
      limit: searchParams.get('limit'),
      sort: searchParams.get('sort'),
    };

    const parsed = paginationSchema.safeParse(queryObj);

    if (!parsed.success) {
      return NextResponse.json(
        {
          error: 'Invalid query parameters',
          details: {
            fieldErrors: z.flattenError(parsed.error).fieldErrors,
          },
        },
        { status: 400 }
      );
    }

    // Use parsed.data.page, parsed.data.limit, parsed.data.sort
    const projects = []; // Your logic

    return NextResponse.json({ data: projects });
  } catch (error) {
    return handleApiError('Failed to fetch projects', error);
  }
}
```

**6. File Upload Validation**

```ts
// src/app/api/upload/route.ts
import { z } from 'zod';
import { fileUploadSchema } from '@/lib/validation/schemas';
import { handleApiError } from '@/lib/errors';
import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  try {
    const formData = await request.formData();
    const file = formData.get('file') as File | null;

    if (!file) {
      return NextResponse.json(
        { error: 'File is required' },
        { status: 400 }
      );
    }

    // Validate file
    const parsed = fileUploadSchema.safeParse({
      name: file.name,
      size: file.size,
      type: file.type,
    });

    if (!parsed.success) {
      return NextResponse.json(
        {
          error: 'Invalid file',
          details: {
            fieldErrors: z.flattenError(parsed.error).fieldErrors,
          },
        },
        { status: 400 }
      );
    }

    // Safe to use: parsed.data.name, file bytes
    const buffer = await file.arrayBuffer();
    // Call your storage upload logic here using parsed.data.name and buffer

    return NextResponse.json(
      { url: 'https://example.com/file.pdf' },
      { status: 201 }
    );
  } catch (error) {
    return handleApiError('Upload failed', error);
  }
}
```

**7. External API Response Validation**

```ts
// src/integrations/services/github-service.ts
import { z } from 'zod';
import { externalApiUserSchema } from '@/lib/validation/schemas';

export async function fetchGithubUser(username: string) {
  const response = await fetch(`https://api.github.com/users/${username}`);

  if (!response.ok) {
    throw new Error('GitHub API error');
  }

  const data = await response.json();

  // Validate response matches schema
  const parsed = externalApiUserSchema.safeParse(data);

  if (!parsed.success) {
    throw new Error('Invalid GitHub API response');
  }

  // Safe to use: parsed.data has required fields
  return {
    id: parsed.data.id,
    email: parsed.data.email,
  };
}
```

## Testing / Verification

```bash
# Test form validation (client-side error before server)
pnpm dev
# Fill form incorrectly, verify errors appear

# Test API validation (server-side)
curl -X POST http://localhost:3000/api/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'  # Should return 400

pnpm test
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards