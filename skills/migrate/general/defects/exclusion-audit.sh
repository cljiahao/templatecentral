#!/usr/bin/env bash
# Sourced by defect-report.sh. Read-only audit of what a project leaves out of coverage, Sonar analysis and mutation testing.
# It lists every exclude and marks it "has reason" or "no reason" by the same rule as the seeded gate scripts/check-exclude-reasons.sh:
# a comment line directly above the entry that starts with "reason:" and has at least 3 words. Framework defaults (test files,
# node_modules, build output, config files) are marked as such. src/components/ui/** is marked as the one exclude templateCentral seeds.
# It also reports: a coverage include list (an exclude of every file it does not list), a minimumReleaseAgeExclude entry in
# pnpm-workspace.yaml, .npmrc or package.json, a folder with source files and no coverage config, a coverage threshold below 80,
# and a config it cannot read (a spread, variable or call in a list, a syntax error, typescript not installed).
# The line text after file:line is the finding; the runner prefixes its own wording, and "older template pattern" does not mean a defect here.
# Self-contained: the scanners sit in exclusion-audit/ next to this file and nothing from the adopted project is run or needed, except
# the project's own typescript, loaded by node to parse a JS or TS config as text (the config is never executed).
# Never reads .env files or secrets, never writes inside the project.
# Bound: all JS, TS and JSON configs are read by one node run (typescript loads once), at most 400 files; a config past that is
# listed as not read. TOML, INI and properties files take one small python or awk run each. The runner skips files over 1 MB. At
# most one find with -print -quit per package.json or pyproject.toml, 4 folder levels deep. The one node run writes its records to
# a temporary file outside the project, removed when the runner exits. CPU figures: tests/fixtures/exclusions/README.md.
# Needs bash 3.2+, find, grep, awk; node for JS, TS and JSON configs; python3 for TOML and INI configs.
MAX_JS_CONFIGS=400
export id=exclusion-audit
export level=check
export names="vitest.config.* vitest.workspace.* vite.config.* jest.config.* stryker.config.* stryker.conf.* .stryker.conf.* package.json pyproject.toml .coveragerc setup.cfg tox.ini sonar-project.properties pnpm-workspace.yaml .npmrc"
export template=skills/scaffold/shared/template/scripts/check-exclude-reasons.sh
export desc="an exclude audit entry, listed so each exclude can be judged; a line marked no reason, allow-list, below 80 or cannot be read needs a decision"
export fix="give each exclude a one-line comment above it that starts with reason: and has at least 3 words, remove excludes that hide hand-written code, and keep coverage at 80 or above"

# Print the audit lines of one scanner's output (tab separated records) for FILE.
audit_records() {
  local tab tag file line kind entry status marker norm
  tab=$(printf '\t')
  while IFS="$tab" read -r tag file line kind entry status; do
    case "$tag" in
      E)
        norm=${entry#\!}
        norm=${norm#./}
        norm=${norm#\*\*/}
        case "$status" in
          default) marker="framework default" ;;
          reason) marker="has reason" ;;
          shared) marker="no reason (shares its line with another exclude)" ;;
          *) marker="no reason" ;;
        esac
        if [ "$norm" = "src/components/ui/**" ]; then marker="seeded exclude (templateCentral adds it on purpose), $marker"; fi
        echo "$file:$line $kind '$entry': $marker"
        ;;
      I)
        if [ "$status" = reason ]; then marker="has reason"; else marker="no reason"; fi
        echo "$file:$line $kind list '$entry' is an allow-list: it excludes every file it does not list, $marker"
        ;;
      X) echo "$file:$line cannot be read: $kind" ;;
      T)
        if awk -v v="$entry" 'BEGIN { exit !(v + 0 < 80) }'; then
          echo "$file:$line coverage threshold $kind is $entry, below 80"
        fi
        ;;
    esac
  done
}

# Print the first source file below DIR, or nothing. Looks 4 levels down; stops at the first hit.
first_source() {
  local dir=$1
  shift
  local expr=() name first=1
  for name in "$@"; do
    if [ "$first" -eq 1 ]; then expr=(-name "$name"); first=0; else expr=("${expr[@]}" -o -name "$name"); fi
  done
  find "$dir" -maxdepth 4 \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build \
    -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o \
    -type f \( "${expr[@]}" \) ! -name '*.d.ts' ! -name '*.config.*' ! -name 'test_*' ! -name '*.test.*' ! -name '*.spec.*' -print -quit
}

# True when DIR holds a coverage config of any supported form. Reads only the config files that sit directly in DIR.
has_coverage_config() {
  local dir=$1 f
  for f in "$dir"/vitest.config.* "$dir"/vitest.workspace.* "$dir"/vite.config.* "$dir"/jest.config.* "$dir"/pyproject.toml "$dir"/.coveragerc "$dir"/setup.cfg "$dir"/tox.ini; do
    if [ -f "$f" ] && [ ! -L "$f" ] && grep -qi 'coverage' "$f" 2> /dev/null; then return 0; fi
  done
  f=$dir/package.json
  if [ -f "$f" ] && [ ! -L "$f" ] && grep -qE 'coverageThreshold|collectCoverage|"nyc"|"c8"' "$f" 2> /dev/null; then return 0; fi
  return 1
}

check() {
  local f=$1 dir base here tools src out tab
  tab=$(printf '\t')
  dir=$(dirname "$f")
  base=$(basename "$f")
  here=$DEFECTS/exclusion-audit
  [ -d "$here" ] || return 1
  [ -r "$here/defaults.txt" ] || return 1
  tools=$(cat "$here/defaults.txt") || return 1
  case "$base" in
    sonar-project.properties)
      out=$(TC_EXCLUDE_DEFAULTS=$tools awk -v file="$f" -f "$here/scan.awk" "$f" 2>&1) || out="X$tab$f${tab}1${tab}the properties scanner failed${tab}${tab}"
      printf '%s\n' "$out" | audit_records
      ;;
    pnpm-workspace.yaml | .npmrc)
      grep -qE 'minimumReleaseAgeExclude|minimum-release-age-exclude' "$f" 2> /dev/null || return 0
      case "$base" in
        .npmrc) src=npmrc ;;
        *) src=yaml ;;
      esac
      awk -v file="$f" -v mode="$src" -f "$here/scan-pnpm.awk" "$f" | pnpm_records
      ;;
    pyproject.toml | .coveragerc | setup.cfg | tox.ini)
      if [ "$base" = .coveragerc ] || grep -qE 'coverage|mutmut' "$f" 2> /dev/null; then
        if command -v python3 > /dev/null 2>&1; then
          out=$(TC_EXCLUDE_DEFAULTS=$tools python3 -I "$here/scan.py" "$f" 2>&1) || out="X$tab$f${tab}1${tab}the TOML and INI scanner failed${tab}${tab}"
          printf '%s\n' "$out" | audit_records
        else
          echo "$f:1 cannot be read: python3 is not installed, so this TOML or INI config was not audited"
        fi
      fi
      if [ "$base" = pyproject.toml ] && ! has_coverage_config "$dir"; then
        src=$(first_source "$dir" '*.py')
        if [ -n "$src" ]; then echo "$f:1 no coverage config: the folder has Python source (for example ${src#"$dir"/}) and no coverage config"; fi
      fi
      ;;
    package.json)
      if grep -q 'minimumReleaseAgeExclude' "$f" 2> /dev/null; then
        awk -v file="$f" -v mode=json -f "$here/scan-pnpm.awk" "$f" | pnpm_records
      fi
      if grep -q '"jest"' "$f" 2> /dev/null; then
        js_records "$f"
      fi
      if [ ! -f "$dir/pnpm-workspace.yaml" ] && ! grep -q '"workspaces"' "$f" 2> /dev/null && ! has_coverage_config "$dir"; then
        src=$(first_source "$dir" '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs')
        if [ -n "$src" ]; then echo "$f:1 no coverage config: the folder has source files (for example ${src#"$dir"/}) and no coverage config"; fi
      fi
      ;;
    *)
      if grep -qE 'coverage|mutate|Coverage' "$f" 2> /dev/null; then js_records "$f"; fi
      ;;
  esac
  return 0
}

# Print audit lines for the JS, TS or JSON config FILE. The first call scans every candidate config once and keeps the records.
js_records() {
  local f=$1 cache=${TMPDIR:-/tmp}/exclusion-audit.$$ cands c n=0 listed='' all
  if ! command -v node > /dev/null 2>&1; then
    echo "$f:1 cannot be read: node is not installed, so this JS or TS config was not audited"
    return 0
  fi
  if [ ! -f "$cache" ]; then
    cands=()
    all=$(find_files "$P" 'vitest.config.*' 'vitest.workspace.*' 'vite.config.*' 'jest.config.*' 'stryker.config.*' 'stryker.conf.*' '.stryker.conf.*' package.json | LC_ALL=C sort)
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in
        */package.json) grep -q '"jest"' "$c" 2> /dev/null || continue ;;
        *) grep -qE 'coverage|mutate|Coverage' "$c" 2> /dev/null || continue ;;
      esac
      n=$((n + 1))
      if [ "$n" -le "$MAX_JS_CONFIGS" ]; then
        cands+=("$c")
        listed="$listed$c$NL"
      fi
    done <<< "$all"
    trap 'rm -f "$cache"' EXIT
    {
      while IFS= read -r c; do
        [ -n "$c" ] && printf 'S\t%s\n' "$c"
      done <<< "$listed"
      if [ "${#cands[@]}" -gt 0 ]; then
        TC_EXCLUDE_DEFAULTS=$(cat "$DEFECTS/exclusion-audit/defaults.txt") node "$DEFECTS/exclusion-audit/scan.mjs" --root "$P" "${cands[@]}" 2>&1 || printf 'X\t%s\t1\tthe JS config scanner failed\n' "${cands[0]}"
      fi
    } > "$cache"
  fi
  if ! awk -F'\t' -v f="$f" '$1 == "S" && $2 == f { found = 1 } END { exit !found }' "$cache"; then
    echo "$f:1 not read: the audit reads at most $MAX_JS_CONFIGS JS and TS configs per run"
    return 0
  fi
  awk -F'\t' -v f="$f" '$1 != "S" && $2 == f' "$cache" | audit_records
}

# Print audit lines for minimumReleaseAgeExclude records (P file line entry status).
pnpm_records() {
  local tab tag file line entry status marker
  tab=$(printf '\t')
  while IFS="$tab" read -r tag file line entry status; do
    [ "$tag" = P ] || continue
    case "$status" in
      reason) marker="has reason" ;;
      nojson) marker="package.json cannot hold a comment; move the setting to pnpm-workspace.yaml to give it a reason" ;;
      *) marker="no reason" ;;
    esac
    echo "$file:$line minimumReleaseAgeExclude entry '$entry' skips the package release-age wait: $marker"
  done
}
