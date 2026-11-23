// TypeScript and JavaScript reader for check-comments.sh: path and ranges on stdin, one finding per line, exit 0 clean, 1 findings, 2 cannot run.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const opt = { max: 0, adr: false, root: process.cwd(), tsFrom: '' };
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--max') opt.max = Number(argv[++i]);
  else if (argv[i] === '--adr') opt.adr = true;
  else if (argv[i] === '--root') opt.root = path.resolve(argv[++i]);
  else if (argv[i] === '--ts-from') opt.tsFrom = path.resolve(argv[++i]);
}

function die(msg) {
  process.stderr.write(`check-comments: ${msg}\n`);
  process.exit(2);
}
if (!(opt.max >= 1)) die('internal: --max must be a positive number');

let ts;
try {
  ts = createRequire(path.join(opt.tsFrom || opt.root, 'noop.js'))('typescript');
} catch {
  die("the project's own typescript package is missing. Fix: run the project install (pnpm install) so node_modules/typescript exists, then re-run.");
}
if (typeof ts.createScanner !== 'function' || typeof ts.createSourceFile !== 'function') {
  die('the installed typescript package has no scanner API. Fix: install a typescript release that ships the JavaScript compiler API.');
}

const DIRECTIVE_ANYWHERE = /(@ts-(expect-error|ignore|nocheck|check)|NOSONAR|\bnoqa\b)/;
const DIRECTIVE_START = /^(eslint-|prettier-ignore|istanbul\s|c8\s|v8\s|pragma\b|@jsx|@vitest-environment|@jest-environment|<reference\s)/;
const LICENCE = /(Copyright|SPDX-License-Identifier|Licensed under|MIT License|Permission is hereby|Apache License|All rights reserved)/i;
const DECL_KINDS = new Set(
  [
    'FunctionDeclaration', 'ClassDeclaration', 'InterfaceDeclaration', 'TypeAliasDeclaration', 'EnumDeclaration',
    'ModuleDeclaration', 'VariableStatement', 'MethodDeclaration', 'PropertyDeclaration', 'GetAccessor', 'SetAccessor',
    'Constructor', 'MethodSignature', 'PropertySignature', 'IndexSignature', 'CallSignature', 'ConstructSignature',
    'EnumMember', 'ExportDeclaration', 'ExportAssignment',
  ].map((k) => ts.SyntaxKind[k]),
);
const FUNC_KINDS = new Set(
  [
    'FunctionDeclaration', 'FunctionExpression', 'ArrowFunction', 'MethodDeclaration', 'Constructor', 'GetAccessor',
    'SetAccessor', 'ClassStaticBlockDeclaration',
  ]
    .map((k) => ts.SyntaxKind[k])
    .filter((k) => k !== undefined),
);
const JSDOC_FIRST = ts.SyntaxKind.FirstJSDocNode;
const JSDOC_LAST = ts.SyntaxKind.LastJSDocNode;

function scriptKind(file) {
  const e = path.extname(file).toLowerCase();
  if (e === '.tsx') return ts.ScriptKind.TSX;
  if (e === '.jsx') return ts.ScriptKind.JSX;
  if (e === '.js' || e === '.mjs' || e === '.cjs') return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
}

function leaves(sf) {
  const out = [];
  const walk = (n) => {
    if (n.kind >= JSDOC_FIRST && n.kind <= JSDOC_LAST) return;
    const kids = n.getChildren(sf);
    if (kids.length === 0) {
      const s = n.getStart(sf, false);
      if (n.kind !== ts.SyntaxKind.SyntaxList && n.end > s) out.push({ start: s, end: n.end });
      return;
    }
    kids.forEach(walk);
  };
  walk(sf);
  return out;
}

function gapComments(text, toks) {
  const found = [];
  const scanner = ts.createScanner(ts.ScriptTarget.Latest, false, ts.LanguageVariant.Standard);
  const scanGap = (from, to) => {
    if (to <= from) return;
    scanner.setText(text.slice(from, to));
    for (let k = scanner.scan(); k !== ts.SyntaxKind.EndOfFileToken; k = scanner.scan()) {
      const s = from + (scanner.getTokenStart ? scanner.getTokenStart() : scanner.getTokenPos());
      const e = from + scanner.getTextPos();
      if (k === ts.SyntaxKind.SingleLineCommentTrivia) found.push({ pos: s, end: e, block: false });
      else if (k === ts.SyntaxKind.MultiLineCommentTrivia) found.push({ pos: s, end: e, block: true });
    }
  };
  let cursor = 0;
  for (const t of toks) {
    scanGap(cursor, t.start);
    cursor = t.end;
  }
  scanGap(cursor, text.length);
  return found;
}

function lowerBound(toks, pos) {
  let lo = 0;
  let hi = toks.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (toks[mid].start < pos) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

function commentLines(text, c, sf) {
  const raw = text.slice(c.pos, c.end).replace(/\r/g, '');
  const startLine = sf.getLineAndCharacterOfPosition(c.pos).line + 1;
  if (!c.block) return [{ line: startLine, text: raw.replace(/^\/\/\/?/, '').trim(), counts: true }];
  const parts = raw.split('\n');
  return parts.map((p, i) => {
    let t = p;
    if (i === 0) t = t.replace(/^\/\*+/, '');
    if (i === parts.length - 1) t = t.replace(/\*+\/$/, '');
    t = t.replace(/^\s*\*+ ?/, '').trim();
    const delimOnly = (i === 0 || i === parts.length - 1) && parts.length > 1 && t === '';
    return { line: startLine + i, text: t, counts: !delimOnly };
  });
}

function isDirective(item, whole) {
  const t = whole.replace(/^[\s*!/]+/, '');
  return DIRECTIVE_ANYWHERE.test(whole) || DIRECTIVE_START.test(t) || item === 'shebang';
}

function checkFile(rel, rangesSpec, report) {
  const abs = path.resolve(opt.root, rel);
  let text;
  try {
    text = fs.readFileSync(abs, 'utf8');
  } catch (e) {
    die(`cannot read ${rel}: ${e.code || e.message}`);
  }
  const sf = ts.createSourceFile(abs, text, ts.ScriptTarget.Latest, true, scriptKind(abs));
  if (sf.parseDiagnostics && sf.parseDiagnostics.length > 0) {
    const d = sf.parseDiagnostics[0];
    const ln = sf.getLineAndCharacterOfPosition(d.start || 0).line + 1;
    report(rel, ln, 'comments/parse', `file does not parse (${ts.flattenDiagnosticMessageText(d.messageText, ' ')}), so its comments cannot be judged. Fix: repair the syntax error.`);
    return;
  }
  let changed = null;
  if (rangesSpec !== 'all') {
    changed = new Set();
    for (const r of rangesSpec.split(',')) {
      const [a, b] = r.split('-').map(Number);
      for (let l = a; l <= b; l++) changed.add(l);
    }
  }
  const touches = (a, b) => {
    if (changed === null) return true;
    for (let l = a; l <= b; l++) if (changed.has(l)) return true;
    return false;
  };

  const toks = leaves(sf);
  const comments = gapComments(text, toks);
  if (comments.length === 0) return;

  const declStarts = new Set();
  const bodies = [];
  const visit = (n) => {
    if (n.kind >= JSDOC_FIRST && n.kind <= JSDOC_LAST) return;
    if (DECL_KINDS.has(n.kind)) declStarts.add(n.getStart(sf, false));
    if (FUNC_KINDS.has(n.kind)) {
      if (n.body) bodies.push({ start: n.body.getStart(sf, false), end: n.body.end });
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);

  const lineOf = (p) => sf.getLineAndCharacterOfPosition(p).line + 1;
  const lineStart = (p) => sf.getPositionOfLineAndCharacter(lineOf(p) - 1, 0);
  const lineEnd = (p) => {
    const l = lineOf(p);
    return l >= sf.getLineStarts().length ? text.length : sf.getLineStarts()[l];
  };
  const firstTok = toks.length > 0 ? toks[0].start : text.length;

  const items = [];
  for (const c of comments) {
    const i = lowerBound(toks, c.end);
    const prev = i > 0 ? toks[i - 1] : null;
    const next = i < toks.length ? toks[i] : null;
    const codeBefore = prev !== null && prev.end > lineStart(c.pos) && prev.end <= c.pos;
    const codeAfter = c.block && next !== null && next.start < lineEnd(c.end - 1) && lineOf(next.start) === lineOf(c.end - 1);
    const lines = commentLines(text, c, sf);
    const whole = lines.map((l) => l.text).join('\n');
    const shebang = c.pos === 0 && text.startsWith('#!');
    items.push({
      c, lines, whole, codeBefore, codeAfter, next,
      startLine: lines[0].line, endLine: lines[lines.length - 1].line,
      directive: isDirective(shebang ? 'shebang' : '', whole),
      top: c.end <= firstTok,
    });
  }

  for (const it of items) {
    if (it.directive) continue;
    if ((it.codeBefore || it.codeAfter) && touches(it.startLine, it.endLine)) {
      report(rel, it.startLine, 'comments/trailing', 'comment shares a line with code. Fix: move it directly above the declaration it explains, or delete it.');
    }
  }

  const full = items.filter((it) => !it.codeBefore && !it.codeAfter);
  let k = 0;
  while (k < full.length) {
    let j = k;
    while (j + 1 < full.length && full[j + 1].startLine === full[j].endLine + 1) j++;
    const chain = full.slice(k, j + 1);
    k = j + 1;
    const judged = chain.filter((it) => !it.directive);
    if (judged.length === 0) continue;
    if (judged[0].top && LICENCE.test(judged[0].whole)) continue;
    const startLine = judged[0].startLine;
    const chainEnd = chain[chain.length - 1];
    const lines = judged.flatMap((it) => it.lines);
    const anyChanged = judged.some((it) => touches(it.startLine, it.endLine));
    if (anyChanged) {
      const pos = judged[0].c.pos;
      const inBody = bodies.some((b) => pos > b.start && judged[0].c.end <= b.end);
      if (inBody) {
        report(rel, startLine, 'comments/placement', 'comment inside a function body. Fix: delete it, or move the note directly above the function.');
      } else if (!judged[0].top) {
        const nx = chainEnd.next;
        const ok = nx !== null && lineOf(nx.start) === chainEnd.endLine + 1 && declStarts.has(nx.start);
        if (!ok) report(rel, startLine, 'comments/placement', 'comment is not at the top of the file or directly above a declaration. Fix: move it directly above the declaration it explains, or delete it.');
      }
      const count = lines.filter((l) => l.counts).length;
      if (count > MAXLINES) {
        const adr = opt.adr ? ' Cite the ADR by number (for example ADR-0007) instead of restating it.' : '';
        report(rel, startLine, 'comments/length', `comment block is ${count} lines, limit ${MAXLINES}. Fix: cut it to ${MAXLINES} lines or fewer.${adr}`);
      }
    }
    const joined = lines.map((l) => l.text).join('\n').trim();
    if (/^[([{]/.test(joined) && /[)\]}]$/.test(joined) && anyChanged) {
      report(rel, startLine, 'comments/bracketed', 'comment is wholly in brackets. Fix: write it as a plain sentence without brackets.');
      continue;
    }
    const re = /(^|\s)\([^()]*\S[^()]*\)/g;
    let m;
    const all = lines.map((l) => l.text).join('\n');
    while ((m = re.exec(all)) !== null) {
      const before = all.slice(0, m.index + m[1].length);
      const ln = lines[before.split('\n').length - 1].line;
      if (touches(ln, ln)) report(rel, ln, 'comments/aside', 'parenthetical aside in a comment. Fix: make it a plain sentence, or delete it.');
    }
  }
}

const MAXLINES = opt.max;
const findings = [];
const report = (f, l, rule, msg) => findings.push({ f, l, line: `${f}:${l}: ${rule}: ${msg}` });
const specs = fs.readFileSync(0, 'utf8').split('\n').filter((s) => s !== '');
for (const s of specs) {
  const tab = s.lastIndexOf('\t');
  checkFile(s.slice(0, tab), s.slice(tab + 1), report);
}
findings.sort((a, b) => (a.f < b.f ? -1 : a.f > b.f ? 1 : a.l - b.l));
for (const f of findings) process.stdout.write(`${f.line}\n`);
process.exit(findings.length > 0 ? 1 : 0);
