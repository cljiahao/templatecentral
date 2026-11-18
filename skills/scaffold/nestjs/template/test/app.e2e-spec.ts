import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test } from '@nestjs/testing';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';

describe('AppController (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({ imports: [AppModule] }).compile();

    // Mirrors app.factory.ts's adapter options so request IDs behave as in the running app.
    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter({ genReqId: () => crypto.randomUUID() })
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it.each([
    ['/', 'Hello World!'],
    ['/health', '{"status":"ok"}'],
  ])('GET %s returns 200 with the expected payload', async (url, payload) => {
    const result = await app.inject({ method: 'GET', url });
    expect([result.statusCode, result.payload]).toEqual([200, payload]);
  });
});
