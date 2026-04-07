import { APIError } from '@/lib/errors';

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';

const BINARY_CONTENT_TYPES = [
  'application/zip',
  'application/octet-stream',
  'application/gzip',
  'application/pdf',
  'image/',
  'video/',
  'audio/',
];

const TEXT_CONTENT_TYPES = [
  'text/plain',
  'text/html',
  'text/csv',
  'text/xml',
  'application/xml',
];

export abstract class FetchClient {
  constructor(
    protected baseUrl: string,
    protected headers: Record<string, string>
  ) {}

  // ── Core Request ──────────────────────────────────────────────────

  protected async request<T>(
    path: string,
    method: HttpMethod = 'GET',
    body?: unknown,
    query: Record<string, string | number | boolean | undefined> = {}
  ): Promise<T> {
    const url = new URL(`${this.baseUrl}/${path}`, window.location.origin);

    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v));
    }

    const headers: Record<string, string> = { ...this.headers };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    const res = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (!res.ok) {
      const data = await this.parseErrorBody(res);
      console.error(`${res.status} ${res.statusText}:`, data);
      throw new APIError({ statusCode: res.status, data });
    }

    return this.parseResponse<T>(res);
  }

  // ── Response Parsing ──────────────────────────────────────────────

  private async parseResponse<T>(res: Response): Promise<T> {
    if (res.status === 204) return undefined as T;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('application/json'))
      return (await res.json()) as T;
    if (this.matchesContentType(contentType, BINARY_CONTENT_TYPES))
      return (await res.arrayBuffer()) as T;
    if (this.matchesContentType(contentType, TEXT_CONTENT_TYPES))
      return (await res.text()) as T;
    if (contentType.includes('multipart/form-data'))
      return (await res.formData()) as T;

    return this.fallbackParse<T>(res);
  }

  private async parseErrorBody(res: Response): Promise<unknown> {
    if (res.status === 204) return undefined;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('json') || contentType.includes('+json')) {
      try {
        return await res.json();
      } catch {
        /* not valid JSON — fall through */
      }
    }

    const text = await res.text().catch(() => '');
    if (!text) return { message: res.statusText };

    try {
      return JSON.parse(text);
    } catch {
      if (
        contentType.includes('text/html') ||
        text.trimStart().startsWith('<')
      ) {
        console.error(
          `[HTTP ${res.status}] Received HTML error response from ${res.url}`
        );
        return { message: res.statusText };
      }
      return { message: text };
    }
  }

  private async fallbackParse<T>(res: Response): Promise<T> {
    try {
      return (await res.json()) as T;
    } catch {
      return (await res.text()) as T;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  private matchesContentType(contentType: string, patterns: string[]): boolean {
    return patterns.some((p) => contentType.includes(p));
  }
}
