import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { ZodSerializationException } from 'nestjs-zod';
import { ZodError } from 'zod';
import { HTTP_STATUS_MESSAGES } from '../constants';

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  // 5xx messages are server-side detail: log them, return generic text.
  catch(exception: HttpException, host: ArgumentsHost): void {
    if (exception instanceof ZodSerializationException) {
      const zodError: unknown = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
    }

    const ctx = host.switchToHttp();
    const reply = ctx.getResponse<FastifyReply>();
    const status = exception.getStatus();
    const isServerError = status >= 500;
    if (isServerError) {
      this.logger.error(exception.message, exception.stack);
    }
    reply.status(status).send({
      statusCode: status,
      message: isServerError ? HTTP_STATUS_MESSAGES.INTERNAL_ERROR : exception.message,
    });
  }
}
