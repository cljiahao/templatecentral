#!/usr/bin/env bash
# Gate-config ratchet: gate-ratchet.sh <base-ref|auto>. Fails when HEAD weakens a gate versus the merge base. Offline; runs the merge-base copy of itself and reads tracked files through git only.
# gate-ratchet.sh --list-guarded [ref] prints "kind<TAB>path<TAB>enforced" for every tracked file the ratchet compares; enforced is 1 when the allow-gate-change label can never waive the kind. ci-gates.sh, verify-harness.sh, protect-files.sh and the tests read that one list.
# Scope: the ratchet guards gate scripts and the files that call them, thresholds, test and install scripts and their flags, lint and test-runner settings, and conftest collection control. Test bodies are covered by the coverage gate, not by the ratchet.
# Guarded set, derived from the tracked tree, never listed by hand: each file under .claude/hooks/, each .claude/*.sh, .claude/settings.json, every scripts/ or .claude/ path named in a hook, .claude/*.sh, gates.txt, scripts/, lefthook, a Node hook-manager folder, CI file, Makefile or package.json gate script, and every protect-files.sh pattern except instruction, invariant, agent, MCP, image and merge-snapshot entries. Skill, agent, rule and markdown files are never read. Parsed configs keep their parsed comparison; the rest are compared by content.
# Test scripts: every package.json script whose name has a test, coverage, lint, typecheck, build, check, verify, ci, format or audit word keeps its word list. Any change is a finding except these known-safe words: --reporter, --coverage.reporter, --outputFile (with or without a value), --coverage.reportsDirectory=, --silent, --color, --no-color. A script that is gone is a finding; a new script is covered by the flag checks and the CI and lefthook comparison.
# pytest: any change to a [tool.pytest.ini_options] key or a new key is a finding, except raising --cov-fail-under and the markers, pythonpath and asyncio_default_fixture_loop_scope keys.
# Type checkers: tsconfig and pyright strictness may tighten, never loosen; a new tsconfig or pyright config may not switch strictness off.
# Gate-time budget: .claude/gate-budget.conf may not be deleted, and its three limits may not rise; a conf with no merge-base copy is held to the seeded defaults (600, 180, 25) and may not set a higher limit or leave one out. The kind is not enforced, so a human applying the allow-gate-change label can waive a raise or a deletion, by design.
# Allow-lists: dep-audit-allow.txt may only lose lines; comment-hygiene-patterns.txt may only gain lines at the end.
set -uo pipefail

die() {
  printf 'gate-ratchet: %s\n' "$1" >&2
  exit 2
}

list_mode=""
if [ "${1:-}" = --list-guarded ]; then list_mode=1; list_ref=${2:-HEAD}; fi
wd=$(mktemp -d "${TMPDIR:-/tmp}/gate-ratchet.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$wd"' EXIT

if [ -z "$list_mode" ]; then
  base_ref=${1:-}
  if [ "$base_ref" = auto ]; then
    base_ref=""
    for cand in '@{upstream}' origin/HEAD origin/main origin/master; do
      if git rev-parse --verify -q "$cand^{commit}" >/dev/null 2>&1; then base_ref=$cand; break; fi
    done
    if [ -z "$base_ref" ]; then
      if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${TF_BUILD:-}" ] || { [ -n "${CI:-}" ] && [ "${CI:-}" != false ]; }; then
        die "no base branch found (no upstream, origin/main or origin/master), so the ratchet cannot run in CI; fetch the base branch with full history"
      fi
      echo "gate-ratchet: DID NOT RUN: no upstream, origin/main or origin/master to compare against, so no gate was checked. Fetch a base branch or pass a ref; CI runs this gate on the pull request."
      exit 0
    fi
  fi
  [ -n "$base_ref" ] || die "usage: gate-ratchet.sh <base-ref|auto> (for example origin/main; auto picks the upstream or origin/main)"
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
  mb=$(git merge-base "$base_ref" HEAD 2>/dev/null) || die "no merge base between $base_ref and HEAD (check out with full history)"

  # A PR must not rewrite the checker that judges it: run the merge-base copy when the base has one.
  if [ -z "${GATE_RATCHET_REEXEC:-}" ]; then
    base_ratchet=$(git ls-tree --name-only "$mb" -- scripts/gate-ratchet.sh) || die "cannot list the merge base $mb"
    if [ -n "$base_ratchet" ]; then
      git show "$mb:scripts/gate-ratchet.sh" > "$wd/base-ratchet.sh" || die "cannot read scripts/gate-ratchet.sh at the merge base $mb"
      GATE_RATCHET_REEXEC=1 bash "$wd/base-ratchet.sh" "$base_ref"
      exit $?
    fi
    if git cat-file -e "$mb:.claude/gates.txt" 2>/dev/null; then
      die "the merge base has .claude/gates.txt but no scripts/gate-ratchet.sh, so the checker in this change would judge itself; restore scripts/gate-ratchet.sh at the base"
    fi
  fi
else
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
  git rev-parse --verify -q "$list_ref^{commit}" >/dev/null 2>&1 || die "--list-guarded: $list_ref is not a commit"
fi

# Files compared by parsed values, by the kind of parser they need; the guard kind is never listed here, it comes from guard_scan.
kind_of() {
  case "$1" in
    .jscpd.json | */.jscpd.json) KIND=jscpd ;;
    eslint.config.* | */eslint.config.*) KIND=eslint ;;
    vitest.config.* | vite.config.* | vitest.workspace.* | */vitest.config.* | */vite.config.* | */vitest.workspace.*) KIND=vitest ;;
    sonar-project.properties | */sonar-project.properties) KIND=sonar ;;
    package.json | */package.json) KIND=pkgjson ;;
    pyproject.toml | */pyproject.toml) KIND=pyproject ;;
    .gitleaks.toml | */.gitleaks.toml) KIND=gitleaks ;;
    scripts/test-budget.sh | */scripts/test-budget.sh) KIND=budget ;;
    .claude/gates.txt | */.claude/gates.txt) KIND=gates ;;
    .claude/registry-hosts.txt | */.claude/registry-hosts.txt) KIND=hosts ;;
    .claude/dep-audit-allow.txt | */.claude/dep-audit-allow.txt) KIND=allow ;;
    .claude/comment-hygiene-patterns.txt | */.claude/comment-hygiene-patterns.txt) KIND=patterns ;;
    .claude/gate-budget.conf | */.claude/gate-budget.conf) KIND=gatetime ;;
    tsconfig.json | tsconfig.*.json | */tsconfig.json | */tsconfig.*.json) KIND=tsconfig ;;
    pyrightconfig.json | */pyrightconfig.json) KIND=pyright ;;
    pnpm-workspace.yaml | */pnpm-workspace.yaml) KIND=pnpmws ;;
    .github/dependabot.yml | */.github/dependabot.yml) KIND=dependabot ;;
    .npmrc | */.npmrc) KIND=npmrc ;;
    .hadolint.yaml | */.hadolint.yaml | .hadolint.yml | */.hadolint.yml) KIND=hadolint ;;
    .github/workflows/ci.yml | */.github/workflows/ci.yml | azure-pipelines.yml | */azure-pipelines.yml | azure-pipelines/templatecentral-gates.yml | */azure-pipelines/templatecentral-gates.yml) KIND=ci ;;
    conftest.py | */conftest.py) KIND=conftest ;;
    *) KIND="" ;;
  esac
}

# Runs a match test (grep or awk) and returns its 0 or 1 status; any other status is a tool failure and ends the run with status 2, so a failed test never reads as "no match". Under a command substitution the caller must pass a status of 2 on.
gs_test() {
  local rc
  "$@"
  rc=$?
  [ "$rc" -le 1 ] || die "$1 failed with status $rc"
  return "$rc"
}

# Runs grep and accepts its no-match status (1) as success; any other status, a real failure, is returned as failure.
gs_grep() {
  local rc
  grep "$@"
  rc=$?
  [ "$rc" -le 1 ]
}

# Tracked files of <ref> into $wd/tracked.lst, then the derived guard set into $wd/guard.lst: each file under .claude/hooks/, each .claude/*.sh, .claude/settings.json, each Node hook-manager file, every scripts/ or .claude/ path named in a gate-bearing source, and the protect-files.sh gate patterns. Gate-bearing sources are hooks, .claude/*.sh, gates.txt, scripts/, lefthook, a Node hook-manager folder, CI files, the Makefile and the gate or install scripts of a package.json; skill, agent, rule and markdown files are never read. No stage hides a failure: every command writes to a file and its status is checked, so a source that cannot be listed, read or parsed returns 1.
guard_scan() {
  local ref=$1 f pf line labels reason mre
  mre='(scripts|[.]claude)/[A-Za-z0-9_@./-]*[A-Za-z0-9_@-]'
  git ls-tree -r "$ref" > "$wd/tree.raw" 2>/dev/null || return 1
  awk -F'\t' '$1 !~ /^160000 / { print substr($0, index($0, "\t") + 1) }' "$wd/tree.raw" > "$wd/tracked.lst" || return 1
  : > "$wd/mentions.lst"; : > "$wd/guard.lst"; : > "$wd/pats.lst"
  gs_grep -E '(^|/)[.]claude/hooks/|(^|/)[.]claude/[^/]*[.]sh$|(^|/)[.]claude/settings[.]json$|(^|/)lefthook[.]yml$|(^|/)[.]lefthook/|(^|/)[.]hus[k]y/' "$wd/tracked.lst" > "$wd/guard.lst" || return 1
  gs_grep -E '(^|/)[.]claude/(hooks/|[^/]*[.]sh$|gates[.]txt$|settings[.]json$)|(^|/)scripts/|(^|/)[.]lefthook/|(^|/)[.]hus[k]y/|(^|/)[.]github/workflows/|(^|/)azure-pipelines|(^|/)(lefthook[.]yml|Makefile|package[.]json)$' "$wd/tracked.lst" > "$wd/sources.raw" || return 1
  gs_grep -Ev '[.]md$' "$wd/sources.raw" > "$wd/sources.lst" || return 1
  while IFS= read -r f; do
    git show "$ref:$f" > "$wd/src.txt" 2>/dev/null || return 1
    case "$f" in
      package.json | */package.json)
        awk -v K=pkgjson -v B=1 -v CMDS=1 -f "$wd/facts.awk" "$wd/src.txt" > "$wd/cmds.txt" 2>/dev/null || return 1
        gs_grep -aoE "$mre" "$wd/cmds.txt" >> "$wd/mentions.lst" || return 1
        ;;
      *) gs_grep -aoE "$mre" "$wd/src.txt" >> "$wd/mentions.lst" || return 1 ;;
    esac
  done < "$wd/sources.lst"
  sort -u -o "$wd/mentions.lst" "$wd/mentions.lst" || return 1
  awk 'NR == FNR { m[$0] = 1; next } { p = $0; while (1) { if (p in m) { print $0; break }; i = index(p, "/"); if (!i) break; p = substr(p, i + 1) } }' "$wd/mentions.lst" "$wd/tracked.lst" >> "$wd/guard.lst" || return 1
  gs_grep -E '(^|/)[.]claude/hooks/protect-files[.]sh$' "$wd/tracked.lst" > "$wd/pf.lst" || return 1
  pf=$(head -n 1 "$wd/pf.lst")
  if [ -n "$pf" ]; then
    git show "$ref:$pf" > "$wd/src.txt" 2>/dev/null || return 1
    gs_grep -E '^  [^ #].*\) reason=' "$wd/src.txt" > "$wd/pf.rows" || return 1
    : > "$wd/pats.split"
    while IFS= read -r line; do
      reason=${line#*reason=}
      case "$reason" in *"instruction file"* | *"binding invariants"* | *"agent definition"* | *"MCP server"* | *"container image"* | *"merge base snapshot"*) continue ;; esac
      labels=${line%%\) reason=*}
      printf '%s\n' "$labels" | tr '|' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' >> "$wd/pats.split" || return 1
    done < "$wd/pf.rows"
    gs_grep -v '^$' "$wd/pats.split" > "$wd/pats.nz" || return 1
    sort -u "$wd/pats.nz" > "$wd/pats.lst" || return 1
    awk 'NR == FNR { g = $0; gsub(/[.]/, "[.]", g); gsub(/[*]/, ".*", g); re[++n] = "^" g "$"; next } { for (i = 1; i <= n; i++) if ($0 ~ re[i]) { print; break } }' "$wd/pats.lst" "$wd/tracked.lst" >> "$wd/guard.lst" || return 1
  fi
  sort -u -o "$wd/guard.lst" "$wd/guard.lst" || return 1
}

# The content-frozen kinds (guard, budget, ci, gates, hosts, gitleaks, patterns), which the allow-gate-change label can never waive and verify-harness.sh hashes; ci-gates.sh and verify-harness.sh read this as the third column of --list-guarded.
enforced_kind() {
  case "$1" in guard | budget | ci | gates | hosts | gitleaks | patterns) return 0 ;; esac
  return 1
}

# Reads paths on stdin and prints "kind<TAB>path<TAB>enforced" (1 or 0) for each one the ratchet compares, in one pass without a subshell per path.
classify() {
  local g p e
  awk 'NR == FNR { g[$0] = 1; next } { print (($0 in g) ? 1 : 0) "\t" $0 }' "$wd/guard.lst" - > "$wd/classify.in" || die "cannot mark the guarded paths (awk failed)"
  while IFS=$'\t' read -r g p; do
    kind_of "$p"
    if [ -z "$KIND" ] && [ "$g" = 1 ]; then KIND=guard; fi
    [ -n "$KIND" ] || continue
    e=0
    if enforced_kind "$KIND"; then e=1; fi
    printf '%s\t%s\t%s\n' "$KIND" "$p" "$e"
  done < "$wd/classify.in"
}

# True when the merge base tracked this exact path.
base_has() { gs_test grep -Fxq -- "$1" "$wd/base.paths"; }

# True when HEAD tracks this exact path.
head_has() { gs_test grep -Fxq -- "$1" "$wd/head.paths"; }

# True when any pyproject.toml the merge base tracked, at any depth, sets pytest or coverage options.
py_settings() {
  local f
  gs_grep -E '(^|/)pyproject[.]toml$' "$wd/base.paths" > "$wd/pyproject.lst" || die "cannot list the pyproject.toml files of the merge base"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git show "$mb:$f" > "$wd/py.txt" || die "cannot read $f at the merge base $mb"
    if gs_test grep -Eq '^[[:space:]]*[[]tool[.](pytest|coverage)' "$wd/py.txt"; then return 0; fi
  done < "$wd/pyproject.lst"
  return 1
}

# A new config file with one of these names competes with a ratcheted config that the merge base already had; prints why and returns 0.
shadow_reason() {
  local name fam fams dir f
  name=${1##*/}
  dir=""
  case "$1" in */*) dir=${1%/*}/ ;; esac
  case "$name" in
    ruff.toml | .ruff.toml) if base_has "${dir}pyproject.toml"; then echo "ruff reads it instead of pyproject.toml"; return 0; fi ;;
    .coveragerc | pytest.ini | tox.ini | setup.cfg) if py_settings; then echo "pytest and coverage may read it instead of the pyproject.toml settings"; return 0; fi ;;
    .gitleaksignore) if base_has "${dir}.gitleaks.toml"; then echo "gitleaks reads it besides .gitleaks.toml"; return 0; fi ;;
    .eslintignore) if gs_test grep -Eq "^${dir}eslint[.]config[.][^/]*$" "$wd/base.paths"; then echo "it adds ignores besides eslint.config"; return 0; fi ;;
    jscpd.json | .jscpdrc | .jscpdrc.json | .jscpd.yml | .jscpd.yaml | .jscpd.js) if base_has "${dir}.jscpd.json"; then echo "jscpd may read it instead of .jscpd.json"; return 0; fi ;;
    sonar-project.properties | .sonarcloud.properties) if gs_test grep -Eq '(^|/)sonar-project[.]properties$' "$wd/base.paths"; then echo "sonar may read it besides the tracked sonar-project.properties"; return 0; fi ;;
    vitest.workspace.*)
      for f in vite.config. vitest.config. vitest.workspace.; do
        if gs_test awk -v pre="${dir}${f}" 'index($0, pre) == 1 && index(substr($0, length(pre) + 1), "/") == 0 { hit = 1 } END { exit !hit }' "$wd/base.paths"; then
          echo "a workspace file replaces the test projects of ${f}* and only one is read"
          return 0
        fi
      done
      ;;
    eslint.config.* | vitest.config.* | vite.config.* | jest.config.*)
      case "${name#*.config.}" in js | mjs | cjs | ts | mts | cts | json) ;; *) return 1 ;; esac
      fam=${name%%.config.*}
      case "$fam" in vite | vitest) fams="vite vitest" ;; *) fams=$fam ;; esac
      for f in $fams; do
        if gs_test awk -v pre="${dir}${f}.config." 'index($0, pre) == 1 && substr($0, length(pre) + 1) ~ /^([cm]?[jt]s|json)$/ { hit = 1 } END { exit !hit }' "$wd/base.paths"; then
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
    allow)
      local l
      while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in '' | '#'*) continue ;; esac
        grep -Fxq -- "$l" "$wd/base" || return 1
      done < "$wd/head"
      return 0
      ;;
    patterns)
      local n
      n=$(awk 'END { print NR }' "$wd/base")
      head -n "$n" "$wd/head" | cmp -s - "$wd/base"
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
function emit(kind, key, val) { if (kind == "skip" || CMDS != "") return; gsub(/[\t\n]/, " ", key); gsub(/[\t\n]/, " ", val); printf "%s\t%s\t%s\n", kind, key, val }
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

# The value at index p must be a bare array literal of plain strings with nothing chained after it; anything else cannot be read, so it fails closed. STRICT_END is the index after the array.
function strict_array(p, kind, key,   n, c, j, ch, q) {
  n = length(T)
  if (substr(T, p, 1) != "[") fail(key " is not a bare array literal of strings: " substr(vtext(p), 1, 60))
  p++
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n]/) p++
    c = substr(T, p, 1)
    if (c == "]") break
    if (c != "\"" && c != "'" && c != "`") fail(key " array holds something other than a string literal: " substr(vtext(p), 1, 60))
    j = p + 1
    while (j <= n) {
      ch = substr(T, j, 1)
      if (ch == "\\") { j += 2; continue }
      if (ch == c) break
      if (c == "`" && ch == "$" && substr(T, j + 1, 1) == "{") fail(key " array holds a template string with an expression")
      j++
    }
    if (j > n) fail("unterminated string in " key)
    emit(kind, key, substr(T, p + 1, j - p - 1))
    p = j + 1
    while (p <= n && substr(T, p, 1) ~ /[ \t\n]/) p++
    c = substr(T, p, 1)
    if (c == ",") { p++; continue }
    if (c != "]") fail(key " array element is followed by something other than a comma or ]")
    break
  }
  if (p > n || substr(T, p, 1) != "]") fail("unterminated array in " key)
  p++
  while (p <= n && substr(T, p, 1) ~ /[ \t\n]/) p++
  c = substr(T, p, 1)
  if (p <= n && c != "," && c != "}") fail(key " array has something chained after it: " substr(vtext(p), 1, 60))
  STRICT_END = p
}

# Every quoted or bare <name>: key must hold a strict array; each string becomes one fact of the given kind.
function strict_named(name, kind,   from) {
  from = 1
  while (find("(^|[^A-Za-z0-9_$.])[\"']?" name "[\"']?[ \t\n]*:[ \t\n]*", from)) {
    strict_array(MS + ML, kind, name); from = STRICT_END
  }
}

# Keys of the coverage object at index p (just after its brace): tracked keys are read here or elsewhere, neutral ones ignored, the rest become cfg facts; a repeated key cannot be read.
function cov_walk(p, pre,   n, k, kn, v, e, id) {
  n = length(T); id = ++WALKN
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (p > n || substr(T, p, 1) == "}") return
    if (match(substr(T, p), /^(["'][^"']*["']|[A-Za-z0-9_$]+)[ \t\n]*:[ \t\n]*/)) {
      k = substr(T, p, RLENGTH); p += RLENGTH
      kn = k; sub(/[ \t\n]*:[ \t\n]*$/, "", kn); gsub(/["']/, "", kn)
      if ((id SUBSEP kn) in SEENK) fail("coverage key " pre kn " is given twice, so the file cannot be read reliably")
      SEENK[id SUBSEP kn] = 1
      v = vtext(p); e = VEND
      if (pre == "" && kn == "thresholds" && v ~ /^[{]/) cov_walk(p + 1, "thresholds.")
      else if (pre == "" && kn ~ /^(include|exclude)$/) strict_array(p, (kn == "exclude" ? "set" : "req"), kn)
      else if (pre == "" && kn ~ /^(provider|reporter|reportsDirectory|reportOnFailure)$/) { }
      else if (pre == "thresholds." && kn ~ /^(lines|functions|branches|statements)$/) {
        if (!plain_num(v)) fail("coverage threshold " kn " is not a plain decimal literal: " v)
        emit("min", "coverage-" kn, v)
      }
      else emit("cfg", "coverage." pre kn, v)
      p = e
    } else {
      v = vtext(p); emit("cfg", "coverage." pre "?", v); p = VEND
    }
  }
}

# Keys of the test object at index p (just after its brace): the neutral list and the keys read elsewhere are skipped, every other key is a cfg fact, so a new or changed one is a finding.
function test_walk(p,   n, k, kn, v, e, id) {
  n = length(T); id = ++WALKN
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (p > n || substr(T, p, 1) == "}") return
    if (match(substr(T, p), /^(["'][^"']*["']|[A-Za-z0-9_$]+)[ \t\n]*:[ \t\n]*/)) {
      k = substr(T, p, RLENGTH); p += RLENGTH
      kn = k; sub(/[ \t\n]*:[ \t\n]*$/, "", kn); gsub(/["']/, "", kn)
      if ((id SUBSEP kn) in SEENT) fail("test key " kn " is given twice, so the file cannot be read reliably")
      SEENT[id SUBSEP kn] = 1
      v = vtext(p); e = VEND
      if (kn !~ /^(globals|environment|env|pool|poolOptions|maxWorkers|minWorkers|setupFiles|globalSetup|reporters|outputFile|testTimeout|hookTimeout|teardownTimeout|css|alias|clearMocks|mockReset|restoreMocks|unstubEnvs|unstubGlobals|silent|coverage|include|exclude|passWithNoTests)$/) emit("cfg", "test." kn, v)
      p = e
    } else {
      v = vtext(p); emit("cfg", "test.?", v); p = VEND
    }
  }
}

function do_vitest(   from, m, name, v, p) {
  from = 1
  while (find("(^|[^A-Za-z0-9_$.])[\"']?test[\"']?[ \t\n]*:[ \t\n]*[{]", from)) {
    p = MS + ML - 1
    test_walk(p + 1); from = p + 1
  }
  from = 1
  while (find("(^|[^A-Za-z0-9_$.])[\"']?coverage[\"']?[ \t\n]*:[ \t\n]*", from)) {
    p = MS + ML
    if (substr(T, p, 1) != "{") fail("coverage is not an object literal: " substr(vtext(p), 1, 60))
    cov_walk(p + 1, ""); from = p + 1
  }
  from = 1
  while (find("(lines|functions|branches|statements)[\"']?[ \t\n]*:[ \t\n]*", from)) {
    m = substr(T, MS, ML); name = substr(m, 1, index(m, ":") - 1); gsub(/[ \t\n"']/, "", name)
    v = tok(MS + ML)
    if (!plain_num(v)) fail("coverage threshold " name " is not a plain decimal literal: " v)
    emit("min", "coverage-" name, v)
    from = MS + ML
  }
  strict_named("exclude", "set")
  strict_named("include", "req")
  nopass = "passWith" "NoTests"
  from = 1
  while (find(nopass "[\"']?[ \t\n]*:[ \t\n]*", from)) {
    v = tok(MS + ML)
    if (v != "false") emit("set", nopass, v)
    from = MS + ML
  }
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
      sect = line; gsub(/^[ \t]*[[]+[ \t]*/, "", sect); gsub(/[ \t]*[]]+[ \t]*$/, "", sect)
      gsub(/[ \t]*[.][ \t]*/, ".", sect); gsub(/["']/, "", sect); SECTS[sect] = 1
      csect = sect
      if (line ~ /^[ \t]*[[][[]/) {
        HC[sect]++; csect = sect "#" HC[sect]
        if (cfg_scope(sect) && !(sect ~ /allowlist/)) emit("cfg", "[[" csect "]]", "")
      }
      continue
    }
    if (!match(line, /^[ \t]*([A-Za-z0-9_.-]+[.])?("[^"]*"|'[^']*'|[A-Za-z0-9_.-]+)[ \t]*=/)) continue
    raw = substr(line, 1, RLENGTH - 1); gsub(/^[ \t]*/, "", raw); gsub(/[ \t]*$/, "", raw)
    rest = substr(line, RLENGTH + 1); pos = LO[i] + RLENGTH
    s2 = sect; k2 = raw
    if (raw !~ /^["']/ && match(raw, /[.]["']/)) {
      pre = substr(raw, 1, RSTART - 1); k2 = substr(raw, RSTART + 1)
      s2 = (sect == "") ? pre : sect "." pre
    } else if (raw !~ /["']/ && raw ~ /[.]/) {
      n = split(raw, parts, "."); k2 = parts[n]; pre = parts[1]
      for (j = 2; j < n; j++) pre = pre "." parts[j]
      s2 = (sect == "") ? pre : sect "." pre
    }
    gsub(/["']/, "", k2)
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
      if (TN == "coverage-fail_under") CFU = v
    } else if (MODE == "gitleaks" && (s2 ~ /allowlist/ || s2 == "extend") && k2 ~ /^(path|paths|regex|regexes|commit|commits|stopword|stopwords|url)$/) {
      emit("set", "allow:" k2, v); known = 1
    } else if (MODE == "pyproject" && s2 ~ /^tool[.]ruff$/ && k2 == "extend") {
      emit("set", "ruff-extend", v); known = 1
    }
    if (!known && cfg_scope(s2) && !cfg_neutral(s2, k2)) {
      if (s2 ~ /^tool[.]pytest/) vtxt = mask_cov(vtxt)
      if (!cov_only(vtxt)) emit("cfg", csect "|" raw, vtxt)
    }
    else if (!known && ((s2 == "" && k2 == "tool") || (s2 == "tool" && k2 ~ /^(ruff|coverage|pytest|pyright|mypy)$/))) emit("cfg", csect "|" raw, vtxt)
    if (k2 == "useDefault" && rest ~ /true/) emit("req", "extend", "useDefault")
  }
}
# addopts text with the --cov-fail-under number masked; the min fact already stops a lower number.
function mask_cov(v) {
  gsub(/["'][ \t]*--cov-fail-under(=|[ \t]+)[0-9]+([.][0-9]+)?[ \t]*["']/, "", v)
  gsub(/["']--cov-fail-under["'][ \t\n]*,[ \t\n]*["'][0-9]+([.][0-9]+)?["']/, "", v)
  gsub(/[ \t]+--cov-fail-under(=|[ \t]+)[0-9]+([.][0-9]+)?/, "", v)
  gsub(/--cov-fail-under(=|[ \t]+)[0-9]+([.][0-9]+)?[ \t]*/, "", v)
  gsub(/[ \t\n]+/, " ", v); gsub(/ ?, ?/, ",", v); gsub(/,+/, ",", v)
  gsub(/\[ /, "[", v); gsub(/ \]/, "]", v); gsub(/\[,/, "[", v); gsub(/,\]/, "]", v)
  return v
}
# True for a masked pytest value that holds nothing once --cov-fail-under is gone.
function cov_only(v) {
  gsub(/[]["' ,\t\n]/, "", v)
  return v == ""
}
# Tables whose every key must be known: all of .gitleaks.toml, and the ruff, coverage, pytest, pyright and mypy tables of pyproject.toml.
function cfg_scope(s) {
  if (MODE == "gitleaks") return 1
  return (s ~ /^tool[.](ruff|coverage|pytest|pyright|mypy)([.]|$)/)
}
# Keys that change nothing about what a gate catches.
function cfg_neutral(s, k) {
  if (MODE == "gitleaks") return (k ~ /^(title|description)$/ || (s == "extend" && k == "useDefault"))
  if (s ~ /^tool[.]ruff[.]format/ || s ~ /^tool[.]ruff[.]lint[.]isort/) return 1
  if (s == "tool.ruff" && k ~ /^(line-length|indent-width|target-version|src|output-format|cache-dir)$/) return 1
  if (s == "tool.coverage.report" && k ~ /^(show_missing|skip_covered|precision)$/) return 1
  if (s ~ /^tool[.]pytest/ && k ~ /^(markers|pythonpath|asyncio_default_fixture_loop_scope)$/) return 1
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

function do_pyproject(   from, r, seen) {
  toml_lines()
  if (B == 1 && !(("tool.ruff" in SECTS) || ("tool.ruff.lint" in SECTS))) fail("no [tool.ruff] section")
  from = 1; seen = 0
  while (find("--cov-fail-under", from)) {
    from = MS + ML
    r = substr(T, from, 40)
    if (match(r, /^(=|[ \t]+|["'][ \t\n]*,[ \t\n]*["'])/)) r = substr(r, RLENGTH + 1)
    else fail("--cov-fail-under is not followed by a plain decimal literal")
    if (!match(r, /^[0-9]+([.][0-9]+)?/) || !flag_end_ok(substr(r, RLENGTH + 1, 1))) fail("--cov-fail-under is not a plain decimal literal")
    emit("min", "pytest-cov-fail-under", substr(r, 1, RLENGTH)); seen = 1
  }
  if (!seen && CFU != "") emit("min", "pytest-cov-fail-under", CFU)
  from = 1
  while (find("(^|[^A-Za-z0-9_-])--no-cov([^A-Za-z0-9_-]|$)", from)) { emit("set", "pytest-flag", "--no-cov"); from = MS + ML }
  from = 1
  while (find("--cov-config", from)) { from = MS + ML; emit("set", "pytest-flag", "--cov-config" tok(from)) }
  from = 1
  while (find("(^|[^A-Za-z0-9_-])-p([ \t]|[\"'][ \t\n]*,[ \t\n]*[\"'])?no:(cov|pytest_cov)", from)) { emit("set", "pytest-flag", "-p no:cov"); from = MS + ML }
  from = 1
  while (find("(^|[^A-Za-z0-9_-])(-c|--config-file)([ =\t]|[\"'][ \t\n]*,[ \t\n]*[\"'])", from)) { emit("set", "pytest-flag", "config-file"); from = MS + ML }
}

# One logical properties line: key, then the value after = or : or blanks. Escapes, interpolation and a repeated key cannot be read.
function sonar_line(l,   key, rest, items, ni, i, it, kk) {
  if (!match(l, /^[^=: \t\f]+/)) fail("sonar line without a key: " l)
  key = substr(l, 1, RLENGTH); rest = substr(l, RLENGTH + 1)
  sub(/^[ \t\f]*[=:]?[ \t\f]*/, "", rest); sub(/[ \t\f]+$/, "", rest)
  if (key ~ /\\/ || rest ~ /\\/) fail("sonar key or value with an escape sequence: " key)
  if (rest ~ /[$][{]/) fail("sonar value with interpolation: " key)
  if (key in SKEY) fail("sonar key " key " is given twice, so the file cannot be read reliably")
  SKEY[key] = 1
  kk = key
  if (kk ~ /^sonar[.](exclusions|coverage[.]exclusions|test[.]exclusions|cpd[.]exclusions)$/ || kk ~ /^sonar[.]issue[.]ignore[.]/) {
    ni = split(rest, items, ",")
    for (i = 1; i <= ni; i++) { it = items[i]; gsub(/^[ \t]+|[ \t]+$/, "", it); if (it != "") emit("set", kk, it) }
  } else if (kk ~ /^sonar[.](inclusions|sources)$/) {
    if (kk == "sonar.inclusions") emit("set", "sonar-inclusions", "defined")
    ni = split(rest, items, ",")
    for (i = 1; i <= ni; i++) { it = items[i]; gsub(/^[ \t]+|[ \t]+$/, "", it); if (it != "") emit("req", kk, it) }
  } else if (kk ~ /^sonar[.](projectKey|projectName|projectVersion|organization|sourceEncoding|host[.]url|links[.][A-Za-z0-9_.]+|python[.]version)$/) {
  } else emit("cfg", kk, rest)
}

function do_sonar(   n, L, i, line, buf, m) {
  n = split(T, L, "\n"); buf = ""; cont = 0
  for (i = 1; i <= n; i++) {
    line = L[i]; sub(/\r$/, "", line)
    sub(/^[ \t\f]+/, "", line)
    if (!cont && (line == "" || line ~ /^[#!]/)) continue
    if (match(line, /\\+$/) && RLENGTH % 2 == 1) { buf = buf substr(line, 1, length(line) - 1); cont = 1; continue }
    sonar_line(buf line); buf = ""; cont = 0
  }
  if (cont) sonar_line(buf)
}

# Flags that change what a test script measures or which config it reads; each exact word is a fact, so a flag the merge base already had stays allowed and a new one is a finding.
function script_flags(name, s,   nw, W, i, w, opt, hasv) {
  if (s ~ /\\u/) fail("script " name " holds a \\u escape, which hides what it runs")
  hasv = (s ~ /(^|[^A-Za-z0-9_-])vitest([^A-Za-z0-9_-]|$)/)
  nw = split(s, W, /[ \t]+/)
  for (i = 1; i <= nw; i++) {
    w = W[i]; gsub(/^[\\"'(]+/, "", w); gsub(/[\\"');&|]+$/, "", w)
    if (w == "--coverage") emit("req", "coverage-flag", name)
    else if (w ~ /^--coverage=/) { if (w !~ /^--coverage=(true|1)$/) emit("set", "script-flag", name ": " w) }
    else if (w ~ /^--coverage[.]/) {
      opt = substr(w, 12); sub(/=.*$/, "", opt)
      if (opt !~ /^(reporter|reportsDirectory|provider|clean|cleanOnRerun|reportOnFailure|skipFull)$/) emit("set", "script-flag", name ": " w)
    }
    else if (w == "--no-coverage" || w ~ /^--(pass[W]ithNoTests|pass-with-no-tests)(=|$)/) emit("set", "script-flag", name ": " w)
    else if (hasv && (w == "--config" || w == "-c" || w == "--workspace" || w == "--root")) emit("set", "script-flag", name ": " w " " W[i + 1])
    else if (hasv && w ~ /^--(config|workspace|root)=/) emit("set", "script-flag", name ": " w)
  }
}

# Scripts the gates run: a test, coverage, lint, type-check, build, check, verify, ci, format or audit word in the name, with a pre or post prefix ignored.
function gate_script(name,   n, parts, i, t) {
  n = split(tolower(name), parts, /[:._\/-]+/)
  for (i = 1; i <= n; i++) {
    t = parts[i]
    if (t ~ /^(prepare|prepublish|prepack|postinstall|preinstall)$/) return 1
    sub(/^(pre|post)/, "", t)
    if (t ~ /^(install|test|tests|coverage|cov|lint|eslint|ruff|typecheck|tsc|types|build|check|verify|ci|format|fmt|audit|e2e|mutation|mutate|dup|cpd|jscpd|secrets|scan|sonar|validate|gate|gates|pyright|mypy|vitest|pytest|knip)$/) return 1
  }
  return 0
}

# A script's words with the known-safe ones dropped; any other difference from the merge base is a finding.
function wl_norm(s,   nw, W, i, w, out, skip) {
  nw = split(s, W, /[ \t]+/); out = ""; skip = 0
  for (i = 1; i <= nw; i++) {
    w = W[i]; gsub(/^[\\"'(]+/, "", w); gsub(/[\\"');]+$/, "", w)
    if (w == "") continue
    if (skip) { skip = 0; if (w !~ /^-/ && W[i] !~ /^[;&|<>]/) continue }
    if (w ~ /^(--reporter|--coverage[.]reporter|--outputFile)$/) { skip = 1; continue }
    if (w ~ /^--(reporter|coverage[.]reporter|coverage[.]reportsDirectory|outputFile)=/ || w == "--silent" || w == "--color" || w == "--no-color") continue
    out = out (out == "" ? "" : " ") w
  }
  return out
}

function scripts_walk(p,   n, j, ch, name, c, s) {
  n = length(T)
  if (substr(T, p, 1) != "{") fail("scripts is not an object literal")
  p++
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    c = substr(T, p, 1)
    if (c == "}") return
    if (c != "\"") fail("a scripts entry has no quoted name")
    j = p + 1
    while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
    name = substr(T, p + 1, j - p - 1); p = j + 1
    if (name ~ /\\/) fail("script name with an escape sequence: " name)
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    if (substr(T, p, 1) != "\"") fail("script " name " is not a string")
    j = p + 1
    while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
    s = substr(T, p + 1, j - p - 1); p = j + 1
    if (CMDS != "") { if (gate_script(name)) print s; continue }
    script_flags(name, s)
    emit("scr", name, "")
    if (gate_script(name)) emit("wl", name, wl_norm(s))
  }
  fail("unterminated scripts object")
}

function do_pkgjson(   p, n, j, ch, key, v) {
  json_dups()
  n = length(T); p = index(T, "{") + 1
  if (p <= 1) fail("package.json is not a JSON object")
  while (p > 1 && p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) != "\"") break
    j = p + 1
    while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
    key = substr(T, p + 1, j - p - 1); p = j + 1
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    if (key == "scripts") scripts_walk(p)
    v = vtext(p); p = VEND
  }
}

function jstr_end(p,   j, ch, n) {
  n = length(T); j = p + 1
  while (j <= n) { ch = substr(T, j, 1); if (ch == "\\") { j += 2; continue }; if (ch == "\"") break; j++ }
  return j
}

function ts_strict(k) {
  return k ~ /^(strict|noImplicitAny|strictNullChecks|strictFunctionTypes|strictBindCallApply|strictPropertyInitialization|noImplicitThis|alwaysStrict|useUnknownInCatchVariables|noUncheckedIndexedAccess|exactOptionalPropertyTypes|noImplicitReturns|noFallthroughCasesInSwitch|noUnusedLocals|noUnusedParameters|noImplicitOverride|checkJs)$/
}

function ts_options(p,   n, j, key, v) {
  n = length(T)
  if (substr(T, p, 1) != "{") fail("compilerOptions is not an object literal")
  p++
  while (p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) == "}") return
    if (substr(T, p, 1) != "\"") fail("a compilerOptions entry has no quoted name")
    j = jstr_end(p); key = substr(T, p + 1, j - p - 1); p = j + 1
    if (key ~ /\\/) fail("compiler option name with an escape sequence: " key)
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    v = vtext(p); p = VEND
    if (ts_strict(key)) {
      if (v == "true") emit("flag", key, 1)
      else if (v == "false") emit("flag", key, 0)
      else fail("compiler option " key " is not true or false: " v)
    }
  }
  fail("unterminated compilerOptions")
}

function do_tsconfig(   p, n, j, key, v) {
  n = length(T); p = index(T, "{") + 1
  if (p <= 1) fail("tsconfig is not a JSON object")
  while (p > 1 && p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) != "\"") break
    j = jstr_end(p); key = substr(T, p + 1, j - p - 1); p = j + 1
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    if (key == "compilerOptions") ts_options(p)
    else if (key == "extends") emit("cfg", "extends", vtext(p))
    else if (key == "exclude") strict_array(p, "set", "exclude")
    else if (key == "include" || key == "files") strict_array(p, "req", key)
    v = vtext(p); p = VEND
  }
}

function sev_of(v) {
  gsub(/^"|"$/, "", v)
  if (v == "none" || v == "false") return 0
  if (v == "information" || v == "warning") return 1
  if (v == "error" || v == "true") return 2
  return -1
}

function do_pyright(   p, n, j, key, v, m, sv, mode) {
  n = length(T); p = index(T, "{") + 1; mode = 2
  if (p <= 1) fail("pyrightconfig is not a JSON object")
  while (p > 1 && p <= n) {
    while (p <= n && substr(T, p, 1) ~ /[ \t\n,]/) p++
    if (substr(T, p, 1) != "\"") break
    j = jstr_end(p); key = substr(T, p + 1, j - p - 1); p = j + 1
    while (p <= n && substr(T, p, 1) ~ /[ \t\n:]/) p++
    v = vtext(p)
    if (key == "typeCheckingMode") {
      m = v; gsub(/^"|"$/, "", m)
      if (m == "off") mode = 0; else if (m == "basic") mode = 1; else if (m == "standard") mode = 2; else if (m == "strict") mode = 3
      else fail("typeCheckingMode is not a plain mode name: " v)
    } else if (key ~ /^report[A-Za-z]+$/) {
      sv = sev_of(v)
      if (sv < 0) fail(key " is not a plain severity: " v)
      emit("sev", key, sv)
    } else if (key == "ignore" || key == "exclude") strict_array(p, "set", key)
    else if (key == "include" || key == "strict") strict_array(p, "req", "pyright-" key)
    else if (key !~ /^(venvPath|venv|pythonVersion|pythonPlatform|extraPaths|stubPath|typeshedPath|verboseOutput)$/) emit("cfg", key, v)
    p = VEND
  }
  emit("min", "pyright-mode", mode)
  emit("flag", "typeCheckingMode", (mode >= 2) ? 1 : 0)
}

function do_gitleaks(   n) {
  toml_lines()
  n = 0; for (s in SECTS) n++
  if (n == 0 && !find("useDefault", 1)) fail("no section or useDefault found")
}

# Plugins that only add features and cannot hide tests.
function neutral_plugin(name) { return name ~ /^pytest_(asyncio|cov|mock|timeout|xdist|randomly|django|env|socket|httpx|anyio|benchmark)$/ }

# Python line with the comment and triple-quoted string text removed; QS carries an open triple quote to the next line.
function py_code(line,   i, n, c, c3, out, q, e) {
  n = length(line); out = ""; i = 1
  while (i <= n) {
    if (QS != "") {
      e = index(substr(line, i), QS)
      if (!e) return out
      i += e + 2; QS = ""; out = out "\"\""; continue
    }
    c = substr(line, i, 1); c3 = substr(line, i, 3)
    if (c3 == "\"\"\"" || c3 == "'''") { QS = c3; i += 3; continue }
    if (c == "#") return out
    if (c == "\"" || c == "'") {
      q = c; out = out c; i++
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\\") { out = out substr(line, i, 2); i += 2; continue }
        out = out c; i++
        if (c == q) break
      }
      continue
    }
    out = out c; i++
  }
  return out
}

# True for a code line that can hide tests: a collection or run hook, collect_ignore, an autouse fixture, pytestmark, or a skip or exit call.
function py_hit(code,   rest, tk) {
  if (code ~ /(^|[^A-Za-z0-9_])(autouse|pytestmark|importorskip)([^A-Za-z0-9_]|$)/) return 1
  if (code ~ /(^|[^A-Za-z0-9_.])(pytest[.](skip|xfail|exit)|sys[.]exit|os[.]_exit)([^A-Za-z0-9_]|$)/) return 1
  rest = code
  while (match(rest, /(^|[^A-Za-z0-9_.])(collect_ignore_glob|collect_ignore|pytest_[A-Za-z0-9_]*)([^A-Za-z0-9_]|$)/)) {
    tk = substr(rest, RSTART, RLENGTH); gsub(/^[^A-Za-z]|[^A-Za-z0-9_]$/, "", tk)
    if (!neutral_plugin(tk) && tk !~ /^pytest_(plugins|configure|addoption)$/) return 1
    rest = substr(rest, RSTART + RLENGTH - 1)
  }
  return 0
}

function py_start(code) { return py_hit(code) || code ~ /(^|[^A-Za-z0-9_.])pytest_(plugins|configure|addoption)([^A-Za-z0-9_]|$)/ }
function bal(s,   k, c, d) { gsub(/"[^"]*"|'[^']*'/, "", s); d = 0; for (k = 1; k <= length(s); k++) { c = substr(s, k, 1); if (c ~ /[([{]/) d++; else if (c ~ /[)\]}]/) d-- }; return d }
function indent_of(line) { match(line, /^[ \t]*/); return RLENGTH }

# A pytest_plugins assignment whose entries are all neutral plugin names.
function plugins_neutral(blk,   r, rest, tk) {
  if (blk !~ /^[ \t]*pytest_plugins[ \t]*(:[^=]*)?[+]?=/) return 0
  r = blk; sub(/^[^=]*=/, "", r); rest = r
  while (match(rest, /"[^"]*"|'[^']*'/)) {
    tk = substr(rest, RSTART + 1, RLENGTH - 2)
    if (!neutral_plugin(tk)) return 0
    rest = substr(rest, 1, RSTART - 1) " " substr(rest, RSTART + RLENGTH)
  }
  gsub(/[][(), \t\n]/, "", rest)
  return rest == ""
}

function reg_stmt(c) {
  if (c ~ /^[ \t]*pass[ \t]*$/) return 1
  if (c ~ /^[ \t]*config[.]addinivalue_line[(][ \t]*["']markers["']/) return 1
  if (c ~ /^[ \t]*(parser|group)[.](addoption|addini)[(]/) return 1
  if (c ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*parser[.]getgroup[(]/) return 1
  return 0
}

# A pytest_configure or pytest_addoption hook whose body only registers markers or options.
function reg_neutral(blk,   n, B, i, d) {
  n = split(blk, B, "\n")
  if (B[1] !~ /^[ \t]*(async[ \t]+)?def[ \t]+pytest_(configure|addoption)[ \t]*[(]/) return 0
  if (B[1] ~ /[)][ \t]*:[ \t]*[^ \t]/) return 0
  d = bal(B[1])
  for (i = 2; i <= n; i++) {
    if (d <= 0 && !reg_stmt(B[i])) return 0
    d += bal(B[i])
  }
  return 1
}

# Code blocks that can hide tests, one set fact each, so a new or edited block is a finding and plain fixtures and helpers are not read.
function do_conftest(   n, L, C, i, j, m, B, k, blk, base, depth, l, hit) {
  n = split(T, L, "\n"); QS = ""
  for (i = 1; i <= n; i++) { C[i] = py_code(L[i]); sub(/[ \t]+$/, "", C[i]) }
  for (i = 1; i <= n; i++) {
    if (!py_start(C[i])) continue
    base = indent_of(C[i]); blk = C[i]; depth = bal(C[i])
    for (j = i + 1; j <= n; j++) {
      l = C[j]
      if (l ~ /[^ \t]/ && depth <= 0 && indent_of(l) <= base) break
      if (l ~ /[^ \t]/) blk = blk "\n" l
      depth += bal(l)
    }
    hit = 0; m = split(blk, B, "\n")
    for (k = 1; k <= m; k++) if (py_hit(B[k])) { hit = 1; break }
    if (!hit) hit = (B[1] ~ /(^|[^A-Za-z0-9_.])pytest_plugins([^A-Za-z0-9_]|$)/) ? !plugins_neutral(blk) : !reg_neutral(blk)
    if (hit) emit("set", "conftest-hook", blk)
    i = j - 1
  }
}

function do_budget() {
  if (!find("TEST_BUDGET_MAX_RATIO-[0-9]+([.][0-9]+)?[}]", 1)) fail("no TEST_BUDGET_MAX_RATIO default found")
  emit("max", "test-budget-ratio", num_in(substr(T, MS + 21, ML - 21)))
}

function do_gatetime(   i, n, L, line, k, v) {
  n = split(T, L, "\n")
  for (i = 1; i <= n; i++) {
    line = L[i]
    if (line == "" || line ~ /^#/) continue
    if (line !~ /^[a-z_]+=[0-9]+$/) fail("gate-budget.conf line " i " is not key=integer")
    k = substr(line, 1, index(line, "=") - 1); v = substr(line, index(line, "=") + 1)
    if (k == "total_budget_seconds" || k == "per_gate_budget_seconds" || k == "regression_percent") emit("max", "gatetime:" k, v)
    else if (k != "runs_kept") fail("gate-budget.conf line " i ": unknown key " k)
  }
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
  else if (K == "sonar") do_sonar()
  else if (K == "pkgjson") do_pkgjson()
  else if (K == "tsconfig") { T = clean(T, "js"); do_tsconfig() }
  else if (K == "pyright") { T = clean(T, "js"); do_pyright() }
  else if (K == "conftest") do_conftest()
  else if (K == "budget") do_budget()
  else if (K == "gates") do_gates()
  else if (K == "hosts") do_hosts()
  else if (K == "gatetime") do_gatetime()
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
function script_at_base(v,   s) {
  for (s in bscr) if (index(v, s ": ") == 1) return 1
  return 0
}
function nm(key,   i) { i = index(key, "#"); return i ? substr(key, 1, i - 1) : key }
function stronger(kind, a, b) { return (kind == "max") ? (a + 0 < b + 0) : (a + 0 > b + 0) }
{
  k = $1 SUBSEP $2
  if (FILENAME == ARGV[1]) {
    if ($1 == "set") bset[k SUBSEP $3] = 1
    else if ($1 == "req") breq[k SUBSEP $3] = 1
    else if ($1 == "cfg") bcfg[$2] = $3
    else if ($1 == "wl") bwl[$2] = $3
    else if ($1 == "scr") bscr[$2] = 1
    else if ($1 == "flag") { if (!($2 in bflag) || $3 + 0 < bflag[$2] + 0) bflag[$2] = $3 }
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
    else if ($1 == "wl") hwl[$2] = $3
    else if ($1 == "scr") { }
    else if ($1 == "flag") { if (!($2 in hflag) || $3 + 0 < hflag[$2] + 0) hflag[$2] = $3 }
    else if (!(k in hagg)) { hagg[k] = $3; horder[++nh] = k }
    else if (($1 == "max" && $3 + 0 > hagg[k] + 0) || ($1 != "max" && $3 + 0 < hagg[k] + 0)) hagg[k] = $3
  }
}
END {
  bad = 0
  for (i = 1; i <= no; i++) {
    k = order[i]; split(k, p, SUBSEP)
    if (!(k in hagg)) { printf "WEAKENED %s: %s %s was %s, now removed\n", F, p[1], p[2], label(p[1], bagg[k]); bad = 1 }
    else if (p[1] == "max" && hagg[k] + 0 > bagg[k] + 0) { printf "WEAKENED %s: limit %s was %s%s, now %s\n", F, p[2], bagg[k], (SEEDED + 0 ? " (seeded default)" : ""), hagg[k]; bad = 1 }
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
  if (!NEWFILE) for (i = 1; i <= nn; i++) { split(hnew[i], p, SUBSEP); if (p[2] == "script-flag" && p[3] ~ /: (--config|-c|--workspace|--root)([ =]|$)/ && !script_at_base(p[3])) continue; if (p[2] == "conftest-hook") printf "WEAKENED %s: new or edited collection hook, plugin list, collect_ignore, autouse, skip or exit block, which can hide tests: '%s'\n", F, substr(p[3], 1, 120); else printf "WEAKENED %s: new ignore or exclude in %s was absent, now '%s'\n", F, p[2], p[3]; bad = 1 }
  for (k in hwl) if (!(k in bwl) && k ~ /^(prepare|prepublish|prepack|install|preinstall|postinstall)$/) { printf "WEAKENED %s: new install-time script %s (it runs on every install and can skip the gates; a gate script may only change by the known-safe words in the gate-ratchet.sh header)\n", F, k; bad = 1 }
  for (k in bwl) {
    if (!(k in hwl)) { printf "WEAKENED %s: script %s was '%s', now removed (a gate script may only change by the known-safe words in the gate-ratchet.sh header)\n", F, k, bwl[k]; bad = 1 }
    else if (hwl[k] != bwl[k]) { printf "WEAKENED %s: script %s was '%s', now '%s' (a gate script may only change by the known-safe words in the gate-ratchet.sh header)\n", F, k, bwl[k], hwl[k]; bad = 1 }
  }
  for (k in bflag) {
    if (bflag[k] + 0 != 1) continue
    if (!(k in hflag)) { printf "WEAKENED %s: strictness option %s was on, now removed\n", F, k; bad = 1 }
    else if (hflag[k] + 0 == 0) { printf "WEAKENED %s: strictness option %s was on, now off\n", F, k; bad = 1 }
  }
  for (k in hflag) if (hflag[k] + 0 == 0 && !(k in bflag)) { printf "WEAKENED %s: strictness option %s is off in a setting the merge base did not have\n", F, k; bad = 1 }
  for (k in bcfg) {
    if (!(k in hcfg)) { printf "WEAKENED %s: setting %s was '%s', now removed (a setting the checker does not know must stay as it was)\n", F, k, bcfg[k]; bad = 1 }
    else if (hcfg[k] != bcfg[k]) { printf "WEAKENED %s: setting %s was '%s', now '%s' (a setting the checker does not know must stay as it was)\n", F, k, bcfg[k], hcfg[k]; bad = 1 }
  }
  if (!NEWFILE) for (k in hcfg) if (!(k in bcfg)) { printf "WEAKENED %s: new setting %s = '%s' (a setting the checker does not know must stay as it was)\n", F, k, hcfg[k]; bad = 1 }
  for (k in breq) if (!(k in hreq) && !NEWFILE) { split(k, p, SUBSEP); printf "WEAKENED %s: required %s '%s' was present, now removed\n", F, p[2], p[3]; bad = 1 }
  exit bad
}
AWK

if [ -n "$list_mode" ]; then
  guard_scan "$list_ref" || die "--list-guarded: cannot list or read the tracked files of $list_ref"
  [ -s "$wd/tracked.lst" ] || die "--list-guarded: cannot list the tracked files of $list_ref"
  classify < "$wd/tracked.lst"
  exit 0
fi

# A gitlink (mode 160000, a submodule) is listed here but is no blob: `git show` cannot read it, so leave it out as guard_scan does.
git ls-tree -r "$mb" > "$wd/base.tree" || die "cannot list the tracked files of the merge base $mb"
git ls-tree -r HEAD > "$wd/head.tree" || die "cannot list the tracked files of HEAD"
awk -F'\t' '$1 !~ /^160000 / { print substr($0, index($0, "\t") + 1) }' "$wd/base.tree" > "$wd/base.paths" || die "cannot read the tracked files of the merge base $mb"
awk -F'\t' '$1 !~ /^160000 / { print substr($0, index($0, "\t") + 1) }' "$wd/head.tree" > "$wd/head.paths" || die "cannot read the tracked files of HEAD"
sort -u "$wd/base.paths" "$wd/head.paths" > "$wd/paths.lst" || die "cannot merge the tracked file lists"
[ -s "$wd/paths.lst" ] || die "cannot list tracked files"
if ! gs_test grep -Eq '(^|/)[.]claude/gates[.]txt$' "$wd/base.paths"; then
  echo "gate-ratchet: first adoption: the merge base has no .claude/gates.txt, nothing to compare"
  exit 0
fi
guard_scan "$mb" || die "cannot derive the guarded set of the merge base $mb (a tracked file could not be read)"
classify < "$wd/paths.lst" > "$wd/kinds.tsv"
git diff -M --name-status --diff-filter=R "$mb" HEAD > "$wd/renames.txt" || die "cannot list the renames since the merge base $mb"

weakened=0
unreadable=0
checked=0
while IFS=$'\t' read -r kind path _; do
  checked=$((checked + 1))
  : > "$wd/base"; : > "$wd/head"; : > "$wd/base.f"; : > "$wd/head.f"
  have_base=0; have_head=0
  if base_has "$path"; then
    git show "$mb:$path" > "$wd/base" || die "cannot read $path at the merge base $mb"
    have_base=1
  fi
  if head_has "$path"; then
    git show "HEAD:$path" > "$wd/head" || die "cannot read $path at HEAD"
    have_head=1
  fi
  if [ "$have_head" -eq 0 ]; then
    if [ "$kind" = conftest ]; then continue; fi
    moved=$(awk -F'\t' -v p="$path" '$2 == p { print $3; exit }' "$wd/renames.txt") || die "cannot read the renames since the merge base"
    if [ -n "$moved" ]; then
      printf 'WEAKENED %s: file was present at the merge base, now removed (renamed to %s; tools read the original name, so a rename counts as a removal)\n' "$path" "$moved"
    else
      printf 'WEAKENED %s: file was present at the merge base, now removed\n' "$path"
    fi
    weakened=1
    continue
  fi
  file_bad=0
  newfile=""
  seeded=0
  if [ "$kind" != guard ] && [ "$kind" != allow ] && [ "$kind" != patterns ]; then
    if ! msg=$(awk -v K="$kind" -v B="$have_base" -f "$wd/facts.awk" "$wd/head" 2>&1 > "$wd/head.f"); then
      printf 'UNREADABLE %s: %s (fail closed)\n' "$path" "$msg"
      unreadable=1
      continue
    fi
    if [ "$have_base" -eq 0 ]; then
      case "$kind" in tsconfig | pyright) newfile=1; : > "$wd/base.f" ;; conftest) : > "$wd/base.f" ;; gatetime) seeded=1; printf 'max\tgatetime:total_budget_seconds\t600\nmax\tgatetime:per_gate_budget_seconds\t180\nmax\tgatetime:regression_percent\t25\n' > "$wd/base.f" ;; *) continue ;; esac
    elif ! msg=$(awk -v K="$kind" -v B="$have_base" -f "$wd/facts.awk" "$wd/base" 2>&1 > "$wd/base.f"); then
      printf 'NOTE %s: unreadable at the merge base (%s); compared with an empty baseline\n' "$path" "$msg"
      : > "$wd/base.f"
    fi
    if ! awk -v F="$path" -v NEWFILE="$newfile" -v SEEDED="$seeded" -f "$wd/compare.awk" "$wd/base.f" "$wd/head.f"; then
      file_bad=1
    fi
  fi
  if [ "$have_base" -eq 0 ]; then
    if [ "$file_bad" -eq 1 ]; then weakened=1; fi
    continue
  fi
  if [ "$file_bad" -eq 0 ] && ! content_ok "$kind"; then
    case "$kind" in
      allow) printf 'WEAKENED %s: the advisory allow-list gained a line the merge base did not have\n' "$path" ;;
      patterns) printf 'WEAKENED %s: comment-hygiene patterns were removed, edited or reordered (lines may only be added at the end)\n' "$path" ;;
      *) printf 'WEAKENED %s: gate script, runner or manifest changed (content differs from the merge base)\n' "$path" ;;
    esac
    file_bad=1
  fi
  if [ "$file_bad" -eq 1 ]; then weakened=1; fi
done < "$wd/kinds.tsv"

added=$(git diff --no-renames --name-only --diff-filter=A "$mb" HEAD) || die "cannot list the files added since the merge base $mb"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  why=$(shadow_reason "$path")
  src=$?
  if [ "$src" -ge 2 ]; then die "cannot check $path against the ratcheted config files"; fi
  if [ "$src" -eq 0 ]; then
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
