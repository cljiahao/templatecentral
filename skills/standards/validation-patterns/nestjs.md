<!-- ref: standards/validation-patterns/nestjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### NestJS (TypeScript + Zod via nestjs-zod)

The scaffold registers `ZodValidationPipe` globally (`APP_PIPE`), so any `createZodDto` class used as a `@Body()`/`@Query()` type is validated automatically. Plain-typed params (`@Param('id') id: string`) are NOT — give them an explicit pipe.

**1. DTOs**

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
```

```ts
// src/modules/projects/dto/list-projects-query.dto.ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const listProjectsQuerySchema = z.object({
  page: z.coerce.number().int().positive().max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(10),
});

export class ListProjectsQueryDto extends createZodDto(listProjectsQuerySchema) {}
```

**2. Controller — validate at the boundary, delegate everything else**

> **File uploads with Fastify**: `FileInterceptor` from `@nestjs/platform-express` is incompatible with the Fastify adapter. Use `@fastify/multipart` (`pnpm add @fastify/multipart`), registered inside `bootstrap()` before `app.listen()` — `register` returns a promise, so await it:
> ```ts
> // src/main.ts — inside bootstrap(), before app.listen()
> const fastify = app.getHttpAdapter().getInstance();
> await fastify.register(import('@fastify/multipart'), {
>   limits: { fileSize: 10 * 1024 * 1024, files: 1 },
> });
> ```

```ts
// src/modules/projects/projects.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import { ApiBody, ApiConsumes, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { FastifyRequest } from 'fastify';
import { ZodValidationPipe } from 'nestjs-zod';
import { z } from 'zod';
import { CreateProjectDto } from './dto/create-project.dto';
import { ListProjectsQueryDto } from './dto/list-projects-query.dto';
import { ProjectsService } from './projects.service';

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
  async list(@Query() query: ListProjectsQueryDto) {
    return await this.service.listProjects(query.page, query.limit);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get project by ID' })
  async getById(@Param('id', new ZodValidationPipe(z.uuid())) id: string) {
    return await this.service.getProject(id);
  }

  @Post('upload')
  @ApiOperation({ summary: 'Upload a file' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    required: true,
    schema: {
      type: 'object',
      required: ['file'],
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  async uploadFile(@Req() req: FastifyRequest) {
    const file = req.isMultipart() ? await req.file() : undefined;
    if (!file) {
      throw new BadRequestException('File is required');
    }
    return await this.service.storeUpload(file);
  }
}
```

**3. Service — upload checks live here, not in the controller**

```ts
// src/modules/projects/projects.service.ts (upload excerpt)
import { randomUUID } from 'node:crypto';
import type { MultipartFile } from '@fastify/multipart';
import { BadRequestException, Injectable, PayloadTooLargeException } from '@nestjs/common';

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'application/pdf'];

@Injectable()
export class ProjectsService {
  async storeUpload(file: MultipartFile) {
    // mimetype is client-supplied — for high assurance, also verify magic bytes
    // (e.g. with the file-type package) against the buffer below.
    if (!ALLOWED_TYPES.includes(file.mimetype)) {
      throw new BadRequestException('File type not allowed');
    }

    // toBuffer() throws a plain Error once the stream exceeds limits.fileSize. Unconverted,
    // it bypasses HttpExceptionFilter and surfaces as an unformatted 500.
    let buffer: Buffer;
    try {
      buffer = await file.toBuffer();
    } catch {
      throw new PayloadTooLargeException('File exceeds the maximum allowed size');
    }

    // file.filename is attacker-controlled (`../`, absolute paths, NUL bytes) — it must
    // NEVER become part of a storage path. It survives only as sanitized display metadata.
    const storageKey = randomUUID();
    const displayName = file.filename.replace(/[^\w.\- ]/g, '_').slice(0, 255);

    return { storageKey, displayName, size: buffer.byteLength };
  }
}
```

## Testing / Verification

```bash
pnpm start:dev

# Invalid body → 400 from the global ZodValidationPipe
curl -X POST http://localhost:3000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'

# Non-UUID path param → 400
curl http://localhost:3000/projects/not-a-uuid

pnpm test
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
