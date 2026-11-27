import eslintComments from '@eslint-community/eslint-plugin-eslint-comments/configs';
import js from '@eslint/js';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import reactHooks from 'eslint-plugin-react-hooks';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const sonarjsPlugin = sonarjs.configs.recommended.plugins.sonarjs;

// Layer allow-list for docs/architecture.md: one entry per layer, naming every `@/` layer it may import.
const MAX_DEPTH = 5;
const SLASH = String.raw`\x2f`;
const LAYERS = [
  { name: 'pages', unit: 'src/pages', allow: 'pages|components|lib', features: true },
  { name: 'feature', unit: 'src/features/*', allow: 'components|lib', features: true },
  { name: 'components', unit: 'src/components/*', allow: 'components|lib' },
  { name: 'app shell', unit: 'src/components/layout', allow: 'components|lib', features: true },
  { name: 'lib', unit: 'src/lib', allow: 'lib' },
  { name: 'hooks', unit: 'src/hooks', allow: 'hooks|lib' },
  {
    name: 'src root',
    unit: 'src',
    allow: 'app|router|pages|components|lib|styles',
    features: true,
    depth: 0,
  },
];

// One block per file depth, so a relative import may climb only as far as its own layer folder.
// no-restricted-imports skips import(), so the same two regexes also feed a no-restricted-syntax selector (`\x2f` is `/`, which esquery cannot hold).
const layerBlocks = ({ name, unit, allow, features, depth = MAX_DEPTH }) =>
  Array.from({ length: depth + 1 }, (_, d) => {
    const index = features ? '|features/[^/]+$' : '';
    const viaIndex = features ? ' and a feature through its index (@/features/<name>)' : '';
    const named = allow.split('|').join(', @/');
    const rules = [
      {
        regex: `^@/(?!(?:${allow})(?:/|$)${index})`,
        message: `Layer rule (docs/architecture.md): ${name} may import only @/${named}${viaIndex}.`,
      },
      {
        regex: `^(?:\\.\\./){${d + 1}}`,
        message: `Layer rule (docs/architecture.md): a relative import may not leave its ${name} folder; reach another layer through the @/ alias.`,
      },
    ];
    return {
      files: [`${unit}/${'*/'.repeat(d)}${d === MAX_DEPTH ? '**/' : ''}*.{ts,tsx}`],
      rules: {
        'no-restricted-imports': ['error', { patterns: rules }],
        'no-restricted-syntax': [
          'error',
          ...rules.map(({ regex, message }) => ({
            selector: `ImportExpression[source.value=/${regex.replaceAll('/', SLASH)}/]`,
            message,
          })),
        ],
      },
    };
  });

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
  ...LAYERS.flatMap(layerBlocks),
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
    // shadcn/ui primitives are generated; these rules cannot be fixed without diverging from shadcn add output (input-group).
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
