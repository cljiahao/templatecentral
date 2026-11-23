import { defineConfig, mergeConfig } from 'vitest/config';
import { a } from './a';

export default mergeConfig(a, defineConfig({ test: { globals: true } }));
