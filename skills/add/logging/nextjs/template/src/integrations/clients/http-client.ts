// src/integrations/clients/http-client.ts
import { logger } from '@/lib/logger';

// origin + path only: userinfo, query, and fragment can all carry credentials.
function sanitizeUrl(url: string): string {
  const { origin, pathname } = new URL(url);
  return `${origin}${pathname}`;
}

export async function httpGet(url: string, options?: RequestInit): Promise<Response> {
  const start = Date.now();
  const safeUrl = sanitizeUrl(url);
  try {
    const res = await fetch(url, options);
    logger.info(
      { method: 'GET', url: safeUrl, status: res.status, duration_ms: Date.now() - start },
      'Outbound HTTP'
    );
    return res;
  } catch (err) {
    logger.error(
      { method: 'GET', url: safeUrl, duration_ms: Date.now() - start, error_type: (err as Error).name },
      'Outbound HTTP error'
    );
    throw err;
  }
}
