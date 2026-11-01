<!-- ref: add/pagination/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### NestJS (TypeScript + Zod; Drizzle or Kysely)

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

Run `TC_PART=leaf TC_LEAF=add/pagination/nestjs bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/pagination/nestjs/template/` (listed in `<skill-dir>/pagination/nestjs/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**1. Pagination Query DTO** (shared — every paginated module reuses it)

Copied verbatim from `<skill-dir>/pagination/nestjs/template/src/common/dto/pagination.dto.ts` by the copy step; do not re-type it.

**2. Pagination Service**

Copied verbatim from `<skill-dir>/pagination/nestjs/template/src/common/services/pagination.service.ts` by the copy step; do not re-type it.

`PaginationService` has no module of its own — register it in each feature module that uses it. Then export the module from `src/modules/index.ts` (`export * from './projects/projects.module';`) and append `ProjectsModule` to the existing `imports` array in `src/app.module.ts` — never replace that array:

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

`src/modules/projects/projects.dto.ts` may already exist (from `templatecentral:add (endpoint)`,
holding `CreateProjectDto`). **Add** the schema and class below to it — do not
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

**5. Table + Service**

The `projects` table must exist. Pick the variant matching `src/database/`.

**Drizzle** — add to `src/database/schema.ts`, then `pnpm db:generate && pnpm db:migrate`:

```ts
export const projects = pgTable('projects', {
  id: text('id').primaryKey().$defaultFn(() => crypto.randomUUID()),
  name: text('name').notNull(),
  description: text('description'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdateFn(() => new Date()),
});
```

```ts
// src/modules/projects/projects.service.ts (Drizzle)
import { Injectable } from '@nestjs/common';
import { asc, count, desc } from 'drizzle-orm';

import type { PaginatedResponse, PaginationParams } from '../../common/dto/pagination.dto';
import { PaginationService } from '../../common/services/pagination.service';
import { DrizzleService } from '../../database/drizzle.service';
import { projects } from '../../database/schema';
import { ProjectDto } from './projects.dto';

// The keys are the allow-list, so it cannot drift from the sortable columns.
const SORT_COLUMNS = {
  name: projects.name,
  createdAt: projects.createdAt,
  updatedAt: projects.updatedAt,
} as const;
const SORT_FIELDS = Object.keys(SORT_COLUMNS) as (keyof typeof SORT_COLUMNS)[];

@Injectable()
export class ProjectsService {
  constructor(
    private readonly drizzle: DrizzleService,
    private readonly pagination: PaginationService,
  ) {}

  async listProjects(query: PaginationParams): Promise<PaginatedResponse<ProjectDto>> {
    const sort = this.pagination.parseSortParam(query.sort, SORT_FIELDS);
    const offset = this.pagination.calculateOffset(query.page, query.limit);
    const column = sort ? SORT_COLUMNS[sort.field] : projects.createdAt;
    const orderBy = sort?.direction === 'asc' ? asc(column) : desc(column);

    const [rows, [{ total }]] = await Promise.all([
      this.drizzle.db.select().from(projects).orderBy(orderBy).limit(query.limit).offset(offset),
      this.drizzle.db.select({ total: count() }).from(projects),
    ]);

    return {
      data: {
        // createZodDto classes have no mapping constructor; parsing also strips unlisted columns.
        items: rows.map((p) => ProjectDto.schema.parse(p)),
        pagination: this.pagination.createMetadata(query.page, query.limit, Number(total)),
      },
    };
  }
}
```

**Kysely** — add `projects: ProjectsTable;` to `Database` in `src/database/types.ts`, plus the table interface and a migration, then `pnpm migrate`. Name the migration `NNN_projects.ts` with the next unused number in `src/database/migrations/` — Kysely runs migrations in name order and, by default, fails when a new file sorts before one already executed (e.g. `002_add_auth.ts` from add (auth)):

```ts
export interface ProjectsTable {
  id: Generated<string>;
  name: string;
  description: string | null;
  created_at: Generated<Date>;
  updated_at: Generated<Date>;
}
```

```ts
// src/database/migrations/NNN_projects.ts — NNN = next unused number (e.g. 002, or 003 after 002_add_auth.ts)
import { type Kysely, sql } from 'kysely';

export async function up(db: Kysely<unknown>): Promise<void> {
  await db.schema
    .createTable('projects')
    .addColumn('id', 'text', (col) => col.primaryKey().defaultTo(sql`gen_random_uuid()::text`))
    .addColumn('name', 'text', (col) => col.notNull())
    .addColumn('description', 'text')
    .addColumn('created_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .addColumn('updated_at', 'timestamptz', (col) => col.notNull().defaultTo(sql`now()`))
    .execute();
}

export async function down(db: Kysely<unknown>): Promise<void> {
  await db.schema.dropTable('projects').execute();
}
```

```ts
// src/modules/projects/projects.service.ts (Kysely)
import { Injectable } from '@nestjs/common';

import type { PaginatedResponse, PaginationParams } from '../../common/dto/pagination.dto';
import { PaginationService } from '../../common/services/pagination.service';
import { KyselyService } from '../../database/kysely.service';
import { ProjectDto } from './projects.dto';

// API sort name → column. The keys are the allow-list, so the two cannot drift.
const SORT_COLUMNS = { name: 'name', createdAt: 'created_at', updatedAt: 'updated_at' } as const;
const SORT_FIELDS = Object.keys(SORT_COLUMNS) as (keyof typeof SORT_COLUMNS)[];

@Injectable()
export class ProjectsService {
  constructor(
    private readonly db: KyselyService,
    private readonly pagination: PaginationService
  ) {}

  async listProjects(query: PaginationParams): Promise<PaginatedResponse<ProjectDto>> {
    const sort = this.pagination.parseSortParam(query.sort, SORT_FIELDS);
    const offset = this.pagination.calculateOffset(query.page, query.limit);

    const [rows, { total }] = await Promise.all([
      this.db
        .selectFrom('projects')
        .select(['id', 'name', 'description', 'created_at', 'updated_at'])
        .orderBy(sort ? SORT_COLUMNS[sort.field] : 'created_at', sort?.direction ?? 'desc')
        .limit(query.limit)
        .offset(offset)
        .execute(),
      this.db
        .selectFrom('projects')
        .select((eb) => eb.fn.countAll<string>().as('total'))
        .executeTakeFirstOrThrow(),
    ]);

    return {
      data: {
        // createZodDto classes have no mapping constructor; parsing also strips unlisted columns.
        items: rows.map((r) =>
          ProjectDto.schema.parse({
            id: r.id,
            name: r.name,
            description: r.description,
            createdAt: r.created_at,
            updatedAt: r.updated_at,
          })
        ),
        pagination: this.pagination.createMetadata(query.page, query.limit, Number(total)),
      },
    };
  }
}
```

**Mongoose** — same contract: `this.model.find().sort({ [field]: direction === 'asc' ? 1 : -1 }).skip(offset).limit(limit).lean()` alongside `this.model.countDocuments()`, mapping `_id` to `id` before `ProjectDto.schema.parse`.

The route is public as written — apply the authorization decision from `templatecentral:add (endpoint)` (Step 6) before shipping.

> **Coupling with `add/error-handling/nestjs`.** Its `HttpExceptionFilter` collapses most
> 400 bodies to `{ error: 'Bad request' }` but passes through a body that already carries an
> `error` key — the shape `parseSortParam` throws. **Preserve that pass-through branch** and confirm with:
>
> ```bash
> curl 'http://localhost:3000/projects?sort=asc_bogus'
> # Must list the allowed fields, NOT collapse to {"error":"Bad request"}
> ```

## Tests

Copied verbatim from `<skill-dir>/pagination/nestjs/template/test/common/pagination.service.spec.ts` by the copy step; do not re-type it.

## Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
pnpm start:dev
curl 'http://localhost:3000/projects?page=1&limit=10&sort=asc_name'   # 200
curl 'http://localhost:3000/projects?page=-1'                         # 400 VALIDATION_ERROR
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards