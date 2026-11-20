import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    // The request logger would print one line per request into test output.
    env: { LOG_LEVEL: 'silent' },
    include: ['test/**/*.e2e-spec.ts'],
  },
});
