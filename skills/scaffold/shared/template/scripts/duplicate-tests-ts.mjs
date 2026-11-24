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
const NAME_BASES = new Set(['it', 'test', 'describe', 'suite', 'context']);
const HOOKS = ['beforeEach', 'afterEach', 'beforeAll', 'afterAll'];
// Prefixed forms: the base name plus the modifier they stand for.
const PREFIXED = new Map([
  ['xit', ['it', 'skip']],
  ['xtest', ['test', 'skip']],
  ['xdescribe', ['describe', 'skip']],
  ['fit', ['it', 'only']],
  ['fdescribe', ['describe', 'only']],
]);
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
        if (NAME_BASES.has(original) || PREFIXED.has(original) || HOOKS.includes(original)) {
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
  // Drops `as const`, `satisfies T`, parentheses and type assertions around an expression.
  const unwrap = (node) => {
    let n = node;
    while (n && (ts.isAsExpression(n) || ts.isParenthesizedExpression(n) || ts.isTypeAssertionExpression(n) || (ts.isSatisfiesExpression && ts.isSatisfiesExpression(n)) || ts.isNonNullExpression(n))) n = n.expression;
    return n;
  };

  // { base, mods } for `it`, `it.only`, `it.skipIf(x)`, `it.each(t)`, `v.it`, an aliased name, or null.
  const describeCallee = (expr) => {
    const mods = [];
    let node = expr;
    for (;;) {
      if (ts.isIdentifier(node)) {
        let base = aliases.get(node.text) || node.text;
        if (namespaces.has(node.text) && mods.length > 0) base = mods.shift();
        if (PREFIXED.has(base)) {
          mods.unshift(PREFIXED.get(base)[1]);
          base = PREFIXED.get(base)[0];
        }
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
    let table = null;
    if (info.mods.some((m) => PARAM_MODIFIERS.has(m))) {
      for (let e = call.expression; ; ) {
        if (ts.isCallExpression(e)) {
          table = e.arguments;
          break;
        }
        if (ts.isTaggedTemplateExpression(e)) {
          table = [e.template];
          break;
        }
        if (ts.isPropertyAccessExpression(e)) e = e.expression;
        else break;
      }
      if (!table) return { kind: 'U' };
    }
    const direct = call.arguments.find((a) => isFunctionLike(a));
    if (direct) return { kind: 'C', fn: direct, table };
    const named = call.arguments.slice(1).find((a) => ts.isIdentifier(a));
    if (named && functions.has(named.text)) return { kind: 'C', fn: functions.get(named.text), table };
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
      parts.push(textOf(kid));
    }
    const value = parts.join('\n');
    contextMemo.set(node, value);
    return value;
  };

  const textOf = (node) => {
    const tokens = [];
    leaves(node, tokens);
    return tokens.map(tokenText).join(' ');
  };
  const identifiersOf = (node, into) => {
    if (ts.isIdentifier(node)) into.add(node.text);
    ts.forEachChild(node, (kid) => {
      identifiersOf(kid, into);
    });
    return into;
  };
  const boundIn = (name) => identifiersOf(name, new Set());
  const boundNames = (st) => {
    const names = new Set();
    if (ts.isImportDeclaration(st)) {
      const clause = st.importClause;
      if (clause && clause.name) names.add(clause.name.text);
      const nb = clause && clause.namedBindings;
      if (nb && ts.isNamespaceImport(nb)) names.add(nb.name.text);
      if (nb && ts.isNamedImports(nb)) for (const el of nb.elements) names.add(el.name.text);
    } else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) identifiersOf(d.name, names);
    } else if (
      (ts.isFunctionDeclaration(st) || ts.isClassDeclaration(st) || ts.isEnumDeclaration(st) || ts.isInterfaceDeclaration(st) || ts.isTypeAliasDeclaration(st) || ts.isModuleDeclaration(st)) &&
      st.name
    ) {
      names.add(st.name.text);
    }
    return names;
  };
  const sideEffect = (node) => {
    let found = false;
    const visit = (n) => {
      if (found || isFunctionLike(n) || ts.isClassLike(n)) return;
      if (ts.isCallExpression(n) || ts.isNewExpression(n) || ts.isAwaitExpression(n)) found = true;
      else ts.forEachChild(n, visit);
    };
    visit(node);
    return found;
  };
  const caseIds = new Map();
  const idsOfCase = (c) => {
    if (!caseIds.has(c)) {
      const ids = new Set();
      for (const part of [...c.fn.parameters, c.fn.body]) if (part) identifiersOf(part, ids);
      if (c.table) for (const arg of c.table) identifiersOf(arg, ids);
      caseIds.set(c, ids);
    }
    return caseIds.get(c);
  };
  const holderRefs = new Map();
  const referencedBelow = (holder) => {
    if (!holderRefs.has(holder)) {
      const ids = new Set();
      for (const c of cases) {
        if (c.kind === 'C' && c.call.pos >= holder.pos && c.call.end <= holder.end) for (const id of idsOfCase(c)) ids.add(id);
      }
      holderRefs.set(holder, ids);
    }
    return holderRefs.get(holder);
  };
  // Statements of a file or block that are not cases, with the names they bind and the names they use.
  const scopeMemo = new Map();
  const scopeItems = (node) => {
    if (scopeMemo.has(node)) return scopeMemo.get(node);
    const items = [];
    for (const st of flatChildren(node)) {
      if (hasCase.has(st) || punctuation.has(st.kind) || st.kind === K.EndOfFileToken) continue;
      const names = boundNames(st);
      const idents = identifiersOf(st, new Set());
      let always = false;
      if (ts.isImportDeclaration(st)) always = false;
      else if (names.size > 0) {
        const used = referencedBelow(node);
        always = ts.isVariableStatement(st) && sideEffect(st) && ![...names].some((n) => used.has(n));
      } else always = true;
      items.push({ st, names, idents, always, text: null });
    }
    scopeMemo.set(node, items);
    return items;
  };
  const isHolder = (node) => ts.isSourceFile(node) || ts.isBlock(node) || ts.isModuleBlock(node);

  // A table resolves only when every reference in its scope is a plain read: the declaration, each(T) or for(T), T.length.
  const wrapperKinds = (n) => ts.isParenthesizedExpression(n) || ts.isAsExpression(n) || ts.isSatisfiesExpression(n) || ts.isNonNullExpression(n) || ts.isTypeAssertionExpression(n);
  const bindsLexically = (st, name) => boundNames(st).has(name) && !(ts.isVariableStatement(st) && !(st.declarationList.flags & ts.NodeFlags.BlockScoped));
  const rebindsName = (n, name) => {
    if (isFunctionLike(n) || ts.isFunctionDeclaration(n) || ts.isMethodDeclaration(n) || ts.isConstructorDeclaration(n)) return n.parameters.some((param) => boundIn(param.name).has(name));
    if (ts.isBlock(n) || ts.isModuleBlock(n)) return n.statements.some((st) => bindsLexically(st, name));
    if (ts.isForStatement(n) || ts.isForInStatement(n) || ts.isForOfStatement(n)) {
      return !!n.initializer && ts.isVariableDeclarationList(n.initializer) && !!(n.initializer.flags & ts.NodeFlags.BlockScoped) && n.initializer.declarations.some((d) => boundIn(d.name).has(name));
    }
    if (ts.isCatchClause(n)) return !!n.variableDeclaration && boundIn(n.variableDeclaration.name).has(name);
    return false;
  };
  const onlyPlainReads = (name, decl, root) => {
    let ok = true;
    const walk = (n) => {
      if (!ok) return;
      if (n !== root && rebindsName(n, name)) return;
      if (ts.isIdentifier(n) && n.text === name && n !== decl.name) {
        const par = n.parent;
        if ((ts.isPropertyAccessExpression(par) && par.name === n) || (ts.isPropertyAssignment(par) && par.name === n)) {
          // a property name, not a reference
        } else {
          let top = n;
          while (top.parent && wrapperKinds(top.parent) && top.parent.expression === top) top = top.parent;
          const up = top.parent;
          const isEachArg = up && ts.isCallExpression(up) && up.arguments.includes(top) && ts.isPropertyAccessExpression(up.expression) && (up.expression.name.text === 'each' || up.expression.name.text === 'for');
          const isLength = up && ts.isPropertyAccessExpression(up) && up.expression === top && up.name.text === 'length' && !(up.parent && ts.isBinaryExpression(up.parent) && up.parent.left === up && up.parent.operatorToken.kind >= K.FirstAssignment && up.parent.operatorToken.kind <= K.LastAssignment) && !(up.parent && (ts.isPrefixUnaryExpression(up.parent) || ts.isPostfixUnaryExpression(up.parent) || ts.isDeleteExpression(up.parent)));
          if (!isEachArg && !isLength) ok = false;
        }
      }
      ts.forEachChild(n, walk);
    };
    walk(root);
    return ok;
  };

  // The array literal an identifier names in the nearest enclosing scope, or null unless one same-file array literal that is only read.
  const resolveTable = (id, from) => {
    for (let p = from.parent; p; p = p.parent) {
      if ((isFunctionLike(p) || ts.isFunctionDeclaration(p)) && p.parameters.some((param) => boundIn(param.name).has(id.text))) return null;
      if (!isHolder(p)) continue;
      const hits = p.statements.filter((st) => boundNames(st).has(id.text));
      if (hits.length === 0) continue;
      if (hits.length > 1 || !ts.isVariableStatement(hits[0])) return null;
      const decls = hits[0].declarationList.declarations.filter((d) => boundIn(d.name).has(id.text));
      if (decls.length !== 1 || !ts.isIdentifier(decls[0].name) || !decls[0].initializer) return null;
      if (hits[0].modifiers && hits[0].modifiers.some((m) => m.kind === K.ExportKeyword)) return null;
      let root = p;
      if (!(hits[0].declarationList.flags & ts.NodeFlags.BlockScoped)) {
        while (root.parent && !isFunctionLike(root) && !ts.isFunctionDeclaration(root) && !ts.isSourceFile(root)) root = root.parent;
      }
      if (!onlyPlainReads(id.text, decls[0], root)) return null;
      const init = unwrap(decls[0].initializer);
      return ts.isArrayLiteralExpression(init) ? init : null;
    }
    return null;
  };

  // Context of one case: ancestor parts, statements it names, and every other statement that runs.
  const caseContext = (chain, refs) => {
    const scopes = chain.filter(isHolder).map((n) => scopeItems(n));
    for (const items of scopes) {
      for (const it of items) {
        it.on = it.always;
        if (it.on) for (const id of it.idents) refs.add(id);
      }
    }
    for (let grew = true; grew; ) {
      grew = false;
      for (const items of scopes) {
        for (const it of items) {
          if (it.on) continue;
          let hit = false;
          for (const n of it.names) if (refs.has(n)) hit = true;
          if (!hit) continue;
          it.on = true;
          grew = true;
          for (const id of it.idents) refs.add(id);
        }
      }
    }
    const parts = [];
    for (const node of chain) {
      if (isHolder(node)) {
        const texts = [];
        for (const it of scopeItems(node)) {
          if (!it.on) continue;
          if (it.text === null) it.text = textOf(it.st);
          texts.push(it.text);
        }
        parts.push(texts.join('\n'));
      } else parts.push(contextOf(node));
    }
    return parts.filter(Boolean).join('\n\u0003\n');
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
    const refs = new Set();
    for (const part of [...c.fn.parameters, c.fn.body]) if (part) identifiersOf(part, refs);
    const tableText = c.table ? c.table.map(textOf).join(' , ') : '';
    if (c.table) for (const arg of c.table) identifiersOf(arg, refs);
    for (const node of chain) {
      if (isHolder(node)) continue;
      for (const kid of flatChildren(node)) if (!hasCase.has(kid) && !punctuation.has(kid.kind)) identifiersOf(kid, refs);
    }
    const ctx = caseContext(chain, refs);
    const params = c.fn.parameters.map(textOf);
    let first = c.table && c.table[0] && unwrap(c.table[0]);
    if (first && ts.isIdentifier(first)) first = resolveTable(first, c.call);
    if (first && ts.isArrayLiteralExpression(first)) {
      const seenRows = new Set();
      for (const el of first.elements) {
        const row = textOf(el);
        if (seenRows.has(row)) {
          records.push(['R', rel, line(c.call), 0, '-', '-']);
          break;
        }
        seenRows.add(row);
      }
    }
    const bodyTokens = [];
    if (c.fn.body) leaves(c.fn.body, bodyTokens);
    const exact = bodyTokens.map(tokenText);
    const shape = bodyTokens.map((t) => (literalKinds.has(t.kind) ? '\u0001L' : tokenText(t)));
    const key = `${ctx}\n\u0004${params.join(',')}\n\u0005${tableText}`;
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
