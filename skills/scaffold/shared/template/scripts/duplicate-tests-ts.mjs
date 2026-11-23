// Helper of check-duplicate-tests.sh: prints one record per TS/JS test case.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const [root, listFile] = process.argv.slice(2);
const die = (message) => {
  process.stderr.write(`check-duplicate-tests: ${message}\n`);
  process.exit(2);
};
if (!root || !listFile) die('usage: duplicate-tests-ts.mjs <project-root> <file-list>');

const CASE_BASES = new Set(['it', 'test']);
const CASE_MODIFIERS = new Set(['only', 'skip', 'concurrent', 'todo', 'fails', 'failing', 'sequential', 'skipIf', 'runIf']);
const PARAM_MODIFIERS = new Set(['each', 'for']);
const HOOKS = new Set(['beforeEach', 'beforeAll', 'afterEach', 'afterAll', 'before', 'after']);
const SETUP_OBJECTS = new Set(['vi', 'jest']);

const hash = (text) => createHash('sha1').update(text).digest('hex');
const tsCache = new Map();

const loadTypescript = (dir) => {
  let resolved;
  try {
    resolved = createRequire(path.join(dir, 'resolve.js')).resolve('typescript');
  } catch {
    die(`typescript not found for ${dir}: install the project dependencies (pnpm install) so node_modules/typescript exists`);
  }
  if (!tsCache.has(resolved)) tsCache.set(resolved, createRequire(resolved)(resolved));
  return tsCache.get(resolved);
};

const scriptKind = (ts, file) => {
  const ext = path.extname(file);
  if (ext === '.tsx') return ts.ScriptKind.TSX;
  if (ext === '.jsx') return ts.ScriptKind.JSX;
  if (['.js', '.mjs', '.cjs'].includes(ext)) return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
};

// Leaf nodes of a subtree in source order: the token sequence, with comments and whitespace already gone.
const leaves = (ts, node, sf, out) => {
  const { kind } = node;
  if (kind >= ts.SyntaxKind.FirstJSDocNode && kind <= ts.SyntaxKind.LastJSDocNode) return;
  const kids = node.getChildren(sf);
  if (kids.length > 0) {
    for (const kid of kids) leaves(ts, kid, sf, out);
    return;
  }
  if (kind === ts.SyntaxKind.EndOfFileToken) return;
  if (kind === ts.SyntaxKind.JsxText && node.containsOnlyTriviaWhiteSpaces) return;
  out.push(node);
};

const literalKinds = (ts) =>
  new Set([
    ts.SyntaxKind.StringLiteral,
    ts.SyntaxKind.NoSubstitutionTemplateLiteral,
    ts.SyntaxKind.TemplateHead,
    ts.SyntaxKind.TemplateMiddle,
    ts.SyntaxKind.TemplateTail,
    ts.SyntaxKind.NumericLiteral,
    ts.SyntaxKind.BigIntLiteral,
    ts.SyntaxKind.TrueKeyword,
    ts.SyntaxKind.FalseKeyword,
  ]);

// Returns { base, mods } for `it`, `it.only`, `it.skipIf(x)`, `it.each(t)` and the like, or null.
const describeCallee = (ts, expr) => {
  const mods = [];
  let node = expr;
  for (;;) {
    if (ts.isIdentifier(node)) return { base: node.text, mods };
    if (ts.isPropertyAccessExpression(node)) {
      mods.unshift(node.name.text);
      node = node.expression;
    } else if (ts.isCallExpression(node)) node = node.expression;
    else if (ts.isTaggedTemplateExpression(node)) node = node.tag;
    else return null;
  }
};

const isFunctionLike = (ts, node) => ts.isArrowFunction(node) || ts.isFunctionExpression(node);

const context = (ts, statements, sf) => {
  const parts = [];
  for (const statement of statements) {
    if (!ts.isExpressionStatement(statement)) continue;
    let call = statement.expression;
    if (ts.isAwaitExpression(call)) call = call.expression;
    if (!ts.isCallExpression(call)) continue;
    const info = describeCallee(ts, call.expression);
    if (!info) continue;
    if (!HOOKS.has(info.base) && !SETUP_OBJECTS.has(info.base)) continue;
    const tokens = [];
    leaves(ts, call, sf, tokens);
    parts.push(tokens.map((t) => t.getText(sf)).join(' '));
  }
  return parts.join('\n');
};

const records = [];

const analyse = (file, text, ts) => {
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, scriptKind(ts, file));
  if (sf.parseDiagnostics && sf.parseDiagnostics.length > 0) {
    const d = sf.parseDiagnostics[0];
    const { line } = sf.getLineAndCharacterOfPosition(d.start);
    die(`${path.relative(root, file)}:${line + 1}: does not parse (${ts.flattenDiagnosticMessageText(d.messageText, ' ')})`);
  }
  const literals = literalKinds(ts);
  const stack = [context(ts, sf.statements, sf)];

  const visit = (node) => {
    if (ts.isBlock(node) || ts.isModuleBlock(node)) {
      stack.push(context(ts, node.statements, sf));
      ts.forEachChild(node, visit);
      stack.pop();
      return;
    }
    if (ts.isCallExpression(node)) {
      const info = describeCallee(ts, node.expression);
      const isCase =
        info !== null &&
        CASE_BASES.has(info.base) &&
        info.mods.every((m) => CASE_MODIFIERS.has(m) || PARAM_MODIFIERS.has(m));
      if (isCase && !info.mods.some((m) => PARAM_MODIFIERS.has(m))) {
        const fn = node.arguments.find((a) => isFunctionLike(ts, a));
        if (fn) record(node, fn);
      }
    }
    ts.forEachChild(node, visit);
  };

  const record = (call, fn) => {
    const bodyTokens = [];
    leaves(ts, fn.body, sf, bodyTokens);
    const params = [];
    for (const p of fn.parameters) {
      const t = [];
      leaves(ts, p, sf, t);
      params.push(t.map((x) => x.getText(sf)).join(' '));
    }
    const exact = bodyTokens.map((t) => t.getText(sf));
    const shape = bodyTokens.map((t) => (literals.has(t.kind) ? '\u0001L' : t.getText(sf)));
    const ctx = `${stack.filter(Boolean).join('\n')}\n${params.join(',')}`;
    const line = sf.getLineAndCharacterOfPosition(call.getStart(sf)).line + 1;
    records.push([
      path.relative(root, file),
      line,
      bodyTokens.length,
      hash(`${ctx}\u0000${exact.join('\u0002')}`),
      hash(`${ctx}\u0000${shape.join('\u0002')}`),
    ]);
  };

  visit(sf);
};

const files = readFileSync(listFile, 'utf8').split('\0').filter(Boolean);
for (const rel of files) {
  const file = path.resolve(root, rel);
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    die(`cannot read ${rel}`);
  }
  analyse(file, text, loadTypescript(path.dirname(file)));
}
process.stdout.write(records.map((r) => r.join('\t')).join('\n') + (records.length ? '\n' : ''));
