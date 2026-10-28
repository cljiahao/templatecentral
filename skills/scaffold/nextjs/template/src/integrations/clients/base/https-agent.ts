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

// Respect explicit opt-out (NODE_TLS_REJECT_UNAUTHORIZED=0) but default to true in all envs.
// Never use NODE_ENV to disable TLS — staging/UAT servers have valid certs and should be verified.
const DEFAULT_AGENT_OPTIONS: HttpsAgentOptions = {
  rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0',
  keepAlive: true,
  maxSockets: 50,
};

export function createHttpsAgent(options?: HttpsAgentOptions): https.Agent {
  return new https.Agent({ ...DEFAULT_AGENT_OPTIONS, ...options });
}

export function normalizePem(pem: string): string {
  if (pem.trim().startsWith('{')) {
    try {
      const parsed = JSON.parse(pem);
      if (typeof parsed === 'string')
        return parsed.replace(/\\n/g, '\n').trim();
      if (parsed.cert) return String(parsed.cert).replace(/\\n/g, '\n').trim();
    } catch {
      // fall through to string normalization
    }
  }

  return pem.replace(/\\n/g, '\n').replace(/^"|"$/g, '').trim();
}
