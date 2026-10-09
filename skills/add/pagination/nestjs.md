<!-- ref: add/pagination/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### NestJS (TypeScript + Drizzle + Zod)

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Pagination Query DTO** (shared — every paginated module reuses it)

```ts
// src/common/dto/pagination.dto.ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

export const paginationSchema = z.object({
  // Capped: OFFSET cost grows with page, so an unbounded page is a cheap DoS lever.
  page: z.coerce.number().int().min(1, 'Page must be 1 or greater').max(10_000).default(1),
  limit: z.coerce
    .number()
    .int()
    .min(1, 'Limit must be 1 or greater')
    .max(100, 'Limit must be 100 or less')
    .default(10),
  sort: z
    .string()
    .max(64)
    .regex(/^(asc|desc)_\w+$/, 'Invalid sort format: use asc_fieldName or desc_fieldName')
    .optional(),
});

export class PaginationDto extends createZodDto(paginationSchema) {}

export type PaginationParams = z.infer<typeof paginationSchema>;

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

**2. Pagination Service**

```ts
// src/common/services/pagination.service.ts
import { Injectable } from '@nestjs/common';
import type { PaginationMetadata } from '../dto/pagination.dto';

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

    // Split on the FIRST underscore only — field names may be snake_case (e.g. asc_created_at)
    const separatorIndex = sort.indexOf('_');
    if (separatorIndex === -1) return null;
    const direction = sort.slice(0, separatorIndex);
    const field = sort.slice(separatorIndex + 1);
    if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
      return null;
    }

    return { field, direction: direction as 'asc' | 'desc' };
  }
}
```

`PaginationService` has no module of its own — register it in each feature module that uses it:

```ts
// src/modules/projects/projects.module.ts
import { Module } from '@nestjs/common';

import { PaginationService } from '../../common/services/pagination.service';
import { ProjectsController } from './projects.controller';
import { ProjectsService } from './projects.service';

@Module({
  controllers: [ProjectsController],
  providers: [ProjectsService, PaginationService],
})
export class ProjectsModule {}
```

**3. Project Response DTO**

`src/modules/projects/projects.dto.ts` may already exist (from `templatecentral:add (endpoint)` or
`(error-handling)`, holding `CreateProjectDto`). **Add** the schema and class below to it — do not
overwrite the existing DTOs. Create the file (with the two imports) only if it is absent.

```ts
// src/modules/projects/projects.dto.ts — append (keep existing CreateProjectDto etc.)
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

// Response shape: parsing a DB row through it strips any column not listed here.
export const ProjectSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullish(),
  createdAt: z.date(),
  updatedAt: z.date(),
});

export class ProjectDto extends createZodDto(ProjectSchema) {}
```

**4. Controller with Pagination**

Sort parsing, offset math, and row mapping belong in the service — the controller only declares the contract and delegates.

```ts
// src/modules/projects/projects.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { PaginationDto, type PaginatedResponse } from '../../common/dto/pagination.dto';
import type { ProjectDto } from './projects.dto';
import { ProjectsService } from './projects.service';

@ApiTags('Projects')
@Controller('projects')
export class ProjectsController {
  constructor(private readonly projectsService: ProjectsService) {}

  @Get()
  @ApiOperation({ summary: 'List projects with pagination' })
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 10 })
  @ApiQuery({ name: 'sort', required: false, example: 'asc_name' })
  // Validated by the scaffold's global ZodValidationPipe (APP_PIPE).
  list(@Query() query: PaginationDto): Promise<PaginatedResponse<ProjectDto>> {
    return this.projectsService.listProjects(query);
  }
}
```

**5. Service with Drizzle**

```ts
// src/modules/projects/projects.service.ts
import { BadRequestException, Injectable } from '@nestjs/common';
import { asc, count, desc } from 'drizzle-orm';

import type { PaginatedResponse, PaginationParams } from '../../common/dto/pagination.dto';
import { PaginationService } from '../../common/services/pagination.service';
import { DrizzleService } from '../../database/drizzle.service';
import { projects } from '../../database/schema';
import { ProjectDto } from './projects.dto';

type SortField = 'name' | 'createdAt' | 'updatedAt';
const SORT_COLUMNS = {
  name: projects.name,
  createdAt: projects.createdAt,
  updatedAt: projects.updatedAt,
} as const;

// Derived from SORT_COLUMNS so the allow-list can never drift from the sortable columns.
const ALLOWED_SORT_FIELDS = Object.keys(SORT_COLUMNS);

@Injectable()
export class ProjectsService {
  constructor(
    private readonly drizzle: DrizzleService,
    private readonly pagination: PaginationService,
  ) {}

  async listProjects(
    query: PaginationParams,
  ): Promise<PaginatedResponse<ProjectDto>> {
    const orderBy = this.pagination.parseSortParam(
      query.sort,
      ALLOWED_SORT_FIELDS,
    );
    if (query.sort && !orderBy) {
      // Pre-built in the filter's ErrorResponse shape so the allowed list survives it (see note below).
      throw new BadRequestException({
        error: 'Invalid sort field',
        details: {
          fieldErrors: {
            sort: [`Must be one of: ${ALLOWED_SORT_FIELDS.join(', ')}`],
          },
        },
      });
    }

    const offset = this.pagination.calculateOffset(query.page, query.limit);
    const [rows, total] = await this.getProjects(offset, query.limit, orderBy);

    return {
      data: {
        // createZodDto classes have no mapping constructor; parsing also strips unlisted columns.
        items: rows.map((p) => ProjectDto.schema.parse(p)),
        pagination: this.pagination.createMetadata(
          query.page,
          query.limit,
          total,
        ),
      },
    };
  }

  private async getProjects(
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

> **Coupling with `add/error-handling/nestjs`.** Its `HttpExceptionFilter` collapses most
> 400 bodies to `{ error: 'Bad request' }` but passes through a body that already carries an
> `error` key — the shape thrown above. **Preserve that pass-through branch** and confirm with:
>
> ```bash
> curl 'http://localhost:3000/projects?sort=asc_bogus'
> # Must list the allowed fields, NOT collapse to {"error":"Bad request"}
> ```

## Validate

```bash
pnpm start:dev
curl 'http://localhost:3000/projects?page=1&limit=10'
# Expect 400
curl 'http://localhost:3000/projects?page=-1&limit=10'
pnpm test
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards