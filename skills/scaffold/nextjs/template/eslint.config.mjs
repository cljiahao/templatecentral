import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import coreWebVitals from 'eslint-config-next/core-web-vitals';
import typescript from 'eslint-config-next/typescript';
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import sonarjs from 'eslint-plugin-sonarjs';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

const config = [
  ...coreWebVitals,
  ...typescript,
  {
    linterOptions: {
      reportUnusedDisableDirectives: 'error',
      reportUnusedInlineConfigs: 'error',
    },
  },
  eslintComments.recommended,
  // innerHTML, outerHTML, insertAdjacentHTML and document.write take sanitized input only: use DOMPurify or a Trusted Types policy.
  noUnsanitized.configs.recommended,
  {
    ...sonarjs.configs.recommended,
    rules: {
      ...sonarjs.configs.recommended.rules,
      // Honour the `_`-prefix convention for intentionally-unused args/vars.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // Comment hygiene gate — see templatecentral:standards code-standards/comments.md.
      'no-inline-comments': [
        'error',
        { ignorePattern: 'eslint-|@ts-|prettier-|c8 |istanbul |webpackChunkName|@__PURE__' },
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
    // shadcn/ui primitives are generated; prefer-read-only-props cannot be fixed without diverging from shadcn add output.
    files: ['src/components/ui/**/*.{ts,tsx}'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: { 'sonarjs/prefer-read-only-props': 'off' },
  },
  {
    // Test fixtures legitimately use fake secrets and http:// literals to exercise guards.
    files: ['test/**/*.{test,spec}.{ts,tsx}', 'src/**/*.test.{ts,tsx}'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: {
      'sonarjs/no-hardcoded-secrets': 'off',
      'sonarjs/no-clear-text-protocols': 'off',
    },
  },
  { ignores: ['.next/**', 'node_modules/**', 'next-env.d.ts', 'coverage/**', '.claude/**'] },
];

export default config;
