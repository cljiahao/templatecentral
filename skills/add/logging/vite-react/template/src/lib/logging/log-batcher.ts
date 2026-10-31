// src/lib/logging/log-batcher.ts
import { ApiClient } from '@/lib/clients/api-client';

// Omit<LogEntry, 'timestamp'> would NOT work here: a `[k: string]: unknown` index signature
// collapses `keyof LogEntry` to `string`, so Omit silently drops the requirement that
// level/label be present. Split the index-signature part out instead.
type LogFields = { level: string; label: string; [k: string]: unknown };
type LogEntry = LogFields & { timestamp: string };

const queue: LogEntry[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

const BATCH_MS = 5_000;
const MAX_BATCH = 50;

// FetchClient reports failures with console.error, never logError — so a failing /logs
// POST cannot re-enqueue itself into a loop.
class LogClient extends ApiClient {
  // keepalive lets the request complete even if the tab closes
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
    // Console-JSON fallback in dev — no network call
    console.info('[log-batcher]', JSON.stringify(batch));
    return;
  }

  try {
    client ??= new LogClient();
    client.send(batch).catch(() => {
      // Silently discard — logging must never throw
    });
  } catch {
    // ApiClient's constructor throws if VITE_API_BASE_URL is absent; fall back silently
    console.info('[log-batcher]', JSON.stringify(batch));
  }
  // Trade-off: if queue.length > MAX_BATCH after splice, remainder entries flush on
  // the next enqueueLog call (size gate) or next visibilitychange — never silently dropped.
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

// On unload, drain the entire queue (flush() only sends one MAX_BATCH slice)
function flushAll(): void {
  while (queue.length > 0) flush();
}

// Flush on page unload so buffered logs are not lost.
// pagehide fires on bfcache/navigation where visibilitychange may not — register both.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') flushAll();
});
window.addEventListener('pagehide', () => {
  flushAll();
});
