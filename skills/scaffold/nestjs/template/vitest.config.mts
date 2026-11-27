import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    // The request logger would print one line per request into test output.
    env: { LOG_LEVEL: 'silent' },
    // Threads start faster than forks and keep the same test IDs, coverage and isolation.
    pool: 'threads',
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    include: ['test/**/*.{spec,test,e2e-spec}.ts', 'src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      // reason: coverage counts production source files only, never config or tooling files
      include: ['src/**/*.ts'],
      // Production source only: test files are not measured.
      exclude: ['**/*.{test,spec}.ts', '**/*.d.ts'],
      // Global floor on every run. The ratchet gate blocks lowering it or widening exclude.
      thresholds: { lines: 80 },
    },
  },
});
