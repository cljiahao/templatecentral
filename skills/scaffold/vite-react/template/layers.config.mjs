// Layer allow-list for docs/architecture.md: one entry per layer, naming every `@/` layer it may import.
const MAX_DEPTH = 5;
const SLASH = '\\x2f';
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

// One block per file depth, so a relative import may climb only as far as its own layer folder. A no-restricted-syntax selector repeats the regexes because no-restricted-imports skips import().
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

export default LAYERS.flatMap(layerBlocks);
