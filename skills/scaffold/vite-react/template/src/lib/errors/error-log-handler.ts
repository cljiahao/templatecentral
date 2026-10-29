import { APIError } from './api-error';

export const logError = (label: string, error: unknown): void => {
  if (error instanceof APIError) {
    console.error(`${label}:`, {
      message: error.message,
      statusCode: error.statusCode,
      data: error.data,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  if (error instanceof Error) {
    console.error(`${label}:`, {
      message: error.message,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  console.error(`${label}:`, {
    message: String(error),
    timestamp: new Date().toISOString(),
  });
};
