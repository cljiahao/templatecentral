import { afterEach, describe, expect, it, vi } from 'vitest';

import { registerGlobalErrorHandlers } from './global-handlers';

describe('registerGlobalErrorHandlers', () => {
  afterEach(() => vi.restoreAllMocks());

  it('logs uncaught errors from the window error event', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    registerGlobalErrorHandlers();

    const event = new Event('error');
    Object.assign(event, { error: new Error('kaboom') });
    window.dispatchEvent(event);

    expect(spy).toHaveBeenCalled();
  });

  it('logs unhandled promise rejections', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    registerGlobalErrorHandlers();

    // jsdom doesn't emit unhandledrejection on its own — dispatch a shaped event manually.
    const event = new Event('unhandledrejection');
    Object.assign(event, { reason: new Error('nope') });
    window.dispatchEvent(event);

    expect(spy).toHaveBeenCalled();
  });
});
