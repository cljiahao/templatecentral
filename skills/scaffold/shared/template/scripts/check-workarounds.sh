#!/usr/bin/env bash
# Workaround detector: check-workarounds.sh [base-ref]. Looks only at what this change adds or removes, never at code that was already there.
# 1. Added lines that silence a tool (lint, type, coverage, sonar markers, skipped tests, "as any"). Each changed file is read whole and lexed, so strings never count as comments or code and comments never count as code.
# 2. Test files this change deletes, renames to a name no runner picks up, or empties, while the source they cover is still in the tree.
# The root eslint.config is judged by the ratchet, so only its eslint-disable markers are skipped here.
# Empty error handlers are left to the seeded lint: ruff S110 and SIM105 for Python, ESLint no-empty (eslint:recommended) for NestJS and Vite; Next.js relies on eslint-config-next, which could not be read offline.
# No waiver file and no allow comment exist: fix the cause, or change the rule in config in its own reviewed change.
# It stays bash, git and awk like every other gate script: a tokeniser from the project's own toolchain would need node_modules or python3 on every machine that runs the gate.
set -uo pipefail

arg=${1:-}
arg=${arg#refs/heads/}
head=$(git rev-parse --verify -q 'HEAD^{commit}') || { echo "check-workarounds: no commit yet; nothing to compare. Commit first, then push."; exit 0; }

base=""
if [ -n "$arg" ]; then
  git rev-parse --verify -q "$arg^{commit}" > /dev/null || { echo "check-workarounds: base '$arg' not found. Fetch with full history (fetch-depth 0) and run again." >&2; exit 1; }
  base=$arg
else
  for cand in '@{upstream}' origin/HEAD origin/main origin/master main master; do
    rev=$(git rev-parse --verify -q "$cand^{commit}" 2> /dev/null) || continue
    if [ "$rev" != "$head" ]; then base=$cand; break; fi
  done
fi
if [ -n "$base" ]; then
  from=$(git merge-base "$base" HEAD) || { echo "check-workarounds: no common history with '$base'. Fetch with full history (fetch-depth 0) and run again." >&2; exit 1; }
else
  from=$(git hash-object -t tree /dev/null)
fi

wd=$(mktemp -d "${TMPDIR:-/tmp}/workarounds.XXXXXX") || { echo "check-workarounds: cannot create a temporary directory" >&2; exit 1; }
trap 'rm -rf "$wd"' EXIT

git -c core.quotepath=off diff -U0 --no-color --no-ext-diff -M --diff-filter=d --src-prefix=a/ --dst-prefix=b/ "$from" HEAD -- '*.py' '*.pyi' '*.ts' '*.tsx' '*.mts' '*.cts' '*.js' '*.jsx' '*.mjs' '*.cjs' > "$wd/added.diff" || { echo "check-workarounds: git diff failed" >&2; exit 1; }

cat > "$wd/ranges.awk" <<'AWK'
/^diff --git / { st = 1; file = ""; next }
st == 1 && /^--- / { st = 2; next }
st == 2 && /^[+][+][+] / {
  file = substr($0, 5)
  sub(/\t$/, "", file)
  if (file ~ /^"/) { print "BAD\t" file; bad = 1; st = 0; next }
  sub(/^b\//, "", file)
  if (!(file in SEEN)) { SEEN[file] = 1; ORD[++no] = file }
  st = 3
  next
}
st == 3 && /^@@ / {
  s = $3
  sub(/^[+]/, "", s)
  c = 1
  if (index(s, ",")) { c = s; sub(/^[^,]*,/, "", c); sub(/,.*$/, "", s) }
  if (c + 0 > 0) R[file] = R[file] " " s "+" c
  next
}
END {
  for (i = 1; i <= no; i++) if (R[ORD[i]] != "") printf "%s\t%s\n", ORD[i], R[ORD[i]]
  exit bad ? 1 : 0
}
AWK

cat > "$wd/lex.awk" <<'AWK'
function blank(k,   s) { s = ""; while (k-- > 0) s = s " "; return s }
function rep(m,   t) {
  t = $0
  sub(/^[ \t]+/, "", t)
  if (length(t) > 100) t = substr(t, 1, 100) "..."
  printf "%s:%d: %s: %s\n", file, NR, m, t
  found = 1
}

# JavaScript and TypeScript line lexer: C gets the line with string, template and regex text blanked and comments removed; K gets the comment text. State carries across lines.
function lex_js(s,   i, n, c, c2, o, cm, j, ch, e, cls, keep) {
  n = length(s); o = ""; cm = ""; i = 1
  while (i <= n) {
    if (BLK) {
      e = index(substr(s, i), "*/")
      if (!e) { cm = cm substr(s, i); o = o blank(n - i + 1); i = n + 1; break }
      cm = cm substr(s, i, e - 1) " "; o = o blank(e + 1); i += e + 1; BLK = 0; continue
    }
    c = substr(s, i, 1)
    if (TXT) {
      if (c == "\\") { o = o "  "; i += 2; continue }
      if (c == "`") { TXT = 0; o = o "`"; PV = "x"; i++; continue }
      if (c == "$" && substr(s, i + 1, 1) == "{") { NT++; TB[NT] = BD; BD++; TXT = 0; o = o "${"; PV = "{"; i += 2; continue }
      o = o " "; i++; continue
    }
    c2 = substr(s, i, 2)
    if (c == " " || c == "\t") { o = o c; i++; continue }
    if (c2 == "//") { cm = cm substr(s, i + 2); i = n + 1; break }
    if (c2 == "/*") { BLK = 1; o = o "  "; i += 2; continue }
    if (c == "'" || c == "\"") {
      j = i + 1
      while (j <= n) { ch = substr(s, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == c) break; j++ }
      if (j > n) { o = o c blank(n - i); i = n + 1; PV = "x"; break }
      keep = (PV == "[" && substr(s, j + 1) ~ /^[ \t]*[]]/)
      if (keep) o = o substr(s, i, j - i + 1)
      else o = o c blank(j - i - 1) c
      i = j + 1; PV = "x"; continue
    }
    if (c == "`") { TXT = 1; o = o "`"; i++; continue }
    if (c == "/" && (PV == "" || PV ~ /^[][(,=:!&|?{;+*%<>~^-]$/)) {
      j = i + 1; cls = 0
      while (j <= n) {
        ch = substr(s, j, 1)
        if (ch == "\\") { j += 2; continue }
        if (ch == "[") cls = 1
        else if (ch == "]") cls = 0
        else if (ch == "/" && !cls) break
        j++
      }
      if (j <= n) {
        o = o "/" blank(j - i - 1) "/"; i = j + 1
        while (substr(s, i, 1) ~ /^[A-Za-z]$/) { o = o " "; i++ }
        PV = "x"; continue
      }
    }
    if (c == "{") BD++
    else if (c == "}") {
      BD--
      if (NT > 0 && BD == TB[NT]) { NT--; TXT = 1; o = o "}"; i++; continue }
    }
    o = o c; PV = (c ~ /^[A-Za-z0-9_$]$/) ? "x" : c; i++
  }
  C = o; K = cm
}

# Python line lexer: C gets the line with string text blanked and the comment removed; K gets the comment text. Triple-quoted strings carry across lines.
function lex_py(s,   i, n, c, c3, o, cm, j, ch, found) {
  n = length(s); o = ""; cm = ""; i = 1
  while (i <= n) {
    if (TQ != "") {
      j = i; found = 0
      while (j <= n) {
        ch = substr(s, j, 1)
        if (ch == "\\") { j += 2; continue }
        if (substr(s, j, 3) == TQ) { found = 1; break }
        j++
      }
      if (!found) { o = o blank(n - i + 1); i = n + 1; break }
      o = o blank(j - i) TQ; i = j + 3; TQ = ""; continue
    }
    c = substr(s, i, 1); c3 = substr(s, i, 3)
    if (c == "#") { cm = substr(s, i + 1); i = n + 1; break }
    if (c3 == "\"\"\"" || c3 == "'''") { TQ = c3; o = o c3; i += 3; continue }
    if (c == "\"" || c == "'") {
      j = i + 1
      while (j <= n) { ch = substr(s, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == c) break; j++ }
      if (j > n) { o = o c blank(n - i); i = n + 1; break }
      o = o c blank(j - i - 1) c; i = j + 1; continue
    }
    o = o c; i++
  }
  C = o; K = cm
}

# One report per added line: comment tokens first, then code.
function check_js(   kk, cs, cd) {
  kk = tolower(K); gsub(/[ \t]+/, " ", kk)
  if (kk ~ /nosonar/) { rep("NOSONAR"); return }
  if (index(kk, "eslint-disable")) { if (file !~ /^eslint[.]config[.][A-Za-z]+$/) rep("eslint-disable"); return }
  if (index(kk, "@ts-ignore")) { rep("@ts-ignore"); return }
  if (index(kk, "@ts-expect-error")) { rep("@ts-expect-error"); return }
  if (index(kk, "@ts-nocheck")) { rep("@ts-nocheck"); return }
  if (kk ~ /istanbul ignore/) { rep("istanbul ignore"); return }
  if (kk ~ /v8 ignore/) { rep("v8 ignore"); return }
  if (kk ~ /c8 ignore/) { rep("c8 ignore"); return }
  if (kk ~ /node:coverage (ignore|disable)/) { rep("node:coverage ignore"); return }
  cs = C
  if (C ~ /^[ \t]*[?]?[.]/) cs = LASTC " " C
  gsub(/[ \t]+/, " ", cs)
  cd = cs; gsub(/ ?[?]?[.] ?/, ".", cd)
  if (cd ~ /(^|[^A-Za-z0-9_$.])(it|test|describe|suite|bench)(\.[A-Za-z_$][A-Za-z0-9_$]*)*\.todo([^A-Za-z0-9_$]|$)/) { rep(".todo("); return }
  if (cd ~ /(^|[^A-Za-z0-9_$.])(it|test|describe|suite|bench)(\.[A-Za-z_$][A-Za-z0-9_$]*)*\.(skip|only|skipIf|runIf|fails)([^A-Za-z0-9_$]|$)/) { rep(".skip( / .skipIf( / .only( / .runIf( / .fails("); return }
  if (cd ~ /(^|[^A-Za-z0-9_$.])(it|test|describe|suite|bench)(\.[A-Za-z_$][A-Za-z0-9_$]*)*[ ]?\[/) { rep(".skip( / .skipIf( / .only( / .runIf( / .fails( (computed access on a test function)"); return }
  if (cs ~ /(^|[;{}]|=>) ?(xit|xdescribe|xtest)[ ]?\(/ || (TF && cs ~ /(^|[;{}]|=>) ?(fit|fdescribe)[ ]?\(/)) { rep("xit( / xdescribe( / xtest( / fit( / fdescribe("); return }
  if (cs ~ /[^A-Za-z0-9_$]as any([^A-Za-z0-9_]|$)/ || (cs ~ /^ ?any([^A-Za-z0-9_$]|$)/ && LASTC ~ /(^|[^A-Za-z0-9_$])as[ \t]*$/)) { rep("as any"); return }
  if (cs ~ /(^|[^A-Za-z0-9_$>)\]])<any>[A-Za-z0-9_$"']/) { rep("<any> cast"); return }
}

function check_py(   kk, cs) {
  kk = tolower(K); gsub(/[ \t]+/, " ", kk); gsub(/ ?: ?/, ":", kk)
  if (kk ~ /nosonar/) { rep("NOSONAR"); return }
  if (kk ~ /(^|[^a-z0-9_])noqa([^a-z0-9_]|$)/) { rep("# noqa"); return }
  if (kk ~ /(^|[^a-z0-9_])type:ignore/ || kk ~ /(^|[^a-z0-9_])(pyre-ignore|pyre-fixme|pytype:disable)/) { rep("# type: ignore"); return }
  if (kk ~ /mypy:(ignore-errors|disable-error-code)/) { rep("# mypy: ignore-errors"); return }
  if (kk ~ /pyright:(ignore|basic|off)/) { rep("# pyright: ignore"); return }
  if (kk ~ /pylint:(disable|skip-file)/) { rep("# pylint: disable"); return }
  if (kk ~ /(^|[^a-z0-9_])nosec/) { rep("# nosec"); return }
  if (kk ~ /pragma:no ?(cover|branch)/) { rep("# pragma: no cover"); return }
  cs = C; gsub(/[ \t]+/, " ", cs)
  if (cs ~ /(^|[^A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_.]*[.])?mark[.](skip|skipif|xfail)([^A-Za-z0-9_]|$)/) { rep("@pytest.mark.skip / skipif / xfail"); return }
  if (cs ~ /(^|[^A-Za-z0-9_])pytest[.](skip|xfail)[ ]?\(/) { rep("pytest.skip( / pytest.xfail("); return }
  if (cs ~ /(^|[^A-Za-z0-9_.])(pytest[.])?importorskip[ ]?\(/) { rep("pytest.importorskip("); return }
  if (cs ~ /(^|[^A-Za-z0-9_])unittest[.](skip|skipIf|skipUnless|expectedFailure)([^A-Za-z0-9_]|$)/ || cs ~ /^ ?@ ?(skip|skipIf|skipUnless|expectedFailure)([^A-Za-z0-9_]|$)/ || cs ~ /[.]skipTest[ ]?\(/) { rep("unittest.skip / skipIf / skipUnless / skipTest"); return }
}

function count_line(   cs, cd) {
  if (py) { if (C ~ /^[ \t]*(async[ \t]+)?def[ \t]+test/) NTEST++; return }
  cs = C; gsub(/[ \t]+/, " ", cs)
  cd = cs; gsub(/ ?[?]?[.] ?/, ".", cd)
  if (cd ~ /(^|[^A-Za-z0-9_$.])(it|test)(\.[A-Za-z_$][A-Za-z0-9_$]*)*[ ]?\(/) NTEST++
}

BEGIN {
  n = split(ranges, RR, " ")
  for (k = 1; k <= n; k++) {
    split(RR[k], rc, "+")
    for (l = rc[1] + 0; l < rc[1] + rc[2]; l++) ADDED[l] = 1
  }
  TF = (file ~ /[.](test|spec)[.][^\/]*$/ || file ~ /e2e-spec/ || file ~ /(^|\/)(test|tests|__tests__|e2e)\//)
}
{
  if (py) lex_py($0); else lex_js($0)
  if (mode == "count") count_line()
  else if (NR in ADDED) { if (py) check_py(); else check_js() }
  if (C ~ /[^ \t]/) LASTC = C
}
END {
  if (mode == "count") { print NTEST + 0; exit 0 }
  exit found ? 1 : 0
}
AWK

if ! awk -f "$wd/ranges.awk" "$wd/added.diff" > "$wd/ranges.txt"; then
  echo "check-workarounds: a changed file has a quoted path that cannot be read safely:" >&2
  grep '^BAD' "$wd/ranges.txt" >&2
  exit 1
fi

status=0
: > "$wd/markers.txt"
while IFS=$'\t' read -r f r || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  git show "HEAD:$f" > "$wd/cur" 2> /dev/null || { echo "check-workarounds: cannot read $f at HEAD" >&2; exit 1; }
  py=0
  case "$f" in *.py | *.pyi) py=1 ;; esac
  awk -v file="$f" -v ranges="$r" -v py="$py" -v mode=scan -f "$wd/lex.awk" "$wd/cur" >> "$wd/markers.txt" || status=1
done < "$wd/ranges.txt"
if [ -s "$wd/markers.txt" ]; then
  cat "$wd/markers.txt"
  echo "check-workarounds: this change adds the markers listed above, each one silences a tool instead of fixing the cause." >&2
  echo "Fix the cause. If the rule is wrong for the whole project, change the rule in config (eslint.config, pyproject.toml, vitest or vite config) in its own reviewed change." >&2
  status=1
fi

# Sets stem, ext and pat for a test file name and returns 0; returns 1 for any other name.
test_stem() {
  local name=${1##*/} base
  case "$name" in
    *.test.ts | *.test.tsx | *.test.mts | *.test.cts | *.test.js | *.test.jsx | *.test.mjs | *.test.cjs | *.spec.ts | *.spec.tsx | *.spec.mts | *.spec.cts | *.spec.js | *.spec.jsx | *.spec.mjs | *.spec.cjs | *.e2e-spec.ts | *.e2e-spec.js)
      base=${name%.*}
      stem=${base%.test}
      stem=${stem%.spec}
      stem=${stem%.e2e-spec}
      ext=${name##*.}
      ;;
    test_*.py)
      stem=${name#test_}
      stem=${stem%.py}
      ext=py
      ;;
    *_test.py)
      stem=${name%_test.py}
      ext=py
      ;;
    *) return 1 ;;
  esac
  case "$ext" in
    ts | tsx | mts | cts) pat="/${stem}[.](ts|tsx|mts|cts)$" ;;
    js | jsx | mjs | cjs) pat="/${stem}[.](js|jsx|mjs|cjs)$" ;;
    *) pat="/${stem}[.]py$" ;;
  esac
  return 0
}

# Prints the source file a test file covers, when one is still in the tree.
covered_source() {
  local s
  test_stem "$1" || return 1
  s=$(sed 's@^@/@' "$wd/tree.txt" | grep -E "$pat" | grep -vE '(^|/)(test|tests|__tests__)/|[.](test|spec)[.]|/test_|_test[.]py$' | head -n 1)
  [ -n "$s" ] || return 1
  printf '%s\n' "${s#/}"
}

git diff --name-only --no-color -M --diff-filter=D "$from" HEAD > "$wd/deleted.txt" || { echo "check-workarounds: git diff failed" >&2; exit 1; }
git diff --name-status --no-color -M --diff-filter=AMR "$from" HEAD > "$wd/changed.txt" || { echo "check-workarounds: git diff failed" >&2; exit 1; }
git ls-files > "$wd/tree.txt" || { echo "check-workarounds: git ls-files failed" >&2; exit 1; }
: > "$wd/orphans.txt"
while IFS= read -r f || [ -n "$f" ]; do
  src=$(covered_source "$f") || continue
  printf '%s (covers %s)\n' "$f" "$src" >> "$wd/orphans.txt"
done < "$wd/deleted.txt"
while IFS=$'\t' read -r st p1 p2 || [ -n "$st" ]; do
  [ -n "$st" ] || continue
  cur=$p1
  case "$st" in
    R*)
      cur=$p2
      if test_stem "$p1" && ! test_stem "$p2" && src=$(covered_source "$p1"); then
        printf '%s (renamed to %s, a name no test runner picks up; covers %s)\n' "$p1" "$p2" "$src" >> "$wd/orphans.txt"
      fi
      ;;
  esac
  test_stem "$cur" || continue
  git show "HEAD:$cur" > "$wd/cur" 2> /dev/null || continue
  py=0
  case "$cur" in *.py) py=1 ;; esac
  n=$(awk -v file="$cur" -v ranges="" -v py="$py" -v mode=count -f "$wd/lex.awk" "$wd/cur") || n=0
  if [ "$n" -eq 0 ]; then printf '%s (no test call left in the file)\n' "$cur" >> "$wd/orphans.txt"; fi
done < "$wd/changed.txt"
if [ -s "$wd/orphans.txt" ]; then
  while IFS= read -r l; do printf 'removed test: %s\n' "$l"; done < "$wd/orphans.txt"
  echo "check-workarounds: this change deletes, renames away or empties the test files listed above while the source they cover is still in the tree." >&2
  echo "Restore the test file, or remove the source it covers in the same change." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then echo "check-workarounds: no suppression markers added and no covering tests removed"; fi
exit "$status"
