// @ts-check
import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import eslint from '@eslint/js';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

export default tseslint.config(
  {
    ignores: ['eslint.config.mjs', 'vitest.config.ts', 'vitest.config.e2e.ts', '.claude/**'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  eslintPluginPrettierRecommended,
  {
    linterOptions: {
      reportUnusedDisableDirectives: 'error',
      reportUnusedInlineConfigs: 'error',
    },
  },
  eslintComments.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },
      // Source is ES-module syntax; 'commonjs' + projectService on ESLint 10 flags lib-global imports like Body as unused.
      sourceType: 'module',
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    ...sonarjs.configs.recommended,
    rules: {
      ...sonarjs.configs.recommended.rules,
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unsafe-argument': 'warn',
      '@typescript-eslint/no-unsafe-call': 'off',
      // Honour the `_`-prefix convention for intentionally-unused args/vars.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // Comment hygiene gate — see templatecentral:standards code-standards/comments.md.
      'no-inline-comments': [
        'error',
        { ignorePattern: 'eslint-|@ts-|prettier-|c8 |istanbul ' },
      ],
      'sonarjs/no-commented-code': 'error',
      // SonarQube's default quality gate: cognitive complexity 15 per function.
      'sonarjs/cognitive-complexity': ['error', 15],
      // Sonar's inline suppression marker hides findings from the server's quality gate; fix the finding instead.
      'no-warning-comments': ['error', { terms: ['nosonar'], location: 'anywhere' }],
      // Task tags with context are allowed; keep them visible without failing lint.
      'sonarjs/todo-tag': 'warn',
      'sonarjs/fixme-tag': 'warn',
      '@eslint-community/eslint-comments/require-description': [
        'error',
        { ignore: ['eslint-enable'] },
      ],
      '@eslint-community/eslint-comments/disable-enable-pair': [
        'error',
        { allowWholeFile: true },
      ],
    },
  },
  {
    // Test fixtures legitimately use fake secrets and http:// literals to exercise guards.
    files: ['test/**/*.{spec,test}.ts', 'src/**/*.spec.ts', 'test/**/*.e2e-spec.ts'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: {
      'sonarjs/no-hardcoded-secrets': 'off',
      'sonarjs/no-clear-text-protocols': 'off',
    },
  },
);
