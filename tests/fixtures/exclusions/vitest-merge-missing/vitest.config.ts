import { defineConfig, mergeConfig } from 'vitest/config';
import base from './no-such-base';

export default mergeConfig(base, defineConfig({ test: { globals: true } }));
