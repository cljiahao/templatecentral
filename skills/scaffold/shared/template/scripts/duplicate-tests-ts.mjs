// Helper of check-duplicate-tests.sh: prints one record per TS/JS test case.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const [rootArg, listFile] = process.argv.slice(2);
const die = (message) => {
  process.stderr.write(`check-duplicate-tests: ${message}\n`);
  process.exit(2);
};
if (!rootArg || !listFile) die('usage: duplicate-tests-ts.mjs <project-root> <file-list>');
const root = path.resolve(rootArg);

const SUPPORTED_MAJORS = [5, 6];
const CASE_BASES = new Set(['it', 'test']);
const NAME_BASES = new Set(['it', 'test', 'describe', 'suite']);
const CASE_MODIFIERS = new Set(['only', 'skip', 'concurrent', 'todo', 'fails', 'failing', 'sequential', 'skipIf', 'runIf']);
const PARAM_MODIFIERS = new Set(['each', 'for']);
const DEFAULT_IMPORT_MODULES = new Set(['node:test', 'bun:test']);

const hash = (text) => createHash('sha1').update(text).digest('hex');
const tsCache = new Map();

// The compiler comes from node_modules of the project only: the nearest one between the file and the project root.
const loadTypescript = (dir) => {
  let current = dir;
  for (;;) {
    const pkg = path.join(current, 'node_modules', 'typescript', 'package.json');
    if (existsSync(pkg)) {
      if (!tsCache.has(pkg)) {
        const ts = createRequire(path.join(current, 'resolve.js'))('typescript');
        let version = 'unknown';
        try {
          version = String(JSON.parse(readFileSync(pkg, 'utf8')).version || 'unknown');
        } catch {
          version = ts && ts.version ? String(ts.version) : 'unknown';
        }
        const major = Number.parseInt(version, 10);
        const hasApi =
          ts &&
          typeof ts.createSourceFile === 'function' &&
          typeof ts.forEachChild === 'function' &&
          ts.ScriptTarget &&
          ts.ScriptKind &&
          ts.SyntaxKind &&
          ts.SyntaxKind.FirstJSDocNode !== undefined;
        if (!hasApi || !SUPPORTED_MAJORS.includes(major)) {
          die(
            `typescript ${version} at ${path.dirname(pkg)} is not supported: the check needs the compiler API of typescript ` +
              `${SUPPORTED_MAJORS[0]}.x to ${SUPPORTED_MAJORS[SUPPORTED_MAJORS.length - 1]}.x; install a version in that range`,
          );
        }
        tsCache.set(pkg, ts);
      }
      return tsCache.get(pkg);
    }
    if (current === root || path.dirname(current) === current) break;
    current = path.dirname(current);
  }
  return die(`typescript not found under ${root}: install the project dependencies (pnpm install) so node_modules/typescript exists`);
};

const scriptKind = (ts, file) => {
  const ext = path.extname(file);
  if (ext === '.tsx') return ts.ScriptKind.TSX;
  if (ext === '.jsx') return ts.ScriptKind.JSX;
  if (['.js', '.mjs', '.cjs'].includes(ext)) return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
};

const analyse = (file, text, ts) => {
  const rel = path.relative(root, file);
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, scriptKind(ts, file));
  if (sf.parseDiagnostics && sf.parseDiagnostics.length > 0) {
    const d = sf.parseDiagnostics[0];
    const { line } = sf.getLineAndCharacterOfPosition(d.start);
    die(`${rel}:${line + 1}: does not parse under typescript ${ts.version} (${ts.flattenDiagnosticMessageText(d.messageText, ' ')})`);
  }
  const K = ts.SyntaxKind;
  const literalKinds = new Set([
    K.StringLiteral, K.NoSubstitutionTemplateLiteral, K.TemplateHead, K.TemplateMiddle, K.TemplateTail,
    K.NumericLiteral, K.BigIntLiteral, K.TrueKeyword, K.FalseKeyword,
  ]);
  const isFunctionLike = (n) => ts.isArrowFunction(n) || ts.isFunctionExpression(n);

  // Names the test globals are imported under: `import { it as t }`, `import * as v`, `import test from 'node:test'`.
  const aliases = new Map();
  const namespaces = new Set();
  for (const statement of sf.statements) {
    if (!ts.isImportDeclaration(statement) || !statement.importClause) continue;
    const clause = statement.importClause;
    const moduleName = ts.isStringLiteral(statement.moduleSpecifier) ? statement.moduleSpecifier.text : '';
    if (clause.name && DEFAULT_IMPORT_MODULES.has(moduleName)) aliases.set(clause.name.text, 'test');
    const bindings = clause.namedBindings;
    if (bindings && ts.isNamespaceImport(bindings)) namespaces.add(bindings.name.text);
    if (bindings && ts.isNamedImports(bindings)) {
      for (const el of bindings.elements) {
        const original = (el.propertyName || el.name).text;
        if (NAME_BASES.has(original) || ['beforeEach', 'afterEach', 'beforeAll', 'afterAll'].includes(original)) {
          aliases.set(el.name.text, original);
        }
      }
    }
  }

  // Same-file functions a case can name: `function handler() {}` and `const handler = () => {}`.
  const functions = new Map();
  const collectFunctions = (node) => {
    if (ts.isFunctionDeclaration(node) && node.name && node.body && !functions.has(node.name.text)) functions.set(node.name.text, node);
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer && isFunctionLike(node.initializer)) {
      if (!functions.has(node.name.text)) functions.set(node.name.text, node.initializer);
    }
    ts.forEachChild(node, collectFunctions);
  };
  collectFunctions(sf);

  // { base, mods } for `it`, `it.only`, `it.skipIf(x)`, `it.each(t)`, `v.it`, an aliased name, or null.
  const describeCallee = (expr) => {
    const mods = [];
    let node = expr;
    for (;;) {
      if (ts.isIdentifier(node)) {
        let base = aliases.get(node.text) || node.text;
        if (namespaces.has(node.text) && mods.length > 0) base = mods.shift();
        return { base, mods };
      }
      if (ts.isPropertyAccessExpression(node)) {
        mods.unshift(node.name.text);
        node = node.expression;
      } else if (ts.isCallExpression(node)) node = node.expression;
      else if (ts.isTaggedTemplateExpression(node)) node = node.tag;
      else return null;
    }
  };

  const classify = (call) => {
    if (ts.isCallExpression(call.parent) && call.parent.expression === call) return null;
    const info = describeCallee(call.expression);
    if (!info || !CASE_BASES.has(info.base)) return null;
    if (!info.mods.every((m) => CASE_MODIFIERS.has(m) || PARAM_MODIFIERS.has(m))) return null;
    if (info.mods.some((m) => PARAM_MODIFIERS.has(m))) return { kind: 'P' };
    const direct = call.arguments.find((a) => isFunctionLike(a));
    if (direct) return { kind: 'C', fn: direct };
    const named = call.arguments.slice(1).find((a) => ts.isIdentifier(a));
    if (named && functions.has(named.text)) return { kind: 'C', fn: functions.get(named.text) };
    if (call.arguments.length >= 2) return { kind: 'U' };
    return { kind: 'T' };
  };

  const cases = [];
  const hasCase = new Set();
  const find = (node) => {
    if (ts.isCallExpression(node)) {
      const found = classify(node);
      if (found) {
        cases.push({ call: node, ...found });
        for (let p = node; p; p = p.parent) hasCase.add(p);
      }
    }
    ts.forEachChild(node, find);
  };
  find(sf);

  const tokenText = (node) => {
    if (node.kind === K.StringLiteral && /^\.\.?\//.test(node.text)) {
      return `"${path.relative(root, path.resolve(path.dirname(file), node.text))}"`;
    }
    return node.getText(sf);
  };

  // Leaf nodes in source order: the token sequence, comments and whitespace already gone.
  const leaves = (node, out) => {
    const { kind } = node;
    if (kind >= K.FirstJSDocNode && kind <= K.LastJSDocNode) return;
    const kids = node.getChildren(sf);
    if (kids.length > 0) {
      for (const kid of kids) leaves(kid, out);
      return;
    }
    if (kind === K.EndOfFileToken) return;
    if (kind === K.JsxText && node.containsOnlyTriviaWhiteSpaces) return;
    out.push(node);
  };

  const flatChildren = (node) => {
    const out = [];
    for (const kid of node.getChildren(sf)) {
      if (kid.kind === K.SyntaxList) out.push(...flatChildren(kid));
      else out.push(kid);
    }
    return out;
  };

  // Context of a node: its non-case parts, without titles, bare punctuation or the plain describe/it callee.
  const punctuation = new Set([K.OpenParenToken, K.CloseParenToken, K.OpenBraceToken, K.CloseBraceToken, K.CommaToken, K.SemicolonToken, K.EqualsGreaterThanToken]);
  const hasCall = (node) => {
    let found = false;
    const visit = (n) => {
      if (ts.isCallExpression(n)) found = true;
      if (!found) ts.forEachChild(n, visit);
    };
    visit(node);
    return found;
  };
  const contextMemo = new Map();
  const contextOf = (node) => {
    if (contextMemo.has(node)) return contextMemo.get(node);
    const info = ts.isCallExpression(node) ? describeCallee(node.expression) : null;
    const suiteCall = Boolean(info && NAME_BASES.has(info.base));
    const parts = [];
    for (const kid of flatChildren(node)) {
      if (hasCase.has(kid) || punctuation.has(kid.kind)) continue;
      if (suiteCall && kid === node.expression && !hasCall(kid)) continue;
      if (suiteCall && (ts.isStringLiteral(kid) || ts.isNoSubstitutionTemplateLiteral(kid) || ts.isTemplateExpression(kid))) continue;
      const tokens = [];
      leaves(kid, tokens);
      parts.push(tokens.map(tokenText).join(' '));
    }
    const value = parts.join('\n');
    contextMemo.set(node, value);
    return value;
  };

  const records = [];
  const line = (call) => sf.getLineAndCharacterOfPosition(call.getStart(sf)).line + 1;
  for (const c of cases) {
    if (c.kind !== 'C') {
      records.push([c.kind, rel, line(c.call), 0, '-', '-']);
      continue;
    }
    const chain = [];
    for (let p = c.call.parent; p; p = p.parent) chain.unshift(p);
    const ctx = chain.map(contextOf).filter(Boolean).join('\n\u0003\n');
    const params = c.fn.parameters.map((p) => {
      const t = [];
      leaves(p, t);
      return t.map(tokenText).join(' ');
    });
    const bodyTokens = [];
    if (c.fn.body) leaves(c.fn.body, bodyTokens);
    const exact = bodyTokens.map(tokenText);
    const shape = bodyTokens.map((t) => (literalKinds.has(t.kind) ? '\u0001L' : tokenText(t)));
    const key = `${ctx}\n\u0004${params.join(',')}`;
    records.push([
      'C',
      rel,
      line(c.call),
      bodyTokens.length,
      hash(`${key}\u0000${exact.join('\u0002')}`),
      hash(`${key}\u0000${shape.join('\u0002')}`),
    ]);
  }
  return records;
};

const files = readFileSync(listFile, 'utf8').split('\0').filter(Boolean);
const out = [];
for (const rel of files) {
  const file = path.resolve(root, rel);
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    die(`cannot read ${rel}`);
  }
  out.push(...analyse(file, text, loadTypescript(path.dirname(file))));
}
process.stdout.write(out.map((r) => r.join('\t')).join('\n') + (out.length ? '\n' : ''));
