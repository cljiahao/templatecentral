<!-- ref: add/endpoint/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add an Endpoint (NestJS module)

Guide for adding a new feature module following the controller → service → repository architecture.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Naming Convention

Replace `<name>` throughout using these rules:

| Context | Format | Example (`<name>` = `task`) |
|---------|--------|-----------------------------|
| Directory | kebab-case | `src/modules/task/` |
| File names | kebab-case + dot suffix | `task.controller.ts` |
| Class names | PascalCase + suffix | `TaskController`, `TaskService`, `TaskModule` |
| Route path | kebab-case plural | `@Controller('tasks')` |
| Swagger tag | Title case plural | `@ApiTags('Tasks')` |

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create Module Directory

Create `src/modules/<name>/`; Steps 2–7 fill it.

### 2. Define Types

Create `src/modules/<name>/<name>.types.ts`:

```typescript
export interface Task {
  id: string;
  title: string;
  completed: boolean;
  createdAt: string;
  updatedAt: string;
}
```

### 3. Define DTOs

Create `src/modules/<name>/<name>.dto.ts`:

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateTaskSchema = z.object({
  title: z.string().min(1).max(200),
  completed: z.boolean().default(false),
});

const UpdateTaskSchema = CreateTaskSchema.partial();

export class CreateTaskDto extends createZodDto(CreateTaskSchema) {}
export class UpdateTaskDto extends createZodDto(UpdateTaskSchema) {}
```

### 4. Create Repository

Create `src/modules/<name>/<name>.repository.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import type { Task } from './<name>.types';

@Injectable()
export class TaskRepository {
  private tasks = new Map<string, Task>();

  findAll(): Task[] {
    return [...this.tasks.values()];
  }

  findById(id: string): Task | undefined {
    return this.tasks.get(id);
  }

  save(task: Task): Task {
    this.tasks.set(task.id, task);
    return task;
  }

  remove(id: string): boolean {
    return this.tasks.delete(id);
  }
}
```

The repository is persistence-only — it returns `undefined`/`false` for a missing row and the service decides that is a 404. Swap the `Map` for Drizzle/Mongoose after `templatecentral:add (database)`.

### 5. Create Service

Create `src/modules/<name>/<name>.service.ts`:

```typescript
import { randomUUID } from 'node:crypto';
import { Injectable, NotFoundException } from '@nestjs/common';
import { TaskRepository } from './<name>.repository';
import { CreateTaskDto, UpdateTaskDto } from './<name>.dto';
import type { Task } from './<name>.types';

@Injectable()
export class TaskService {
  constructor(private readonly repository: TaskRepository) {}

  findAll(): Task[] {
    return this.repository.findAll();
  }

  findOne(id: string): Task {
    const task = this.repository.findById(id);
    if (!task) throw new NotFoundException('Task not found');
    return task;
  }

  create(dto: CreateTaskDto): Task {
    const now = new Date().toISOString();
    return this.repository.save({ id: randomUUID(), ...dto, createdAt: now, updatedAt: now });
  }

  update(id: string, dto: UpdateTaskDto): Task {
    const existing = this.findOne(id);
    return this.repository.save({ ...existing, ...dto, updatedAt: new Date().toISOString() });
  }

  remove(id: string): void {
    if (!this.repository.remove(id)) throw new NotFoundException('Task not found');
  }
}
```

### 6. Create Controller

Create `src/modules/<name>/<name>.controller.ts`:

```typescript
import {
  Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Patch, Post,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiParam, ApiBody } from '@nestjs/swagger';
import { TaskService } from './<name>.service';
import { CreateTaskDto, UpdateTaskDto } from './<name>.dto';
import type { Task } from './<name>.types';

@ApiTags('Tasks')
@Controller('tasks')
export class TaskController {
  constructor(private readonly taskService: TaskService) {}

  @Get()
  @ApiOperation({ summary: 'List all tasks' })
  findAll(): Task[] { return this.taskService.findAll(); }

  @Get(':id')
  @ApiOperation({ summary: 'Get task by ID' })
  @ApiParam({ name: 'id', type: 'string', format: 'uuid' })
  findOne(@Param('id', ParseUUIDPipe) id: string): Task { return this.taskService.findOne(id); }

  @Post()
  @ApiOperation({ summary: 'Create task' })
  @ApiBody({ type: CreateTaskDto })
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateTaskDto): Task { return this.taskService.create(dto); }

  @Patch(':id')
  @ApiOperation({ summary: 'Update task' })
  @ApiParam({ name: 'id', type: 'string', format: 'uuid' })
  @ApiBody({ type: UpdateTaskDto })
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateTaskDto): Task {
    return this.taskService.update(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete task' })
  @ApiParam({ name: 'id', type: 'string', format: 'uuid' })
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id', ParseUUIDPipe) id: string): void { this.taskService.remove(id); }
}
```

#### Authorization — decide before moving on

The controller above is **fully public**: anyone who can reach the service can create,
update, and delete records. That is almost never what a generated CRUD module should ship
as, so treat authorization as a required decision, not an optional extra.

- **If `src/modules/auth/` exists** (the project ran `templatecentral:add` (auth)), apply
  the project's guard by default. Put `@UseGuards(JwtAuthGuard)` + `@ApiBearerAuth()` on
  the controller class to cover every route, then remove the guard from individual read
  routes only where public access is a deliberate product decision.

  ```typescript
  import { Controller, UseGuards } from '@nestjs/common';
  import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
  import { JwtAuthGuard } from '../auth/jwt-auth.guard';

  @ApiTags('Tasks')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Controller('tasks')
  export class TaskController {
  ```

  Without `@ApiBearerAuth()` the routes still work but Swagger renders them as
  unauthenticated, so "try it out" fails with a confusing 401.

- **If the project has no auth yet**, ask the user explicitly: *"POST/PATCH/DELETE on
  `/tasks` will be reachable without credentials — is unauthenticated write access
  intended?"* If it is not, run `templatecentral:add` (auth) before shipping the module.
- **Ownership is separate from authentication.** A guard only proves *someone* is logged
  in. If a record belongs to a user, the service must also check that the caller owns the
  row before updating or deleting it.

### 7. Create Module

Create `src/modules/<name>/<name>.module.ts`:

```typescript
import { Module } from '@nestjs/common';
import { TaskController } from './<name>.controller';
import { TaskService } from './<name>.service';
import { TaskRepository } from './<name>.repository';

@Module({
  controllers: [TaskController],
  providers: [TaskService, TaskRepository],
  exports: [TaskService],
})
export class TaskModule {}
```

### 8. Register the Module

In `src/modules/index.ts`, add (replace `<name>` with the module name, e.g., `task`):

```typescript
export * from './task/task.module';
```

In `src/app.module.ts`, add `TaskModule` to the existing `./modules` import and **append** it to the `imports` array — never rewrite the array, which also holds `LoggerModule`, `ThrottlerModule`, `DatabaseModule`, and the other feature modules:

```typescript
import { BaseModule, ExampleModule, TaskModule } from './modules';

  imports: [
    // ...existing entries, unchanged
    TaskModule,
  ],
```

### 9. Add Tests

Create `test/modules/<name>.controller.spec.ts` (replace `<name>` with the actual module name, e.g., `task`):

```typescript
import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { TaskController } from '../../src/modules/task/task.controller';
import { TaskService } from '../../src/modules/task/task.service';
import { TaskRepository } from '../../src/modules/task/task.repository';
import { JwtAuthGuard } from '../../src/modules/auth/jwt-auth.guard';

describe('TaskController', () => {
  let controller: TaskController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [TaskController],
      providers: [TaskService, TaskRepository],
    })
      // The guard's own deps (PassportStrategy, PinoLogger) are not in this module; the 401
      // path belongs in an e2e test against the real AppModule.
      .overrideGuard(JwtAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<TaskController>(TaskController);
  });

  it('should return an empty array initially', () => {
    expect(controller.findAll()).toEqual([]);
  });
});
```

Drop the `JwtAuthGuard` import and `.overrideGuard(...)` lines if the controller is deliberately public.

### 10. Validate

After creating all files:
1. Run `pnpm start:dev` — confirm no import or DI errors
2. Open Swagger docs at `/docs` — verify the new endpoints appear under the correct tag
3. Run `pnpm test` — confirm the new unit test passes
4. Test one endpoint manually via Swagger or `curl` to verify the full flow

## Rules

- **Tests are mandatory** — never add or change a module's HTTP surface (controller/service/repository) without new or updated Vitest tests in `test/` in the same change.
- NEVER forget to register the module in `app.module.ts` and export from `modules/index.ts`

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards