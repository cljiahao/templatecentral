import { ApiClient } from '@/lib/clients/api-client';

// Omit<LogEntry, 'timestamp'> would drop the level/label requirement because of the index signature.
type LogFields = { level: string; label: string; [k: string]: unknown };
type LogEntry = LogFields & { timestamp: string };

const queue: LogEntry[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

const BATCH_MS = 5_000;
const MAX_BATCH = 50;

// FetchClient reports failures via console.error, so a failing /logs POST cannot loop.
class LogClient extends ApiClient {
  protected override keepalive = true;

  send(batch: LogEntry[]): Promise<void> {
    return this.request('logs', 'POST', batch);
  }
}

let client: LogClient | undefined;

function flush(): void {
  if (queue.length === 0) return;
  const batch = queue.splice(0, MAX_BATCH);

  if (import.meta.env.DEV) {
    console.info('[log-batcher]', JSON.stringify(batch));
    return;
  }

  try {
    client ??= new LogClient();
    client.send(batch).catch(() => {
      // Logging must never throw.
    });
  } catch {
    // ApiClient throws if VITE_API_BASE_URL is absent; fall back silently.
    console.info('[log-batcher]', JSON.stringify(batch));
  }
  // Remainder beyond MAX_BATCH flushes on the next enqueue or visibilitychange.
}

export function enqueueLog(entry: LogFields): void {
  queue.push({ ...entry, timestamp: new Date().toISOString() });
  if (flushTimer === null) {
    flushTimer = setTimeout(() => {
      flushTimer = null;
      flush();
    }, BATCH_MS);
  }
  if (queue.length >= MAX_BATCH) {
    if (flushTimer !== null) clearTimeout(flushTimer);
    flushTimer = null;
    flush();
  }
}

function flushAll(): void {
  while (queue.length > 0) flush();
}

// pagehide fires on bfcache navigation where visibilitychange may not; register both.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') flushAll();
});
window.addEventListener('pagehide', () => {
  flushAll();
});
