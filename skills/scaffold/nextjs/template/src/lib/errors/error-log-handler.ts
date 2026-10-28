import { APIError } from '@/integrations/error';
import { logger } from '@/lib/logger';

export const logError = (label: string, error: unknown): void => {
  if (error instanceof APIError) {
    logger.error({
      label,
      message: error.message,
      statusCode: error.statusCode,
    });
    return;
  }
  if (error instanceof Error) {
    logger.error({ label, message: error.message });
    return;
  }
  logger.error({ label, message: String(error) });
};
