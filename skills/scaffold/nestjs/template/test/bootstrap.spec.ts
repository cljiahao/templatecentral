import { describe, expect, it, vi } from 'vitest';
import { bootstrap, runBootstrap } from '../src/bootstrap';
import { appConfig } from '../src/config';

describe('bootstrap', () => {
  it('listens on all interfaces and logs the docs URL', async () => {
    const listen = vi.fn().mockResolvedValue(undefined);
    const log = vi.fn();
    await bootstrap(() =>
      Promise.resolve({ app: { listen }, logger: { log }, docsEnabled: true } as never)
    );
    expect(listen).toHaveBeenCalledWith(appConfig.PORT, '0.0.0.0');
    expect(log).toHaveBeenCalledTimes(2);
  });

  it('logs the failure and exits with code 1 when startup rejects', async () => {
    const exit = vi.fn();
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    await runBootstrap(() => Promise.reject(new Error('boom')), exit);
    expect(exit).toHaveBeenCalledWith(1);
  });
});
