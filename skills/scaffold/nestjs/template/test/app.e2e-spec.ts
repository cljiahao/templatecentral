import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';

describe('AppController (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    // Mirror main.ts's adapter options so request IDs (and anything keyed off them, e.g. log
    // correlation) behave the same under test as in the running app.
    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter({ genReqId: () => crypto.randomUUID() })
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET / should return "Hello World!"', () => {
    return app.inject({ method: 'GET', url: '/' }).then((result) => {
      expect(result.statusCode).toBe(200);
      expect(result.payload).toBe('Hello World!');
    });
  });

  it('GET /health should return OK', () => {
    return app.inject({ method: 'GET', url: '/health' }).then((result) => {
      expect(result.statusCode).toBe(200);
      expect(JSON.parse(result.payload)).toEqual({ status: 'ok' });
    });
  });
});
