import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { BaseController } from '../../src/modules/base/base.controller';
import { BaseService } from '../../src/modules/base/base.service';

describe('BaseController', () => {
  let controller: BaseController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [BaseController],
      providers: [BaseService],
    }).compile();

    controller = module.get<BaseController>(BaseController);
  });

  it('should return "Hello World!"', () => {
    expect(controller.getHello()).toBe('Hello World!');
  });

  it('should return health status ok', () => {
    expect(controller.checkHealth()).toEqual({ status: 'ok' });
  });
});
