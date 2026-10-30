import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { appConfig } from '../env.config';

/** Mounts Swagger UI at /docs outside prod/uat. Returns whether it was mounted. */
export function setupSwagger(app: INestApplication): boolean {
  if (appConfig.ENVIRONMENT === 'prod' || appConfig.ENVIRONMENT === 'uat') {
    return false;
  }

  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, cleanupOpenApiDoc(document));
  return true;
}
