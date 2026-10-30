import { config } from 'dotenv';

config({ quiet: true });

import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Logger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { appConfig, setupCors, setupSecurity, setupSwagger } from './config';

// Fastify trustProxy: "*" → trust every hop (closed networks only — the leftmost, client-supplied
// X-Forwarded-For entry wins); otherwise comma-separated IPs/CIDRs that must cover EVERY proxy in
// the chain (one-hop ALB → App: ALB CIDR; two-hop ALB → Traefik → App: Traefik's AND the ALB's
// CIDRs). Numeric hop counts were removed in fastify 5.12.1 (security advisory): they
// cannot validate the connecting peer, so they now trust nothing.
function resolveTrustProxy(value: string | undefined): boolean | string | undefined {
  return value === '*' ? true : value;
}

async function bootstrap(): Promise<void> {
  const trustProxy = resolveTrustProxy(appConfig.TRUST_PROXY);
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    // Fastify assigns req.id before pino-http runs, so the UUID generator must live here; a
    // pino-http genReqId is ignored and logs show Fastify's sequential req-1, req-2.
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

  const port = appConfig.PORT;
  await app.listen(port, '0.0.0.0');

  logger.log(`${appConfig.PROJECT_NAME} running on: http://localhost:${port}`);
  if (docsEnabled) {
    logger.log(`Swagger docs available at: http://localhost:${port}/docs`);
  }
}

bootstrap().catch((err) => {
  console.error(err);
  process.exit(1);
});
