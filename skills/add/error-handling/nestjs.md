<!-- ref: add/error-handling/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS — Error Handling

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Enhanced HTTP Exception Filter**

```ts
// src/common/filters/http-exception.filter.ts
import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { ZodSerializationException, ZodValidationException } from 'nestjs-zod';
import { z, ZodError } from 'zod';

interface ErrorResponse {
  error: string;
  details?: {
    fieldErrors?: Record<string, string[]>;
    code?: string;
  };
}

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const reply = ctx.getResponse<FastifyReply>();
    const status = exception.getStatus();

    let errorResponse: ErrorResponse = {
      error: 'An error occurred',
    };

    if (exception instanceof ZodValidationException) {
      // Request validation failure (global ZodValidationPipe) — a client 400 with field details
      const zodError = exception.getZodError();
      if (zodError instanceof ZodError) {
        const fieldErrors = z.flattenError(zodError).fieldErrors as Record<string, string[]>;
        errorResponse = {
          error: 'Validation failed',
          details: { fieldErrors, code: 'VALIDATION_ERROR' },
        };
        this.logger.warn(`Validation error: ${zodError.message}`);
      }
    } else if (exception instanceof ZodSerializationException) {
      // Response serialization failure — a server bug (500). Log it; never leak schema details.
      const zodError = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
      errorResponse = { error: 'Internal server error' };
    } else if (status === HttpStatus.BAD_REQUEST) {
      errorResponse = { error: 'Bad request', details: { code: 'BAD_REQUEST' } };
    } else if (status === HttpStatus.UNAUTHORIZED) {
      errorResponse = { error: 'Authentication required' };
    } else if (status === HttpStatus.FORBIDDEN) {
      errorResponse = { error: 'Access denied' };
    } else if (status === HttpStatus.NOT_FOUND) {
      errorResponse = { error: 'Resource not found' };
    } else if (status === HttpStatus.CONFLICT) {
      errorResponse = { error: 'Resource conflict', details: { code: 'CONFLICT' } };
    } else if (status === HttpStatus.TOO_MANY_REQUESTS) {
      errorResponse = { error: 'Too many requests' };
      void reply.header('Retry-After', '60');
    }

    if (status >= 500) {
      this.logger.error(`HTTP ${status}: ${exception.message}`);
    } else {
      this.logger.warn(`HTTP ${status}: ${exception.message}`);
    }

    void reply.status(status).send(errorResponse);
  }
}
```

**2. Custom Exception Example**

```ts
// src/common/exceptions/not-found.exception.ts
// Name with a domain prefix to avoid shadowing @nestjs/common's built-in NotFoundException
import { HttpException, HttpStatus } from '@nestjs/common';

export class AppNotFoundException extends HttpException {
  constructor(message: string = 'Resource not found') {
    super(message, HttpStatus.NOT_FOUND);
  }
}

// src/modules/projects/projects.service.ts
import { Injectable } from '@nestjs/common';
import { AppNotFoundException } from '../../common/exceptions/not-found.exception';

@Injectable()
export class ProjectsService {
  async getProject(id: string) {
    const project = null; // replace with: await this.drizzle.db.select().from(projects).where(eq(projects.id, id)).then(r => r[0] ?? null)
    
    if (!project) {
      throw new AppNotFoundException('Project not found');
    }
    
    return project;
  }
}
```

**3. API Route with Validation**

```ts
// src/modules/projects/projects.controller.ts
import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { ProjectsService } from './projects.service';

const CreateProjectSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

class CreateProjectDto extends createZodDto(CreateProjectSchema) {}

@ApiTags('projects')
@Controller('projects')
export class ProjectsController {
  constructor(private readonly service: ProjectsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new project' })
  @ApiResponse({ status: 201, description: 'Project created' })
  @ApiResponse({ status: 400, description: 'Validation failed' })
  async create(@Body() dto: CreateProjectDto) {
    return await this.service.createProject(dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get project by ID' })
  @ApiResponse({ status: 200, description: 'Project found' })
  @ApiResponse({ status: 404, description: 'Project not found' })
  async getById(@Param('id') id: string) {
    return await this.service.getProject(id);
  }
}
```

## Validate

```bash
# Test controller validation
pnpm test

# Check Swagger docs at /docs includes error schemas
pnpm start:dev
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards