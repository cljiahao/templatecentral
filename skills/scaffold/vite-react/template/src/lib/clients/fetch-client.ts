// Not the '@/lib/errors' barrel: it loads error-log-handler, which add (logging) wires to an
// ApiClient subclass — importing through it makes a cycle that breaks `extends`.
import { APIError } from '@/lib/errors/api-error';

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

const TEXT_CONTENT_TYPES = ['text/plain', 'text/html', 'text/csv', 'text/xml', 'application/xml'];

const REQUEST_TIMEOUT_MS = 30_000;

export abstract class FetchClient {
  // Subclass knobs: cookie auth (add auth) sends 'include'; unload-time senders need keepalive.
  protected credentials: RequestCredentials = 'same-origin';
  protected keepalive = false;

  constructor(
    protected baseUrl: string,
    protected headers: Record<string, string>
  ) {}

  /** Per-request headers (e.g. a CSRF token) — the base client has no auth knowledge. */
  protected requestHeaders(_method: HttpMethod): Record<string, string> {
    return {};
  }

  protected async request<T>(
    path: string,
    method: HttpMethod = 'GET',
    body?: unknown,
    query: Record<string, string | number | boolean | undefined> = {},
    signal?: AbortSignal
  ): Promise<T> {
    const url = new URL(
      `${this.baseUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`,
      window.location.origin
    );

    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v));
    }

    const headers: Record<string, string> = { ...this.headers, ...this.requestHeaders(method) };
    let payload: BodyInit | undefined;
    if (body instanceof FormData) {
      // No Content-Type — the browser must add its own multipart boundary.
      payload = body;
    } else if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }

    // fetch has no default timeout — an unresponsive upstream would leave the
    // calling React Query hook pending indefinitely without this.
    const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
    const res = await fetch(url, {
      method,
      headers,
      body: payload,
      credentials: this.credentials,
      keepalive: this.keepalive,
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
    });

    if (!res.ok) {
      const data = await this.parseErrorBody(res);
      // Log status/URL only — never the error body (may contain PII)
      console.error(`[HTTP ${res.status}] ${res.statusText} from ${res.url}`);
      throw new APIError({ statusCode: res.status, data });
    }

    return this.parseResponse<T>(res);
  }

  private async parseResponse<T>(res: Response): Promise<T> {
    if (res.status === 204) return undefined as T;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('application/json')) return (await res.json()) as T;
    if (this.matchesContentType(contentType, BINARY_CONTENT_TYPES))
      return (await res.arrayBuffer()) as T;
    if (this.matchesContentType(contentType, TEXT_CONTENT_TYPES)) return (await res.text()) as T;
    if (contentType.includes('multipart/form-data')) return (await res.formData()) as T;

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
      if (contentType.includes('text/html') || text.trimStart().startsWith('<')) {
        console.error(`[HTTP ${res.status}] Received HTML error response from ${res.url}`);
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

  private matchesContentType(contentType: string, patterns: string[]): boolean {
    return patterns.some((p) => contentType.includes(p));
  }
}
