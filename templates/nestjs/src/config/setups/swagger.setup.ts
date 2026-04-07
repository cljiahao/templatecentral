import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { appConfig } from '..';

export function setupSwagger(app: INestApplication): void {
  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, cleanupOpenApiDoc(document));
}
