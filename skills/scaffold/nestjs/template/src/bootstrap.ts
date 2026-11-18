import { createApp } from './app.factory';
import { appConfig } from './config';

export async function bootstrap(create: typeof createApp = createApp): Promise<void> {
  const { app, logger, docsEnabled } = await create();

  const port = appConfig.PORT;
  await app.listen(port, '0.0.0.0');

  logger.log(`${appConfig.PROJECT_NAME} running on: http://localhost:${port}`);
  if (docsEnabled) {
    logger.log(`Swagger docs available at: http://localhost:${port}/docs`);
  }
}

export function runBootstrap(
  start: () => Promise<void> = bootstrap,
  exit: (code: number) => void = (code) => process.exit(code)
): Promise<void> {
  return start().catch((err: unknown) => {
    console.error(err);
    exit(1);
  });
}
