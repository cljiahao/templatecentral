import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    include: ['test/**/*.{spec,test,e2e-spec}.ts', 'src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      include: ['src/**/*.ts'],
      // Production source only: test files are not measured.
      exclude: ['**/*.{test,spec}.ts', '**/*.d.ts'],
    },
  },
});
