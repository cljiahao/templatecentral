import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, OpenAPIObject, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { appConfig } from '../env.config';

/** Builds the OpenAPI document; the contract export script calls it too. */
export function buildOpenApiDocument(app: INestApplication): OpenAPIObject {
  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  return cleanupOpenApiDoc(SwaggerModule.createDocument(app, options));
}

/** Mounts Swagger UI at /docs outside prod/uat. Returns whether it was mounted. */
export function setupSwagger(app: INestApplication): boolean {
  if (appConfig.ENVIRONMENT === 'prod' || appConfig.ENVIRONMENT === 'uat') {
    return false;
  }

  SwaggerModule.setup('docs', app, buildOpenApiDocument(app));
  return true;
}
