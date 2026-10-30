import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { ExampleController } from '../../src/modules/example/example.controller';
import { ExampleService } from '../../src/modules/example/example.service';
import { ExampleRepository } from '../../src/modules/example/example.repository';

describe('ExampleController', () => {
  let controller: ExampleController;
  let service: ExampleService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [ExampleController],
      providers: [ExampleService, ExampleRepository],
    }).compile();

    controller = module.get<ExampleController>(ExampleController);
    service = module.get<ExampleService>(ExampleService);
  });

  it('should return an empty array initially', () => {
    expect(controller.findAll()).toEqual([]);
  });

  it('should create and retrieve an example', () => {
    const created = controller.create({ name: 'Test', description: 'Desc' });
    expect(created.name).toBe('Test');
    expect(created.id).toBeDefined();

    const found = controller.findOne(created.id);
    expect(found.name).toBe('Test');
  });

  it('should update an example', () => {
    const created = service.create({ name: 'Original' });
    const updated = controller.update(created.id, { name: 'Updated' });
    expect(updated.name).toBe('Updated');
  });

  it('should delete an example', () => {
    const created = service.create({ name: 'ToDelete' });
    controller.remove(created.id);
    expect(controller.findAll()).toEqual([]);
  });
});
