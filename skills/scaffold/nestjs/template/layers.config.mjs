// Layer allow-list for docs/architecture.md: a relative import may climb only as far as its own layer folder, plus the listed `via` targets.
const MAX_DEPTH = 5;
// esquery ends a regex at the first slash, so a selector regex writes each slash as \x2f.
const SLASH = '\\x2f';
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

// One block per file depth, so a relative import may climb only as far as its own layer folder. A no-restricted-syntax selector repeats the regexes because no-restricted-imports skips import().
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

export default LAYERS.flatMap(layerBlocks);
