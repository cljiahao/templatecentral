import { Module } from '@nestjs/common';
import { APP_FILTER, APP_PIPE } from '@nestjs/core';
import { ZodValidationPipe } from 'nestjs-zod';
import { LoggerModule } from 'nestjs-pino';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { BaseModule, ExampleModule } from './modules';
import { appConfig } from './config';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: appConfig.LOG_LEVEL,
        // The default serializer logs all headers, leaking bearer JWTs and session cookies.
        redact: {
          paths: ['req.headers.authorization', 'req.headers.cookie', 'res.headers["set-cookie"]'],
          remove: true,
        },
        ...(appConfig.ENVIRONMENT !== 'prod' &&
          appConfig.ENVIRONMENT !== 'uat' && {
            transport: { target: 'pino-pretty', options: { singleLine: true } },
          }),
      },
    }),
    BaseModule,
    ExampleModule,
  ],
  providers: [
    {
      provide: APP_PIPE,
      useClass: ZodValidationPipe,
    },
    {
      provide: APP_FILTER,
      useClass: HttpExceptionFilter,
    },
  ],
})
export class AppModule {}
