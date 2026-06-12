<!-- ref: add/pagination/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
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
import { PaginationMetadata } from '@/lib/types/pagination';

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
    // searchParams.get() returns null for missing params, but z.string().default()
    // only fires on undefined — coalesce to undefined so defaults apply.
    const queryParams = {
      page: searchParams.get('page') ?? undefined,
      limit: searchParams.get('limit') ?? undefined,
      sort: searchParams.get('sort') ?? undefined,
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
// src/features/projects/components/projects-list.tsx
'use client';

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';

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

  const { data, isPending, error } = useQuery({
    queryKey: ['projects', page],
    queryFn: async () => {
      const response = await fetch(
        `/api/projects?page=${page}&limit=${limit}&sort=asc_name`
      );
      if (!response.ok) throw new Error('Failed to fetch projects');
      const json = await response.json();
      return json.data as PaginatedResponse;
    },
  });

  if (isPending) return <div>Loading...</div>;
  if (error) return <div>Error loading projects</div>;

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
        <Button
          variant="outline"
          disabled={page === 1}
          onClick={() => setPage(page - 1)}
        >
          Previous
        </Button>

        <span>
          Page {pagination.page} of {Math.ceil(pagination.total / pagination.limit)}
        </span>

        <Button
          variant="outline"
          disabled={!pagination.hasMore}
          onClick={() => setPage(page + 1)}
        >
          Next
        </Button>
      </div>

      <div className="text-sm text-gray-600">
        Showing {(page - 1) * limit + 1} to {Math.min(page * limit, pagination.total)} of{' '}
        {pagination.total} results
      </div>
    </div>
  );
}
```

## Testing / Verification

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

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards