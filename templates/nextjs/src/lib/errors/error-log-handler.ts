import { APIError } from '@/integrations/error';
import { logger } from '@/lib/logger';

export const logError = (logLabel: string, error: unknown): void => {
  if (error instanceof APIError) {
    logger.error({
      label: logLabel,
      error_type: 'APIError',
      message: error.message,
      status_code: error.statusCode,
    });
    return;
  }
  if (error instanceof Error) {
    logger.error({
      label: logLabel,
      error_type: 'Error',
      message: error.message,
    });
    return;
  }
  logger.error({
    label: logLabel,
    error_type: 'unknown',
    message: String(error),
  });
};
