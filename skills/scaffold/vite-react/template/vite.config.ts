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
    // Same-origin `/api` proxy to the backend (`server.proxy`, required by cookie auth) is added
    // by templatecentral:standards (full-stack-pairing).
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
    // CI has no .env (gitignored), and getApiBaseUrl() throws without it — pin one for tests.
    env: { VITE_API_BASE_URL: 'http://api.test' },
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    css: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura'],
    },
  },
});
