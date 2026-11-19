#!/usr/bin/env bash
# Gate-config ratchet: gate-ratchet.sh <base-ref>. Fails when HEAD weakens a gate versus the merge base. Offline; reads tracked files through git only.
set -uo pipefail

die() {
  printf 'gate-ratchet: %s\n' "$1" >&2
  exit 2
}

base_ref=${1:-}
[ -n "$base_ref" ] || die "usage: gate-ratchet.sh <base-ref> (for example origin/main)"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
mb=$(git merge-base "$base_ref" HEAD 2>/dev/null) || die "no merge base between $base_ref and HEAD (check out with full history)"
wd=$(mktemp -d "${TMPDIR:-/tmp}/gate-ratchet.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$wd"' EXIT

# Config files whose values are ratcheted, by the kind of parser they need.
kind_of() {
  case "$1" in
    .jscpd.json | */.jscpd.json) echo jscpd ;;
    eslint.config.* | */eslint.config.*) echo eslint ;;
    vitest.config.ts | vitest.config.e2e.ts | vite.config.ts | */vitest.config.ts | */vitest.config.e2e.ts | */vite.config.ts) echo vitest ;;
    pyproject.toml | */pyproject.toml) echo pyproject ;;
    .gitleaks.toml | */.gitleaks.toml) echo gitleaks ;;
    scripts/test-budget.sh | */scripts/test-budget.sh) echo budget ;;
    .claude/gates.txt | */.claude/gates.txt) echo gates ;;
    .github/workflows/ci.yml | */.github/workflows/ci.yml | azure-pipelines.yml | */azure-pipelines.yml | azure-pipelines/templatecentral-gates.yml | */azure-pipelines/templatecentral-gates.yml) echo ci ;;
    *) echo "" ;;
  esac
}

cat > "$wd/facts.awk" <<'AWK'
function fail(m) { printf "%s\n", m > "/dev/stderr"; ERRSET = 1; exit 3 }
function emit(kind, key, val) { if (kind == "skip") return; gsub(/[\t\n]/, " ", val); printf "%s\t%s\t%s\n", kind, key, val }
function blank(k,   s) { s = ""; while (k-- > 0) s = s " "; return s }

# Copy s with comments blanked; strings are kept whole so a // or # inside one is not a comment.
function clean(s, mode,   i, n, c, c2, c3, out, e, j, ch) {
  n = length(s); out = ""; i = 1
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2); c3 = substr(s, i, 3)
    if (mode == "toml" && (c3 == "\"\"\"" || c3 == "'''")) {
      e = index(substr(s, i + 3), c3)
      if (!e) fail("unterminated multi-line string")
      out = out substr(s, i, e + 5); i += e + 5; continue
    }
    if (mode != "plain" && (c == "\"" || c == "'" || (mode == "js" && c == "`"))) {
      j = i + 1
      while (j <= n) {
        ch = substr(s, j, 1)
        if (ch == "\\" && !(mode == "toml" && c == "'")) { j += 2; continue }
        if (ch == c) break
        if (ch == "\n" && c != "`") fail("unterminated string")
        j++
      }
      if (j > n) fail("unterminated string")
      out = out substr(s, i, j - i + 1); i = j + 1; continue
    }
    if (mode == "js" && c2 == "//") { while (i <= n && substr(s, i, 1) != "\n") { out = out " "; i++ }; continue }
    if (mode == "js" && c2 == "/*") {
      e = index(substr(s, i + 2), "*/")
      if (!e) fail("unterminated comment")
      out = out blank(e + 3); i += e + 3; continue
    }
    if (mode == "toml" && c == "#") { while (i <= n && substr(s, i, 1) != "\n") { out = out " "; i++ }; continue }
    out = out c; i++
  }
  return out
}

# From the [ at index i, emit every string in the array; ARR_END is the index of its closing ].
function scan_array(i, kind, key,   n, d, c, c3, e, j, ch) {
  n = length(T); d = 0
  while (i <= n) {
    c = substr(T, i, 1); c3 = substr(T, i, 3)
    if (c == "[") d++
    else if (c == "]") { d--; if (d == 0) { ARR_END = i; return } }
    else if (TOML && (c3 == "'''" || c3 == "\"\"\"")) {
      e = index(substr(T, i + 3), c3)
      if (!e) fail("unterminated string in an array")
      emit(kind, key, substr(T, i + 3, e - 1)); i += e + 5; continue
    } else if (c == "\"" || c == "'" || c == "`") {
      j = i + 1
      while (j <= n) {
        ch = substr(T, j, 1)
        if (ch == "\\" && !(TOML && c == "'")) { j += 2; continue }
        if (ch == c) break
        j++
      }
      if (j > n) fail("unterminated string in an array")
      emit(kind, key, substr(T, i + 1, j - i - 1)); i = j + 1; continue
    }
    i++
  }
  fail("unterminated array")
}

# Leftmost match of re at or after index from; sets MS (start) and ML (length).
function find(re, from,   r) {
  if (from > length(T)) return 0
  r = match(substr(T, from), re)
  if (!r) return 0
  MS = from + RSTART - 1; ML = RLENGTH
  return 1
}
function num_in(s) { match(s, /[0-9]+([.][0-9]+)?/); return substr(s, RSTART, RLENGTH) }

# Every <name>: [ ... ] array in T becomes one set fact per string.
function arrays_named(name, kind,   from) {
  from = 1
  while (find(name "[ \t\n]*:[ \t\n]*[[]", from)) {
    scan_array(MS + ML - 1, kind, name); from = ARR_END + 1
  }
}

function do_jscpd(   from) {
  if (!find("\"threshold\"[ \t\n]*:[ \t\n]*[0-9]+([.][0-9]+)?", 1)) fail("no \"threshold\" value")
  emit("max", "duplication-threshold", num_in(substr(T, MS + 11, ML - 11)))
  from = 1
  while (find("\"ignore\"[ \t\n]*:[ \t\n]*[[]", from)) { scan_array(MS + ML - 1, "set", "ignore"); from = ARR_END + 1 }
}

function do_eslint(   from, m, name, rest, sev, seen, p, opt) {
  seen = 0; from = 1
  while (find("['\"]?[@A-Za-z0-9/_.-]+['\"]?[ \t\n]*:[ \t\n]*([[][ \t\n]*)?(['\"](off|warn|error)['\"]|[012][],} \t\n])", from)) {
    m = substr(T, MS, ML); from = MS + ML
    name = substr(m, 1, index(m, ":") - 1); gsub(/['" \t\n]/, "", name)
    rest = substr(m, index(m, ":") + 1)
    sev = (rest ~ /off|^[ \t\n]*[[]?[ \t\n]*0/) ? 0 : ((rest ~ /warn|^[ \t\n]*[[]?[ \t\n]*1/) ? 1 : 2)
    emit("sev", name, sev); seen = 1
    p = substr(T, from)
    if (match(p, /^[ \t\n]*,[ \t\n]*[0-9]+[ \t\n]*[],]/)) emit("max", name ".limit", num_in(substr(p, 1, RLENGTH)))
    else if (match(p, /^[ \t\n]*,[ \t\n]*[{][^}]*(max|maximum|threshold|complexity)[ \t\n]*:[ \t\n]*[0-9]+/)) { opt = substr(p, 1, RLENGTH); sub(/.*:[ \t\n]*/, "", opt); emit("max", name ".limit", opt) }
  }
  from = 1
  while (find("[A-Za-z0-9_]+[.]configs[.][A-Za-z0-9_.]+|[A-Za-z0-9_]+[.]recommended", from)) { emit("req", "preset", substr(T, MS, ML)); from = MS + ML; seen = 1 }
  from = 1
  while (find("globalIgnores[(][ \t\n]*[[]", from)) { scan_array(MS + ML - 1, "set", "ignore"); from = ARR_END + 1 }
  arrays_named("ignores", "set")
  if (!seen) fail("no lint rules or presets found")
}

function do_vitest(   from, m, name) {
  from = 1
  while (find("(lines|functions|branches|statements)[ \t\n]*:[ \t\n]*[0-9]+([.][0-9]+)?", from)) {
    m = substr(T, MS, ML); name = substr(m, 1, index(m, ":") - 1); gsub(/[ \t\n]/, "", name)
    emit("min", "coverage-" name, num_in(substr(m, index(m, ":"))))
    from = MS + ML
  }
  arrays_named("exclude", "set")
  nopass = "passWith" "NoTests"
  if (find(nopass "[ \t\n]*:[ \t\n]*true", 1)) emit("set", nopass, "true")
}

# Line-by-line walk of a TOML file; section is the current [header].
function toml_lines(   i, line, key, rest, p, sect, pos, kind) {
  NL = 0; p = 1
  while (p <= length(T)) {
    i = index(substr(T, p), "\n"); NL++; LO[NL] = p
    if (!i) { LT[NL] = substr(T, p); break }
    LT[NL] = substr(T, p, i - 1); p += i
  }
  sect = ""
  for (i = 1; i <= NL; i++) {
    line = LT[i]
    if (line ~ /^[ \t]*[[]/) { sect = line; gsub(/^[ \t]*[[]+[ \t]*/, "", sect); gsub(/[ \t]*[]]+[ \t]*$/, "", sect); SECTS[sect] = 1; continue }
    if (!match(line, /^[ \t]*("[^"]*"|[A-Za-z0-9_.-]+)[ \t]*=/)) continue
    key = substr(line, 1, RLENGTH - 1); gsub(/^[ \t]*|[ \t]*$/, "", key); gsub(/"/, "", key)
    rest = substr(line, RLENGTH + 1); pos = LO[i] + RLENGTH
    p = index(rest, "[")
    if (rest ~ /^[ \t]*[[]/) {
      kind = toml_kind(sect, key)
      if (kind != "") scan_array(pos + p - 1, (kind == "req" ? "req" : "set"), toml_key(sect, key))
      else scan_array(pos + p - 1, "skip", "")
      while (i < NL && LO[i + 1] <= ARR_END) i++
    } else if (rest ~ /^[ \t]*[0-9]/) {
      toml_number(sect, key, num_in(rest))
    } else if (sect ~ /allowlist/ && key ~ /^(path|paths|regex|regexes|commit|commits|stopword|stopwords)$/) {
      gsub(/^[ \t]*|[ \t]*$/, "", rest); emit("set", "allow:" key, rest)
    }
    if (key == "useDefault" && rest ~ /true/) emit("req", "extend", "useDefault")
  }
}
function toml_kind(sect, key) {
  if (MODE == "gitleaks") return (sect ~ /allowlist/ && key ~ /^(paths|regexes|commits|stopwords|files)$/) ? "set" : ""
  if (sect ~ /^tool[.]ruff([.]lint)?$/ && key ~ /^(select|extend-select)$/) return "req"
  if (sect ~ /^tool[.]ruff([.]lint)?$/ && key ~ /^(ignore|extend-ignore|exclude|extend-exclude)$/) return "set"
  if (sect ~ /^tool[.]ruff([.]lint)?[.]per-file-ignores$/) return "set"
  if (sect ~ /^tool[.]coverage[.]run$/ && key ~ /^(omit)$/) return "set"
  return ""
}
function toml_key(sect, key) {
  if (MODE == "gitleaks") return "allow:" key
  if (sect ~ /per-file-ignores$/) return "per-file-ignores:" key
  return (key ~ /select/) ? "select" : key
}
function toml_number(sect, key, v) {
  if (sect ~ /^tool[.]ruff[.]lint[.]mccabe$/ && key == "max-complexity") emit("max", "ruff-max-complexity", v)
  else if (sect ~ /^tool[.]ruff[.]lint[.]pylint$/ && key ~ /^max-/) emit("max", "ruff-pylint-" key, v)
  else if (sect ~ /^tool[.]coverage[.]report$/ && key == "fail_under") emit("min", "coverage-fail_under", v)
}

function do_pyproject(   from) {
  toml_lines()
  if (!(("tool.ruff" in SECTS) || ("tool.ruff.lint" in SECTS))) fail("no [tool.ruff] section")
  from = 1
  while (find("--cov-fail-under[= ][0-9]+([.][0-9]+)?", from)) { emit("min", "pytest-cov-fail-under", num_in(substr(T, MS + 16, ML - 16))); from = MS + ML }
}

function do_gitleaks(   n) {
  toml_lines()
  n = 0; for (s in SECTS) n++
  if (n == 0 && !find("useDefault", 1)) fail("no section or useDefault found")
}

function do_budget() {
  if (!find("TEST_BUDGET_MAX_RATIO-[0-9]+([.][0-9]+)?[}]", 1)) fail("no TEST_BUDGET_MAX_RATIO default found")
  emit("max", "test-budget-ratio", num_in(substr(T, MS + 21, ML - 21)))
}

function do_gates(   i, nl, n, line, f, c) {
  n = split(T, GL, "\n"); c = 0
  for (i = 1; i <= n; i++) {
    line = GL[i]
    if (line ~ /^[ \t]*(#|$)/) continue
    nl = split(line, f, "|")
    if (nl != 3) fail("gate line needs three | separated fields: " line)
    emit("req", "gate", f[1]); c++
    if (f[2] != "-") emit("req", "gate-in-lefthook", f[1])
    if (f[3] != "-") emit("req", "gate-in-ci", f[1])
  }
  if (!c) fail("no gate listed")
}

function do_ci(   i, n, from, L) {
  n = split(T, L, "\n"); T2 = ""
  for (i = 1; i <= n; i++) if (L[i] !~ /^[ \t]*#/) T2 = T2 L[i] "\n"
  T = T2; from = 1
  while (find("--fail-under[= ]+[0-9]+([.][0-9]+)?", from)) { emit("min", "diff-cover-fail-under", num_in(substr(T, MS + 12, ML - 12))); from = MS + ML }
}

{ T = T $0 "\n" }
END {
  if (ERRSET) exit 3
  MODE = K; TOML = (K == "pyproject" || K == "gitleaks")
  if (K == "jscpd") { T = clean(T, "plain"); do_jscpd() }
  else if (K == "eslint") { T = clean(T, "js"); do_eslint() }
  else if (K == "vitest") { T = clean(T, "js"); do_vitest() }
  else if (K == "pyproject") { T = clean(T, "toml"); do_pyproject() }
  else if (K == "gitleaks") { T = clean(T, "toml"); do_gitleaks() }
  else if (K == "budget") do_budget()
  else if (K == "gates") do_gates()
  else if (K == "ci") do_ci()
  if (ERRSET) exit 3
}
AWK

cat > "$wd/compare.awk" <<'AWK'
BEGIN { FS = "\t"; sevname[0] = "off"; sevname[1] = "warn"; sevname[2] = "error" }
function label(kind, key, v) { return (kind == "sev") ? sevname[v] : v }
{
  k = $1 SUBSEP $2
  if (FILENAME == ARGV[1]) {
    if ($1 == "set") bset[k SUBSEP $3] = 1
    else if ($1 == "req") breq[k SUBSEP $3] = 1
    else if (!(k in bagg)) { bagg[k] = $3; order[++no] = k }
    else if (($1 == "max" && $3 + 0 > bagg[k] + 0) || ($1 != "max" && $3 + 0 < bagg[k] + 0)) bagg[k] = $3
  } else {
    if ($1 == "set") { if (!((k SUBSEP $3) in hset) && !((k SUBSEP $3) in bset)) hnew[++nn] = k SUBSEP $3; hset[k SUBSEP $3] = 1 }
    else if ($1 == "req") hreq[k SUBSEP $3] = 1
    else if (!(k in hagg)) hagg[k] = $3
    else if (($1 == "max" && $3 + 0 > hagg[k] + 0) || ($1 != "max" && $3 + 0 < hagg[k] + 0)) hagg[k] = $3
  }
}
END {
  bad = 0
  for (i = 1; i <= no; i++) {
    k = order[i]; split(k, p, SUBSEP)
    if (!(k in hagg)) { printf "WEAKENED %s: %s %s was %s, now removed\n", F, p[1], p[2], label(p[1], p[2], bagg[k]); bad = 1 }
    else if (p[1] == "max" && hagg[k] + 0 > bagg[k] + 0) { printf "WEAKENED %s: limit %s was %s, now %s\n", F, p[2], bagg[k], hagg[k]; bad = 1 }
    else if (p[1] != "max" && hagg[k] + 0 < bagg[k] + 0) {
      printf "WEAKENED %s: %s %s was %s, now %s\n", F, (p[1] == "sev" ? "lint rule" : "threshold"), p[2], label(p[1], p[2], bagg[k]), label(p[1], p[2], hagg[k]); bad = 1
    }
  }
  for (i = 1; i <= nn; i++) { split(hnew[i], p, SUBSEP); printf "WEAKENED %s: new ignore or exclude in %s was absent, now '%s'\n", F, p[2], p[3]; bad = 1 }
  for (k in breq) if (!(k in hreq)) { split(k, p, SUBSEP); printf "WEAKENED %s: required %s '%s' was present, now removed\n", F, p[2], p[3]; bad = 1 }
  exit bad
}
AWK

paths=$( { git ls-tree -r --name-only "$mb"; git ls-tree -r --name-only HEAD; } 2>/dev/null | sort -u)
[ -n "$paths" ] || die "cannot list tracked files"

weakened=0
unreadable=0
checked=0
while IFS= read -r path; do
  kind=$(kind_of "$path")
  [ -n "$kind" ] || continue
  checked=$((checked + 1))
  : > "$wd/base"; : > "$wd/head"; : > "$wd/base.f"; : > "$wd/head.f"
  have_base=0; have_head=0
  if git show "$mb:$path" > "$wd/base" 2>/dev/null; then have_base=1; fi
  if git show "HEAD:$path" > "$wd/head" 2>/dev/null; then have_head=1; fi
  if [ "$have_head" -eq 0 ]; then
    printf 'WEAKENED %s: file was present at the merge base, now removed\n' "$path"
    weakened=1
    continue
  fi
  if ! msg=$(awk -v K="$kind" -f "$wd/facts.awk" "$wd/head" 2>&1 > "$wd/head.f"); then
    printf 'UNREADABLE %s: %s (fail closed)\n' "$path" "$msg"
    unreadable=1
    continue
  fi
  if [ "$have_base" -eq 1 ]; then
    if ! msg=$(awk -v K="$kind" -f "$wd/facts.awk" "$wd/base" 2>&1 > "$wd/base.f"); then
      printf 'NOTE %s: unreadable at the merge base (%s); compared with an empty baseline\n' "$path" "$msg"
      : > "$wd/base.f"
    fi
  fi
  if ! awk -v F="$path" -f "$wd/compare.awk" "$wd/base.f" "$wd/head.f"; then
    weakened=1
  fi
done <<< "$paths"

if [ "$weakened" -eq 1 ]; then
  echo "gate-ratchet: FAIL, a gate is weaker than at the merge base ($checked config files compared)"
  exit 1
fi
if [ "$unreadable" -eq 1 ]; then
  echo "gate-ratchet: FAIL, a gate config file could not be read ($checked config files compared)"
  exit 2
fi
echo "gate-ratchet: ok, no gate weaker than at the merge base ($checked config files compared)"
