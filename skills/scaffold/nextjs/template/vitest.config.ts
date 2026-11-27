import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(rootDir, 'src'),
    },
  },
  test: {
    globals: false,
    environment: 'node',
    // Threads start faster than forks and keep the same test IDs, coverage and isolation.
    pool: 'threads',
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    include: ['test/**/*.{test,spec}.{ts,tsx}', 'src/**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      // reason: coverage counts production source files only, never config or tooling files
      include: ['src/**/*.ts', 'src/**/*.tsx'],
      exclude: [
        '**/*.{test,spec}.{ts,tsx}',
        '**/*.d.ts',
        // reason: vendor-generated shadcn primitives are not hand written, so hand-written code stays at the floor
        'src/components/ui/**',
      ],
      // Global floor on every run. The ratchet gate blocks lowering it or widening exclude.
      thresholds: { lines: 80 },
    },
  },
});
