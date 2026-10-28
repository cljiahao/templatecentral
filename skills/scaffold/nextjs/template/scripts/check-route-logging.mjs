// Fail the build if any App Router API handler is not wrapped in withLogging().
// Enforces the "every route is logged" rule the base scaffold models on its own handlers.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'src/app/api';
const METHODS = 'GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS';
// Matches route.ts|tsx|js|jsx|mjs|mts
const ROUTE_FILE = /^route\.m?[jt]sx?$/;

// Match on comment-stripped, whole-file text (not line-by-line) so commented-out handlers
// don't false-positive and prettier-wrapped `export const POST =\n  withLogging(...)` still passes.
const bareFn = new RegExp(`export\\s+(?:async\\s+)?function\\s+(?:${METHODS})\\b`, 'g');
// Whitespace lives INSIDE the lookahead so it can't backtrack to zero and false-pass `= withLogging`.
const unwrapped = new RegExp(`export\\s+const\\s+(?:${METHODS})\\b\\s*=(?!\\s*withLogging\\b)`, 'g');
// Destructured (`export const { GET } = …`) and re-exported (`export { GET } from …`) handlers
// can never be wrapped in place, so either form is a violation.
const indirect = new RegExp(`export\\s+(?:const\\s+)?\\{[^}]*\\b(?:${METHODS})\\b[^}]*\\}`, 'g');

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (ROUTE_FILE.test(entry)) out.push(p);
  }
  return out;
}

// Blank out comments while preserving newlines so reported line numbers stay accurate.
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
}

const lineOf = (src, index) => src.slice(0, index).split('\n').length;

const files = existsSync(ROOT) ? walk(ROOT) : [];
const violations = [];
for (const file of files) {
  const src = stripComments(readFileSync(file, 'utf8'));
  for (const m of src.matchAll(bareFn)) {
    violations.push(`${file}:${lineOf(src, m.index)} — bare handler export; wrap it in withLogging()`);
  }
  for (const m of src.matchAll(unwrapped)) {
    violations.push(`${file}:${lineOf(src, m.index)} — handler not wrapped in withLogging()`);
  }
  for (const m of src.matchAll(indirect)) {
    violations.push(`${file}:${lineOf(src, m.index)} — destructured/re-exported handler; export each one as withLogging(...)`);
  }
}

if (violations.length > 0) {
  console.error('Route logging check failed — every API handler must be wrapped in withLogging():');
  for (const v of violations) console.error('  ' + v);
  process.exit(1);
}
console.log(`Route logging check passed (${files.length} route file(s)).`);
