import { APIError } from '@/integrations/error';

export const logError = (logLabel: string, error: unknown): void => {
  if (error instanceof APIError) {
    console.error(`${logLabel}:`, {
      message: error.message,
      statusCode: error.statusCode,
      data: error.data,
      timestamp: new Date().toISOString(),
    });
    return;
  }
  if (error instanceof Error) {
    console.error(`${logLabel}:`, {
      message: error.message,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  console.error(`${logLabel}:`, {
    message: String(error),
    timestamp: new Date().toISOString(),
  });
};
