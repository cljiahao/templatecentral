<!-- ref: standards/validation-patterns/nestjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### NestJS (TypeScript + Zod via nestjs-zod)

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

> **File uploads with Fastify**: The NestJS template uses Fastify — `FileInterceptor` from `@nestjs/platform-express` is incompatible. File uploads require `@fastify/multipart` (`pnpm add @fastify/multipart`) and registering it inside `bootstrap()` before `app.listen()` — `register` returns a promise, so await it:
> ```ts
> // src/main.ts — add inside bootstrap(), before app.listen()
> const fastify = app.getHttpAdapter().getInstance();
> await fastify.register(import('@fastify/multipart'), {
>   limits: { fileSize: 10 * 1024 * 1024 },
> });
> ```

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
  Req,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import type { FastifyRequest } from 'fastify';
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
    query: z.infer<typeof paginationSchema>, // z.infer is correct here — ZodValidationPipe applies defaults; this is the post-parse output type
  ) {
    return await this.service.listProjects(query.page, query.limit);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get project by ID' })
  async getById(@Param('id') id: string) {
    return await this.service.getProject(id);
  }

  @Post('upload')
  @ApiOperation({ summary: 'Upload a file' })
  async uploadFile(@Req() req: FastifyRequest) {
    if (!req.isMultipart()) {
      throw new BadRequestException('File is required');
    }

    const data = await req.file();
    if (!data) {
      throw new BadRequestException('File is required');
    }

    // Note: data.mimetype is client-supplied — for high assurance, verify magic bytes
    // (e.g. with the file-type package) instead of trusting the declared type.
    const allowed = ['image/jpeg', 'image/png', 'application/pdf'];
    if (!allowed.includes(data.mimetype)) {
      throw new BadRequestException('File type not allowed');
    }

    // toBuffer() throws once the stream exceeds limits.fileSize (set at registration) —
    // no manual size check needed.
    const buffer = await data.toBuffer();

    // Safe to use: buffer, data.filename
    return { message: 'File uploaded' };
  }
}
```

## Testing / Verification

```bash
pnpm start:dev

# Test Swagger docs with validation schemas
curl -X POST http://localhost:3000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'  # Should return 400

pnpm test
```

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards