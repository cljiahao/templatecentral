import { APIError } from '@/integrations/error';
import { logError } from '@/lib/errors/error-log-handler';
import { NextResponse } from 'next/server';

const STATUS_MESSAGES: Record<number, string> = {
  400: 'Invalid request',
  401: 'Authentication required',
  403: 'Access denied',
  404: 'Resource not found',
  408: 'Request timed out',
  409: 'Conflict',
  429: 'Too many requests',
  500: 'Internal server error',
  502: 'Service temporarily unavailable',
  503: 'Service temporarily unavailable',
};

export const handleApiError = (label: string, error: unknown) => {
  logError(label, error);

  if (error instanceof APIError) {
    const status = error.statusCode;
    const message = STATUS_MESSAGES[status] ?? label;
    return NextResponse.json({ error: message }, { status });
  }

  return NextResponse.json({ error: label }, { status: 500 });
};
