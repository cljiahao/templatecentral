---
name: shared-add-pagination
description: Use when building list endpoints with multiple pages — covers offset-based pagination, response envelopes, CWE-400 resource exhaustion prevention, and per-stack implementations.
---

# Add Pagination & Filtering

Implement consistent pagination across your stack. All list endpoints return paginated responses with metadata. Pagination prevents resource exhaustion (CWE-400) by enforcing limits and defaults.

## When to Use

- Building API endpoints that return lists (projects, users, products, etc.)
- Adding page/limit query parameters to existing list endpoints
- Implementing "next/previous" navigation in UI
- Preventing unbounded queries that could consume database resources

## Security Checklist

- [ ] **Max limit enforced** — Query enforces maximum results per page (e.g., max 100 items)
- [ ] **Default limit applied** — Missing `limit` parameter uses safe default (e.g., 10-20 items)
- [ ] **Sort field validated** — Sort column comes from a whitelist, never raw user input
- [ ] **Negative page/limit rejected** — Page < 1 and limit < 1 return 400 error
- [ ] **Page calculation correct** — Offset calculated as `(page - 1) * limit`, no off-by-one errors
- [ ] **Total count bounded** — Total count does not require O(n) database scan (use index or estimate)
- [ ] **Pagination metadata included** — Every list response includes page, limit, total, hasMore

## Unified Pagination Response Schema

All list endpoints return this shape (matches Phase 1 `shared-add-error-handling` format):

**Success response:** (status 200)
```json
{
  "data": {
    "items": [
      { "id": "1", "name": "Project A" },
      { "id": "2", "name": "Project B" }
    ],
    "pagination": {
      "page": 1,
      "limit": 10,
      "total": 247,
      "hasMore": true
    }
  }
}
```

**Schema breakdown:**
- `data` — Wrapper object containing:
  - `items` — Array of list items (projects, users, etc.)
  - `pagination` — Object with:
    - `page` — Current page number (1-indexed)
    - `limit` — Number of items per page
    - `total` — Total count of items (may be approximate for performance)
    - `hasMore` — Boolean: true if more pages exist after this one

**Error response:** (status 400, 422, etc.) — See `shared-add-error-handling`
```json
{
  "error": "Invalid query parameters",
  "details": {
    "fieldErrors": {
      "page": ["Must be 1 or greater"],
      "limit": ["Must be between 1 and 100"]
    }
  }
}
```

## Rules

1. **All pagination params must be validated** — Use Zod (TypeScript) or Pydantic (Python) schema from `shared-validation-patterns`
2. **Limit must have a maximum** — Enforce max (e.g., max 100 items per request)
3. **Default limit must be reasonable** — If omitted, use sensible default (10-20 items)
4. **Sort field must be from a whitelist** — Never allow user input directly in ORDER BY; validate against allowed fields
5. **Offset calculated correctly** — Use `(page - 1) * limit` formula consistently
6. **Pagination metadata included** — Every list response must include page, limit, total, hasMore
7. **Database indexes required** — Sort and filter fields must be indexed for performance
8. **Total count careful** — For large tables, consider approximate count or bounded estimation (no full table scans)

## Implementation

### Next.js (TypeScript + Drizzle + Zod)

**1. Reusable Pagination Schema (From validation-patterns)**

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

export const paginationSchema = z.object({
  page: z
    .string()
    .default('1')
    .pipe(z.coerce.number().int().positive('Page must be 1 or greater')),
  limit: z
    .string()
    .default('10')
    .pipe(
      z.coerce.number().int().min(1, 'Limit must be 1 or greater').max(100, 'Limit must be 100 or less')
    ),
  sort: z
    .string()
    .regex(/^(asc|desc)_\w+$/, 'Invalid sort format: use asc_fieldName or desc_fieldName')
    .optional(),
});

export type PaginationParams = z.infer<typeof paginationSchema>;
```

**2. Pagination Response Type**

```ts
// src/lib/types/pagination.ts
export interface PaginationMetadata {
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

export interface PaginatedResponse<T> {
  data: {
    items: T[];
    pagination: PaginationMetadata;
  };
}
```

**3. Pagination Service (Business Logic)**

```ts
// src/lib/pagination/pagination-service.ts
import { PaginationParams, PaginationMetadata } from '@/lib/types/pagination';

export class PaginationService {
  /**
   * Calculate offset from page number
   * @param page - Page number (1-indexed)
   * @param limit - Items per page
   * @returns Offset (0-indexed)
   */
  static calculateOffset(page: number, limit: number): number {
    return (page - 1) * limit;
  }

  /**
   * Create pagination metadata for response
   * @param page - Current page
   * @param limit - Items per page
   * @param total - Total item count
   * @returns Pagination metadata
   */
  static createMetadata(page: number, limit: number, total: number): PaginationMetadata {
    return {
      page,
      limit,
      total,
      hasMore: page * limit < total,
    };
  }

  /**
   * Parse sort parameter into a field/direction pair.
   * @param sort - Sort string: "asc_name" or "desc_createdAt"
   * @param allowedFields - Whitelist of allowed field names
   * @returns { field, direction } or null if invalid — caller maps to ORM-specific orderBy
   */
  static parseSortParam(
    sort: string | undefined,
    allowedFields: string[]
  ): { field: string; direction: 'asc' | 'desc' } | null {
    if (!sort) return null;

    const [direction, field] = sort.split('_');
    if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
      return null; // Invalid sort - caller should reject
    }

    return { field, direction: direction as 'asc' | 'desc' };
  }
}
```

**4. API Route with Pagination**

```ts
// src/app/api/projects/route.ts
import { handleApiError } from '@/lib/errors';
import { paginationSchema } from '@/lib/validation/schemas';
import { PaginationService } from '@/lib/pagination/pagination-service';
import { NextResponse } from 'next/server';
import { asc, count, desc } from 'drizzle-orm';
import { z } from 'zod';
import { db, projects } from '@/integrations/database';

const ALLOWED_SORT_FIELDS = ['name', 'createdAt', 'updatedAt'] as const;
type SortField = typeof ALLOWED_SORT_FIELDS[number];

const SORT_COLUMNS: Record<SortField, typeof projects.name | typeof projects.createdAt | typeof projects.updatedAt> = {
  name: projects.name,
  createdAt: projects.createdAt,
  updatedAt: projects.updatedAt,
};

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const queryParams = {
      page: searchParams.get('page'),
      limit: searchParams.get('limit'),
      sort: searchParams.get('sort'),
    };

    const parsed = paginationSchema.safeParse(queryParams);
    if (!parsed.success) {
      return handleApiError(
        'Invalid query parameters',
        parsed.error,
        z.flattenError(parsed.error).fieldErrors as Record<string, string[]>
      );
    }

    const { page, limit, sort } = parsed.data;

    const sortParam = PaginationService.parseSortParam(sort, [...ALLOWED_SORT_FIELDS]);
    if (sort && !sortParam) {
      return NextResponse.json(
        {
          error: 'Invalid sort field',
          details: { fieldErrors: { sort: [`Must be one of: ${ALLOWED_SORT_FIELDS.join(', ')}`] } },
        },
        { status: 400 }
      );
    }

    const orderByCol = sortParam
      ? sortParam.direction === 'asc'
        ? asc(SORT_COLUMNS[sortParam.field as SortField])
        : desc(SORT_COLUMNS[sortParam.field as SortField])
      : desc(projects.createdAt);

    const offset = PaginationService.calculateOffset(page, limit);
    const [rows, [{ total }]] = await Promise.all([
      db
        .select({ id: projects.id, name: projects.name, description: projects.description })
        .from(projects)
        .orderBy(orderByCol)
        .limit(limit)
        .offset(offset),
      db.select({ total: count() }).from(projects),
    ]);

    return NextResponse.json({
      data: {
        items: rows,
        pagination: PaginationService.createMetadata(page, limit, Number(total)),
      },
    });
  } catch (error) {
    return handleApiError('Failed to fetch projects', error);
  }
}
```

**5. Paginated UI Component (React)**

```tsx
// src/components/projects/projects-list.tsx
'use client';

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';

interface Project {
  id: string;
  name: string;
  description: string | null;
}

interface PaginatedResponse {
  items: Project[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    hasMore: boolean;
  };
}

export function ProjectsList() {
  const [page, setPage] = useState(1);
  const limit = 10;

  const { data, isLoading, error } = useQuery({
    queryKey: ['projects', page],
    queryFn: async () => {
      const response = await fetch(
        `/api/projects?page=${page}&limit=${limit}&sort=asc_name`
      );
      if (!response.ok) throw new Error('Failed to fetch projects');
      const json = await response.json();
      return json.data; // Extract from Phase 1 wrapper
    },
  });

  if (isLoading) return <div>Loading...</div>;
  if (error) return <div>Error: {(error as Error).message}</div>;

  const { items: projects, pagination } = data;

  return (
    <div className="space-y-4">
      <ul className="space-y-2">
        {projects.map((project: Project) => (
          <li key={project.id} className="border p-2 rounded">
            <h3 className="font-bold">{project.name}</h3>
            {project.description && <p className="text-sm text-gray-600">{project.description}</p>}
          </li>
        ))}
      </ul>

      {/* Pagination controls */}
      <div className="flex gap-2 items-center justify-between">
        <button
          disabled={page === 1}
          onClick={() => setPage(page - 1)}
          className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
        >
          Previous
        </button>

        <span>
          Page {pagination.page} of {Math.ceil(pagination.total / pagination.limit)}
        </span>

        <button
          disabled={!pagination.hasMore}
          onClick={() => setPage(page + 1)}
          className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
        >
          Next
        </button>
      </div>

      <div className="text-sm text-gray-600">
        Showing {(page - 1) * limit + 1} to {Math.min(page * limit, pagination.total)} of{' '}
        {pagination.total} results
      </div>
    </div>
  );
}
```

---

### FastAPI (Python + Pydantic + SQLAlchemy)

**1. Reusable Pagination Schema**

```python
# src/lib/validation/schemas.py
from pydantic import BaseModel, Field
from typing import Literal

class PaginationParams(BaseModel):
    page: int = Field(default=1, ge=1, description='Page number (1-indexed)')
    limit: int = Field(
        default=10,
        ge=1,
        le=100,
        description='Items per page (max 100)'
    )
    sort: str | None = Field(
        default=None,
        pattern=r'^(asc|desc)_\w+$',
        description='Sort format: asc_fieldName or desc_fieldName'
    )
```

**2. Pagination Response Model**

```python
# src/lib/types/pagination.py
from pydantic import BaseModel
from typing import Generic, TypeVar

T = TypeVar('T')

class PaginationMetadata(BaseModel):
    page: int
    limit: int
    total: int
    hasMore: bool

class PaginatedResponse(BaseModel, Generic[T]):
    data: list[T]
    pagination: PaginationMetadata
```

**3. Pagination Service**

```python
# src/lib/pagination/pagination_service.py
from typing import Any

class PaginationService:
    """Pagination utilities for consistent pagination across endpoints."""

    @staticmethod
    def calculate_offset(page: int, limit: int) -> int:
        """Calculate offset from page number (1-indexed to 0-indexed)."""
        return (page - 1) * limit

    @staticmethod
    def create_metadata(page: int, limit: int, total: int) -> dict:
        """Create pagination metadata for response."""
        return {
            'page': page,
            'limit': limit,
            'total': total,
            'hasMore': page * limit < total,
        }

    @staticmethod
    def parse_sort_param(
        sort: str | None,
        allowed_fields: list[str]
    ) -> tuple[str, str] | None:
        """Parse sort parameter to (field, direction) tuple.
        
        Args:
            sort: Sort string format: 'asc_fieldName' or 'desc_fieldName'
            allowed_fields: Whitelist of allowed field names
            
        Returns:
            Tuple of (field, direction) or None if invalid
        """
        if not sort:
            return None

        parts = sort.split('_', 1)
        if len(parts) != 2:
            return None

        direction, field = parts
        if field not in allowed_fields or direction not in ['asc', 'desc']:
            return None

        return (field, direction)
```

**4. API Endpoint with Pagination**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, Query, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import ValidationError

from core.database import get_session
from core.exceptions import InvalidInputError
from lib.pagination.pagination_service import PaginationService
from lib.validation.schemas import PaginationParams
from lib.types.pagination import PaginatedResponse
from models.project import Project as ProjectModel
from .schemas import ProjectResponse

router = APIRouter(prefix='/projects', tags=['projects'])

ALLOWED_SORT_FIELDS = ['name', 'created_at', 'updated_at']

@router.get('', response_model=dict)  # Returns wrapped response
async def list_projects(
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=10, ge=1, le=100),
    sort: str | None = Query(default=None, pattern=r'^(asc|desc)_\w+$'),
    session: AsyncSession = get_session(),
) -> dict:
    """List projects with pagination.
    
    Query parameters are validated by Pydantic Query() constraints.
    Returns paginated response with metadata.
    """
    # Validate sort field against whitelist
    sort_result = PaginationService.parse_sort_param(sort, ALLOWED_SORT_FIELDS)
    if sort and not sort_result:
        raise InvalidInputError(
            f'Invalid sort field. Allowed: {", ".join(ALLOWED_SORT_FIELDS)}'
        )

    # Calculate offset
    offset = PaginationService.calculate_offset(page, limit)

    # Query projects
    stmt = select(ProjectModel).offset(offset).limit(limit)
    if sort_result:
        field_name, direction = sort_result
        order_col = getattr(ProjectModel, field_name)
        stmt = stmt.order_by(order_col.asc() if direction == 'asc' else order_col.desc())
    else:
        stmt = stmt.order_by(ProjectModel.created_at.desc())

    result = await session.execute(stmt)
    projects = result.scalars().all()

    # Get total count (indexed query)
    count_stmt = select(func.count(ProjectModel.id))
    count_result = await session.execute(count_stmt)
    total = count_result.scalar()

    # Build response (matches Phase 1 unified schema)
    pagination_metadata = PaginationService.create_metadata(page, limit, total)
    
    return {
        'data': {
            'items': [ProjectResponse.model_validate(p) for p in projects],
            'pagination': pagination_metadata,
        }
    }
```

---

### NestJS (TypeScript + Prisma + Zod)

**1. Pagination DTO**

```ts
// src/modules/projects/dto/pagination.dto.ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const paginationSchema = z.object({
  page: z.coerce.number().int().positive('Page must be 1 or greater').default(1),
  limit: z.coerce
    .number()
    .int()
    .min(1, 'Limit must be 1 or greater')
    .max(100, 'Limit must be 100 or less')
    .default(10),
  sort: z
    .string()
    .regex(/^(asc|desc)_\w+$/, 'Invalid sort format: use asc_fieldName or desc_fieldName')
    .optional(),
});

export class PaginationDto extends createZodDto(paginationSchema) {}

export type PaginationParams = z.infer<typeof paginationSchema>;
```

**2. Pagination Response DTO**

```ts
// src/common/dto/pagination.dto.ts
export interface PaginationMetadata {
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

export interface PaginatedResponse<T> {
  data: {
    items: T[];
    pagination: PaginationMetadata;
  };
}
```

**3. Pagination Service**

```ts
// src/common/services/pagination.service.ts
import { Injectable } from '@nestjs/common';
import type { PaginationMetadata } from '@/common/dto/pagination.dto';

@Injectable()
export class PaginationService {
  calculateOffset(page: number, limit: number): number {
    return (page - 1) * limit;
  }

  createMetadata(page: number, limit: number, total: number): PaginationMetadata {
    return {
      page,
      limit,
      total,
      hasMore: page * limit < total,
    };
  }

  parseSortParam(
    sort: string | undefined,
    allowedFields: string[]
  ): Record<string, 'asc' | 'desc'> | null {
    if (!sort) return null;

    const [direction, field] = sort.split('_');
    if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
      return null;
    }

    return { [field]: direction as 'asc' | 'desc' };
  }
}
```

**4. Controller with Pagination**

```ts
// src/modules/projects/projects.controller.ts
import {
  Controller,
  Get,
  Query,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { ZodValidationPipe } from 'nestjs-zod';
import { z } from 'zod';
import { ProjectsService } from './projects.service';
import { PaginationService } from '@/common/services/pagination.service';
import { PaginationDto } from './dto/pagination.dto';
import type { PaginationMetadata, PaginatedResponse } from '@/common/dto/pagination.dto';
import { ProjectDto } from './dto/project.dto';

const ALLOWED_SORT_FIELDS = ['name', 'createdAt', 'updatedAt'];

@ApiTags('projects')
@Controller('projects')
export class ProjectsController {
  constructor(
    private readonly projectsService: ProjectsService,
    private readonly paginationService: PaginationService
  ) {}

  @Get()
  @ApiOperation({ summary: 'List projects with pagination' })
  @ApiQuery({ name: 'page', example: 1 })
  @ApiQuery({ name: 'limit', example: 10 })
  @ApiQuery({ name: 'sort', required: false, example: 'asc_name' })
  async list(
    @Query(new ZodValidationPipe(z.object({
      page: z.coerce.number().int().positive().default(1),
      limit: z.coerce.number().int().min(1).max(100).default(10),
      sort: z.string().optional(),
    })))
    query: PaginationDto
  ): Promise<PaginatedResponse<ProjectDto>> {
    // Validate sort field
    const orderBy = this.paginationService.parseSortParam(
      query.sort,
      ALLOWED_SORT_FIELDS
    );
    if (query.sort && !orderBy) {
      throw new HttpException(
        {
          error: 'Invalid sort field',
          details: {
            fieldErrors: {
              sort: [`Must be one of: ${ALLOWED_SORT_FIELDS.join(', ')}`],
            },
          },
        },
        HttpStatus.BAD_REQUEST
      );
    }

    // Get paginated results
    const offset = this.paginationService.calculateOffset(query.page, query.limit);
    const [projects, total] = await this.projectsService.getProjects(
      offset,
      query.limit,
      orderBy
    );

    // Build response
    const metadata = this.paginationService.createMetadata(
      query.page,
      query.limit,
      total
    );

    return {
      data: {
        items: projects.map((p) => new ProjectDto(p)),
        pagination: metadata,
      },
    };
  }
}
```

---

### Vite + React (TypeScript + React Query)

**1. Pagination Hook**

```ts
// src/lib/utils/use-pagination.ts
import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';

interface UsePaginationOptions {
  initialPage?: number;
  pageSize?: number;
  enabled?: boolean;
}

export function usePagination(
  queryKey: string[],
  fetchFn: (page: number, limit: number) => Promise<any>,
  options: UsePaginationOptions = {}
) {
  const { initialPage = 1, pageSize = 10, enabled = true } = options;
  const [page, setPage] = useState(initialPage);

  const { data, isLoading, error, isFetching } = useQuery({
    queryKey: [...queryKey, page],
    queryFn: () => fetchFn(page, pageSize),
    enabled,
  });

  const goToPage = useCallback((newPage: number) => {
    setPage(Math.max(1, newPage));
  }, []);

  const nextPage = useCallback(() => {
    if (data?.pagination?.hasMore) {
      setPage((p) => p + 1);
    }
  }, [data]);

  const prevPage = useCallback(() => {
    setPage((p) => Math.max(1, p - 1));
  }, []);

  return {
    data: data?.items || [],
    pagination: data?.pagination,
    page,
    pageSize,
    isLoading,
    isFetching,
    error,
    goToPage,
    nextPage,
    prevPage,
  };
}
```

**2. Projects List Component**

```tsx
// src/features/projects/components/projects-list.tsx
import { usePagination } from '@/lib/utils/use-pagination';
import { fetchProjects } from '@/api/projects';

export function ProjectsList() {
  const { data, pagination, page, isLoading, error, nextPage, prevPage } =
    usePagination(['projects'], fetchProjects);

  if (isLoading) return <div>Loading...</div>;
  if (error) return <div>Error: {(error as Error).message}</div>;

  return (
    <div className="space-y-4">
      <ul className="space-y-2">
        {data.map((project: any) => (
          <li key={project.id} className="border p-2 rounded">
            <h3 className="font-bold">{project.name}</h3>
            {project.description && (
              <p className="text-sm text-gray-600">{project.description}</p>
            )}
          </li>
        ))}
      </ul>

      {pagination && (
        <div className="space-y-2">
          <div className="flex gap-2 justify-between items-center">
            <button
              disabled={page === 1}
              onClick={prevPage}
              className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
            >
              Previous
            </button>

            <span>
              Page {pagination.page} of{' '}
              {Math.ceil(pagination.total / pagination.limit)}
            </span>

            <button
              disabled={!pagination.hasMore}
              onClick={nextPage}
              className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
            >
              Next
            </button>
          </div>

          <div className="text-sm text-gray-600">
            Showing {(page - 1) * pagination.limit + 1} to{' '}
            {Math.min(page * pagination.limit, pagination.total)} of{' '}
            {pagination.total} results
          </div>
        </div>
      )}
    </div>
  );
}
```

**3. API Client**

```ts
// src/api/projects.ts
import { z } from 'zod';

// Matches Phase 1 unified response schema
const paginatedProjectSchema = z.object({
  items: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      description: z.string().nullable(),
    })
  ),
  pagination: z.object({
    page: z.number(),
    limit: z.number(),
    total: z.number(),
    hasMore: z.boolean(),
  }),
});

export async function fetchProjects(
  page: number = 1,
  limit: number = 10
): Promise<z.infer<typeof paginatedProjectSchema>> {
  const response = await fetch(
    `/api/projects?page=${page}&limit=${limit}&sort=asc_name`
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch projects: ${response.status}`);
  }

  const json = await response.json();

  // API returns: { data: { items: [...], pagination: {...} } }
  // Extract from Phase 1 wrapper
  const data = json.data;

  // Validate response shape
  const parsed = paginatedProjectSchema.safeParse(data);
  if (!parsed.success) {
    throw new Error('Invalid API response shape');
  }

  return parsed.data;
}
```

---

## Testing / Verification

### Next.js

```bash
# Test pagination endpoint
curl 'http://localhost:3000/api/projects?page=1&limit=10'

# Expected 200 response:
# {
#   "data": {
#     "items": [{ "id": "1", "name": "Project A" }, ...],
#     "pagination": { "page": 1, "limit": 10, "total": 247, "hasMore": true }
#   }
# }

# Test invalid page
curl 'http://localhost:3000/api/projects?page=0&limit=10'
# Expected 400 response with validation error

# Test limit exceeds max
curl 'http://localhost:3000/api/projects?page=1&limit=200'
# Expected 400 response (limit exceeds 100)

# Test invalid sort field
curl 'http://localhost:3000/api/projects?page=1&limit=10&sort=asc_invalid'
# Expected 400 response (field not in whitelist)

pnpm test
pnpm build
```

### FastAPI

```bash
# Test pagination endpoint
curl 'http://localhost:8000/projects?page=1&limit=10'

# Expected 200 response with pagination metadata

# Test invalid page
curl 'http://localhost:8000/projects?page=0&limit=10'
# Expected 422 response

# Test invalid sort
curl 'http://localhost:8000/projects?page=1&limit=10&sort=invalid_field'
# Expected 400 response

pytest -v
```

### NestJS

```bash
pnpm start:dev

# Test paginated endpoint
curl 'http://localhost:3000/projects?page=1&limit=10'

# Test invalid params
curl 'http://localhost:3000/projects?page=-1&limit=10'
# Expected 400 response

pnpm test
```

### Vite + React

```bash
pnpm dev

# Component renders paginated list with prev/next controls
# Clicking next fetches page 2
# Previous button disabled on page 1
# hasMore correctly controls Next button state

pnpm test
```

## See Also

- `shared-add-error-handling` — Pagination errors use unified error response schema
- `shared-validation-patterns` — Pagination query params validated with Zod/Pydantic
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Add pagination to new list endpoints
- Stack-specific `code-standards` — Database indexing best practices for sort fields
