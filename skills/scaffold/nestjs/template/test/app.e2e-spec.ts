import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test } from '@nestjs/testing';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
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

  // nestjs-zod runs against Nest/Swagger majors outside its declared peers; these three tests prove the coupling.
  it('POST /examples rejects an invalid body with 400 and the project error shape (ZodValidationPipe)', async () => {
    const result = await app.inject({ method: 'POST', url: '/examples', payload: { name: '' } });
    expect(result.statusCode).toBe(400);
    const body = result.json<{ statusCode: number; message: string }>();
    expect([body.statusCode, typeof body.message]).toEqual([400, 'string']);
  });

  it('POST /examples accepts a valid body and serialises the created item (createZodDto)', async () => {
    const result = await app.inject({
      method: 'POST',
      url: '/examples',
      payload: { name: 'proof', description: 'nestjs-zod' },
    });
    expect(result.statusCode).toBe(201);
    expect(result.json()).toMatchObject({ name: 'proof', description: 'nestjs-zod' });
  });

  it('builds an OpenAPI document that carries the DTO schema after cleanupOpenApiDoc', () => {
    const document = cleanupOpenApiDoc(
      SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('proof').build())
    );
    expect(document.components?.schemas).toHaveProperty('CreateExampleDto');
  });
});
