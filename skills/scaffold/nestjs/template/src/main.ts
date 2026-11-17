import { config } from 'dotenv';

config({ quiet: true });

import { createApp } from './app.factory';
import { appConfig } from './config';

async function bootstrap(): Promise<void> {
  const { app, logger, docsEnabled } = await createApp();

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
