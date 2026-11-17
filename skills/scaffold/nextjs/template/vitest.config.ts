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
    passWithNoTests: true,
    pool: 'forks',
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    include: ['test/**/*.{test,spec}.{ts,tsx}', 'src/**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      include: ['src/**/*.ts', 'src/**/*.tsx'],
      exclude: ['**/*.test.{ts,tsx}', '**/*.d.ts', 'src/components/ui/**'],
    },
  },
});
