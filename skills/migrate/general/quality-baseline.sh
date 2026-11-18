#!/usr/bin/env bash
# Quality baseline: measure a project. It does not intentionally write to it; the last row reports any write.
# Usage: quality-baseline.sh <project-dir> [--label before|after] [--static|--full [--keep-coverage <dir>]]
#        quality-baseline.sh --compare <before-file> [<after-file>]
#   --compare  reads two saved tables (or one table with before and after columns), prints a verdict table and exits 1
#            when lint or type findings, tests failed, suppressions, exclusions, duplication or complexity rose, or
#            coverage or configured thresholds fell, or a number that was measured is no longer measured.
#   --static (default) counts files and lines only. It runs no project code and no tool, uses no network, installs nothing.
#   --full   also runs the project's lint, typecheck and tests, and installs pinned scratch tools into its own scratch directory
#            (network access). Project code runs: tests execute.
#   --keep-coverage <dir>  with --full: copy the Cobertura XML to <dir>/cobertura.xml; <dir> must be outside the project
#            and its parent must exist.
# Prints one markdown table on stdout. Exit 0 when measured, 2 on a usage error.
# --compare exits 0 when nothing got worse and no gate configuration file changed, 1 when a number got worse, 2 on unusable input, 3 when a gate configuration file changed and nothing got worse.
# Needs bash 3.2+, BSD or GNU coreutils, git; python3 or node reads the JSON/XML reports.
set -u

# Scratch tool versions are pinned so a before run and an after run measure with identical tools.
ESLINT_VERSION=10.12.0
TSESLINT_VERSION=8.60.1
SONARJS_VERSION=4.2.2
JSCPD_VERSION=5.4.3
DIFFCOVER_VERSION=11.0.3   # used by quality-pass.md
COMPLEXITY_LIMIT=15
RUN_LIMIT=${QB_RUN_LIMIT:-600}

# Gate configuration files whose content hash goes into the table; matched on the project-relative path, never on contents.
is_gate_config() {
  case "$1" in
    *'|'*|*$'\n'*|node_modules/*|*/node_modules/*|.venv/*|*/.venv/*|venv/*|*/venv/*|dist/*|*/dist/*|build/*|*/build/*|.next/*|*/.next/*|.git/*|*/.git/*|coverage/*|*/coverage/*|*/__pycache__/*) return 1 ;;
    secrets/*|*/secrets/*|.secrets/*|*/.secrets/*) return 1 ;;
  esac
  case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
    .env*|*.pem|*.key|*.p12|*.pfx|*secret*|*credential*|id_rsa*|*.token) return 1 ;;
  esac
  case "$1" in
    # The bracket in .hus[k]y keeps the lint that forbids that hook manager's name in skills/ from matching this fingerprint pattern.
    .github/workflows/*.yml|.github/workflows/*.yaml|.github/actions/*|.github/dependabot.yml|.github/dependabot.yaml|.hus[k]y/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*) return 0 ;;
  esac
  case "$(basename "$1")" in
    playwright.config.*|knip.json|.oxlintrc|.oxlintrc.*|.stylelintrc|.stylelintrc.*|.semgrepignore) return 0 ;;
    eslint.config.*|.eslintrc|.eslintrc.*|.eslintignore|.prettierrc|.prettierrc.*|prettier.config.*|.prettierignore|.editorconfig|biome.json|biome.jsonc) return 0 ;;
    tsconfig*.json|jsconfig.json|next.config.*|nest-cli.json|vite.config.*|vitest.config.*|vitest.workspace.*|jest.config.*|.nycrc|.nycrc.*|.c8rc|.c8rc.*|c8.config.*) return 0 ;;
    codecov.yml|.codecov.yml|.jscpd.json|sonar-project.properties|stryker.conf.*|stryker.config.*|.stryker.conf.*|.stryker.config.*) return 0 ;;
    ruff.toml|.ruff.toml|mypy.ini|.mypy.ini|pyrightconfig.json|.flake8|.pylintrc|pylintrc|pytest.ini|.coveragerc|conftest.py|setup.cfg|tox.ini|pyproject.toml|package.json) return 0 ;;
    lefthook.yml|lefthook.yaml|.gitleaks.toml|gitleaks.toml|.gitleaksignore|.pre-commit-config.yaml|.gitlab-ci.yml|azure-pipelines.yml|Jenkinsfile) return 0 ;;
  esac
  return 1
}

usage() { echo "usage: quality-baseline.sh <project-dir> [--label before|after] [--static|--full [--keep-coverage <dir>]] | --compare <before-file> [<after-file>]" >&2; exit 2; }

# vals <file> <first|last>: print "metric<TAB>value" for each table row, from the first or the last value column.
# A trailing "verdict" column (this script's own compare output) is not a value column.
vals() {
  awk -F'|' -v which="$2" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    NF >= 4 {
      if (trim($2) == "Metric") off = (trim($(NF - 1)) == "verdict") ? 1 : 0
      k = trim($2); v = trim(which == "first" ? $3 : $(NF - 1 - off))
      if (k != "") print k "\t" v
    }' "$1"
}

# vcount <file>: number of value columns in the table.
vcount() {
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    NF >= 4 { n = NF - 3; if (trim($2) == "Metric" && trim($(NF - 1)) == "verdict") n-- }
    END { print n + 0 }' "$1"
}

# row_of <file> <first|last> <metric>: one metric's value from the first or the last value column.
row_of() { vals "$1" "$2" | awk -F'\t' -v k="$3" '$1 == k { print $2; exit }'; }

# commits_ok <before-file> <after-file>: tie the two tables to commits; print a line, return 2 when they are not a before and an after.
commits_ok() {
  local bh ah bt at repo=${QB_REPO:-.} inrepo=0
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 && inrepo=1
  bh=$(row_of "$1" first "git head"); ah=$(row_of "$2" last "git head")
  bt=$(row_of "$1" first "git tree"); at=$(row_of "$2" last "git tree")
  if ! printf '%s' "$bh" | grep -Eqx '[0-9a-f]{40}|no git' || ! printf '%s' "$ah" | grep -Eqx '[0-9a-f]{40}|no git'; then
    echo "--compare: a table has no git head row; take both runs with this script's --full mode" >&2; return 2
  fi
  if [ "$bh" = "no git" ] || [ "$ah" = "no git" ]; then
    if [ "$inrepo" -eq 1 ]; then echo "--compare: a table says no git but $repo is a git repository; retake the baseline with this script inside the repository" >&2; return 2; fi
    echo "commits: no git, the tie to a commit is not checked"; return 0
  fi
  echo "commits: before ${bh:0:9} ($bt), after ${ah:0:9} ($at)"
  if [ "$inrepo" -eq 0 ]; then echo "--compare: the tables carry commit hashes but $repo is not a git repository; run from the repository or set QB_REPO" >&2; return 2; fi
  if ! git -C "$repo" cat-file -e "$bh^{commit}" 2>/dev/null || ! git -C "$repo" cat-file -e "$ah^{commit}" 2>/dev/null; then
    echo "--compare: a commit named in a table is not in $repo, so the tie cannot be checked" >&2; return 2
  fi
  if [ "$bh" = "$ah" ]; then
    if [ "$bt" = clean ] && [ "$at" = clean ]; then
      echo "--compare: both runs are at one commit with a clean tree, so the before run was not taken before the change" >&2; return 2
    fi
  else
    git -C "$repo" merge-base --is-ancestor "$bh" "$ah" || { echo "--compare: the before commit is not an ancestor of the after commit" >&2; return 2; }
  fi
  return 0
}

# compare_main <before-file> [<after-file>]: print a verdict table; exit 1 when a number got worse or is no longer measured, 2 on a table it cannot trust.
compare_main() {
  local bf=$1 af=${2:-$1} f
  for f in "$bf" "$af"; do [ -f "$f" ] || { echo "--compare: cannot read $f" >&2; exit 2; }; done
  if [ $# -eq 1 ] && [ "$(vcount "$bf")" -lt 2 ]; then
    echo "--compare: $bf has one value column; pass a second file or a file with before and after columns" >&2; exit 2
  fi
  if ! { [ "$(row_of "$bf" first mode)" = full ] && [ "$(row_of "$af" last mode)" = full ]; }; then
    echo "--compare: both tables must come from --full runs (mode row full); a --static table measures no lint, type, test or coverage number" >&2; exit 2
  fi
  commits_ok "$bf" "$af" || exit 2
  { vals "$bf" first; echo "---"; vals "$af" last; } | awk -F'\t' '
    function has(v) { return v ~ /^[0-9]+(\.[0-9]+)?( |%|$)/ }
    function num(v) { match(v, /^[0-9]+(\.[0-9]+)?/); return substr(v, RSTART, RLENGTH) + 0 }
    function na(v) { return v ~ /^n\/a( |$)/ }
    function absent(v) { return v ~ /^n\/a \((no pnpm|dependencies not installed: no node_modules|no eslint\.config\.\*|no tsconfig\.json|no vitest or jest in package\.json|ruff not installed|no configured type checker on PATH or in \.venv|no python|pytest not installed|pytest-cov not installed|no src, app or lib directory|no pnpm or npx|no package\.json, pyproject\.toml or requirements file)\)$/ }
    function total(v) { return match(v, / of [0-9]+$/) ? substr(v, RSTART + 4) + 0 : -1 }
    function key(k) { return k ~ /^complexity over/ ? "complexity" : k }
    $0 == "---" { seen = 1; next }
    !seen { if (key($1) in b) { printf "--compare: the before table has more than one %s row\n", key($1) > "/dev/stderr"; err = 2; exit 2 } b[key($1)] = $2; next }
    { if (key($1) in a) { printf "--compare: the after table has more than one %s row\n", key($1) > "/dev/stderr"; err = 2; exit 2 } a[key($1)] = $2 }
    END {
      if (err) exit err
      n = split("lint findings:-1;type errors:-1;tests failed:-1;complexity:-1;duplication:-1;suppression lines matching (code files):-1;coverage, lint and Sonar exclusions:-1;line coverage:1;coverage thresholds configured:1", spec, ";")
      for (i = 1; i <= n; i++) {
        split(spec[i], p, ":"); m = p[1]
        if (!(m in b) || !(m in a)) { printf "--compare: the table has no %s row\n", m > "/dev/stderr"; exit 2 }
        if (!has(b[m]) && !na(b[m])) { printf "--compare: malformed %s value before: %s\n", m, b[m] > "/dev/stderr"; exit 2 }
        if (!has(a[m]) && !na(a[m])) { printf "--compare: malformed %s value after: %s\n", m, a[m] > "/dev/stderr"; exit 2 }
        if (na(b[m]) && !absent(b[m])) { printf "--compare: %s was not measured before for a reason other than an absent tool: %s\n", m, b[m] > "/dev/stderr"; exit 2 }
      }
      for (w = 1; w <= 2; w++) {
        t = (w == 1) ? "before" : "after"; gv = (w == 1) ? b["gate config files"] : a["gate config files"]
        if (gv == "") { printf "--compare: the %s table has no gate configuration section; retake the baseline with this version of the script\n", t > "/dev/stderr"; exit 2 }
        if (!has(gv)) { printf "--compare: gate configuration files were not hashed in the %s table (%s); install shasum or sha256sum and retake the baseline\n", t, gv > "/dev/stderr"; exit 2 }
      }
      gn = 0
      for (k in b) if (index(k, "gate config: ") == 1 && b[k] != "-") seen_g[k] = 1
      for (k in a) if (index(k, "gate config: ") == 1 && a[k] != "-") seen_g[k] = 1
      for (k in seen_g) { j = ++gn; while (j > 1 && gl[j - 1] > k) { gl[j] = gl[j - 1]; j-- } gl[j] = k }
      print "| Metric | before | after | verdict |"; print "|---|---|---|---|"
      cmp = 0; bad = 0
      for (i = 1; i <= n; i++) {
        split(spec[i], p, ":"); m = p[1]; dir = p[2]; bv = b[m]; av = a[m]
        if (na(bv)) v = has(av) ? "newly measured (" av ")" : "skipped (tool absent before and after)"
        else if (na(av)) { v = "WORSE (not measured after)"; bad++; cmp++ }
        else {
          cmp++; d = (num(av) - num(bv)) * dir
          if (d < 0) { v = "WORSE"; bad++ } else if (d > 0) v = "improved"; else v = "same"
          if (m ~ /^suppression/ && d < 0) supbad = 1
          if (m == "tests failed" && total(bv) >= 0 && total(av) >= 0 && total(av) < total(bv)) {
            v = "WORSE (test total fell " total(bv) " to " total(av) "; a deliberate, confirmed consolidation is recorded by the user retaking the baseline, not by the agent)"; if (d >= 0) bad++
          }
        }
        printf "| %s | %s | %s | %s |\n", m, bv, av, v
      }
      split("mode;git head;git tree", extra, ";")
      for (i = 1; i <= 3; i++) printf "| %s | %s | %s | - |\n", extra[i], b[extra[i]], a[extra[i]]
      printf "| gate config files | %s | %s | - |\n", b["gate config files"], a["gate config files"]
      gc = 0
      for (i = 1; i <= gn; i++) {
        k = gl[i]; bv = (k in b && b[k] != "-") ? b[k] : "-"; av = (k in a && a[k] != "-") ? a[k] : "-"
        st = (bv == "-") ? "added" : (av == "-") ? "removed" : (bv == av) ? "same" : "changed"
        printf "| %s | %s | %s | %s |\n", k, bv, av, st
        if (st != "same") { gc++; gstate[gc] = st; gpath[gc] = substr(k, 14) }
      }
      if (gc > 0) { printf "\nGate configuration changed (%d):\n", gc; for (i = 1; i <= gc; i++) printf "  %s: %s\n", gstate[i], gpath[i] }
      if (supbad) print "\nSuppressions rose: a user-approved suppression is recorded by the user retaking the baseline with the reason; the agent never retakes it."
      if (cmp == 0) { print "\nNothing comparable: the before table has no measured number."; exit 1 }
      if (bad > 0) { printf "\nFAIL: %d metric(s) got worse.\n", bad; exit 1 }
      if (gc > 0) { printf "\nREVIEW: %d gate configuration file(s) changed; show this list to the user before reporting the migration as done.\n", gc; exit 3 }
      print "\nOK: no measured number got worse."
    }'
}

if [ "${1:-}" = --compare ]; then
  shift
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || usage
  compare_main "$@"
  exit $?
fi

LABEL=before
MODE=static
PROJECT=
KEEP=
while [ $# -gt 0 ]; do
  case "$1" in
    --label) [ $# -ge 2 ] || usage; LABEL=$2; shift 2 ;;
    --static) MODE=static; shift ;;
    --full) MODE=full; shift ;;
    --keep-coverage) [ $# -ge 2 ] || usage; KEEP=$2; shift 2 ;;
    -*) usage ;;
    *) [ -z "$PROJECT" ] || usage; PROJECT=$1; shift ;;
  esac
done
if [ -z "$PROJECT" ] || [ ! -d "$PROJECT" ]; then usage; fi
case "$LABEL" in before|after) ;; *) usage ;; esac
P=$(cd "$PROJECT" && pwd -P) || usage
if [ -n "$KEEP" ]; then
  [ "$MODE" = full ] || usage
  KEEPPARENT=$(cd "$(dirname "$KEEP")" 2>/dev/null && pwd -P) || usage
  KEEP="$KEEPPARENT/$(basename "$KEEP")"
  # Refuse a target that resolves to the project or inside it. Resolved paths cover symlinks; -ef covers a
  # case-variant spelling of the project path on a case-insensitive filesystem.
  inside_project() {
    local d=$1
    while :; do
      [ "$d" = "$P" ] && return 0
      [ -e "$d" ] && [ "$d" -ef "$P" ] && return 0
      [ "$d" = / ] && return 1
      d=$(dirname "$d")
    done
  }
  if [ -L "$KEEP" ] || [ -e "$KEEP" ] && [ ! -d "$KEEP" ]; then echo "--keep-coverage: $KEEP must be a directory" >&2; exit 2; fi
  if [ -d "$KEEP" ]; then
    KEEP=$(cd "$KEEP" && pwd -P)
    if inside_project "$KEEP"; then echo "--keep-coverage must name a directory outside the project" >&2; exit 2; fi
  elif inside_project "$KEEPPARENT"; then echo "--keep-coverage must name a directory outside the project" >&2; exit 2
  fi
fi

# Read-only git: no optional lock files, no fsmonitor daemon.
g() { GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false "$@"; }

S=$(mktemp -d "${TMPDIR:-/tmp}/qbaseline.XXXXXX") || { echo "cannot create a scratch directory" >&2; exit 2; }
# `limited` starts each background job in its own process group (set -m), so a signal reaches the tool's children too.
CHILD=; WATCH=
cleanup() {
  local p
  if [ -n "$CHILD$WATCH" ]; then
    for p in $CHILD $WATCH; do kill -TERM -- "-$p" 2>/dev/null; done
    sleep 1
    for p in $CHILD $WATCH; do kill -KILL -- "-$p" 2>/dev/null; done
  fi
  case "${S:-}" in
    */qbaseline.*) if [ -d "$S" ]; then rm -rf "$S"; fi ;;
  esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

have() { command -v "$1" >/dev/null 2>&1; }
ROWS=
row() { ROWS="${ROWS}| $1 | $2 |
"; }

# limited <out-file> <cmd...>: run in the project dir, stdin closed, stdout to the file and stderr to <file>.err,
# killed after RUN_LIMIT seconds. Sets RC; 124 means timeout.
limited() {
  local out=$1; shift
  set -m
  # The braces hide bash's harmless "setpgid: Operation not permitted" race notice (the child sets its own group).
  { ( cd "$P" && exec "$@" ) </dev/null >"$out" 2>"$out.err" & CHILD=$!; } 2>/dev/null
  { ( sleep "$RUN_LIMIT"; : >"$out.timeout"; kill -TERM -- "-$CHILD"; sleep 2; kill -KILL -- "-$CHILD" ) >/dev/null 2>&1 & WATCH=$!; } 2>/dev/null
  set +m
  { wait "$CHILD"; RC=$?; } 2>/dev/null
  kill -KILL -- "-$WATCH" 2>/dev/null; wait "$WATCH" 2>/dev/null
  kill -KILL -- "-$CHILD" 2>/dev/null
  CHILD=; WATCH=
  if [ -f "$out.timeout" ]; then RC=124; fi
  return 0
}

# jval <kind> <file>: print a number from a JSON or XML report, empty when unreadable.
jval() {
  [ -f "$2" ] || return 0
  if have python3; then
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, re, sys
k, f = sys.argv[1], sys.argv[2]
try:
    if k == "eslint":
        print(sum(len(x["messages"]) for x in json.load(open(f))))
    elif k == "sonar":
        print(sum(1 for x in json.load(open(f)) for m in x["messages"] if m.get("ruleId") == "sonarjs/cognitive-complexity"))
    elif k == "list":
        print(len(json.load(open(f))))
    elif k == "jscpd":
        print(json.load(open(f))["statistics"]["total"]["percentage"])
    elif k == "vitest":
        d = json.load(open(f)); print(d["numFailedTests"], d["numTotalTests"])
    elif k == "pyright":
        print(json.load(open(f))["summary"]["errorCount"])
    elif k == "cobertura":
        m = re.search(r'<coverage[^>]*line-rate="([0-9.]+)"', open(f).read(4000)); print(round(float(m.group(1)) * 100, 2))
    elif k == "junit":
        t = re.search(r"<testsuite\s[^>]*>", open(f).read()).group(0)
        a = lambda n: int(re.search(n + r'="(\d+)"', t).group(1))
        print(a("failures") + a("errors"), a("tests"))
except Exception:
    pass
PY
  elif have node; then
    node - "$1" "$2" <<'JS' 2>/dev/null
const fs = require("fs");
const [k, f] = process.argv.slice(2);
try {
  const txt = fs.readFileSync(f, "utf8");
  const j = () => JSON.parse(txt);
  if (k === "eslint") console.log(j().reduce((n, x) => n + x.messages.length, 0));
  else if (k === "sonar") console.log(j().reduce((n, x) => n + x.messages.filter((m) => m.ruleId === "sonarjs/cognitive-complexity").length, 0));
  else if (k === "list") console.log(j().length);
  else if (k === "jscpd") console.log(j().statistics.total.percentage);
  else if (k === "vitest") console.log(j().numFailedTests, j().numTotalTests);
  else if (k === "pyright") console.log(j().summary.errorCount);
  else if (k === "cobertura") console.log(Math.round(parseFloat(txt.slice(0, 4000).match(/<coverage[^>]*line-rate="([0-9.]+)"/)[1]) * 10000) / 100);
  else if (k === "junit") {
    const t = txt.match(/<testsuite\s[^>]*>/)[0];
    const a = (n) => parseInt(t.match(new RegExp(n + '="(\\d+)"'))[1], 10);
    console.log(a("failures") + a("errors"), a("tests"));
  }
} catch (e) { /* unreadable report: print nothing */ }
JS
  fi
}

# Tracked and untracked-but-not-ignored files that still exist, NUL separated.
# Falls back to find when the project is not a git repository.
list_files() {
  if is_git; then
    ( cd "$P" && g ls-files -z --cached --others --exclude-standard )
  else
    ( cd "$P" && find . \( -name node_modules -o -name .venv -o -name dist -o -name .next -o -name .git \) -prune -o -type f -print0 )
  fi
}

is_git() { ( cd "$P" && g rev-parse --is-inside-work-tree ) >/dev/null 2>&1; }

# Everything a run could have written to the project: git status, a hash of the working diff, and any file
# newer than a stamp (this also catches caches in ignored directories and non-git projects).
status_snapshot() {
  if is_git; then
    ( cd "$P" && g status --porcelain -z --untracked-files=all ) | tr '\0' '\n'
    ( cd "$P" && g diff --no-ext-diff --no-textconv HEAD 2>/dev/null | cksum )
  fi
}
newer_files() { find "$P" -type f -newer "$S/stamp" -not -path '*/.git/*' -not -path "$S/*" 2>/dev/null; }

# code_files: the code files of list_files (no config, no env file, no key, no registry credential), NUL separated.
code_files() {
  local f
  while IFS= read -r -d '' f; do
    printf '%s' "$f" | grep -Eq "$CODERE" || continue
    printf '%s' "$f" | grep -Eq "$SKIPRE" && continue
    printf '%s\0' "$f"
  done < <(list_files)
}

# copy_tree <dest>: scratch copy of the working tree's code files, including uncommitted and untracked ones.
# Configs, .npmrc, .env*, keys and other secrets are never copied.
copy_tree() {
  mkdir -p "$1" || return 1
  code_files | ( cd "$P" && tar --null -T - -cf - 2>/dev/null ) | tar -x -C "$1"
}

STACK=unknown
if [ -f "$P/package.json" ]; then STACK=typescript
elif [ -f "$P/pyproject.toml" ] || ls "$P"/requirements*.txt >/dev/null 2>&1; then STACK=python
fi

SRC=
for d in src app lib; do [ -d "$P/$d" ] && { SRC=$d; break; }; done
[ -n "$SRC" ] || SRC=.

BEFORE=$(status_snapshot)
# The commit and tree state the table was taken at; --compare ties a before and an after run to them.
GITHEAD="no git"; GITTREE="no git"
if is_git; then
  h=$( cd "$P" && g rev-parse HEAD 2>/dev/null ) && [ -n "$h" ] && GITHEAD=$h
  if [ "$GITHEAD" != "no git" ]; then
    if [ -n "$( cd "$P" && g status --porcelain --untracked-files=all 2>/dev/null )" ]; then GITTREE=dirty; else GITTREE=clean; fi
  fi
fi
: >"$S/stamp"

NA_NOSTACK="n/a (no package.json, pyproject.toml or requirements file)"
LINT=$NA_NOSTACK TYPES=$NA_NOSTACK TESTS=$NA_NOSTACK TESTRC=$NA_NOSTACK SECS=$NA_NOSTACK COV=$NA_NOSTACK CPLX=$NA_NOSTACK DUP=$NA_NOSTACK
TOOLS=

# ---------------------------------------------------------------- TypeScript
measure_typescript() {
  local nm="n/a (no pnpm)"
  have pnpm || { LINT=$nm; TYPES=$nm; TESTS=$nm; TESTRC=$nm; SECS=$nm; COV=$nm; return; }
  nm="n/a (dependencies not installed: no node_modules)"
  [ -d "$P/node_modules" ] || { LINT=$nm; TYPES=$nm; TESTS=$nm; TESTRC=$nm; SECS=$nm; COV=$nm; return; }

  # Lint: the tool is called directly, never through a project script.
  if ls "$P"/eslint.config.* >/dev/null 2>&1; then
    limited "$S/eslint.log" pnpm exec eslint . -f json -o "$S/eslint.json"
    local n; n=$(jval eslint "$S/eslint.json")
    if [ -n "$n" ]; then LINT=$n; else LINT="n/a (failed: eslint failed, exit $RC)"; fi
  else LINT="n/a (no eslint.config.*)"; fi

  # Types: tsc has no machine-readable output; count its own `error TS` lines from the captured file.
  if [ -f "$P/tsconfig.json" ]; then
    # Never write build info into the project: composite needs incremental, so point its file into scratch.
    # --showConfig resolves extends and JSON comments.
    local tscflags=(--noEmit --incremental false)
    limited "$S/tsconfig.shown" pnpm exec tsc --showConfig
    grep -Eq '"composite"[[:space:]]*:[[:space:]]*true' "$S/tsconfig.shown" && tscflags=(--noEmit --tsBuildInfoFile "$S/tsbuildinfo")
    limited "$S/tsc.log" pnpm exec tsc "${tscflags[@]}"
    if [ "$RC" -eq 124 ]; then TYPES="n/a (failed: timeout)"
    elif [ "$RC" -eq 0 ]; then TYPES=0
    elif grep -q 'error TS' "$S/tsc.log"; then TYPES=$(grep -c 'error TS' "$S/tsc.log")
    else TYPES="n/a (failed: tsc failed, exit $RC)"; fi
  else TYPES="n/a (no tsconfig.json)"; fi

  # Tests and coverage in one run.
  local t0 t1
  t0=$(date +%s)
  if grep -q '"vitest"' "$P/package.json"; then
    limited "$S/test.log" pnpm exec vitest run --cache=false --coverage --coverage.reporter=cobertura --coverage.reportsDirectory="$S/cov" --reporter=json --outputFile="$S/vitest.json"
    t1=$(date +%s)
    local r; r=$(jval vitest "$S/vitest.json")
    if [ -n "$r" ]; then TESTS="${r% *} failed of ${r#* }"; else TESTS="n/a (failed: no test report, exit $RC)"; fi
  elif grep -q '"jest"' "$P/package.json"; then
    limited "$S/test.log" pnpm exec jest --coverage --coverageReporters=cobertura --coverageDirectory="$S/cov" --json --outputFile="$S/jest.json"
    t1=$(date +%s)
    local jt
    jt=$(jval vitest "$S/jest.json")   # jest --json uses the same numFailedTests / numTotalTests keys
    if [ -n "$jt" ]; then TESTS="${jt% *} failed of ${jt#* }"; else TESTS="n/a (failed: no test report, exit $RC)"; fi
  else
    TESTS="n/a (no vitest or jest in package.json)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return
  fi
  if [ "$RC" -eq 124 ]; then TESTRC="timeout"; else TESTRC=$RC; fi
  SECS=$((t1 - t0))
  local c; c=$(jval cobertura "$S/cov/cobertura-coverage.xml")
  if [ -n "$c" ]; then COV="$c%"; else COV="n/a (failed: no coverage report; is a coverage provider installed?)"; fi
}

complexity_typescript() {
  have pnpm || { CPLX="n/a (no pnpm)"; return; }
  local cc="$S/cc"
  copy_tree "$cc" || { CPLX="n/a (failed: could not copy the working tree)"; return; }
  # A minimal manifest: the scratch run needs the three lint packages and no project dependency.
  rm -f "$cc/pnpm-lock.yaml" "$cc/pnpm-workspace.yaml" "$cc/package-lock.json" "$cc/yarn.lock"
  printf '{"name":"qbaseline-scratch","private":true}\n' >"$cc/package.json"
  cat >"$cc/cc.eslint.config.mjs" <<CFG
import tseslint from 'typescript-eslint';
import sonarjs from 'eslint-plugin-sonarjs';
export default [
  { ignores: ['**/node_modules/**', '**/dist/**', '**/.next/**', '**/coverage/**', '**/build/**', '**/*.d.ts'] },
  {
    files: ['**/*.{ts,tsx,js,jsx,mjs,cjs}'],
    languageOptions: { parser: tseslint.parser, parserOptions: { ecmaFeatures: { jsx: true } } },
    plugins: { sonarjs },
    rules: { 'sonarjs/cognitive-complexity': ['error', ${COMPLEXITY_LIMIT}] },
  },
];
CFG
  ( cd "$cc" && pnpm add -D --ignore-workspace --ignore-scripts --save-exact "eslint@$ESLINT_VERSION" "typescript-eslint@$TSESLINT_VERSION" "eslint-plugin-sonarjs@$SONARJS_VERSION" ) </dev/null >"$S/cc-install.log" 2>&1 \
    || { CPLX="n/a (failed: private registry or no network: could not install the scratch lint tools)"; return; }
  ( cd "$cc" && pnpm exec eslint -c cc.eslint.config.mjs --no-inline-config . -f json -o "$S/cc.json" ) </dev/null >"$S/cc-run.log" 2>&1
  local n; n=$(jval sonar "$S/cc.json")
  if [ -n "$n" ]; then CPLX=$n; else CPLX="n/a (failed: complexity run failed)"; fi
}

# ---------------------------------------------------------------- Python
py_bin() { # py_bin <tool>: project virtualenv first, then PATH
  if [ -x "$P/.venv/bin/$1" ]; then echo "$P/.venv/bin/$1"; elif have "$1"; then command -v "$1"; fi
}

measure_python() {
  local ruff py
  ruff=$(py_bin ruff)
  py=$(py_bin python); [ -n "$py" ] || py=$(py_bin python3)

  if [ -n "$ruff" ]; then
    limited "$S/ruff.log" "$ruff" check --no-cache --output-format json -o "$S/ruff.json" .
    local n; n=$(jval list "$S/ruff.json")
    if [ -n "$n" ]; then LINT=$n; else LINT="n/a (ruff failed, exit $RC)"; fi
    TOOLS="${TOOLS}$("$ruff" --version 2>/dev/null); "
  else LINT="n/a (ruff not installed)"; fi

  local pyright mypy
  pyright=$(py_bin pyright); mypy=$(py_bin mypy)
  if [ -n "$pyright" ] && { [ -f "$P/pyrightconfig.json" ] || grep -q 'tool.pyright' "$P/pyproject.toml" 2>/dev/null; }; then
    limited "$S/pyright.json" "$pyright" --outputjson
    local n; n=$(jval pyright "$S/pyright.json")
    if [ -n "$n" ]; then TYPES=$n; else TYPES="n/a (failed: pyright failed, exit $RC)"; fi
  elif [ -n "$mypy" ] && { [ -f "$P/mypy.ini" ] || grep -q 'tool.mypy' "$P/pyproject.toml" 2>/dev/null; }; then
    limited "$S/mypy.log" "$mypy" --cache-dir "$S/mypy" .
    if [ "$RC" -eq 124 ]; then TYPES="n/a (failed: timeout)"; else
      TYPES=$(grep -c ': error:' "$S/mypy.log")
      if [ "${TYPES:-0}" -eq 0 ] && [ "$RC" -ne 0 ]; then TYPES="n/a (failed: mypy failed, exit $RC)"; fi
    fi
  else TYPES="n/a (no configured type checker on PATH or in .venv)"; fi

  if [ -z "$py" ]; then TESTS="n/a (no python)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return; fi
  if ! "$py" -c 'import pytest' >/dev/null 2>&1; then TESTS="n/a (pytest not installed)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return; fi
  local covarg=(--cov="$SRC" --cov-report="xml:$S/coverage.xml") t0 t1
  "$py" -c 'import pytest_cov' >/dev/null 2>&1 || covarg=()
  t0=$(date +%s)
  PYTHONDONTWRITEBYTECODE=1 COVERAGE_FILE="$S/.coverage" limited "$S/pytest.log" "$py" -m pytest --junitxml="$S/junit.xml" -q -p no:cacheprovider ${covarg[@]+"${covarg[@]}"}
  t1=$(date +%s)
  local r; r=$(jval junit "$S/junit.xml")
  if [ -n "$r" ]; then TESTS="${r% *} failed of ${r#* }"; else TESTS="n/a (failed: no test report, exit $RC)"; fi
  if [ "$RC" -eq 124 ]; then TESTRC="timeout"; else TESTRC=$RC; fi
  SECS=$((t1 - t0))
  if [ "${#covarg[@]}" -eq 0 ]; then COV="n/a (pytest-cov not installed)"
  else
    local c; c=$(jval cobertura "$S/coverage.xml")
    if [ -n "$c" ]; then COV="$c%"; else COV="n/a (failed: no coverage report)"; fi
  fi
}

complexity_python() {
  local ruff; ruff=$(py_bin ruff)
  [ -n "$ruff" ] || { CPLX="n/a (ruff not installed)"; return; }
  local cc="$S/cc"
  copy_tree "$cc" || { CPLX="n/a (failed: could not copy the working tree)"; return; }
  ( cd "$cc" && "$ruff" check --isolated --select C901 --config "lint.mccabe.max-complexity = $COMPLEXITY_LIMIT" --output-format json -o "$S/c901.json" . ) </dev/null >"$S/c901.log" 2>&1
  local n; n=$(jval list "$S/c901.json")
  if [ -n "$n" ]; then CPLX="$n (cyclomatic proxy)"; else CPLX="n/a (failed: ruff C901 run failed)"; fi
}

# ---------------------------------------------------------------- Duplication
measure_duplication() {
  [ "$SRC" != . ] || { DUP="n/a (no src, app or lib directory)"; return; }
  local runner
  if have pnpm && [ "$STACK" = typescript ]; then runner=(pnpm dlx)
  elif have npx; then runner=(npx --yes)
  elif have pnpm; then runner=(pnpm dlx)
  else DUP="n/a (no pnpm or npx)"; return; fi
  # Code formats only; tests, generated output, lock files, JSON and markdown are out.
  limited "$S/jscpd.log" "${runner[@]}" "jscpd@$JSCPD_VERSION" --reporters json --output "$S/jscpd" \
    --format "typescript,tsx,javascript,jsx,python" \
    --ignore '**/node_modules/**,**/.next/**,**/dist/**,**/build/**,**/coverage/**,**/.venv/**,**/__pycache__/**,**/*.json,**/*.md,**/*.lock,**/*.d.ts,**/*.test.*,**/*.spec.*,**/__tests__/**,**/tests/**,**/test/**' "$SRC"
  local n; n=$(jval jscpd "$S/jscpd/jscpd-report.json")
  if [ -n "$n" ]; then DUP="$n%"; else DUP="n/a (failed: jscpd failed, exit $RC)"; fi
}

# ---------------------------------------------------------------- Static counts
TESTRE='(\.(test|spec)\.[cm]?[jt]sx?$|(^|/)(__tests__|tests?)/|(^|/)test_[^/]*\.py$|_test\.py$)'
CODERE='\.([cm]?[jt]sx?|py)$'
SKIPRE='(\.d\.ts$|(^|/)(__snapshots__|generated|fixtures|node_modules|vendor|dist|\.next|\.venv)/)'
SUPPRESS='eslint-disable|biome-ignore|[Nn][Oo][Qq][Aa]|nosec|pylint:[[:space:]]*disable|type:[[:space:]]*ignore|pyright:[[:space:]]*ignore|@ts-expect-error|@ts-ignore|@ts-nocheck|NOSONAR|SuppressWarnings|istanbul[[:space:]]+ignore|c8[[:space:]]+ignore|v8[[:space:]]+ignore|pragma:[[:space:]]*no[[:space:]]+(cover|branch)'
EXCLUDE="coverage\.exclude|collectCoverageFrom|coveragePathIgnorePatterns|testPathIgnorePatterns|modulePathIgnorePatterns|testIgnore|globalIgnores[[:space:]]*\(|\[tool\.coverage|coverage:[[:space:]]*\{[^}]*exclude|ignore_errors|ignorePatterns|extend-exclude|exclude_lines|exclude_also|per-file-ignores|--ignore[= ]|^[[:space:]]*(lint\.)?(ignore|extend-ignore|exclude|omit)[[:space:]]*[=:]|(^|[^A-Za-z_])ignores[[:space:]]*:|[\"'](exclude|excludes|ignore|ignores|omit|includes)[\"'][[:space:]]*:"
THRESH='coverageThreshold|thresholds|fail_under|fail-under'
CASERE='^[[:space:]]*((it|test)(\.[a-z]+)?\(|(async )?def test_)'

# strip_comments <file>: the file with block comments, // comments and # comments (after whitespace) outside strings removed; newlines are kept so line structure survives.
strip_comments() {
  awk 'BEGIN { RS = "\001"; ORS = "" }
    { s = $0; n = length(s); o = ""; q = ""; i = 1
      while (i <= n) {
        c = substr(s, i, 1); d = substr(s, i + 1, 1)
        if (q != "") {
          if (c == "\n" && q != "`") q = ""
          else if (c == "\\") { o = o c d; i += 2; continue }
          else if (c == q) q = ""
          o = o c; i++; continue }
        if (c == "\"" || c == "\047" || c == "`") { q = c; o = o c; i++; continue }
        if (c == "/" && d == "*") {
          j = index(substr(s, i + 2), "*/"); blk = (j == 0) ? substr(s, i) : substr(s, i, j + 3)
          k = gsub(/\n/, "", blk); o = o " "; while (k-- > 0) o = o "\n"
          i += (j == 0) ? length(s) : j + 3; continue }
        if ((c == "/" && d == "/") || (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n]/))) {
          while (i <= n && substr(s, i, 1) != "\n") i++
          continue }
        o = o c; i++ }
      print o }' "$1"
}

# excl_entries <file> <js|ini|yaml>: the number of exclusion entries, so a new entry in an existing list counts, including entries on continuation lines.
excl_entries() {
  local kind=$2 pkg=0
  [ "$(basename "$1")" = package.json ] && pkg=1
  { if [ "$kind" = js ]; then strip_comments "$1"; else cat "$1"; fi; } | RE="$EXCLUDE" KIND="$kind" PKG="$pkg" awk -v q="'" '
    function strip(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function items(s,  m, parts, k, n) {
      sub(/[ \t]+[#;].*$/, "", s); gsub(/[][]/, "", s); m = split(s, parts, ","); n = 0
      for (k = 1; k <= m; k++) if (strip(parts[k]) != "") n++
      return n }
    function scan(s, ng,  i, n, ch, e, st, j, k, cc, cls) {
      n = length(s); rest = ""
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch ~ /[ \t]/) continue
        st = (opened && dep == base && eexp)
        if (ch == "\"" || ch == q) {
          e = i + 1
          while (e <= n && substr(s, e, 1) != ch) { if (substr(s, e, 1) == "\\") e++; e++ }
          if (st) { eexp = 0; if (!ng || substr(s, i + 1, 1) == "!") { c++; got++ } }
          i = e; continue }
        if (ch == "#" || (ch == "/" && substr(s, i + 1, 1) == "/")) break
        if (ch == ",") { if (opened && dep == base) eexp = 1; continue }
        if (ch == "[" || ch == "{" || ch == "(") {
          if (st) { eexp = 0; if (!ng) { c++; got++ } }
          dep++
          if (!opened && ch != "(") { opened = 1; base = dep; eexp = 1 }
          continue }
        if (ch == "]" || ch == "}" || ch == ")") {
          dep--
          if (opened && dep < base) { inl = 0; rest = substr(s, i + 1); return }
          continue }
        if (st) { eexp = 0; if (!ng) { c++; got++ } }
        if (st && ch == "/") {
          cls = 0
          for (j = i + 1; j <= n; j++) {
            cc = substr(s, j, 1)
            if (cc == "\\") { j++; continue }
            if (cc == "[") cls = 1
            else if (cc == "]") cls = 0
            else if (cc == "/" && !cls) break
          }
          i = j }
      }
      inl = (opened && dep >= base) }
    function ocount(s, pat,  k, n) { n = 0; while ((k = match(s, pat)) > 0) { n++; s = substr(s, RSTART + RLENGTH) } return n }
    BEGIN { re = ENVIRON["RE"]; kind = ENVIRON["KIND"]; pkg = ENVIRON["PKG"] + 0
      ikey = "^(omit|exclude|excludes|exclude_lines|exclude-lines|exclude_also|exclude_patterns|ignore|extend-ignore|extend-exclude|disable|per-file-ignores|extend-per-file-ignores|ignore-paths|ignore-patterns|ignore-modules|norecursedirs|ignore_errors|addopts|sonar\\..*(exclusions|ignore).*)$" }
    kind == "ini" {
      if ($0 ~ /^[ \t]*[#;]/) next
      if (cont == 1 && $0 ~ /^[ \t]+[^ \t]/) { if ($0 !~ /^[ \t]+[A-Za-z_.-]+[ \t]*[=:]/) c += items($0); next }
      if (cont == 2 && $0 ~ /^[ \t]+[^ \t]/) { c += ocount($0, "--ignore"); next }
      cont = 0
      if (match($0, /^[ \t]*[A-Za-z_.-]+[ \t]*[=:]/)) {
        k = $0; sub(/[ \t]*[=:].*$/, "", k); k = tolower(strip(k))
        v = substr($0, RLENGTH + 1)
        if (k ~ ikey) {
          if (k == "addopts") { c += ocount(v, "--ignore"); cont = 2 }
          else if (k == "ignore_errors") c++
          else { c += items(v); cont = 1 }
        }
      }
      next }
    kind == "yaml" {
      if ($0 ~ /^[ \t]*(#|$)/) next
      match($0, /[^ \t]/); ind = RSTART - 1
      if (ylist) {
        if ($0 ~ /^[ \t]*-([ \t]|$)/ && ind >= kind_ind) { if (iind < 0) iind = ind; if (ind == iind) c++; next }
        if (ind > kind_ind) {
          if ($0 ~ /^[ \t]*(paths|patterns|files|globs)[ \t]*:[ \t]*(#.*)?$/ && iind < 0) { kind_ind = ind; next }
          next }
        ylist = 0 }
      if (yflow) { s = $0; sub(/[ \t]+#.*$/, "", s); e = index(s, "]"); c += items(e > 0 ? substr(s, 1, e - 1) : s); if (e > 0) yflow = 0; next }
      if (yrules && ind <= rind) yrules = 0
      if (pend) {
        pend = 0
        if ($0 ~ /^[ \t]*-[ \t]*["'"'"']?(off|0)["'"'"']?[ \t]*(#.*)?$/) { c++; next }
      }
      if ($0 ~ /^[ \t]*rules[ \t]*:[ \t]*(#.*)?$/) { yrules = 1; rind = ind; next }
      if (yrules && match($0, /^[ \t]*[^ \t:#][^:]*:/)) {
        v = substr($0, RSTART + RLENGTH); sub(/[ \t]+#.*$/, "", v); v = strip(v)
        if (v ~ /^["'"'"']?(off|0)["'"'"']?$/ || v ~ /^\[[ \t]*["'"'"']?(off|0)["'"'"']?[ \t]*[,\]]/) c++
        else if (v == "") pend = 1
        next }
      if ($0 ~ /^[ \t]*(ignorePatterns|exclude|excludes|ignore|ignores|omit)[ \t]*:/) {
        v = $0; sub(/^[^:]*:/, "", v); sub(/[ \t]+#.*$/, "", v); v = strip(v)
        if (v == "") { ylist = 1; kind_ind = ind; iind = -1 }
        else if (substr(v, 1, 1) == "[") { sub(/^\[/, "", v); e = index(v, "]"); if (e > 0) c += items(substr(v, 1, e - 1)); else { c += items(v); yflow = 1 } }
        else c++
      }
      next }
    {
      line = $0
      if (tsec) {
        if (!inl && line ~ /^[ \t]*\[/) tsec = 0
        else if (inl) { scan(line, 0); next }
        else { got = 0; dep = 0; opened = 0; eexp = 0; base = 0; scan(line, 0); if (got == 0 && !opened && line ~ /=/) c++; next }
      }
      if (inl) { scan(line, ng); line = inl ? "" : rest; if (line == "") next }
      if (pend && line ~ /[^ \t]/) { pend = 0; got = 0; dep = 0; opened = 0; eexp = 0; base = 0; scan(line, png); if (got == 0 && !inl && !png && !opened) c++; line = inl ? "" : rest; if (line == "") next }
      if (line ~ /^[ \t]*\[[^]]*per-file-ignores[^]]*\][ \t]*$/) { tsec = 1; next }
      while (line != "" && match(line, re)) {
        key = substr(line, RSTART, RLENGTH); rem = substr(line, RSTART + RLENGTH); quoted = (key ~ /["'"'"']/ && key !~ /\[tool/)
        if (key ~ /^coverage:[ \t]*\{/) { k = index(key, "exclude"); rem = substr(key, k + 7) rem; key = "exclude" }
        ng = (key ~ /collectCoverageFrom|includes/)
        if (key ~ /--ignore/) { c += 1; line = rem; continue }
        if (key ~ /^\[tool/) { line = ""; continue }
        if (key ~ /ignore_errors/ && rem ~ /^[ \t]*["'"'"']?[ \t]*(=|:)?[ \t]*(false|False|no|off|0)[ \t]*(#.*)?$/) { line = ""; continue }
        sub(/^["'"'"']?[ \t]*[:=]/, "", rem)
        if (pkg && quoted && rem ~ /^[ \t]*["'"'"']/) { line = rem; continue }
        got = 0; dep = 0; opened = 0; eexp = 0; base = 0; inl = 0
        if (rem !~ /[^ \t]/) { pend = 1; png = ng; line = ""; continue }
        scan(rem, ng)
        if (got == 0 && !inl && !ng && !opened) c++
        line = inl ? "" : rest
      }
    }
    END { print c + 0 }'
}

# eslint_off <file>: the number of rules set to off or 0 directly under a rules object, as a bare value or the first element of the array form.
eslint_off() {
  awk -v q="'" -v deep="${2:-0}" '
    BEGIN { RS = "\001" }
    function nextnb(j) { while (j <= n && substr(s, j, 1) ~ /[ \t\r\n]/) j++; return j }
    function strend(j,  c, k) { c = substr(s, j, 1); k = j + 1; while (k <= n && substr(s, k, 1) != c) { if (substr(s, k, 1) == "\\") k++; k++ } return k }
    function isoff(j,  c, e) {
      c = substr(s, j, 1)
      if (c == "\"" || c == q) { e = strend(j); return substr(s, j + 1, e - j - 1) == "off" }
      if (c == "0") return substr(s, j + 1, 1) !~ /[0-9A-Za-z_.]/
      return 0 }
    {
      s = $0; n = length(s); sp = 0; last = ""; pend = 0
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == "/" && substr(s, i + 1, 1) == "/") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
        if (ch == "/" && substr(s, i + 1, 1) == "*") { i += 2; while (i < n && !(substr(s, i, 1) == "*" && substr(s, i + 1, 1) == "/")) i++; i++; continue }
        if (ch == "\"" || ch == q || ch == "`") { e = strend(i); last = substr(s, i + 1, e - i - 1); i = e; continue }
        if (ch ~ /[A-Za-z_$]/) { j = i; while (j < n && substr(s, j + 1, 1) ~ /[A-Za-z0-9_$]/) j++; last = substr(s, i, j - i + 1); i = j; continue }
        if (ch == "{") { st[++sp] = (pend || (deep && sp > 0 && st[sp] == "R")) ? "R" : "O"; pend = 0; last = ""; continue }
        if (ch == "[") { st[++sp] = "A"; last = ""; continue }
        if (ch == "}" || ch == "]") { if (sp > 0) sp--; last = ""; continue }
        if (ch == ",") { last = ""; continue }
        if (ch == ":") {
          j = nextnb(i + 1)
          if (last == "rules" && substr(s, j, 1) == "{") pend = 1
          else if (sp > 0 && st[sp] == "R") {
            if (substr(s, j, 1) == "[") { if (isoff(nextnb(j + 1))) c++ }
            else if (isoff(j)) c++
          }
        }
      }
    }
    END { print c + 0 }' "$1"
}

# sha256_stdin: the SHA-256 of standard input.
sha256_stdin() { if have shasum; then shasum -a 256; else sha256sum; fi; }

# gate_config_rows: one row per gate configuration file with the first 16 hex digits of its SHA-256, and a count row; only paths and hashes are printed.
gate_config_rows() {
  local f h list=
  if ! have shasum && ! have sha256sum; then row "gate config files" "n/a (no shasum or sha256sum)"; return; fi
  while IFS= read -r -d '' f; do
    f=${f#./}
    if ! { is_gate_config "$f" && [ -f "$P/$f" ] && [ ! -L "$P/$f" ]; }; then continue; fi
    h=$(sha256_stdin <"$P/$f" 2>/dev/null | cut -c1-16)
    [ -n "$h" ] && list="${list}gate config: $f|$h
"
  done < <(list_files)
  row "gate config files" "$(printf '%s' "$list" | awk 'END { print NR }')"
  while IFS='|' read -r f h; do
    [ -n "$f" ] && row "$f" "$h"
  done <<EOF
$(printf '%s' "$list" | LC_ALL=C sort)
EOF
}

count_static() {
  local f tl=0 sl=0 cases=0 supp=0 excl=0 thr=0 n base kind
  while IFS= read -r -d '' f; do
    [ -f "$P/$f" ] || continue
    if printf '%s' "$f" | grep -Eq "$CODERE" && ! printf '%s' "$f" | grep -Eq "$SKIPRE"; then
      n=$(grep -c . "$P/$f" 2>/dev/null); n=${n:-0}
      if printf '%s' "$f" | grep -Eq "$TESTRE"; then
        tl=$((tl + n))
        n=$(grep -cE "$CASERE" "$P/$f" 2>/dev/null); cases=$((cases + ${n:-0}))
      else
        sl=$((sl + n))
      fi
      n=$(grep -oE "$SUPPRESS" "$P/$f" 2>/dev/null | wc -l); supp=$((supp + ${n:-0}))
    fi
    case "$(basename "$f")" in
      .eslintignore)
        n=$(grep -cvE '^[[:space:]]*(#|$)' "$P/$f" 2>/dev/null); excl=$((excl + ${n:-0})) ;;
      vitest.config.*|vite.config.*|jest.config.*|playwright.config.*|.eslintrc|.eslintrc.*|package.json|pyproject.toml|.coveragerc|sonar-project.properties|eslint.config.*|.jscpd.json|biome.json|biome.jsonc|ruff.toml|.ruff.toml|.nycrc|.nycrc.json|.pylintrc|pylintrc|pytest.ini|setup.cfg|tox.ini)
        base=$(basename "$f")
        case "$base" in
          .coveragerc|sonar-project.properties|.pylintrc|pylintrc|pytest.ini|setup.cfg|tox.ini) kind=ini ;;
          *.yml|*.yaml) kind=yaml ;;
          *) kind=js ;;
        esac
        n=$(excl_entries "$P/$f" "$kind"); excl=$((excl + ${n:-0}))
        case "$base" in
          eslint.config.*|package.json) n=$(eslint_off "$P/$f") ;;
          .eslintrc|.eslintrc.json|.eslintrc.js|.eslintrc.cjs) n=$(eslint_off "$P/$f") ;;
          biome.json|biome.jsonc) n=$(eslint_off "$P/$f" 1) ;;
          *) n=0 ;;
        esac
        excl=$((excl + ${n:-0}))
        n=$(grep -cE "$THRESH" "$P/$f" 2>/dev/null); thr=$((thr + ${n:-0})) ;;
      tsconfig*.json)
        n=$(excl_entries "$P/$f" js); excl=$((excl + ${n:-0})) ;;
    esac
  done < <(list_files)
  TESTLOC=$tl SRCLOC=$sl CASES=$cases SUPP=$supp EXCL=$excl THR=$thr
  if [ "$sl" -gt 0 ]; then RATIO=$(awk -v t="$tl" -v s="$sl" 'BEGIN { printf "%.2f", t / s }'); else RATIO="n/a (no source lines)"; fi
}

# ---------------------------------------------------------------- Run
NA_STATIC="n/a (static mode: nothing was run)"
if [ "$MODE" = full ]; then
  case "$STACK" in
    typescript) measure_typescript; complexity_typescript
      TOOLS="${TOOLS}eslint $ESLINT_VERSION, typescript-eslint $TSESLINT_VERSION, eslint-plugin-sonarjs $SONARJS_VERSION" ;;
    python) measure_python; complexity_python ;;
  esac
  [ "$STACK" = unknown ] || { measure_duplication; TOOLS="${TOOLS:+$TOOLS, }jscpd $JSCPD_VERSION"; }
  [ "$STACK" = unknown ] || TOOLS="${TOOLS:+$TOOLS, }diff-cover $DIFFCOVER_VERSION (quality pass)"
elif [ "$STACK" != unknown ]; then
  LINT=$NA_STATIC TYPES=$NA_STATIC TESTS=$NA_STATIC TESTRC=$NA_STATIC SECS=$NA_STATIC COV=$NA_STATIC CPLX=$NA_STATIC DUP=$NA_STATIC
fi
count_static
KEPT=
if [ -n "$KEEP" ] && [ "$MODE" = full ]; then
  KEPT="n/a (no coverage report)"
  for x in "$S/cov/cobertura-coverage.xml" "$S/coverage.xml"; do
    [ -f "$x" ] || continue
    # Create and resolve the directory, re-check it, copy to a temporary name inside it, then rename into place.
    # rename(2) replaces a destination symlink instead of following it, and the link is refused first anyway.
    mkdir -p "$KEEP" || { KEPT="n/a (cannot create $KEEP)"; break; }
    KEEP=$(cd "$KEEP" && pwd -P) || { KEPT="n/a (cannot resolve $KEEP)"; break; }
    if inside_project "$KEEP"; then KEPT="n/a ($KEEP is inside the project)"; break; fi
    tmpcov=$(mktemp "$KEEP/.cobertura.XXXXXX") || { KEPT="n/a (cannot write in $KEEP)"; break; }
    if [ -L "$KEEP/cobertura.xml" ]; then rm -f "$tmpcov"; KEPT="n/a ($KEEP/cobertura.xml is a symlink)"; break; fi
    if cp "$x" "$tmpcov" && mv -f "$tmpcov" "$KEEP/cobertura.xml"; then KEPT="$KEEP/cobertura.xml"; else rm -f "$tmpcov"; KEPT="n/a (could not write $KEEP/cobertura.xml)"; fi
    break
  done
fi

AFTER=$(status_snapshot)
NEWER=$(newer_files)
# Files a run wrote that git ignores (logs, caches) are listed apart from changes git can see.
VISIBLE=; IGN=
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if is_git && ( cd "$P" && g check-ignore -q -- "$f" ); then IGN="${IGN}${f#"$P"/} "; else VISIBLE="${VISIBLE}${f#"$P"/} "; fi
done <<EOF
$NEWER
EOF
if [ "$BEFORE" != "$AFTER" ] || [ -n "$VISIBLE" ]; then TREE="CHANGED (git state differs or files written: ${VISIBLE:-see git status})"
elif [ -n "$IGN" ]; then TREE="unchanged in git; the run wrote ignored files: ${IGN%% *} (and $(printf '%s' "$IGN" | wc -w | tr -d ' ') in all)"
else TREE="unchanged"; fi

row "stack" "$STACK"
row "lint findings" "$LINT"
row "type errors" "$TYPES"
row "tests failed" "$TESTS"
row "test exit status" "$TESTRC"
row "test seconds" "$SECS"
row "line coverage" "$COV"
row "complexity over $COMPLEXITY_LIMIT" "$CPLX"
row "duplication" "$DUP"
row "test LOC" "$TESTLOC"
row "source LOC" "$SRCLOC"
row "test:source ratio" "$RATIO"
row "test cases (static count; a parametrized case counts once)" "$CASES"
row "suppression lines matching (code files)" "$SUPP"
row "coverage, lint and Sonar exclusions" "$EXCL"
row "coverage thresholds configured" "$THR"
gate_config_rows
row "mode" "$MODE"
row "git head" "$GITHEAD"
row "git tree" "$GITTREE"
[ -z "$KEEP" ] || row "coverage xml kept" "$KEPT"
row "scratch tool versions" "${TOOLS:-none (static mode)}"
row "project tree after the run" "$TREE"

printf '| Metric | %s |\n|---|---|\n%s' "$LABEL" "$ROWS"
# Normal exit: clean up here as well as in the EXIT trap; the function is idempotent.
cleanup
exit 0
