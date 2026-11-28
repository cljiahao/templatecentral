<!-- ref: add/endpoint/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add an Endpoint (NestJS module)

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
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
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
  findAll(): Task[] {
    return this.taskService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get task by ID' })
  @ApiParam({ name: 'id', type: 'string', format: 'uuid' })
  findOne(@Param('id', ParseUUIDPipe) id: string): Task {
    return this.taskService.findOne(id);
  }

  @Post()
  @ApiOperation({ summary: 'Create task' })
  @ApiBody({ type: CreateTaskDto })
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateTaskDto): Task {
    return this.taskService.create(dto);
  }

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
  remove(@Param('id', ParseUUIDPipe) id: string): void {
    this.taskService.remove(id);
  }
}
```

#### Authorization — decide before moving on

The controller above is **fully public**: anyone can create, update and delete records.

- **If `src/modules/auth/` exists**, put `@UseGuards(JwtAuthGuard)` + `@ApiBearerAuth()` on
  the controller class, and remove the guard from read routes only where public access is
  deliberate.

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

  Without `@ApiBearerAuth()` Swagger shows the routes as unauthenticated and "try it out" fails with a 401.

- **No auth yet**: ask whether unauthenticated POST/PATCH/DELETE on `/tasks` is intended;
  if not, run `templatecentral:add` (auth) first. Ownership is separate from authentication:
  the service must also check that the caller owns a row before updating or deleting it.

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

In `src/modules/index.ts`, add (`<name>` = module name, e.g. `task`):

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

Apply the test-value rule (`docs/CONSTITUTION.md` §4). Extend an existing spec when one covers the module, otherwise create `test/modules/<name>.controller.spec.ts` (`<name>` = module name, e.g. `task`); for a public controller, drop the `JwtAuthGuard` import and `.overrideGuard(...)` lines:

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
      // The guard path belongs in an e2e test against the real AppModule.
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

### 10. Validate

1. Run `pnpm start:dev` and open Swagger at `/docs`: no import or DI errors, and the new endpoints sit under the correct tag
2. Run `pnpm test` and test one endpoint via Swagger or `curl`: the new unit test passes and the full flow works
