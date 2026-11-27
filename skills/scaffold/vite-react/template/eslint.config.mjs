import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import js from '@eslint/js';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import reactHooks from 'eslint-plugin-react-hooks';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import layers from './layers.config.mjs';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

export default tseslint.config(
  // The seeded gate helpers are guarded harness files that nobody may edit, so lint cannot be satisfied.
  {
    ignores: [
      'dist',
      'coverage/**',
      '.claude/**',
      'scripts/{check-comments,check-exclude-reasons,duplicate-tests-ts}.mjs',
    ],
  },
  {
    linterOptions: {
      reportUnusedDisableDirectives: 'error',
      reportUnusedInlineConfigs: 'error',
    },
  },
  eslintComments.recommended,
  ...layers,
  // innerHTML, outerHTML, insertAdjacentHTML and document.write take only DOMPurify or Trusted Types sanitized input.
  noUnsanitized.configs.recommended,
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      'react-hooks': reactHooks,
      'jsx-a11y': jsxA11y,
      ...sonarjs.configs.recommended.plugins,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // The full jsx-a11y recommended set, at error level.
      ...jsxA11y.flatConfigs.recommended.rules,
      ...sonarjs.configs.recommended.rules,
      // Honour the `_`-prefix convention for intentionally-unused args/vars.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
      // Comment hygiene gate — see templatecentral:standards code-standards/comments.md.
      'no-inline-comments': ['error', { ignorePattern: 'eslint-|@ts-|prettier-|c8 |istanbul ' }],
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
    // Standards: named exports only in application code.
    files: ['src/**/*.{ts,tsx}'],
    rules: { 'no-restricted-exports': ['error', { restrictDefaultExports: { direct: true } }] },
  },
  {
    // shadcn/ui primitives are generated and cannot follow these rules without diverging from shadcn add output.
    files: ['src/components/ui/**/*.tsx'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: {
      'sonarjs/prefer-read-only-props': 'off',
      'jsx-a11y/click-events-have-key-events': 'off',
      'jsx-a11y/no-noninteractive-element-interactions': 'off',
    },
  },
  {
    // Test fixtures legitimately use fake secrets and http:// literals to exercise guards.
    files: ['src/**/*.{test,spec}.{ts,tsx}'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: {
      'sonarjs/no-hardcoded-secrets': 'off',
      'sonarjs/no-clear-text-protocols': 'off',
    },
  }
);
