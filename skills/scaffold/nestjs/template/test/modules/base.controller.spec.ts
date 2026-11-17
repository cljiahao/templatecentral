import { describe, expect, it } from 'vitest';
import { Test } from '@nestjs/testing';
import { BaseController } from '../../src/modules/base/base.controller';
import { BaseService } from '../../src/modules/base/base.service';

describe('BaseController', () => {
  it('returns the greeting and an ok health status', async () => {
    const module = await Test.createTestingModule({
      controllers: [BaseController],
      providers: [BaseService],
    }).compile();
    const controller = module.get(BaseController);
    expect([controller.getHello(), controller.checkHealth()]).toEqual([
      'Hello World!',
      { status: 'ok' },
    ]);
  });
});
