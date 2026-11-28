import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import coreWebVitals from 'eslint-config-next/core-web-vitals';
import typescript from 'eslint-config-next/typescript';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import sonarjs from 'eslint-plugin-sonarjs';
import layers from './layers.config.mjs';

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
  // The full jsx-a11y recommended set at error level; eslint-config-next registers the plugin and warns on a subset.
  { files: ['**/*.{jsx,tsx}'], rules: { ...jsxA11y.flatConfigs.recommended.rules } },
  ...layers,
  // innerHTML, outerHTML, insertAdjacentHTML and document.write take only DOMPurify or Trusted Types sanitized input.
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
      'no-empty': 'error',
      '@typescript-eslint/no-unused-expressions': 'error',
      'sonarjs/fixme-tag': 'warn',
      '@eslint-community/eslint-comments/require-description': [
        'error',
        { ignore: ['eslint-enable'] },
      ],
      '@eslint-community/eslint-comments/disable-enable-pair': ['error', { allowWholeFile: true }],
    },
  },
  {
    // Standards: PascalCase types and classes, camelCase functions and variables.
    files: ['**/*.{ts,tsx}'],
    rules: {
      '@typescript-eslint/naming-convention': [
        'error',
        { selector: 'typeLike', format: ['PascalCase'] },
        {
          selector: ['variable', 'function'],
          format: ['camelCase', 'PascalCase', 'UPPER_CASE'],
          leadingUnderscore: 'allowSingleOrDouble',
        },
      ],
    },
  },
  {
    // Standards: named exports only, except the route files Next.js reads a default export from.
    files: ['src/**/*.{ts,tsx}'],
    ignores: ['src/app/**/{page,layout,loading,error,global-error,not-found,template,default}.tsx'],
    rules: { 'no-restricted-exports': ['error', { restrictDefaultExports: { direct: true } }] },
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
  // The seeded gate helpers are guarded harness files that nobody may edit, so lint cannot be satisfied.
  {
    ignores: [
      'coverage/**',
      '.claude/**',
      'scripts/{check-comments,check-exclude-reasons,duplicate-tests-ts}.mjs',
    ],
  },
];

export default config;
