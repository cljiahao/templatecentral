// TypeScript and JavaScript reader for check-comments.sh: path and ranges on stdin, one finding per line, exit 0 clean, 1 findings, 2 cannot run.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const opt = { max: 0, maxLine: 0, maxReason: 0, maxTags: 0, adr: false, root: process.cwd(), tsFrom: '' };
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--max') opt.max = Number(argv[++i]);
  else if (argv[i] === '--max-line') opt.maxLine = Number(argv[++i]);
  else if (argv[i] === '--max-reason') opt.maxReason = Number(argv[++i]);
  else if (argv[i] === '--max-tags') opt.maxTags = Number(argv[++i]);
  else if (argv[i] === '--adr') opt.adr = true;
  else if (argv[i] === '--root') opt.root = path.resolve(argv[++i]);
  else if (argv[i] === '--ts-from') opt.tsFrom = path.resolve(argv[++i]);
}

function die(msg) {
  process.stderr.write(`check-comments: ${msg}\n`);
  process.exit(2);
}
if (!(opt.max >= 1 && opt.maxLine >= 1 && opt.maxReason >= 1 && opt.maxTags >= 1)) die('internal: --max, --max-line, --max-reason and --max-tags must be positive numbers');

const tsDir = path.join(opt.tsFrom || opt.root, 'node_modules', 'typescript');
if (!fs.existsSync(path.join(tsDir, 'package.json'))) {
  die("the project's own typescript package is missing (looked in node_modules/typescript under the project folder only). Fix: run the project install (pnpm install) so node_modules/typescript exists, then re-run.");
}
let ts;
try {
  ts = createRequire(path.join(tsDir, 'noop.js'))(tsDir);
} catch {
  die(`the typescript package in ${tsDir} cannot be loaded. Fix: reinstall it (pnpm install).`);
}
const absent = ['createScanner', 'createSourceFile', 'forEachChild', 'flattenDiagnosticMessageText'].filter((k) => typeof ts[k] !== 'function');
for (const k of ['ScriptTarget', 'ScriptKind', 'SyntaxKind', 'LanguageVariant']) if (!ts[k]) absent.push(k);
if (absent.length > 0) {
  die(`typescript ${ts.version || 'of unknown version'} lacks the compiler API this gate needs (${absent.join(', ')} missing). Fix: install the typescript version pinned in the project's package.json, a release that ships the JavaScript compiler API.`);
}

const RULE_ID = '[@\\w/.][@\\w/.-]*';
const RULES = `${RULE_ID}(?:\\s*,\\s*${RULE_ID})*`;
const WEB_VALUE = '(?:"[^"]*"|\'[^\']*\'|\\[[^\\]]*\\]|[^\\s,]+)';
const WEB_PAIR = `webpack[A-Za-z]+\\s*:\\s*${WEB_VALUE}`;
const DASH = '(?:\\s+--\\s+(?<reason>\\S.*))';
const TEXT = '(?:\\s+(?<reason>\\S.*))';
const DIRECTIVES = [
  new RegExp(`^eslint-(?:disable|disable-line|disable-next-line)(?:\\s+${RULES})?${DASH}$`),
  new RegExp(`^eslint-enable(?:\\s+${RULES})?(?:\\s+--\\s+\\S.*)?$`),
  /^eslint-env\s+[\w,\s-]+$/,
  new RegExp(`^@ts-(?:expect-error|ignore|nocheck)${TEXT}$`),
  /^@ts-check$/,
  /^prettier-ignore(?:-start|-end)?$/,
  new RegExp(`^(?:istanbul|c8|v8)\\s+ignore\\s+(?:next|if|else|file|start)(?:\\s+\\d+)?${DASH}$`),
  /^(?:istanbul|c8|v8)\s+ignore\s+stop$/,
  /^biome-ignore-end$/,
  /^biome-ignore(?:-all|-start)?(?:\s+\w+(?:\/\w+)+)*:\s*(?<reason>\S.*)$/,
  new RegExp(`^NOSONAR(?:\\s*\\([\\w:,\\s.-]*\\))?${DASH}$`),
  new RegExp(`^gitleaks:allow${DASH}$`),
  /^[@#]__(?:PURE|NO_SIDE_EFFECTS|INLINE|NOINLINE)__$/,
  new RegExp(`^${WEB_PAIR}(?:\\s*,\\s*${WEB_PAIR})*$`),
  /^@vite-ignore$/,
  /^@jsx(?:Runtime|ImportSource|Frag)?\s+\S+$/,
  /^@(?:vitest|jest)-environment\s+[\w-]+$/,
  new RegExp(`^pragma:\\s*no\\s+(?:cover|branch)${DASH}$`),
  /^<reference\s+[\w-]+="[^"]*"(?:\s+[\w-]+="[^"]*")*\s*\/>$/,
];
const SUPPRESSORS = [
  [/^eslint-disable(?:-line|-next-line)?(?=\s|$)/, '// eslint-disable-next-line rule -- reason'],
  [/^@ts-(?:expect-error|ignore|nocheck)\b/, '// @ts-expect-error reason'],
  [/^(?:istanbul|c8|v8)\s+ignore\b/, '/* istanbul ignore next -- reason */'],
  [/^biome-ignore(?:-all|-start)?\b/, '// biome-ignore lint/group/rule: reason'],
  [/^NOSONAR\b/, '// NOSONAR -- reason'],
  [/^gitleaks:allow/, '// gitleaks:allow -- reason'],
  [/^pragma:\s*no\s+(?:cover|branch)\b/, '// pragma: no cover -- reason'],
];
const COPYRIGHT = /^(?:\(c\)\s*|©\s*)?copyright\s*(?:\(c\)|©|:|\d)/i;
const RESERVED = /\s*all rights reserved\.?\s*$/i;
const ALL_RIGHTS = /^all rights reserved\.?$/i;
const SENTENCE_END = /[.!?](?:\s|$)/;
const SPDX_ATOM = '\\(*[A-Za-z0-9][A-Za-z0-9.+-]*\\)*';
const SPDX = new RegExp(`^SPDX-License-Identifier:\\s*${SPDX_ATOM}(?:\\s+(?:AND|OR|WITH)\\s+${SPDX_ATOM})*$`);
const MAX_COPYRIGHT_CHARS = 100;
const MAX_HOLDER_WORDS = 10;
const MAX_TITLE_WORDS = 4;
const MAX_TAG_WORDS = 8;
const NAMED_TAGS = new Set('param arg argument property prop typedef template typeparam callback'.split(' '));
const MAX_COPYRIGHT_LINES = 5;
const MAX_LICENCE_LINES = 40;
const MIN_LICENCE_WORDS = 4;
const LICENCE_FILE = 'check-comments.licences.txt';
const DATA_TAGS = new Set(
  (
    'param arg argument returns return type typedef template typeparam property prop callback yields yield throws exception extends implements augments ' +
    'public private protected internal readonly override virtual abstract sealed packagedocumentation since version defaultvalue default access async ' +
    'constant const enum event fires function this namespace module memberof name kind alias class constructor global inheritdoc ignore hidden beta alpha ' +
    'experimental category group deprecated author license link'
  ).split(' '),
);
const FILLER = new Set(['todo', 'fixme', 'xxx', 'tbd']);
const MIN_REASON_WORDS = 3;
const TAG_NAME = /^@([A-Za-z]+)/;
const ASIDE = /(^|\s)\([^()]*\S[^()]*\)/g;
const JSDOC_FIRST = ts.SyntaxKind.FirstJSDocNode;
const JSDOC_LAST = ts.SyntaxKind.LastJSDocNode;
const FUNC_KINDS = new Set(
  [
    'FunctionDeclaration', 'FunctionExpression', 'ArrowFunction', 'MethodDeclaration', 'Constructor', 'GetAccessor',
    'SetAccessor', 'ClassStaticBlockDeclaration',
  ]
    .map((k) => ts.SyntaxKind[k])
    .filter((k) => k !== undefined),
);

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

function afterType(rest) {
  const r = rest.trimStart();
  if (!r.startsWith('{')) return r;
  let depth = 0;
  for (let i = 0; i < r.length; i++) {
    if (r[i] === '{') depth++;
    else if (r[i] === '}' && --depth === 0) return r.slice(i + 1);
  }
  return '';
}

function isDataTag(t) {
  const m = TAG_NAME.exec(t);
  if (m === null || !DATA_TAGS.has(m[1].toLowerCase())) return false;
  const words = afterType(t.slice(m[0].length)).split(/\s+/).filter((w) => w !== '');
  if (NAMED_TAGS.has(m[1].toLowerCase())) words.shift();
  return words.length <= MAX_TAG_WORDS;
}

function commentLines(text, c, sf) {
  const raw = text.slice(c.pos, c.end).replace(/\r/g, '');
  const startLine = sf.getLineAndCharacterOfPosition(c.pos).line + 1;
  if (!c.block) return [{ line: startLine, text: raw.replace(/^\/\/\/?/, '').trim(), counts: true }];
  const jsdoc = raw.startsWith('/**');
  const parts = raw.split('\n');
  return parts.map((p, i) => {
    let t = p;
    if (i === 0) t = t.replace(/^\/\*+/, '');
    if (i === parts.length - 1) t = t.replace(/\*+\/$/, '');
    t = t.replace(/^\s*\*+ ?/, '').trim();
    const tag = jsdoc && isDataTag(t);
    return { line: startLine + i, text: t, counts: t !== '' && !tag, tag };
  });
}

function weakReason(reason) {
  const words = (reason.match(/[\p{L}\p{N}_'-]+/gu) || []).filter((w) => !FILLER.has(w.toLowerCase()) && w.length >= 2 && /\p{L}/u.test(w));
  return words.length < MIN_REASON_WORDS || new Set(words.map((w) => w.toLowerCase())).size < 2;
}

function suppressorForm(flat) {
  for (const [re, form] of SUPPRESSORS) if (re.test(flat)) return form;
  return '';
}

function directiveOf(lines) {
  const flat = lines.map((l) => l.text.replace(/^[\s*!/]+/, '')).filter((t) => t !== '').join(' ');
  for (const re of DIRECTIVES) {
    const m = re.exec(flat);
    if (m) {
      const reason = (m.groups && m.groups.reason) || '';
      if (m.groups && 'reason' in m.groups && weakReason(reason)) return { is: true, reason: '', bad: suppressorForm(flat) };
      return { is: true, reason, bad: '' };
    }
  }
  const form = suppressorForm(flat);
  if (form) return { is: true, reason: '', bad: form };
  return { is: false, reason: '', bad: '' };
}

function normWords(text) {
  return text.toLowerCase().replace(/(?:^|\s)(?:\d+[.)]|[-*•])(?=\s|$)/g, ' ').match(/[\p{L}\p{N}]+/gu) || [];
}

function loadLicences() {
  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), LICENCE_FILE);
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch (e) {
    die(`cannot read the bundled licence texts ${LICENCE_FILE}: ${e.code || e.message}. Fix: restore the file next to this script.`);
  }
  const texts = [];
  for (const line of raw.split('\n')) {
    if (line.startsWith('@@ ')) texts.push([]);
    else if (texts.length > 0) texts[texts.length - 1].push(normWords(line));
  }
  const out = [];
  for (const all of texts) {
    const lines = all.filter((w) => w.length > 0);
    if (lines.length === 0) continue;
    out.push(` ${lines.flat().join(' ')} `);
    if (lines[0].length <= MAX_TITLE_WORDS && lines.length > 1) out.push(` ${lines.slice(1).flat().join(' ')} `);
  }
  if (out.length === 0) die(`the bundled licence texts ${LICENCE_FILE} hold no licence. Fix: restore the file next to this script.`);
  return out;
}
const LICENCES = loadLicences();

function isCopyright(t) {
  if (t.length > MAX_COPYRIGHT_CHARS) return false;
  if (SPDX.test(t) || ALL_RIGHTS.test(t)) return true;
  const m = COPYRIGHT.exec(t);
  if (m === null) return false;
  let rest = t.slice(m[0].length).replace(RESERVED, '').trim();
  if (rest.endsWith('.')) rest = rest.slice(0, -1);
  return rest.split(/\s+/).filter((w) => w !== '').length <= MAX_HOLDER_WORDS && !SENTENCE_END.test(rest);
}

function licenceLines(lines, used) {
  const out = new Set(lines.filter((l) => l.text === ''));
  if (!used.open) return out;
  const copy = lines.filter((l) => l.text !== '' && isCopyright(l.text));
  const rest = lines.filter((l) => l.text !== '' && !copy.includes(l));
  const within = used.copyright + copy.length <= MAX_COPYRIGHT_LINES;
  if (within) {
    for (const l of copy) out.add(l);
    used.copyright += copy.length;
  }
  used.open = within && rest.length === 0;
  const matchable = rest.filter((l) => normWords(l.text).length > 0);
  const found = matchable.flatMap((l) => normWords(l.text));
  if (matchable.length > 0 && used.licence + matchable.length <= MAX_LICENCE_LINES && found.length >= MIN_LICENCE_WORDS) {
    const prefix = ` ${found.join(' ')} `;
    if (LICENCES.some((lic) => lic.startsWith(prefix))) {
      for (const l of matchable) out.add(l);
      used.licence += matchable.length;
    }
  }
  return out;
}

function checkFile(rel, rangesSpec, report) {
  const abs = path.resolve(opt.root, rel);
  let text;
  try {
    text = fs.readFileSync(abs, 'utf8').replace(/^﻿/, '');
  } catch (e) {
    die(`cannot read ${rel}: ${e.code || e.message}`);
  }
  const sf = ts.createSourceFile(abs, text, ts.ScriptTarget.Latest, true, scriptKind(abs));
  if (sf.parseDiagnostics && sf.parseDiagnostics.length > 0) {
    const d = sf.parseDiagnostics[0];
    const ln = sf.getLineAndCharacterOfPosition(d.start || 0).line + 1;
    report(rel, ln, 'comments/parse', `file does not parse with typescript ${ts.version} (${ts.flattenDiagnosticMessageText(d.messageText, ' ')}), so its comments cannot be judged. Fix: repair the syntax error, or install a typescript release that supports the syntax used.`);
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

  const targetStarts = new Set();
  const bodies = [];
  const emptyJsx = [];
  const inList = (list, n) => Array.isArray(list) && list.includes(n);
  const visit = (n) => {
    if (n.kind >= JSDOC_FIRST && n.kind <= JSDOC_LAST) return;
    const p = n.parent;
    if (p && p.kind !== ts.SyntaxKind.JsxAttributes && (inList(p.statements, n) || inList(p.members, n) || inList(p.properties, n) || inList(p.clauses, n) || inList(p.elements, n) || inList(p.arguments, n) || inList(p.types, n) || inList(p.parameters, n))) {
      targetStarts.add(n.getStart(sf, false));
    }
    if (n.kind === ts.SyntaxKind.UnionType) {
      for (const list of n.getChildren(sf)) {
        if (list.kind === ts.SyntaxKind.SyntaxList) for (const t of list.getChildren(sf)) if (t.kind === ts.SyntaxKind.BarToken) targetStarts.add(t.getStart(sf, false));
      }
    }
    if (n.kind === ts.SyntaxKind.ConditionalExpression) {
      for (const t of [n.questionToken, n.colonToken]) if (t) targetStarts.add(t.getStart(sf, false));
    }
    if (n.kind === ts.SyntaxKind.IfStatement && n.elseStatement) {
      const kw = n.getChildren(sf).find((c) => c.kind === ts.SyntaxKind.ElseKeyword);
      if (kw) targetStarts.add(kw.getStart(sf, false));
    }
    if (n.kind === ts.SyntaxKind.JsxExpression && !n.expression) emptyJsx.push({ start: n.getStart(sf, false), end: n.end });
    if (FUNC_KINDS.has(n.kind) && n.body) bodies.push({ start: n.body.pos, end: n.body.end });
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
    const dir = directiveOf(lines);
    items.push({
      c, lines, whole: lines.map((l) => l.text).join('\n'), codeBefore, codeAfter, next,
      startLine: lines[0].line, endLine: lines[lines.length - 1].line,
      directive: dir.is, reason: dir.reason, bad: dir.bad,
      top: c.end <= firstTok,
      jsx: emptyJsx.some((j) => c.pos >= j.start && c.end <= j.end),
    });
  }

  for (const it of items) {
    if (it.bad && touches(it.startLine, it.endLine)) {
      report(rel, it.startLine, 'comments/directive', `directive without a reason or in the wrong form. Fix: write it as \`${it.bad}\`, with a one-line reason of at least three words that is not only TODO.`);
    }
    if (it.jsx) {
      if (touches(it.startLine, it.endLine)) report(rel, it.startLine, 'comments/placement', 'comment inside a function body. Fix: delete it, or move the note on its own line directly above the function.');
      continue;
    }
    if (it.directive) continue;
    if ((it.codeBefore || it.codeAfter) && touches(it.startLine, it.endLine)) {
      report(rel, it.startLine, 'comments/trailing', 'comment shares a line with code. Fix: move it on its own line directly above the statement or declaration it explains, or delete it.');
    }
  }

  for (const it of items) {
    if (!it.directive || it.reason === '') continue;
    const nonEmpty = it.lines.filter((l) => l.text !== '');
    const at = nonEmpty[0].line;
    if (!touches(it.startLine, it.endLine)) continue;
    if (nonEmpty.length > 1) report(rel, at, 'comments/length', 'directive reason spans several lines. Fix: keep the reason on one line, or delete it.');
    else if (it.reason.length > opt.maxReason) report(rel, at, 'comments/length', `directive reason is ${it.reason.length} characters, limit ${opt.maxReason}. Fix: shorten the reason, or delete it.`);
    if (new RegExp(ASIDE.source).test(it.reason)) report(rel, at, 'comments/aside', 'parenthetical aside in a directive reason. Fix: make it a plain phrase, or delete it.');
  }

  const own = items.filter((it) => !it.codeBefore && !it.codeAfter && !it.jsx);
  const tagGroups = new Map();
  for (const it of own) {
    const n = it.c.block && text.startsWith('/**', it.c.pos) ? it.lines.filter((l) => l.tag).length : 0;
    const g = tagGroups.get(it.next) || { n: 0, first: it, touched: false };
    g.n += n;
    g.touched = g.touched || touches(it.startLine, it.endLine);
    tagGroups.set(it.next, g);
  }
  for (const g of tagGroups.values()) {
    if (g.n > opt.maxTags && g.touched) {
      report(rel, g.first.startLine, 'comments/length', `comments above one declaration have ${g.n} JSDoc tag lines, limit ${opt.maxTags}. Fix: drop tags that restate the signature, or cut it to ${opt.maxTags} or fewer.`);
    }
  }
  let k = 0;
  const used = { copyright: 0, licence: 0, open: true };
  let topTotal = 0;
  let topChains = 0;
  let topLine = null;
  let topChanged = false;
  while (k < own.length) {
    let j = k;
    while (j + 1 < own.length && own[j + 1].startLine === own[j].endLine + 1) j++;
    const chain = own.slice(k, j + 1);
    k = j + 1;
    const prose = chain.filter((it) => !it.directive);
    const exempt = prose.length > 0 && prose[0].top ? licenceLines(prose.flatMap((it) => it.lines), used) : new Set();
    for (const it of chain) {
      for (const l of it.lines) {
        if (l.text.length > opt.maxLine && !exempt.has(l) && touches(l.line, l.line)) {
          report(rel, l.line, 'comments/length', `comment line is ${l.text.length} characters, limit ${opt.maxLine}. Fix: cut it or split it into shorter sentences.`);
        }
      }
    }
    const counted = chain.filter((it) => !it.directive || it.reason !== '');
    if (counted.length === 0) continue;
    if (prose.length > 0 && prose[0].top) {
      if (counted.flatMap((it) => it.lines).every((l) => exempt.has(l) || !l.counts)) continue;
      topChains++;
      topTotal += counted.flatMap((it) => it.lines).filter((l) => l.counts && !exempt.has(l)).length;
      if (topLine === null) topLine = counted[0].startLine;
      topChanged = topChanged || counted.some((it) => touches(it.startLine, it.endLine));
    }
    const startLine = counted[0].startLine;
    const proseChanged = prose.some((it) => touches(it.startLine, it.endLine));
    const anyChanged = counted.some((it) => touches(it.startLine, it.endLine));
    if (proseChanged) {
      const first = prose[0];
      const chainEnd = chain[chain.length - 1];
      const inBody = bodies.some((b) => first.c.pos >= b.start && first.c.end <= b.end);
      if (inBody) {
        report(rel, first.startLine, 'comments/placement', 'comment inside a function body. Fix: delete it, or move the note on its own line directly above the function.');
      } else if (!first.top) {
        const nx = chainEnd.next;
        const ok = nx !== null && lineOf(nx.start) === chainEnd.endLine + 1 && targetStarts.has(nx.start);
        if (!ok) report(rel, first.startLine, 'comments/placement', 'comment is not on its own line at the top of the file or directly above a statement, declaration, member or property. Fix: move it there, or delete it.');
      }
    }
    if (anyChanged) {
      const count = counted.flatMap((it) => it.lines).filter((l) => l.counts && !exempt.has(l)).length;
      if (count > opt.max) {
        const adr = opt.adr ? ' Cite the ADR by number (for example ADR-0007) instead of restating it.' : '';
        report(rel, startLine, 'comments/length', `comment block is ${count} lines, limit ${opt.max}. Fix: cut it to ${opt.max} lines or fewer.${adr}`);
      }
    }
    if (prose.length === 0) continue;
    const lines = prose.flatMap((it) => it.lines).filter((l) => !exempt.has(l));
    if (lines.length === 0) continue;
    const joined = lines.map((l) => l.text).join('\n').trim();
    if (/^[([{]/.test(joined) && /[)\]}]$/.test(joined) && proseChanged) {
      report(rel, prose[0].startLine, 'comments/bracketed', 'comment is wholly in brackets. Fix: write it as a plain sentence without brackets.');
      continue;
    }
    const all = lines.map((l) => l.text).join('\n');
    const re = new RegExp(ASIDE.source, 'g');
    let m;
    while ((m = re.exec(all)) !== null) {
      const before = all.slice(0, m.index + m[1].length);
      const ln = lines[before.split('\n').length - 1].line;
      if (touches(ln, ln)) report(rel, ln, 'comments/aside', 'parenthetical aside in a comment. Fix: make it a plain sentence, or delete it.');
    }
  }
  if (topChains > 1 && topTotal > opt.max && topChanged) {
    report(rel, topLine, 'comments/length', `comments before the first line of code total ${topTotal} lines, limit ${opt.max}. Fix: cut them to ${opt.max} lines or fewer; only a licence header is exempt.`);
  }
}

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
