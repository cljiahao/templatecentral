import { describe, expect, it } from 'vitest';
import { Test } from '@nestjs/testing';
import { ExampleController } from '../../src/modules/example/example.controller';
import { ExampleService } from '../../src/modules/example/example.service';
import { ExampleRepository } from '../../src/modules/example/example.repository';

describe('ExampleController', () => {
  it('creates, retrieves, updates and deletes an example', async () => {
    const module = await Test.createTestingModule({
      controllers: [ExampleController],
      providers: [ExampleService, ExampleRepository],
    }).compile();
    const controller = module.get(ExampleController);

    expect(controller.findAll()).toEqual([]);
    const created = controller.create({ name: 'Test', description: 'Desc' });
    expect(controller.findOne(created.id).name).toBe('Test');
    expect(controller.update(created.id, { name: 'Updated' }).name).toBe('Updated');
    controller.remove(created.id);
    expect(controller.findAll()).toEqual([]);
  });
});
