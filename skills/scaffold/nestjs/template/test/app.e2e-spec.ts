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

  // nestjs-zod runs on Nest/Swagger majors outside its declared peers; the next three tests prove that coupling.
  it('POST /examples rejects an invalid body with 400 in the project error shape (ZodValidationPipe)', async () => {
    const result = await app.inject({ method: 'POST', url: '/examples', payload: { name: '' } });
    const body = result.json<{ statusCode: number; message: string }>();
    expect([result.statusCode, body.statusCode, typeof body.message]).toEqual([400, 400, 'string']);
  });

  it('creates, reads, updates and deletes an example, serialising each response (createZodDto)', async () => {
    const created = await app.inject({ method: 'POST', url: '/examples', payload: { name: 'a' } });
    const { id } = created.json<{ id: string }>();
    expect(created.statusCode).toBe(201);
    const send = (method: 'GET' | 'PUT' | 'DELETE', payload?: object) =>
      app.inject({ method, url: `/examples/${id}`, payload });
    expect((await send('GET')).json()).toMatchObject({ id, name: 'a' });
    expect((await send('PUT', { name: 'b' })).json()).toMatchObject({ id, name: 'b' });
    expect((await send('DELETE')).statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/examples' })).json()).toEqual([]);
  });

  it('builds an OpenAPI document that carries the DTO schema after cleanupOpenApiDoc', () => {
    const document = cleanupOpenApiDoc(
      SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('proof').build())
    );
    expect(document.components?.schemas).toHaveProperty('CreateExampleDto');
  });
});
