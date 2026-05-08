---
name: nestjs-add-module
description: Use when the user asks to create a new feature module, add CRUD endpoints, or wire up a new resource in a NestJS project.
---

# Add a NestJS Module

Guide for adding a new feature module following the controller → service → repository architecture.

## Prerequisites

Requires a project scaffolded with `templatecentral:nestjs-scaffold`. See Step 0.

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

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create Module Directory

Create `src/modules/<name>/` with the following files:

### 2. Define Types

Define the domain interface first — this establishes the data shape before any implementation.

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
import { Injectable, NotFoundException } from '@nestjs/common';
import type { Task } from './<name>.types';

@Injectable()
export class TaskRepository {
  private tasks = new Map<string, Task>();

  findAll(): Task[] {
    return [...this.tasks.values()];
  }

  findById(id: string): Task {
    const task = this.tasks.get(id);
    if (!task) throw new NotFoundException(`Task ${id} not found`);
    return task;
  }

  create(task: Task): Task {
    this.tasks.set(task.id, task);
    return task;
  }

  update(id: string, data: Partial<Task>): Task {
    const existing = this.findById(id);
    const updated = { ...existing, ...data, updatedAt: new Date().toISOString() };
    this.tasks.set(id, updated);
    return updated;
  }

  remove(id: string): void {
    if (!this.tasks.delete(id)) throw new NotFoundException(`Task ${id} not found`);
  }
}
```

### 5. Create Service

Create `src/modules/<name>/<name>.service.ts`:

```typescript
import { Injectable } from '@nestjs/common';
import { TaskRepository } from './<name>.repository';
import { CreateTaskDto, UpdateTaskDto } from './<name>.dto';
import type { Task } from './<name>.types';

@Injectable()
export class TaskService {
  constructor(private readonly repository: TaskRepository) {}

  findAll(): Task[] { return this.repository.findAll(); }
  findOne(id: string): Task { return this.repository.findById(id); }

  create(dto: CreateTaskDto): Task {
    const now = new Date().toISOString();
    const task: Task = { id: crypto.randomUUID(), ...dto, createdAt: now, updatedAt: now };
    return this.repository.create(task);
  }

  update(id: string, dto: UpdateTaskDto): Task {
    return this.repository.update(id, dto);
  }

  remove(id: string): void { this.repository.remove(id); }
}
```

### 6. Create Controller

Create `src/modules/<name>/<name>.controller.ts`:

```typescript
import { Controller, Get, Post, Put, Delete, Param, Body, HttpCode, HttpStatus } from '@nestjs/common';
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
  @ApiParam({ name: 'id', type: 'string' })
  findOne(@Param('id') id: string): Task { return this.taskService.findOne(id); }

  @Post()
  @ApiOperation({ summary: 'Create task' })
  @ApiBody({ type: CreateTaskDto })
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateTaskDto): Task { return this.taskService.create(dto); }

  @Put(':id')
  @ApiOperation({ summary: 'Update task' })
  @ApiParam({ name: 'id', type: 'string' })
  @ApiBody({ type: UpdateTaskDto })
  update(@Param('id') id: string, @Body() dto: UpdateTaskDto): Task {
    return this.taskService.update(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete task' })
  @ApiParam({ name: 'id', type: 'string' })
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string): void { this.taskService.remove(id); }
}
```

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

In `src/app.module.ts`, add to imports (keep existing modules like `ExampleModule` until you remove example code):

```typescript
import { TaskModule } from './modules';

@Module({
  imports: [BaseModule, ExampleModule, TaskModule],
  // ...
})
```

### 9. Add Tests

Create `test/modules/<name>.controller.spec.ts` (replace `<name>` with the actual module name, e.g., `task`):

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { TaskController } from '../../src/modules/task/task.controller';
import { TaskService } from '../../src/modules/task/task.service';
import { TaskRepository } from '../../src/modules/task/task.repository';

describe('TaskController', () => {
  let controller: TaskController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [TaskController],
      providers: [TaskService, TaskRepository],
    }).compile();

    controller = module.get<TaskController>(TaskController);
  });

  it('should return an empty array initially', () => {
    expect(controller.findAll()).toEqual([]);
  });
});
```

### 10. Validate

After creating all files:
1. Run `pnpm start:dev` — confirm no import or DI errors
2. Open Swagger docs at `/docs` — verify the new endpoints appear under the correct tag
3. Run `pnpm test` — confirm the new unit test passes
4. Test one endpoint manually via Swagger or `curl` to verify the full flow

## Rules

- **Tests are mandatory** — never add or change a module’s HTTP surface (controller/service/repository) without new or updated Vitest tests in `test/` in the same change.
- NEVER forget to register the module in `app.module.ts` and export from `modules/index.ts`

## Validate

```bash
pnpm build    # zero compile errors
pnpm test     # module tests pass
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
