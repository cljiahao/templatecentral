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

> **File uploads with Fastify**: The NestJS template uses Fastify — `FileInterceptor` from `@nestjs/platform-express` is incompatible. File uploads require `@fastify/multipart` (`pnpm add @fastify/multipart`) and registering it in `main.ts` before `app.listen()`:
> ```ts
> // src/main.ts — add before app.listen()
> app.getHttpAdapter().getInstance().register(import('@fastify/multipart'), {
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
  @ApiOperation({ summary: 'Upload a file' })
  async uploadFile(@Req() req: FastifyRequest) {
    if (!req.isMultipart()) {
      throw new BadRequestException('File is required');
    }

    const data = await req.file();
    if (!data) {
      throw new BadRequestException('File is required');
    }

    const allowed = ['image/jpeg', 'image/png', 'application/pdf'];
    if (!allowed.includes(data.mimetype)) {
      throw new BadRequestException('File type not allowed');
    }

    const buffer = await data.toBuffer();
    const maxSize = 10 * 1024 * 1024;
    if (buffer.length > maxSize) {
      throw new BadRequestException('File must be under 10MB');
    }

    // Safe to use: buffer, data.filename, data.mimetype
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
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards