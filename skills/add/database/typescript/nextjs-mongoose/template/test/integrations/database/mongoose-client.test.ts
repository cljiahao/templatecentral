import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// A fake connection: no models, so the index wait after connecting has nothing to init.
const connection = vi.hoisted(() => ({ modelNames: () => [] as string[] }));
const connect = vi.hoisted(() => vi.fn());

vi.mock('mongoose', () => ({ default: { connect } }));

// The client keeps its cache on globalThis and reads MONGODB_URL at import, so each test starts clean.
async function loadConnectDB() {
  vi.resetModules();
  const mod = await import('@/integrations/database/mongoose-client');
  return mod.connectDB;
}

describe('connectDB retry', () => {
  beforeEach(() => {
    vi.stubEnv('MONGODB_URL', 'mongodb://localhost:27017/test');
    delete (globalThis as { mongoose?: unknown }).mongoose;
    connect.mockReset();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('retries on the next call after a failed connect', async () => {
    connect.mockRejectedValueOnce(new Error('connect failed')).mockResolvedValueOnce(connection);
    const connectDB = await loadConnectDB();

    await expect(connectDB()).rejects.toThrow('connect failed');
    await expect(connectDB()).resolves.toBe(connection);
    expect(connect).toHaveBeenCalledTimes(2);
  });

  it('reuses the cached connection once connected', async () => {
    connect.mockResolvedValue(connection);
    const connectDB = await loadConnectDB();

    await connectDB();
    await connectDB();
    expect(connect).toHaveBeenCalledTimes(1);
  });
});
