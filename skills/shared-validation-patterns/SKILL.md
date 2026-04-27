---
name: validation-patterns
description: Use to add consistent input validation across all stacks — covers Zod schemas, Pydantic models, OWASP/CWE compliance, file uploads, and error transformation patterns.
---

# Validation Patterns & Sanitization

Implement consistent input validation at all entry points: form submissions, API endpoints, query parameters, file uploads, and external API responses. Use Zod (TypeScript) or Pydantic (Python) to enforce type safety and prevent common vulnerabilities (SQL injection, XSS, path traversal).

## When to Use

- Creating forms with client and server validation
- Building API endpoints that accept user input
- Validating query parameters, path parameters, or file uploads
- Consuming external APIs and validating responses
- Ensuring OWASP/CWE compliance (SQL injection, XSS, path traversal)

## Security Checklist

- [ ] **CWE-89 (SQL Injection)** — Use ORM parameterization or prepared statements; never concatenate user input into queries
- [ ] **CWE-79 (XSS)** — React JSX auto-escapes; Zod/Pydantic validates types; never use `dangerouslySetInnerHTML` with user input
- [ ] **CWE-22 (Path Traversal)** — Reject filenames with `../` or `/`, validate against whitelist, never use user input directly in `fs.readFile()`
- [ ] **CWE-352 (CSRF)** — Framework-handled by SameSite cookies and CSRF tokens; validate origin headers
- [ ] **CWE-287 (Auth Bypass)** — Route/controller-level auth checks before processing user input; never skip auth in business logic
- [ ] **CWE-434 (File Upload)** — Validate file type (whitelist), size, reject suspicious extensions (`.exe`, `.sh`)
- [ ] **CWE-400 (Uncontrolled Resource)** — Rate limit uploads, reject excessive nesting in JSON, enforce max request body size
- [ ] **Validation happens before use** — Parse with Zod/Pydantic before passing to ORM, service layer, or filesystem
- [ ] **Error messages are field-level** — Never echo raw user input; use schema error paths
- [ ] **Server revalidates client validation** — Client-side is UX only; server must always validate independently

## Zod Pattern Library (Reusable)

Common schemas for TypeScript/Next.js projects:

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

// Basic types
export const emailSchema = z
  .string()
  .email('Invalid email address')
  .toLowerCase();

export const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .regex(/[A-Z]/, 'Password must contain an uppercase letter')
  .regex(/[0-9]/, 'Password must contain a number');

export const uuidSchema = z
  .string()
  .uuid('Invalid UUID');

export const urlSchema = z
  .string()
  .url('Invalid URL');

export const dateSchema = z
  .string()
  .datetime()
  .transform((val) => new Date(val));

// File validation
export const fileUploadSchema = z.object({
  name: z
    .string()
    .refine(
      (name) => !name.includes('..') && !name.startsWith('/'),
      'Invalid filename'
    )
    .refine(
      (name) => {
        const ext = name.split('.').pop()?.toLowerCase();
        const blocked = ['exe', 'sh', 'bat', 'cmd', 'dll'];
        return !blocked.includes(ext || '');
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
export const externalApiUserSchema = z.object({
  id: z.number().or(z.string()),
  email: emailSchema,
  name: z.string().optional(),
  createdAt: z.string().optional(),
}).passthrough(); // Allow extra fields, but require these
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

## Implementation

### Next.js (TypeScript + React + Zod)

**1. Form Schema with Client & Server Validation**

```ts
// src/features/auth/schemas/login-form.ts
import { z } from 'zod';

export const LoginFormSchema = z.object({
  email: z
    .string()
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

  // Your auth logic here
  // await authenticate(parsed.data.email, parsed.data.password);

  return { success: true };
}
```

**4. API Route with Request Body Validation**

```ts
// src/app/api/auth/login/route.ts
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

    // Your auth logic
    // const session = await authenticate(parsed.data);

    return NextResponse.json({ data: { success: true } }, { status: 200 });
  } catch (error) {
    return handleApiError('Login failed', error);
  }
}
```

**5. Query Parameter Validation**

```ts
// src/app/api/projects/route.ts
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
    // const url = await storage.upload(parsed.data.name, buffer);

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

### FastAPI (Python + Pydantic)

**1. Request Model with Validation**

```python
# src/api/projects/schemas.py
from pydantic import BaseModel, Field, EmailStr
from datetime import datetime

class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)

    model_config = {
        "json_schema_extra": {
            "example": {
                "name": "My Project",
                "description": "A great project",
            }
        }
    }


class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)


class PaginationQuery(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=10, ge=1, le=100)
    sort: str | None = Field(None, pattern=r'^(asc|desc)_\w+$')
```

**2. API Endpoint with Validation**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, Query, status, UploadFile, File
from pydantic import ValidationError

from core.exceptions import InvalidInputError
from core.logging import log_request, log_error
from .schemas import CreateProjectRequest, ProjectResponse, PaginationQuery

router = APIRouter(prefix="/projects", tags=["projects"])


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectResponse)
async def create_project(req: CreateProjectRequest) -> ProjectResponse:
    """Create a new project.

    Pydantic automatically validates the request body.
    Returns 422 if validation fails.
    """
    # req is guaranteed to be valid
    # Your logic: project = await db.projects.create(req.model_dump())
    from datetime import datetime
    project = ProjectResponse(
        id="1",
        name=req.name,
        description=req.description,
        created_at=datetime.now(),
    )
    return project


@router.get("", response_model=list[ProjectResponse])
async def list_projects(
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=10, ge=1, le=100),
) -> list[ProjectResponse]:
    """List projects with pagination.

    Query parameters are automatically validated and coerced.
    """
    # page and limit are guaranteed to be valid integers
    offset = (page - 1) * limit
    # Your logic: projects = await db.projects.find(skip=offset, limit=limit)
    return []


@router.post("/upload")
async def upload_project_file(file: UploadFile = File(...)):
    """Upload a project file with validation."""
    # Validate file type
    allowed_types = {"image/jpeg", "image/png", "application/pdf"}
    if file.content_type not in allowed_types:
        raise InvalidInputError(
            f"File type {file.content_type} not allowed. "
            f"Allowed: {', '.join(allowed_types)}"
        )

    # Validate file size (max 10MB)
    max_size = 10 * 1024 * 1024
    contents = await file.read()
    if len(contents) > max_size:
        raise InvalidInputError("File must be under 10MB")

    # Validate filename
    if ".." in file.filename or file.filename.startswith("/"):
        raise InvalidInputError("Invalid filename")

    # Safe to use: file.filename, contents
    # await storage.save(file.filename, contents)

    return {"data": {"message": "File uploaded successfully"}}
```

**3. Form Data Validation**

```python
# src/api/auth/routes.py
from fastapi import APIRouter, Form, status
from .schemas import LoginRequest

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", status_code=status.HTTP_200_OK)
async def login(
    email: str = Form(...),
    password: str = Form(...),
):
    """Login via form data with validation."""
    # Manually validate since FastAPI doesn't auto-validate Form data
    try:
        req = LoginRequest(email=email, password=password)
    except ValidationError as e:
        raise InvalidInputError(f"Validation failed: {e}")

    # Safe to use: req.email, req.password
    # session = await auth.login(req.email, req.password)

    return {"data": {"message": "Login successful"}}
```

**4. External API Response Validation**

```python
# src/integrations/services/github_service.py
from pydantic import BaseModel, field_validator
import httpx
from core.exceptions import InvalidInputError

class GitHubUser(BaseModel):
    id: int | str
    login: str
    email: str | None = None

    @field_validator("login", mode="before")
    @classmethod
    def validate_login(cls, v):
        if not v or not isinstance(v, str):
            raise ValueError("login is required")
        return v


async def fetch_github_user(username: str) -> GitHubUser:
    """Fetch and validate GitHub user data."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"https://api.github.com/users/{username}")

    if response.status_code != 200:
        raise InvalidInputError("GitHub user not found")

    try:
        data = response.json()
        user = GitHubUser(**data)  # Validates automatically
        return user
    except ValidationError as e:
        raise InvalidInputError(f"Invalid GitHub API response: {e}")
```

### NestJS (TypeScript + Pydantic-equivalent via nestjs-zod)

**1. DTO with Validation**

```ts
// src/modules/projects/dto/create-project.dto.ts
import { createZodDto } from 'nestjs-zod';
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

export class CreateProjectDto extends createZodDto(createProjectSchema) {}

export type CreateProjectInput = z.infer<typeof createProjectSchema>;
```

**2. Controller with Validation**

```ts
// src/modules/projects/projects.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Post,
  Param,
  Query,
  UploadedFile,
  UseInterceptors,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { ZodValidationPipe } from 'nestjs-zod';
import { z } from 'zod';
import { ProjectsService } from './projects.service';
import { CreateProjectDto } from './dto/create-project.dto';

const paginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(10),
});

@ApiTags('projects')
@Controller('projects')
export class ProjectsController {
  constructor(private readonly service: ProjectsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new project' })
  async create(@Body() dto: CreateProjectDto) {
    return await this.service.createProject(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List projects with pagination' })
  async list(
    @Query(new ZodValidationPipe(paginationSchema))
    query: z.infer<typeof paginationSchema>,
  ) {
    return await this.service.listProjects(query.page, query.limit);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get project by ID' })
  async getById(@Param('id') id: string) {
    return await this.service.getProject(id);
  }

  @Post('upload')
  @UseInterceptors(FileInterceptor('file'))
  async uploadFile(@UploadedFile() file: Express.Multer.File) {
    // Validate file
    if (!file) {
      throw new BadRequestException('File is required');
    }

    const allowed = ['image/jpeg', 'image/png', 'application/pdf'];
    if (!allowed.includes(file.mimetype)) {
      throw new BadRequestException('File type not allowed');
    }

    const maxSize = 10 * 1024 * 1024;
    if (file.size > maxSize) {
      throw new BadRequestException('File must be under 10MB');
    }

    // Safe to use: file.buffer, file.originalname
    return { message: 'File uploaded' };
  }
}
```

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
import { useState } from 'react';
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
    errorMap: () => ({ message: 'Only JPEG, PNG, and PDF files allowed' }),
  }),
});

export function FileUploadForm() {
  const [error, setError] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
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
  id: z.string().uuid(),
  name: z.string(),
  description: z.string().optional(),
  createdAt: z.string().datetime(),
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

### Next.js

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

### FastAPI

```bash
# Test endpoint validation
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'  # Should return 422

pytest -v -s
```

### NestJS

```bash
pnpm start:dev

# Test Swagger docs with validation schemas
curl -X POST http://localhost:3000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'  # Should return 400

pnpm test
```

### Vite + React

```bash
pnpm dev

# Test form validation (client shows error)
# Submit invalid form, verify errors appear

# Test API response validation (if API changes, error caught)
pnpm test
```

## See Also

- `shared/add-error-handling` — Transform validation errors to consistent response format
- `shared/add-logging` — Log validation failures with context
- Stack-specific `code-standards` — Type annotation and schema standards
- Stack-specific `add-api-route`, `add-endpoint`, `add-form` — Use validation patterns in new routes/forms
