// @ts-check
import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import eslint from '@eslint/js';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

// Layer allow-list for docs/architecture.md: a relative import may climb only as far as its own layer folder, plus the listed `via` targets.
const MAX_DEPTH = 5;
const SLASH = String.raw`\x2f`;
const LAYERS = [
  {
    name: 'module',
    unit: 'src/modules/*',
    via: String.raw`(?:[^/]+/[^/]+\.(?:service|module)$|\.\./(?:common|config)(?:/|$))`,
    allowed:
      'import only common, config, or a sibling module through its *.service or *.module file',
  },
  { name: 'common', unit: 'src/common', allowed: 'import nothing outside src/common' },
  { name: 'config', unit: 'src/config', allowed: 'import nothing outside src/config' },
  { name: 'src root', unit: 'src', depth: 0, allowed: 'import nothing above src' },
];

// One block per file depth, so a relative import may climb only as far as its own layer folder.
// no-restricted-imports skips import(), so the same regex also feeds a no-restricted-syntax selector (`\x2f` is `/`, which esquery cannot hold).
const layerBlocks = ({ name, unit, via = '(?!)', allowed, depth = MAX_DEPTH }) =>
  Array.from({ length: depth + 1 }, (_, d) => {
    const regex = `^(?:\\.\\./){${d + 1}}(?!${via})`;
    const message = `Layer rule (docs/architecture.md): a ${name} may ${allowed}.`;
    return {
      files: [`${unit}/${'*/'.repeat(d)}${d === MAX_DEPTH ? '**/' : ''}*.ts`],
      rules: {
        'no-restricted-imports': ['error', { patterns: [{ regex, message }] }],
        'no-restricted-syntax': [
          'error',
          { selector: `ImportExpression[source.value=/${regex.replaceAll('/', SLASH)}/]`, message },
        ],
      },
    };
  });

export default tseslint.config(
  {
    ignores: [
      'eslint.config.mjs',
      'vitest.config.mts',
      'vitest.config.e2e.mts',
      'coverage/**',
      '.claude/**',
    ],
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
  ...LAYERS.flatMap(layerBlocks),
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
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unsafe-argument': 'warn',
      '@typescript-eslint/no-unsafe-call': 'off',
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
    // Standards: PascalCase types and classes, camelCase functions and methods.
    files: ['**/*.ts'],
    rules: {
      '@typescript-eslint/naming-convention': [
        'error',
        { selector: 'typeLike', format: ['PascalCase'] },
        { selector: ['function', 'method'], format: ['camelCase'], leadingUnderscore: 'allow' },
        {
          selector: 'variable',
          format: ['camelCase', 'PascalCase', 'UPPER_CASE'],
          leadingUnderscore: 'allowSingleOrDouble',
        },
      ],
    },
  },
  {
    // Standards: PascalCase types and classes, camelCase functions and methods.
    files: ['**/*.ts'],
    rules: {
      '@typescript-eslint/naming-convention': [
        'error',
        { selector: 'typeLike', format: ['PascalCase'] },
        { selector: ['function', 'method'], format: ['camelCase'], leadingUnderscore: 'allow' },
        {
          selector: 'variable',
          format: ['camelCase', 'PascalCase', 'UPPER_CASE'],
          leadingUnderscore: 'allowSingleOrDouble',
        },
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
  }
);
