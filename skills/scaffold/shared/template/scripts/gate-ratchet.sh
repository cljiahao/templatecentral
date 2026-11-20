#!/usr/bin/env bash
# Gate-config ratchet: gate-ratchet.sh <base-ref>. Fails when HEAD weakens a gate versus the merge base. Offline; runs the merge-base copy of itself and reads tracked files through git only.
set -uo pipefail

die() {
  printf 'gate-ratchet: %s\n' "$1" >&2
  exit 2
}

base_ref=${1:-}
if [ "$base_ref" = auto ]; then
  base_ref=""
  for cand in '@{upstream}' origin/HEAD origin/main origin/master; do
    if git rev-parse --verify -q "$cand^{commit}" >/dev/null 2>&1; then base_ref=$cand; break; fi
  done
  if [ -z "$base_ref" ]; then echo "gate-ratchet: no base branch found (no upstream, origin/main or origin/master), so nothing to compare; CI runs this gate on the pull request"; exit 0; fi
fi
[ -n "$base_ref" ] || die "usage: gate-ratchet.sh <base-ref|auto> (for example origin/main; auto picks the upstream or origin/main)"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
mb=$(git merge-base "$base_ref" HEAD 2>/dev/null) || die "no merge base between $base_ref and HEAD (check out with full history)"
wd=$(mktemp -d "${TMPDIR:-/tmp}/gate-ratchet.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$wd"' EXIT

# A PR must not rewrite the checker that judges it: run the merge-base copy when the base has one.
if [ -z "${GATE_RATCHET_REEXEC:-}" ] && git show "$mb:scripts/gate-ratchet.sh" > "$wd/base-ratchet.sh" 2>/dev/null; then
  GATE_RATCHET_REEXEC=1 bash "$wd/base-ratchet.sh" "$base_ref"
  exit $?
fi

# Files compared by parsed values, by the kind of parser they need; guard files are compared by content only.
kind_of() {
  case "$1" in
    .jscpd.json | */.jscpd.json) echo jscpd ;;
    eslint.config.* | */eslint.config.*) echo eslint ;;
    vitest.config.* | vite.config.* | */vitest.config.* | */vite.config.*) echo vitest ;;
    pyproject.toml | */pyproject.toml) echo pyproject ;;
    .gitleaks.toml | */.gitleaks.toml) echo gitleaks ;;
    scripts/test-budget.sh | */scripts/test-budget.sh) echo budget ;;
    .claude/gates.txt | */.claude/gates.txt) echo gates ;;
    .claude/registry-hosts.txt | */.claude/registry-hosts.txt) echo hosts ;;
    pnpm-workspace.yaml | */pnpm-workspace.yaml) echo pnpmws ;;
    .github/dependabot.yml | */.github/dependabot.yml) echo dependabot ;;
    .npmrc | */.npmrc) echo npmrc ;;
    .hadolint.yaml | */.hadolint.yaml | .hadolint.yml | */.hadolint.yml) echo hadolint ;;
    .github/workflows/ci.yml | */.github/workflows/ci.yml | azure-pipelines.yml | */azure-pipelines.yml | azure-pipelines/templatecentral-gates.yml | */azure-pipelines/templatecentral-gates.yml) echo ci ;;
    scripts/gate-ratchet.sh | */scripts/gate-ratchet.sh | scripts/check-supply-chain.sh | */scripts/check-supply-chain.sh | scripts/check-workflows.sh | */scripts/check-workflows.sh | scripts/check-env-example.sh | */scripts/check-env-example.sh | scripts/check-dockerfile.sh | */scripts/check-dockerfile.sh | scripts/check-secret-scanner.sh | */scripts/check-secret-scanner.sh | scripts/check-workarounds.sh | */scripts/check-workarounds.sh | scripts/scan-secrets.sh | */scripts/scan-secrets.sh | .claude/ci-gates.sh | */.claude/ci-gates.sh | .claude/verify-harness.sh | */.claude/verify-harness.sh | .claude/hooks/protect-files.sh | */.claude/hooks/protect-files.sh | lefthook.yml | */lefthook.yml) echo guard ;;
    *) echo "" ;;
  esac
}

# True when the merge base tracked this exact path.
base_has() { printf '%s\n' "$base_paths" | grep -Fxq -- "$1"; }

# A new config file with one of these names competes with a ratcheted config that the merge base already had; prints why and returns 0.
shadow_reason() {
  local name fam fams dir f
  name=${1##*/}
  dir=""
  case "$1" in */*) dir=${1%/*}/ ;; esac
  case "$name" in
    ruff.toml | .ruff.toml) if base_has "${dir}pyproject.toml"; then echo "ruff reads it instead of pyproject.toml"; return 0; fi ;;
    .coveragerc) if base_has "${dir}pyproject.toml"; then echo "coverage reads it instead of pyproject.toml"; return 0; fi ;;
    .gitleaksignore) if base_has "${dir}.gitleaks.toml"; then echo "gitleaks reads it besides .gitleaks.toml"; return 0; fi ;;
    .eslintignore) if printf '%s\n' "$base_paths" | grep -Eq "^${dir}eslint[.]config[.][^/]*$"; then echo "it adds ignores besides eslint.config"; return 0; fi ;;
    jscpd.json | .jscpdrc | .jscpdrc.json | .jscpd.yml | .jscpd.yaml | .jscpd.js) if base_has "${dir}.jscpd.json"; then echo "jscpd may read it instead of .jscpd.json"; return 0; fi ;;
    eslint.config.* | vitest.config.* | vite.config.* | jest.config.*)
      fam=${name%%.config.*}
      case "$fam" in vite | vitest) fams="vite vitest" ;; *) fams=$fam ;; esac
      for f in $fams; do
        if printf '%s\n' "$base_paths" | awk -v pre="${dir}${f}.config." 'index($0, pre) == 1 && index(substr($0, length(pre) + 1), "/") == 0 { hit = 1 } END { exit !hit }'; then
          echo "a $f.config.* file already exists, and only one is read"
          return 0
        fi
      done
      ;;
  esac
  return 1
}

# CI file text with the tracked coverage number masked and only a full-SHA action pin or a numeric Azure task version masked, so a SHA-to-SHA bump is not a change but a move to a tag or branch is.
mask_ci() {
  sed -E -e 's/--fail-under[= ]+[0-9]+([.][0-9]+)?/--fail-under=N/g' \
    -e 's/(uses:[[:space:]]*[^@[:space:]]+)@[0-9a-f]{40}([[:space:]]+#.*)?[[:space:]]*$/\1@V/' \
    -e 's/(task:[[:space:]]*[^@[:space:]]+)@[0-9]+[[:space:]]*$/\1@V/'
}

# Content check for files whose behaviour is not a parsed value; tracked numbers are masked because the parsed comparison covers them.
content_ok() {
  case "$1" in
    guard) cmp -s "$wd/base" "$wd/head" ;;
    budget)
      sed -E 's/TEST_BUDGET_MAX_RATIO-[0-9]+([.][0-9]+)?\}/TEST_BUDGET_MAX_RATIO-N}/' "$wd/base" > "$wd/base.m"
      sed -E 's/TEST_BUDGET_MAX_RATIO-[0-9]+([.][0-9]+)?\}/TEST_BUDGET_MAX_RATIO-N}/' "$wd/head" > "$wd/head.m"
      cmp -s "$wd/base.m" "$wd/head.m"
      ;;
    ci)
      mask_ci < "$wd/base" > "$wd/base.m"
      mask_ci < "$wd/head" > "$wd/head.m"
      cmp -s "$wd/base.m" "$wd/head.m"
      ;;
    gates)
      local l
      while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in '' | '#'*) continue ;; esac
        grep -Fxq -- "$l" "$wd/head" || return 1
      done < "$wd/base"
      return 0
      ;;
    *) return 0 ;;
  esac
}

cat > "$wd/facts.awk" <<'AWK'
function fail(m) { printf "%s\n", m > "/dev/stderr"; ERRSET = 1; exit 3 }
function emit(kind, key, val) { if (kind == "skip") return; gsub(/[\t\n]/, " ", key); gsub(/[\t\n]/, " ", val); printf "%s\t%s\t%s\n", kind, key, val }
function blank(k,   s) { s = ""; while (k-- > 0) s = s " "; return s }
function plain_num(v) { return v ~ /^[0-9]+([.][0-9]+)?$/ }

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

# From the [ or { at index i, emit every string in the array or table; ARR_END is the index of its closing bracket.
function scan_array(i, kind, key,   n, d, c, c3, e, j, ch) {
  n = length(T); d = 0
  while (i <= n) {
    c = substr(T, i, 1); c3 = substr(T, i, 3)
    if (c == "[" || c == "{") d++
    else if (c == "]" || c == "}") { d--; if (d == 0) { ARR_END = i; return } }
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

# The value text starting at index p, up to the next comma, closing bracket or line end.
function tok(p,   n, c, s) {
  n = length(T); s = ""
  while (p <= n) { c = substr(T, p, 1); if (c == "," || c == "}" || c == "]" || c == "\n") break; s = s c; p++ }
  gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s)
  return s
}

function sq(s) { gsub(/[ \t\n]+/, " ", s); gsub(/^ | $/, "", s); return s }

# Value text from index p up to the comma or closing bracket that ends it at depth 0; VEND is the index of that terminator.
function vtext(p,   n, c, d, j, ch, s0) {
  n = length(T); d = 0; s0 = p
  while (p <= n) {
    c = substr(T, p, 1)
    if (c == "\"" || c == "'" || c == "`") {
      j = p + 1
      while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == c) break; j++ }
      p = j + 1; continue
    }
    if (c == "(" || c == "[" || c == "{") d++
    else if (c == ")" || c == "]" || c == "}") { if (d == 0) break; d-- }
    else if (c == "," && d == 0) break
    p++
  }
  VEND = p
  return sq(substr(T, s0, p - s0))
}

# Every <name>: [ ... ] array in T becomes one fact of the given kind per string.
function arrays_named(name, kind,   from) {
  from = 1
  while (find(name "[ \t\n]*:[ \t\n]*[[]", from)) {
    scan_array(MS + ML - 1, kind, name); from = ARR_END + 1
  }
}

# A JSON object may not repeat a key: parsers disagree on which copy wins.
function json_dups(   i, n, c, d, st, nid, j, ch, key, tail) {
  n = length(T); i = 1; d = 0; nid = 0
  while (i <= n) {
    c = substr(T, i, 1)
    if (c == "{") { d++; nid++; st[d] = nid }
    else if (c == "}") d--
    else if (c == "\"") {
      j = i + 1
      while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
      key = substr(T, i + 1, j - i - 1); tail = substr(T, j + 1, 200)
      if (d > 0 && tail ~ /^[ \t\n]*:/) {
        if ((st[d] SUBSEP key) in JSEEN) fail("duplicate JSON key \"" key "\"")
        JSEEN[st[d] SUBSEP key] = 1
      }
      i = j
    }
    i++
  }
}

# Top-level keys of the JSON object: each key not in KN (tracked or neutral) becomes a cfg fact, so an unknown setting that changes is a finding.
function json_top(   p, n, j, ch, key, v) {
  n = length(T); p = index(T, "{") + 1
  while (p > 1 && p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) != "\"") break
    j = p + 1
    while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
    key = substr(T, p + 1, j - p - 1); p = j + 1
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    v = vtext(p); p = VEND
    if (!(key in KN)) emit("cfg", key, v)
  }
}

# A numeric JSON key that must be a plain decimal; absent means def (a default the tool applies) when def is set.
function jnum(key, fact, def,   v) {
  if (find("\"" key "\"[ \t\n]*:[ \t\n]*", 1)) {
    v = tok(MS + ML)
    if (!plain_num(v)) fail("\"" key "\" is not a plain decimal literal: " v)
    emit("max", fact, v)
  } else if (def != "") emit("max", fact, def)
}

function do_jscpd(   from, v, i, kl) {
  json_dups()
  split("threshold minTokens minLines path gitignore skipLocal ignore reporters output silent verbose absolute blame", kl, " ")
  for (i in kl) KN[kl[i]] = 1
  json_top()
  if (!find("\"threshold\"[ \t\n]*:[ \t\n]*", 1)) fail("no \"threshold\" value")
  v = tok(MS + ML)
  if (!plain_num(v)) fail("\"threshold\" is not a plain decimal literal: " v)
  emit("max", "duplication-threshold", v)
  jnum("minTokens", "jscpd-minTokens", 50)
  jnum("minLines", "jscpd-minLines", 5)
  if (find("\"path\"[ \t\n]*:[ \t\n]*[[]", 1)) scan_array(MS + ML - 1, "req", "path")
  else emit("req", "path", "(cwd)")
  if (find("\"gitignore\"[ \t\n]*:[ \t\n]*true", 1)) emit("set", "flag", "gitignore")
  if (find("\"skipLocal\"[ \t\n]*:[ \t\n]*true", 1)) emit("set", "flag", "skipLocal")
  from = 1
  while (find("\"ignore\"[ \t\n]*:[ \t\n]*[[]", from)) { scan_array(MS + ML - 1, "set", "ignore"); from = ARR_END + 1 }
}

# Brace structure of T: OPN opens in order, CL their closes, PAR the enclosing open; strings are skipped.
function brace_map(   i, n, c, j, ch, sp) {
  n = length(T); NO = 0; sp = 0; i = 1
  while (i <= n) {
    c = substr(T, i, 1)
    if (c == "'" || c == "\"" || c == "`") {
      j = i + 1
      while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == c) break; j++ }
      i = j + 1; continue
    }
    if (c == "{") { NO++; OPN[NO] = i; sp++; STK[sp] = i; PAR[i] = (sp > 1) ? STK[sp - 1] : 0; CL[i] = n + 1 }
    else if (c == "}" && sp > 0) { CL[STK[sp]] = i; sp-- }
    i++
  }
}

# The files: array of the config object holding the rules block that contains index p, or "global".
function scope_of(p,   k, o, best, par, txt, s) {
  best = 0
  for (k = 1; k <= NO; k++) { o = OPN[k]; if (o < p && CL[o] > p) best = o }
  if (!best) return "global"
  par = PAR[best]
  if (!par) return "global"
  txt = substr(T, par, CL[par] - par + 1)
  if (match(txt, /files[ \t\n]*:[ \t\n]*[[][^]]*[]]/)) { s = substr(txt, RSTART, RLENGTH); gsub(/[ \t\n]+/, "", s); return s }
  return "global"
}

function occurrences(s, needle,   c, p) {
  c = 0
  while ((p = index(s, needle)) > 0) { c++; s = substr(s, p + length(needle)) }
  return c
}

# The entries of the exported config array: spreads and bare presets by text, object entries by count.
function eslint_entries(   p, id, v, nobj) {
  p = 0
  if (match(T, /export[ \t\n]+default[ \t\n]+[A-Za-z_$][A-Za-z0-9_$]*[ \t\n]*;/)) {
    id = substr(T, RSTART, RLENGTH); sub(/^export[ \t\n]+default[ \t\n]+/, "", id); sub(/[ \t\n]*;$/, "", id)
    if (find("(const|let|var)[ \t\n]+" id "[ \t\n]*=[ \t\n]*[[]", 1)) p = MS + ML
  } else if (match(T, /export[ \t\n]+default[ \t\n]+[[]/)) p = RSTART + RLENGTH
  else if (match(T, /export[ \t\n]+default[ \t\n]+[^(;]*[(][ \t\n]*[[]?/)) p = RSTART + RLENGTH
  if (!p) fail("cannot find the exported config array")
  nobj = 0
  while (p <= length(T)) {
    while (p <= length(T) && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) ~ /[])]/) break
    v = vtext(p)
    if (v ~ /^[{]/) nobj++
    else emit("req", "entry", v)
    if (substr(T, VEND, 1) != ",") break
    p = VEND + 1
  }
  emit("min", "eslint-config-objects", nobj)
}

function do_eslint(   from, m, name, rest, sev, seen, p, opt, sc, key, lim) {
  seen = 0; from = 1
  brace_map()
  while (find("['\"]?[@A-Za-z0-9/_.-]+['\"]?[ \t\n]*:[ \t\n]*([[][ \t\n]*)?(['\"](off|warn|error)['\"]|[012][],} \t\n])", from)) {
    sc = scope_of(MS)
    m = substr(T, MS, ML); from = MS + ML
    name = substr(m, 1, index(m, ":") - 1); gsub(/['" \t\n]/, "", name)
    rest = substr(m, index(m, ":") + 1)
    sev = (rest ~ /off|^[ \t\n]*[[]?[ \t\n]*0/) ? 0 : ((rest ~ /warn|^[ \t\n]*[[]?[ \t\n]*1/) ? 1 : 2)
    key = (sc == "global") ? name : name "#" sc
    lim = (sc == "global") ? name ".limit" : name ".limit#" sc
    emit("sev", key, sev); seen = 1
    p = substr(T, from)
    if (match(p, /^[ \t\n]*,[ \t\n]*[0-9]+[ \t\n]*[],]/)) emit("max", lim, num_in(substr(p, 1, RLENGTH)))
    else if (match(p, /^[ \t\n]*,[ \t\n]*[{][^}]*(max|maximum|threshold|complexity)[ \t\n]*:[ \t\n]*[0-9]+/)) { opt = substr(p, 1, RLENGTH); sub(/.*:[ \t\n]*/, "", opt); emit("max", lim, opt) }
  }
  from = 1
  while (find("[A-Za-z0-9_]+[.]configs[.][A-Za-z0-9_.]+|[A-Za-z0-9_]+[.]recommended", from)) { emit("req", "preset", substr(T, MS, ML)); from = MS + ML; seen = 1 }
  from = 1
  while (find("globalIgnores[(][ \t\n]*[[]", from)) { scan_array(MS + ML - 1, "set", "ignore"); from = ARR_END + 1 }
  arrays_named("ignores", "set")
  emit("max", "eslint-disable-comments", occurrences(T0, "eslint-disable") - occurrences(T, "eslint-disable"))
  if (!seen) fail("no lint rules or presets found")
  eslint_entries()
}

# Keys of the coverage object at index p (just after its brace): tracked keys are read elsewhere, neutral ones ignored, the rest become cfg facts.
function cov_walk(p, pre,   n, k, kn, v, e) {
  n = length(T)
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (p > n || substr(T, p, 1) == "}") return
    if (match(substr(T, p), /^(["'][^"']*["']|[A-Za-z0-9_$]+)[ \t\n]*:[ \t\n]*/)) {
      k = substr(T, p, RLENGTH); p += RLENGTH
      kn = k; sub(/[ \t\n]*:[ \t\n]*$/, "", kn); gsub(/["']/, "", kn)
      v = vtext(p); e = VEND
      if (pre == "" && kn == "thresholds" && v ~ /^[{]/) cov_walk(p + 1, "thresholds.")
      else if (pre == "" && kn ~ /^(include|exclude|provider|reporter|reportsDirectory|reportOnFailure)$/) { }
      else if (pre == "thresholds." && kn ~ /^(lines|functions|branches|statements)$/) { }
      else emit("cfg", "coverage." pre kn, v)
      p = e
    } else {
      v = vtext(p); emit("cfg", "coverage." pre "?", v); p = VEND
    }
  }
}

function do_vitest(   from, m, name, v) {
  if (find("coverage[ \t\n]*:[ \t\n]*[{]", 1)) cov_walk(MS + ML, "")
  from = 1
  while (find("(lines|functions|branches|statements)[ \t\n]*:[ \t\n]*", from)) {
    m = substr(T, MS, ML); name = substr(m, 1, index(m, ":") - 1); gsub(/[ \t\n]/, "", name)
    v = tok(MS + ML)
    if (!plain_num(v)) fail("coverage threshold " name " is not a plain decimal literal: " v)
    emit("min", "coverage-" name, v)
    from = MS + ML
  }
  arrays_named("exclude", "set")
  arrays_named("include", "req")
  nopass = "passWith" "NoTests"
  if (find(nopass "[ \t\n]*:[ \t\n]*true", 1)) emit("set", nopass, "true")
}

# Line-by-line walk of a TOML file; dotted keys are folded into their section so a.b.c = v reads like [a.b] c = v.
function toml_lines(   i, line, raw, rest, p, sect, csect, pos, kind, s2, k2, n, parts, j, pre, v, known, vtxt, d3, q, e, qe) {
  NL = 0; p = 1
  while (p <= length(T)) {
    i = index(substr(T, p), "\n"); NL++; LO[NL] = p
    if (!i) { LT[NL] = substr(T, p); break }
    LT[NL] = substr(T, p, i - 1); p += i
  }
  sect = ""
  for (i = 1; i <= NL; i++) {
    line = LT[i]
    if (line ~ /^[ \t]*[[]/) {
      sect = line; gsub(/^[ \t]*[[]+[ \t]*/, "", sect); gsub(/[ \t]*[]]+[ \t]*$/, "", sect); SECTS[sect] = 1
      csect = sect
      if (line ~ /^[ \t]*[[][[]/) {
        HC[sect]++; csect = sect "#" HC[sect]
        if (cfg_scope(sect) && !(sect ~ /allowlist/)) emit("cfg", "[[" csect "]]", "")
      }
      continue
    }
    if (!match(line, /^[ \t]*([A-Za-z0-9_.-]+[.])?("[^"]*"|[A-Za-z0-9_.-]+)[ \t]*=/)) continue
    raw = substr(line, 1, RLENGTH - 1); gsub(/^[ \t]*/, "", raw); gsub(/[ \t]*$/, "", raw)
    rest = substr(line, RLENGTH + 1); pos = LO[i] + RLENGTH
    s2 = sect; k2 = raw
    if (raw !~ /^"/ && match(raw, /[.]"/)) {
      pre = substr(raw, 1, RSTART - 1); k2 = substr(raw, RSTART + 1)
      s2 = (sect == "") ? pre : sect "." pre
    } else if (raw !~ /"/ && raw ~ /[.]/) {
      n = split(raw, parts, "."); k2 = parts[n]; pre = parts[1]
      for (j = 2; j < n; j++) pre = pre "." parts[j]
      s2 = (sect == "") ? pre : sect "." pre
    }
    gsub(/"/, "", k2)
    v = rest; gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
    known = 0; vtxt = v
    if (rest ~ /^[ \t]*[[{]/) {
      kind = toml_kind(s2, k2)
      p = index(rest, (rest ~ /^[ \t]*[[]/) ? "[" : "{")
      scan_array(pos + p - 1, (kind == "" ? "skip" : (kind == "req" ? "req" : "set")), (kind == "" ? "" : toml_key(s2, k2)))
      vtxt = sq(substr(T, pos + p - 1, ARR_END - (pos + p - 1) + 1)); known = (kind != "")
      while (i < NL && LO[i + 1] <= ARR_END) i++
    } else if (rest ~ /^[ \t]*('''|""")/) {
      d3 = (rest ~ /^[ \t]*'''/) ? "'''" : "\"\"\""
      q = pos + index(rest, d3) - 1
      e = index(substr(T, q + 3), d3)
      if (!e) fail("unterminated multi-line string")
      qe = q + e + 4; vtxt = sq(substr(T, q, qe - q + 1))
      while (i < NL && LO[i + 1] <= qe) i++
    } else if (toml_track(s2, k2)) {
      if (!plain_num(v)) fail(k2 " is not a plain decimal literal: " v)
      emit(TK, TN, v); known = 1
    } else if (MODE == "gitleaks" && (s2 ~ /allowlist/ || s2 == "extend") && k2 ~ /^(path|paths|regex|regexes|commit|commits|stopword|stopwords|url)$/) {
      emit("set", "allow:" k2, v); known = 1
    } else if (MODE == "pyproject" && s2 ~ /^tool[.]ruff$/ && k2 == "extend") {
      emit("set", "ruff-extend", v); known = 1
    }
    if (!known && cfg_scope(s2) && !cfg_neutral(s2, k2)) emit("cfg", csect "|" raw, vtxt)
    if (k2 == "useDefault" && rest ~ /true/) emit("req", "extend", "useDefault")
  }
}
# Tables whose every key must be known: all of .gitleaks.toml, and the ruff and coverage tables of pyproject.toml.
function cfg_scope(s) {
  if (MODE == "gitleaks") return 1
  return (s ~ /^tool[.](ruff|coverage)([.]|$)/)
}
# Keys that change nothing about what a gate catches.
function cfg_neutral(s, k) {
  if (MODE == "gitleaks") return (k ~ /^(title|description)$/ || (s == "extend" && k == "useDefault"))
  if (s ~ /^tool[.]ruff[.]format/ || s ~ /^tool[.]ruff[.]lint[.]isort/) return 1
  if (s == "tool.ruff" && k ~ /^(line-length|indent-width|target-version|src|output-format|cache-dir)$/) return 1
  if (s == "tool.coverage.report" && k ~ /^(show_missing|skip_covered|precision)$/) return 1
  return 0
}
function toml_kind(s, k) {
  if (MODE == "gitleaks") {
    if (s ~ /allowlist/ && k ~ /^(paths|regexes|commits|stopwords|files)$/) return "set"
    if (s == "extend" && k == "disabledRules") return "set"
    return ""
  }
  if (s ~ /^tool[.]ruff([.]lint)?$/ && k ~ /^(select|extend-select)$/) return "req"
  if (s ~ /^tool[.]ruff([.]lint)?$/ && k ~ /^(ignore|extend-ignore|exclude|extend-exclude|per-file-ignores|extend-per-file-ignores)$/) return "set"
  if (s ~ /^tool[.]ruff([.]lint)?[.](extend-)?per-file-ignores$/) return "set"
  if (s ~ /^tool[.]coverage[.]run$/ && k == "omit") return "set"
  return ""
}
function toml_key(s, k) {
  if (MODE == "gitleaks") return (s == "extend") ? k : "allow:" k
  if (s ~ /per-file-ignores$/) return "per-file-ignores:" k
  if (k ~ /per-file-ignores$/) return "per-file-ignores"
  return (k ~ /select/) ? "select" : k
}
function toml_track(s, k) {
  if (s ~ /^tool[.]ruff[.]lint[.]mccabe$/ && k == "max-complexity") { TK = "max"; TN = "ruff-max-complexity"; return 1 }
  if (s ~ /^tool[.]ruff[.]lint[.]pylint$/ && k ~ /^max-/) { TK = "max"; TN = "ruff-pylint-" k; return 1 }
  if (s ~ /^tool[.]coverage[.]report$/ && k == "fail_under") { TK = "min"; TN = "coverage-fail_under"; return 1 }
  return 0
}

# A number after a flag must end at whitespace, a quote or the line end.
function flag_end_ok(c) { return (c == "" || c == " " || c == "\t" || c == "\n" || c == "\"" || c == "'" || c == "\\") }

function do_pyproject(   from) {
  toml_lines()
  if (!(("tool.ruff" in SECTS) || ("tool.ruff.lint" in SECTS))) fail("no [tool.ruff] section")
  from = 1
  while (find("--cov-fail-under[= ][0-9]+([.][0-9]+)?", from)) {
    if (!flag_end_ok(substr(T, MS + ML, 1))) fail("--cov-fail-under is not a plain decimal literal")
    emit("min", "pytest-cov-fail-under", num_in(substr(T, MS + 16, ML - 16))); from = MS + ML
  }
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

function do_hosts(   i, n, L, line) {
  n = split(T, L, "\n")
  for (i = 1; i <= n; i++) {
    line = L[i]; gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == "" || line ~ /^#/) continue
    emit("set", "registry-host", tolower(line))
  }
}

function yes(v) { return v ~ /^[Tt][Rr][Uu][Ee]$/ }
function no(v) { return v ~ /^[Ff][Aa][Ll][Ss][Ee]$/ }
function norm_yaml(line) {
  sub(/\r$/, "", line)
  sub(/[ \t]+#.*$/, "", line)
  if (line ~ /^["'][A-Za-z]+["'][ \t]*:/) { sub(/^["']/, "", line); sub(/["'][ \t]*:/, ":", line) }
  return line
}
function do_pnpmws(   i, n, L, line, v, inbuilds) {
  n = split(T, L, "\n"); inbuilds = 0
  for (i = 1; i <= n; i++) {
    line = norm_yaml(L[i])
    if (line ~ /^[^ \t#]/) inbuilds = (line ~ /^allowBuilds:/)
    if (line ~ /^minimumReleaseAge:/) { v = line; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["']|["']$/, "", v); if (!plain_num(v)) fail("minimumReleaseAge is not a plain number"); emit("min", "minimumReleaseAge", v) }
    else if (line ~ /^minimumReleaseAgeExclude:/) emit("set", "minimumReleaseAgeExclude", "present")
    else if (line ~ /^dangerouslyAllowAllBuilds:/) { v = line; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["']|["']$/, "", v); if (yes(v)) emit("set", "dangerouslyAllowAllBuilds", "true") }
    else if (line ~ /^(strictDepBuilds|ignoreScripts):/) { v = line; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["']|["']$/, "", v); if (no(v)) { sub(/:.*$/, "", line); emit("set", line, "false") } }
    else if (inbuilds && line ~ /^[ \t]+[^ \t].*:[ \t]*["']?[Tt][Rr][Uu][Ee]["']?[ \t]*$/) { v = line; sub(/:[ \t]*["']?[Tt][Rr][Uu][Ee]["']?[ \t]*$/, "", v); gsub(/^[ \t'"'"'"]+|[ \t'"'"'"]+$/, "", v); emit("set", "allowBuilds", v) }
  }
}

function do_dependabot(   i, n, L, line, v) {
  n = split(T, L, "\n")
  for (i = 1; i <= n; i++) {
    line = norm_yaml(L[i])
    if (match(line, /default-days:[ \t]*["']?[0-9]+/)) {
      v = substr(line, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*["']?/, "", v)
      emit("min", "dependabot-cooldown", v)
    }
  }
}

function do_npmrc(   i, n, L, line) {
  n = split(T, L, "\n")
  for (i = 1; i <= n; i++) {
    line = L[i]; sub(/\r$/, "", line); line = tolower(line); gsub(/[ \t]+/, "", line)
    if (line ~ /^ignore-scripts=false/) emit("set", "npmrc", "ignore-scripts=false")
    else if (line ~ /^dangerously-allow-all-builds=true/) emit("set", "npmrc", "dangerously-allow-all-builds=true")
    else if (line ~ /^(@[^:]+:)?registry=/) emit("set", "npmrc-registry", line)
  }
}

function do_hadolint(   i, n, L, line) {
  n = split(T, L, "\n")
  for (i = 1; i <= n; i++) {
    line = L[i]; sub(/\r$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == "" || line ~ /^#/) continue
    emit("set", "hadolint", line)
  }
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
  while (find("--fail-under[= ]+[0-9]+([.][0-9]+)?", from)) {
    if (!flag_end_ok(substr(T, MS + ML, 1))) fail("--fail-under is not a plain decimal literal")
    emit("min", "diff-cover-fail-under", num_in(substr(T, MS + 12, ML - 12))); from = MS + ML
  }
}

{ T = T $0 "\n" }
END {
  if (ERRSET) exit 3
  MODE = K; TOML = (K == "pyproject" || K == "gitleaks"); T0 = T
  if (K == "jscpd") { T = clean(T, "plain"); do_jscpd() }
  else if (K == "eslint") { T = clean(T, "js"); do_eslint() }
  else if (K == "vitest") { T = clean(T, "js"); do_vitest() }
  else if (K == "pyproject") { T = clean(T, "toml"); do_pyproject() }
  else if (K == "gitleaks") { T = clean(T, "toml"); do_gitleaks() }
  else if (K == "budget") do_budget()
  else if (K == "gates") do_gates()
  else if (K == "hosts") do_hosts()
  else if (K == "pnpmws") do_pnpmws()
  else if (K == "dependabot") do_dependabot()
  else if (K == "npmrc") do_npmrc()
  else if (K == "hadolint") do_hadolint()
  else if (K == "ci") do_ci()
  if (ERRSET) exit 3
}
AWK

cat > "$wd/compare.awk" <<'AWK'
BEGIN { FS = "\t"; sevname[0] = "off"; sevname[1] = "warn"; sevname[2] = "error" }
function label(kind, v) { return (kind == "sev") ? sevname[v] : v }
function nm(key,   i) { i = index(key, "#"); return i ? substr(key, 1, i - 1) : key }
function stronger(kind, a, b) { return (kind == "max") ? (a + 0 < b + 0) : (a + 0 > b + 0) }
{
  k = $1 SUBSEP $2
  if (FILENAME == ARGV[1]) {
    if ($1 == "set") bset[k SUBSEP $3] = 1
    else if ($1 == "req") breq[k SUBSEP $3] = 1
    else if ($1 == "cfg") bcfg[$2] = $3
    else {
      if (!(k in bagg)) { bagg[k] = $3; order[++no] = k }
      else if (($1 == "max" && $3 + 0 > bagg[k] + 0) || ($1 != "max" && $3 + 0 < bagg[k] + 0)) bagg[k] = $3
      n = nm($2)
      if ($1 == "sev" && (!(n in bsevmax) || $3 + 0 > bsevmax[n] + 0)) bsevmax[n] = $3
      if ($1 == "max" && (!(n in blim) || $3 + 0 < blim[n] + 0)) blim[n] = $3
    }
  } else {
    if ($1 == "set") { if (!((k SUBSEP $3) in hset) && !((k SUBSEP $3) in bset)) hnew[++nn] = k SUBSEP $3; hset[k SUBSEP $3] = 1 }
    else if ($1 == "req") hreq[k SUBSEP $3] = 1
    else if ($1 == "cfg") hcfg[$2] = $3
    else if (!(k in hagg)) { hagg[k] = $3; horder[++nh] = k }
    else if (($1 == "max" && $3 + 0 > hagg[k] + 0) || ($1 != "max" && $3 + 0 < hagg[k] + 0)) hagg[k] = $3
  }
}
END {
  bad = 0
  for (i = 1; i <= no; i++) {
    k = order[i]; split(k, p, SUBSEP)
    if (!(k in hagg)) { printf "WEAKENED %s: %s %s was %s, now removed\n", F, p[1], p[2], label(p[1], bagg[k]); bad = 1 }
    else if (p[1] == "max" && hagg[k] + 0 > bagg[k] + 0) { printf "WEAKENED %s: limit %s was %s, now %s\n", F, p[2], bagg[k], hagg[k]; bad = 1 }
    else if (p[1] != "max" && hagg[k] + 0 < bagg[k] + 0) {
      printf "WEAKENED %s: %s %s was %s, now %s\n", F, (p[1] == "sev" ? "lint rule" : "threshold"), p[2], label(p[1], bagg[k]), label(p[1], hagg[k]); bad = 1
    }
  }
  for (i = 1; i <= nh; i++) {
    k = horder[i]
    if (k in bagg) continue
    split(k, p, SUBSEP); n = nm(p[2])
    if (p[1] == "sev" && hagg[k] + 0 == 0) { printf "WEAKENED %s: lint rule %s is off in a block the merge base did not have\n", F, p[2]; bad = 1 }
    else if (p[1] == "sev" && (n in bsevmax) && hagg[k] + 0 < bsevmax[n] + 0) { printf "WEAKENED %s: lint rule %s is %s in a new block, below %s at the merge base\n", F, p[2], label("sev", hagg[k]), label("sev", bsevmax[n]); bad = 1 }
    else if (p[1] == "max" && p[2] ~ /[.]limit/ && (n in blim) && hagg[k] + 0 > blim[n] + 0) { printf "WEAKENED %s: limit %s is %s in a new block, above %s at the merge base\n", F, p[2], hagg[k], blim[n]; bad = 1 }
  }
  for (i = 1; i <= nn; i++) { split(hnew[i], p, SUBSEP); printf "WEAKENED %s: new ignore or exclude in %s was absent, now '%s'\n", F, p[2], p[3]; bad = 1 }
  for (k in bcfg) {
    if (!(k in hcfg)) { printf "WEAKENED %s: setting %s was '%s', now removed (a setting the checker does not know must stay as it was)\n", F, k, bcfg[k]; bad = 1 }
    else if (hcfg[k] != bcfg[k]) { printf "WEAKENED %s: setting %s was '%s', now '%s' (a setting the checker does not know must stay as it was)\n", F, k, bcfg[k], hcfg[k]; bad = 1 }
  }
  for (k in hcfg) if (!(k in bcfg)) { printf "WEAKENED %s: new setting %s = '%s' (a setting the checker does not know must stay as it was)\n", F, k, hcfg[k]; bad = 1 }
  for (k in breq) if (!(k in hreq)) { split(k, p, SUBSEP); printf "WEAKENED %s: required %s '%s' was present, now removed\n", F, p[2], p[3]; bad = 1 }
  exit bad
}
AWK

base_paths=$(git ls-tree -r --name-only "$mb" 2>/dev/null)
paths=$( { printf '%s\n' "$base_paths"; git ls-tree -r --name-only HEAD; } 2>/dev/null | sort -u)
[ -n "$paths" ] || die "cannot list tracked files"
if ! printf '%s\n' "$base_paths" | grep -Eq '(^|/)[.]claude/gates[.]txt$'; then
  echo "gate-ratchet: first adoption: the merge base has no .claude/gates.txt, nothing to compare"
  exit 0
fi
renames=$(git diff -M --name-status --diff-filter=R "$mb" HEAD 2>/dev/null)

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
    moved=$(printf '%s\n' "$renames" | awk -F'\t' -v p="$path" '$2 == p { print $3; exit }')
    if [ -n "$moved" ]; then
      printf 'WEAKENED %s: file was present at the merge base, now removed (renamed to %s; tools read the original name, so a rename counts as a removal)\n' "$path" "$moved"
    else
      printf 'WEAKENED %s: file was present at the merge base, now removed\n' "$path"
    fi
    weakened=1
    continue
  fi
  file_bad=0
  if [ "$kind" != guard ]; then
    if ! msg=$(awk -v K="$kind" -f "$wd/facts.awk" "$wd/head" 2>&1 > "$wd/head.f"); then
      printf 'UNREADABLE %s: %s (fail closed)\n' "$path" "$msg"
      unreadable=1
      continue
    fi
    if [ "$have_base" -eq 0 ]; then continue; fi
    if ! msg=$(awk -v K="$kind" -f "$wd/facts.awk" "$wd/base" 2>&1 > "$wd/base.f"); then
      printf 'NOTE %s: unreadable at the merge base (%s); compared with an empty baseline\n' "$path" "$msg"
      : > "$wd/base.f"
    fi
    if ! awk -v F="$path" -f "$wd/compare.awk" "$wd/base.f" "$wd/head.f"; then
      file_bad=1
    fi
  fi
  if [ "$have_base" -eq 0 ]; then continue; fi
  if [ "$file_bad" -eq 0 ] && ! content_ok "$kind"; then
    printf 'WEAKENED %s: gate script, runner or manifest changed (content differs from the merge base)\n' "$path"
    file_bad=1
  fi
  if [ "$file_bad" -eq 1 ]; then weakened=1; fi
done <<< "$paths"

added=$(git diff --no-renames --name-only --diff-filter=A "$mb" HEAD 2>/dev/null)
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if why=$(shadow_reason "$path"); then
    printf 'WEAKENED %s: new config file competes with a ratcheted one (%s)\n' "$path" "$why"
    weakened=1
  fi
done <<< "$added"

if [ "$weakened" -eq 1 ]; then
  echo "gate-ratchet: FAIL, a gate is weaker than at the merge base ($checked config files compared)"
  echo "Fix: restore each WEAKENED setting above to its merge-base value. If the rule is wrong for the whole project, change it in its own reviewed change that touches only that config."
  exit 1
fi
if [ "$unreadable" -eq 1 ]; then
  echo "gate-ratchet: FAIL, a gate config file could not be read ($checked config files compared)"
  echo "Fix: make the file parseable again (restore it from the merge base), then rerun."
  exit 2
fi
echo "gate-ratchet: ok, no gate weaker than at the merge base ($checked config files compared)"
