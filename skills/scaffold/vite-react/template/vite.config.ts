/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const __dirname = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    open: true,
    // templatecentral:standards full-stack-pairing adds the same-origin /api server.proxy that cookie auth needs.
  },
  preview: {
    port: 3000,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    // CI has no .env and getApiBaseUrl() throws without one, so pin it for tests.
    env: { VITE_API_BASE_URL: 'http://api.test' },
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    css: true,
    // Threads start faster than forks and keep the same test IDs, coverage and isolation.
    pool: 'threads',
    // CI runners are small: half the cores per process keeps memory flat; sharding adds the parallelism.
    maxWorkers: process.env.CI ? '50%' : undefined,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura', 'lcov'],
      include: ['src/**/*.{ts,tsx}'],
      // Production source only: test files and the test setup file are not measured.
      exclude: ['**/*.{test,spec}.{ts,tsx}', 'src/test/**', '**/*.d.ts'],
    },
  },
});
