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

**1. Pagination DTO**

```ts
// src/modules/projects/dto/pagination.dto.ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

export const paginationSchema = z.object({
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
import { ProjectsService } from './projects.service';
import { PaginationService } from '../../common/services/pagination.service';
import { PaginationDto } from './dto/pagination.dto';
import type { PaginationMetadata, PaginatedResponse } from '../../common/dto/pagination.dto';
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
  @ApiQuery({ name: 'page', required: false, example: 1 })
  @ApiQuery({ name: 'limit', required: false, example: 10 })
  @ApiQuery({ name: 'sort', required: false, example: 'asc_name' })
  async list(
    // The scaffold's global APP_PIPE ZodValidationPipe validates PaginationDto — no explicit pipe needed
    @Query() query: PaginationDto
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
        // createZodDto classes have no mapping constructor — validate rows via the static schema
        items: projects.map((p) => ProjectDto.schema.parse(p)),
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

import { DrizzleService } from '../../database/drizzle.service';
import { projects } from '../../database/schema';

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

## Validate

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
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards