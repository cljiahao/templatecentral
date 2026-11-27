import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Logger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { appConfig, setupCors, setupSecurity, setupSwagger } from './config';

// Fastify 5.12.1+: numeric hops trust nothing; list CIDRs covering every proxy hop. '*' lets client X-Forwarded-For win.
export function resolveTrustProxy(value: string | undefined): boolean | string | undefined {
  return value === '*' ? true : value;
}

// Builds and initializes the app without listening, so tests can drive it with `app.inject()`.
// Fastify assigns req.id before pino-http runs, so genReqId must live here.
export async function createApp(): Promise<{
  app: NestFastifyApplication;
  logger: Logger;
  docsEnabled: boolean;
}> {
  const trustProxy = resolveTrustProxy(appConfig.TRUST_PROXY);
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({
      genReqId: () => crypto.randomUUID(),
      ...(trustProxy ? { trustProxy } : {}),
    }),
    { bufferLogs: true }
  );
  const logger = app.get(Logger);
  app.useLogger(logger);

  await setupSecurity(app);
  logger.log('Security middleware configured');

  setupCors(app);
  logger.log('CORS configured');

  const docsEnabled = setupSwagger(app);

  await app.init();
  logger.log('Application initialized');

  return { app, logger, docsEnabled };
}
