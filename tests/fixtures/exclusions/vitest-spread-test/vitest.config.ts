import { defineConfig } from 'vitest/config';
const shared = { coverage: { exclude: ['src/gen/**'] } };
export default defineConfig({ test: { ...shared } });
