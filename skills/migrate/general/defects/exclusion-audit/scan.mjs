// Scanner for check-exclude-reasons.sh: reads JS, TS and JSON configs as syntax trees without running them.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const defaults = new Set((process.env.TC_EXCLUDE_DEFAULTS || '').split('\n').filter(Boolean));
const REASON = /^reason:\s+\S+(\s+\S+){2,}\s*$/;
const PLACEHOLDERS = new Set((process.env.TC_REASON_PLACEHOLDERS || '').split('\n').filter(Boolean));
function validReason(text) {
  if (!REASON.test(text)) return false;
  const words = text.slice('reason:'.length).split(/[\s,;"`()]+/).map((w) => w.replace(/[.:]+$/, '').toLowerCase()).filter(Boolean);
  if (words.some((w) => PLACEHOLDERS.has(w))) return false;
  return new Set(words.filter((w) => w.length >= 3)).size >= 3;
}
const clean = (s) => String(s).replace(/[\t\r\n]+/g, ' ');
const emit = (...fields) => console.log(fields.map(clean).join('\t'));

const args = process.argv.slice(2);
let root = process.cwd();
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--root') root = path.resolve(args[++i] || '.');
  else files.push(args[i]);
}

const tsCache = new Map();
function loadTs(dir) {
  if (!tsCache.has(dir)) {
    let mod = null;
    try {
      mod = createRequire(path.join(dir, 'package.json'))('typescript');
    } catch {
      mod = null;
    }
    tsCache.set(dir, mod);
  }
  return tsCache.get(dir);
}

const DYNAMIC = 'is built dynamically (spread, variable or call); write it as a literal array of strings so each entry can carry a reason';

const visited = new Set();

function scan(file, depth = 0, inherited = null) {
  const abs = path.resolve(root, file);
  const base = path.basename(file);
  const ts = loadTs(path.dirname(abs));
  if (!ts) {
    emit('X', file, 1, 'typescript is not installed for this project, so the config cannot be read; run the package install first');
    return;
  }
  if (/\.ya?ml$/.test(base)) {
    emit('X', file, 1, 'a YAML coverage config cannot be read; use the JSON form of the file');
    return;
  }
  const text = fs.readFileSync(abs, 'utf8');
  const isJson = base.endsWith('.json') || /^\.(nyc|c8)rc$/.test(base);
  const sf = isJson ? ts.parseJsonText(abs, text) : ts.createSourceFile(abs, text, ts.ScriptTarget.Latest, true);
  const problems = sf.parseDiagnostics || [];
  if (problems.length > 0) {
    const at = sf.getLineAndCharacterOfPosition(problems[0].start || 0).line + 1;
    emit('X', file, at, 'config has a syntax error, so it cannot be read');
    return;
  }
  const lineOf = (pos) => sf.getLineAndCharacterOfPosition(pos).line + 1;
  const lineStartsBlank = (pos) => /^[ \t]*$/.test(text.slice(text.lastIndexOf('\n', pos - 1) + 1, pos));

  const commentAt = new Map();
  const gather = (node) => {
    for (const r of ts.getLeadingCommentRanges(text, node.pos) || []) {
      if (r.kind === ts.SyntaxKind.SingleLineCommentTrivia && lineStartsBlank(r.pos)) {
        commentAt.set(lineOf(r.pos), text.slice(r.pos + 2, r.end).trim());
      }
    }
    for (const child of node.getChildren(sf)) gather(child);
  };
  gather(sf);
  const hasReason = (line) => validReason(commentAt.get(line) || '');

  const unwrap = (e) => {
    let cur = e;
    while (
      cur &&
      (ts.isParenthesizedExpression(cur) || ts.isAsExpression(cur) || ts.isSatisfiesExpression(cur) || ts.isTypeAssertionExpression(cur) || ts.isNonNullExpression(cur))
    ) {
      cur = cur.expression;
    }
    return cur;
  };
  const isStr = (n) => ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n);
  const nameOf = (m) => {
    if (!m.name) return null;
    if (ts.isIdentifier(m.name) || ts.isStringLiteral(m.name)) return m.name.text;
    if (ts.isComputedPropertyName(m.name) && isStr(m.name.expression)) return m.name.expression.text;
    return null;
  };

  // Returns the literal entries of a list property, or null after reporting a dynamic list.
  const literalList = (member, label) => {
    if (!ts.isPropertyAssignment(member)) {
      emit('X', file, lineOf(member.getStart(sf)), `${label} ${DYNAMIC}`);
      return null;
    }
    const v = unwrap(member.initializer);
    if (isStr(v)) return [{ text: v.text, line: lineOf(v.getStart(sf)) }];
    if (ts.isArrayLiteralExpression(v)) {
      const items = [];
      for (const el of v.elements) {
        const e = unwrap(el);
        if (!isStr(e)) {
          emit('X', file, lineOf(el.getStart(sf)), `${label} ${DYNAMIC}`);
          return null;
        }
        items.push({ text: e.text, line: lineOf(e.getStart(sf)) });
      }
      return items;
    }
    emit('X', file, lineOf(member.getStart(sf)), `${label} ${DYNAMIC}`);
    return null;
  };

  const isDefault = (t) => defaults.has(t.startsWith('!') ? t.slice(1) : t);

  // One E record per entry: a reason is the comment line directly above it, or above the key when the list has one non-default entry.
  const emitExcludes = (kind, member, items) => {
    const keyLine = lineOf(member.getStart(sf));
    const own = items.filter((it) => !isDefault(it.text));
    const perLine = new Map();
    for (const it of own) perLine.set(it.line, (perLine.get(it.line) || 0) + 1);
    for (const it of items) {
      let status;
      if (isDefault(it.text)) status = 'default';
      else if (perLine.get(it.line) > 1) status = 'shared';
      else if (hasReason(it.line - 1) || (own.length === 1 && hasReason(keyLine - 1))) status = 'reason';
      else status = 'none';
      emit('E', file, it.line, kind, it.text, status);
    }
  };

  const emitInclude = (kind, member, items) => {
    if (items.length === 0) return;
    const keyLine = lineOf(member.getStart(sf));
    emit('I', file, keyLine, kind, items.map((it) => it.text).join(', '), hasReason(keyLine - 1) ? 'reason' : 'none');
  };

  const THRESHOLD_KEYS = ['lines', 'functions', 'branches', 'statements'];
  const thresholds = (node) => {
    const v = unwrap(node);
    if (!v || !ts.isObjectLiteralExpression(v)) return;
    for (const m of v.properties) {
      if (!ts.isPropertyAssignment(m)) continue;
      const key = nameOf(m);
      const val = unwrap(m.initializer);
      if (THRESHOLD_KEYS.includes(key) && ts.isNumericLiteral(val)) emit('T', file, lineOf(m.getStart(sf)), key, val.text);
      else if (ts.isObjectLiteralExpression(val)) thresholds(val);
    }
  };

  const coverageBlock = (member) => {
    if (!ts.isPropertyAssignment(member)) {
      emit('X', file, lineOf(member.getStart(sf)), `the coverage block ${DYNAMIC}`);
      return;
    }
    const v = unwrap(member.initializer);
    if (v.kind === ts.SyntaxKind.TrueKeyword || v.kind === ts.SyntaxKind.FalseKeyword) return;
    if (!ts.isObjectLiteralExpression(v)) {
      emit('X', file, lineOf(member.getStart(sf)), `the coverage block ${DYNAMIC}`);
      return;
    }
    for (const m of v.properties) {
      if (ts.isSpreadAssignment(m)) {
        emit('X', file, lineOf(m.getStart(sf)), `the coverage block ${DYNAMIC}`);
        continue;
      }
      const key = nameOf(m);
      if (key === 'exclude') {
        const items = literalList(m, 'the coverage exclude list');
        if (items) emitExcludes('coverage-exclude', m, items);
      } else if (key === 'include') {
        const items = literalList(m, 'the coverage include list');
        if (items) emitInclude('coverage-include', m, items);
      } else if (key === 'thresholds' && ts.isPropertyAssignment(m)) {
        thresholds(m.initializer);
      } else if (THRESHOLD_KEYS.includes(key) && ts.isPropertyAssignment(m) && ts.isNumericLiteral(unwrap(m.initializer))) {
        emit('T', file, lineOf(m.getStart(sf)), key, unwrap(m.initializer).text);
      }
    }
  };

  const testBlock = (member) => {
    if (!ts.isPropertyAssignment(member)) return;
    const v = unwrap(member.initializer);
    if (!ts.isObjectLiteralExpression(v)) return;
    for (const m of v.properties) {
      if (ts.isSpreadAssignment(m)) emit('X', file, lineOf(m.getStart(sf)), `a spread inside the test block can hide the coverage block; ${DYNAMIC}`);
    }
  };

  const jestKey = (member, key) => {
    if (key === 'coverageThreshold') {
      if (ts.isPropertyAssignment(member)) thresholds(member.initializer);
      return;
    }
    const label = key === 'collectCoverageFrom' ? 'collectCoverageFrom' : 'coveragePathIgnorePatterns';
    const items = literalList(member, label);
    if (!items) return;
    if (key === 'coveragePathIgnorePatterns') {
      emitExcludes('coverage-exclude', member, items);
      return;
    }
    emitInclude(
      'coverage-include',
      member,
      items.filter((it) => !it.text.startsWith('!')),
    );
    emitExcludes(
      'coverage-exclude',
      member,
      items.filter((it) => it.text.startsWith('!')),
    );
  };

  const mutateKey = (member) => {
    const items = literalList(member, 'the mutate list');
    if (!items) return;
    emitExcludes(
      'mutation-exclude',
      member,
      items.filter((it) => it.text.startsWith('!')),
    );
  };

  const nycKey = (member, key) => {
    const items = literalList(member, `the ${key} list`);
    if (!items) return;
    if (key === 'exclude') emitExcludes('coverage-exclude', member, items);
    else emitInclude('coverage-include', member, items);
  };

  const strykerKey = (member) => {
    const items = literalList(member, 'the mutation list');
    if (items) emitExcludes('mutation-exclude', member, items);
  };

  const vitestLike = /^(vitest|vite)\.(config|workspace)\./.test(base);
  const jestLike = /^jest\.config\./.test(base);
  const strykerLike = /^\.?stryker\.(config|conf)\./.test(base);
  const nycLike = /^\.(nyc|c8)rc(\.json)?$/.test(base);
  const jscpdLike = base === '.jscpd.json';
  const isPackageJson = base === 'package.json';

  const walk = (node, mode) => {
    if (ts.isPropertyAssignment(node) || ts.isShorthandPropertyAssignment(node) || ts.isSpreadAssignment(node)) {
      const key = nameOf(node);
      if (mode === 'vitest' && key === 'coverage') coverageBlock(node);
      else if (mode === 'vitest' && key === 'test') testBlock(node);
      else if (mode === 'jest' && (key === 'coveragePathIgnorePatterns' || key === 'collectCoverageFrom' || key === 'coverageThreshold')) jestKey(node, key);
      else if (mode === 'stryker' && key === 'mutate') mutateKey(node);
      else if (mode === 'stryker' && (key === 'ignorePatterns' || key === 'excludedMutations')) strykerKey(node);
      else if (mode === 'nyc' && (key === 'exclude' || key === 'include')) nycKey(node, key);
      else if (mode === 'jscpd' && key === 'ignore') {
        const items = literalList(node, 'the jscpd ignore list');
        if (items) emitExcludes('cpd-ignore', node, items);
      } else if (ts.isPropertyAssignment(node) && ts.isComputedPropertyName(node.name) && !isStr(node.name.expression)) {
        emit('X', file, lineOf(node.getStart(sf)), 'a computed key can hide a coverage setting; write the key as a plain name');
      }
    }
    ts.forEachChild(node, (c) => walk(c, mode));
  };

  const BINDINGS = new Map();
  for (const st of sf.statements) {
    if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) if (ts.isIdentifier(d.name) && d.initializer) BINDINGS.set(d.name.text, { init: d.initializer });
    } else if (ts.isFunctionDeclaration(st) && st.name && st.body) {
      BINDINGS.set(st.name.text, { fn: st });
    } else if (ts.isImportDeclaration(st) && ts.isStringLiteral(st.moduleSpecifier) && st.importClause) {
      const spec = st.moduleSpecifier.text;
      const names = [];
      if (st.importClause.name) names.push(st.importClause.name.text);
      const nb = st.importClause.namedBindings;
      if (nb && ts.isNamespaceImport(nb)) names.push(nb.name.text);
      if (nb && ts.isNamedImports(nb)) for (const el of nb.elements) names.push(el.name.text);
      for (const n of names) BINDINGS.set(n, { imp: spec });
    }
  }
  const returnsOf = (body) => {
    const found = [];
    const visit = (n) => {
      if (ts.isReturnStatement(n)) found.push(n.expression);
      if (!ts.isFunctionLike(n)) ts.forEachChild(n, visit);
    };
    ts.forEachChild(body, visit);
    return found;
  };
  const followImport = (spec) => {
    if (!/^\.{1,2}\//.test(spec)) {
      emit('X', file, 1, `the config uses '${spec}' from another package, which is not read; write the coverage block in this file`);
      return;
    }
    const dir = path.dirname(abs);
    const cands = [spec, ...['.ts', '.mts', '.cts', '.js', '.mjs', '.cjs', '.json'].map((x) => spec + x), ...['.ts', '.js', '.mjs'].map((x) => path.join(spec, 'index' + x))];
    const hit = cands.map((c) => path.resolve(dir, c)).find((c) => fs.existsSync(c) && fs.statSync(c).isFile());
    if (!hit) {
      emit('X', file, 1, `the config imports '${spec}', which cannot be found; write the coverage block in this file`);
      return;
    }
    const rel = path.isAbsolute(file) ? hit : path.relative(root, hit);
    if (files.includes(rel) || visited.has(rel)) return;
    if (depth >= 1) {
      emit('X', file, 1, `the config imports '${spec}', which imports further; write the coverage block in one file`);
      return;
    }
    visited.add(rel);
    scan(rel, depth + 1, mode);
  };
  const resolves = (expr, depth) => {
    const e = unwrap(expr);
    if (!e || depth > 8) return false;
    if (ts.isObjectLiteralExpression(e) || ts.isArrayLiteralExpression(e) || isStr(e)) return true;
    if (ts.isAwaitExpression(e)) return resolves(e.expression, depth + 1);
    if (ts.isArrowFunction(e) || ts.isFunctionExpression(e)) {
      if (ts.isBlock(e.body)) {
        const rets = returnsOf(e.body);
        return rets.length > 0 && rets.every((r) => resolves(r, depth + 1));
      }
      return resolves(e.body, depth + 1);
    }
    if (ts.isCallExpression(e)) return e.arguments.length > 0 && e.arguments.every((a) => resolves(a, depth + 1));
    if (ts.isIdentifier(e)) {
      const b = BINDINGS.get(e.text);
      if (!b) return false;
      if (b.imp !== undefined) {
        followImport(b.imp);
        return true;
      }
      if (b.init) return resolves(b.init, depth + 1);
      if (b.fn) {
        const rets = returnsOf(b.fn.body);
        return rets.length > 0 && rets.every((r) => resolves(r, depth + 1));
      }
    }
    return false;
  };
  const rootOk = () => {
    const roots = [];
    for (const st of sf.statements) {
      if (ts.isExportAssignment(st)) roots.push(st.expression);
      else if (ts.isExpressionStatement(st) && ts.isBinaryExpression(st.expression) && st.expression.operatorToken.kind === ts.SyntaxKind.EqualsToken) {
        const left = st.expression.left.getText(sf);
        if (left === 'module.exports' || left === 'exports.default') roots.push(st.expression.right);
      }
    }
    return roots.length > 0 && roots.every((r) => resolves(r, 0));
  };

  if (isJson || nycLike || jscpdLike) {
    const rootObj = sf.statements[0] && sf.statements[0].expression;
    if (!rootObj || !ts.isObjectLiteralExpression(rootObj)) {
      emit('X', file, 1, 'JSON config root is not an object, so it cannot be read');
      return;
    }
    if (isPackageJson) {
      for (const m of rootObj.properties) {
        const k = nameOf(m);
        if (!ts.isPropertyAssignment(m)) continue;
        if (k === 'jest') walk(m.initializer, 'jest');
        else if (k === 'nyc' || k === 'c8') walk(m.initializer, 'nyc');
      }
    } else if (strykerLike) {
      walk(rootObj, 'stryker');
    } else if (jestLike) {
      walk(rootObj, 'jest');
    } else if (nycLike) {
      walk(rootObj, 'nyc');
    } else if (jscpdLike) {
      walk(rootObj, 'jscpd');
    }
    return;
  }
  const mode = vitestLike ? 'vitest' : jestLike ? 'jest' : strykerLike ? 'stryker' : inherited;
  if (!mode) return;
  const relevant = mode !== 'vitest' || !/^vite\.config\./.test(base) || /coverage|vitest/.test(text);
  const rootSpreads = () => {
    const seen = new Set();
    const visit = (expr, d) => {
      const e = unwrap(expr);
      if (!e || d > 8 || seen.has(e)) return;
      seen.add(e);
      if (ts.isObjectLiteralExpression(e)) {
        for (const m of e.properties) {
          if (ts.isSpreadAssignment(m)) emit('X', file, lineOf(m.getStart(sf)), `a spread in the config root can hide a coverage setting; write the root as one plain object literal`);
        }
      } else if (ts.isAwaitExpression(e)) visit(e.expression, d + 1);
      else if (ts.isArrowFunction(e) || ts.isFunctionExpression(e)) {
        if (ts.isBlock(e.body)) returnsOf(e.body).forEach((r) => visit(r, d + 1));
        else visit(e.body, d + 1);
      } else if (ts.isCallExpression(e)) e.arguments.forEach((a) => visit(a, d + 1));
      else if (ts.isIdentifier(e)) {
        const b = BINDINGS.get(e.text);
        if (b && b.init) visit(b.init, d + 1);
        else if (b && b.fn) returnsOf(b.fn.body).forEach((r) => visit(r, d + 1));
      }
    };
    for (const st of sf.statements) {
      if (ts.isExportAssignment(st)) visit(st.expression, 0);
      else if (ts.isExpressionStatement(st) && ts.isBinaryExpression(st.expression) && st.expression.operatorToken.kind === ts.SyntaxKind.EqualsToken) {
        const left = st.expression.left.getText(sf);
        if (left === 'module.exports' || left === 'exports.default') visit(st.expression.right, 0);
      }
    }
  };
  if (depth > 0) {
    for (const b of BINDINGS.values()) if (b.imp !== undefined && /^\.{1,2}\//.test(b.imp)) followImport(b.imp);
  }
  if (relevant && depth === 0) rootSpreads();
  if (relevant && depth === 0 && !rootOk()) {
    emit('X', file, 1, 'config root is not an object literal, a function returning one, or a same-file variable holding one, so it cannot be read statically');
  }
  walk(sf, mode);
}

for (const f of files) {
  try {
    scan(f);
  } catch (err) {
    emit('X', f, 1, `config could not be read: ${err && err.message ? err.message : err}`);
  }
}
