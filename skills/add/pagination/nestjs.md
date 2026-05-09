<!-- ref: add/pagination/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### NestJS (TypeScript + Drizzle + Zod)

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
  ): { field: string; direction: 'asc' | 'desc' } | null {
    if (!sort) return null;

    const [direction, field] = sort.split('_');
    if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
      return null;
    }

    return { field, direction: direction as 'asc' | 'desc' };
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
      orderBy  // { field, direction } | null
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

**5. Service with Drizzle**

```ts
// src/modules/projects/projects.service.ts
import { Injectable } from '@nestjs/common';
import { asc, count, desc } from 'drizzle-orm';

import { DrizzleService } from '@/database/drizzle.service';
import { projects } from '@/database/schema';

type SortField = 'name' | 'createdAt' | 'updatedAt';
const SORT_COLUMNS = {
  name: projects.name,
  createdAt: projects.createdAt,
  updatedAt: projects.updatedAt,
} as const;

@Injectable()
export class ProjectsService {
  constructor(private readonly drizzle: DrizzleService) {}

  async getProjects(
    offset: number,
    limit: number,
    sortParam: { field: string; direction: 'asc' | 'desc' } | null,
  ): Promise<[typeof projects.$inferSelect[], number]> {
    const orderByCol = sortParam
      ? sortParam.direction === 'asc'
        ? asc(SORT_COLUMNS[sortParam.field as SortField])
        : desc(SORT_COLUMNS[sortParam.field as SortField])
      : desc(projects.createdAt);

    const [rows, [{ total }]] = await Promise.all([
      this.drizzle.db.select().from(projects).orderBy(orderByCol).limit(limit).offset(offset),
      this.drizzle.db.select({ total: count() }).from(projects),
    ]);

    return [rows, Number(total)];
  }
}
```

## Testing / Verification

```bash
pnpm start:dev

# Test paginated endpoint
curl 'http://localhost:3000/projects?page=1&limit=10'

# Test invalid params
curl 'http://localhost:3000/projects?page=-1&limit=10'
# Expected 400 response

pnpm test
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards