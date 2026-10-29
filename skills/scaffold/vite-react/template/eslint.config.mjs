import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

export default tseslint.config(
  { ignores: ['dist', '.claude/**'] },
  {
    linterOptions: {
      reportUnusedDisableDirectives: 'error',
      reportUnusedInlineConfigs: 'error',
    },
  },
  eslintComments.recommended,
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      'react-hooks': reactHooks,
      ...sonarjs.configs.recommended.plugins,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      ...sonarjs.configs.recommended.rules,
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
    // shadcn/ui primitives are generated, not hand-edited — prefer-read-only-props
    // fires on their prop typing and can't be fixed without diverging from `shadcn add` output.
    files: ['src/components/ui/**/*.tsx'],
    plugins: { sonarjs: sonarjsPlugin },
    rules: { 'sonarjs/prefer-read-only-props': 'off' },
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
