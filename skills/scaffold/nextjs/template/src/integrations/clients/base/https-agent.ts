import https from 'node:https';

export interface HttpsAgentOptions {
  cert?: string | Buffer;
  key?: string | Buffer;
  ca?: string | Buffer | Array<string | Buffer>;
  rejectUnauthorized?: boolean;
  keepAlive?: boolean;
  maxSockets?: number;
  passphrase?: string;
}

// Never use NODE_ENV to disable TLS; only NODE_TLS_REJECT_UNAUTHORIZED=0 opts out.
const DEFAULT_AGENT_OPTIONS: HttpsAgentOptions = {
  rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0',
  keepAlive: true,
  maxSockets: 50,
};

export function createHttpsAgent(options?: HttpsAgentOptions): https.Agent {
  return new https.Agent({ ...DEFAULT_AGENT_OPTIONS, ...options });
}

function unwrapJsonPem(pem: string): string | undefined {
  try {
    const parsed = JSON.parse(pem);
    if (typeof parsed === 'string') return parsed.replace(/\\n/g, '\n').trim();
    if (parsed.cert) return String(parsed.cert).replace(/\\n/g, '\n').trim();
  } catch {
    return undefined;
  }
  return undefined;
}

// A value that is not JSON falls through to string normalization.
export function normalizePem(pem: string): string {
  const unwrapped = pem.trim().startsWith('{') ? unwrapJsonPem(pem) : undefined;
  if (unwrapped !== undefined) return unwrapped;

  return pem.replace(/\\n/g, '\n').replace(/^"|"$/g, '').trim();
}
