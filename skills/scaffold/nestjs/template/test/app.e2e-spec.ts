import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { NestFastifyApplication } from '@nestjs/platform-fastify';
import { createApp } from '../src/app.factory';

// Boots the app through createApp(), so the e2e run sees the production adapter, security and CORS setup.
describe('AppController (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    app = (await createApp()).app;
  });

  afterAll(() => app.close());

  it('GET / returns 200 with the hello payload', async () => {
    const result = await app.inject({ method: 'GET', url: '/' });
    expect([result.statusCode, result.payload]).toEqual([200, 'Hello World!']);
  });

  it('POST /examples rejects an invalid body with 400 in the project error shape (ZodValidationPipe)', async () => {
    const result = await app.inject({ method: 'POST', url: '/examples', payload: { name: '' } });
    const body = result.json<{ statusCode: number; message: string }>();
    expect([result.statusCode, body.statusCode, typeof body.message]).toEqual([400, 400, 'string']);
  });

  it('creates, reads, updates and deletes an example, serialising each response (createZodDto)', async () => {
    const list = () => app.inject({ method: 'GET', url: '/examples' });
    expect((await list()).json()).toEqual([]);
    const payload = { name: 'a', description: 'd' };
    const created = await app.inject({ method: 'POST', url: '/examples', payload });
    const { id } = created.json<{ id: string }>();
    const send = (method: 'GET' | 'PUT' | 'DELETE', body?: object) =>
      app.inject({ method, url: `/examples/${id}`, ...(body && { payload: body }) });
    const read = await send('GET');
    expect([created.statusCode, read.statusCode, read.json()]).toMatchObject([
      201,
      200,
      { id, ...payload },
    ]);
    const updated = await send('PUT', { name: 'b' });
    expect([updated.statusCode, updated.json()]).toMatchObject([200, { id, name: 'b' }]);
    expect((await send('DELETE')).statusCode).toBe(204);
    expect((await list()).json()).toEqual([]);
  });

  it('builds an OpenAPI document that carries the DTO schema after cleanupOpenApiDoc', () => {
    const document = SwaggerModule.createDocument(app, new DocumentBuilder().build());
    expect(cleanupOpenApiDoc(document).components?.schemas).toHaveProperty('CreateExampleDto');
  });
});
