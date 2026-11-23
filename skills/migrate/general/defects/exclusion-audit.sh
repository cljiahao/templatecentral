#!/usr/bin/env bash
# Sourced by defect-report.sh. Read-only audit of what a project leaves out of coverage, Sonar analysis and mutation testing.
# The exit code stays 0 by design: the findings are in the output lines, so read the lines, not the exit code.
# It lists every exclude and marks it "has reason" or "no reason" by the same rule as the seeded gate scripts/check-exclude-reasons.sh:
# a comment line directly above the entry that starts with "reason:" and has at least 3 different words of 3+ letters, none a placeholder
# (TODO, TBD, FIXME, XXX, WIP, TEMP, LATER, HACK); in a Sonar list the reason must name its entry as a whole word and no other entry.
# Framework defaults (test files, type declarations, root config files, root build output) are marked as such. src/components/ui/** is
# marked as the one exclude templateCentral seeds. Which entries hide source comes from exclusion-audit/rules.sh, the same file the gate uses:
# an exclude of a whole source root or of every file of a source type hides hand-written source whatever its reason; any other exclude under
# a source root is reported as covering hand-written code, on its own line.
# It also reports: a coverage include list (an exclude of every file it does not list), an inline coverage marker in source (istanbul, c8,
# v8, node:coverage, pragma: no cover) with no reason, a minimumReleaseAgeExclude entry in pnpm-workspace.yaml, .npmrc or package.json,
# an exclude on a command line (package.json scripts, CI files, lefthook, Makefile), a --config, --cov-config or --rcfile that points at a
# file the audit does not read, a folder with source files and no coverage config, a coverage threshold below 80, and a config it cannot
# read (a spread, variable or call in a list, a syntax error, a karma, codecov or nyc.config file that sets an exclude, a Sonar file with
# a NUL byte, typescript not installed).
# The line text after file:line is the finding; the runner prefixes its own wording, and "older template pattern" does not mean a defect here.
# Self-contained: the scanners sit in exclusion-audit/ next to this file and nothing from the adopted project is run or needed, except
# the project's own typescript, loaded by node to parse a JS or TS config as text (the config is never executed).
# Files come from one list shared by config discovery and the marker scan (rules_files in exclusion-audit/rules.sh): inside a git work tree
# the files git tracks or sees untracked and does not ignore, outside one every file except node_modules, .git and virtualenv folders.
# No folder is skipped by its name, so packages/build/vitest.config.ts is audited. The runner still hands the first call its own list.
# Never reads .env files or secrets, never writes inside the project.
# Bound: all JS, TS and JSON configs are read by one node run (typescript loads once), at most 400 files; a config past that is
# listed as not read. TOML, INI and properties files take one small python or awk run each. The runner skips files over 1 MB. At
# most one find with -print -quit per package.json or pyproject.toml, 4 folder levels deep. One extra find reads the source files for
# inline markers, once per run. The one node run writes its records to a file made with mktemp outside the project, and a second small
# file marks that the marker scan ran; an EXIT trap set when this file loads removes both. CPU figures: tests/fixtures/exclusions/README.md.
# Needs bash 3.2+, find, grep, awk; node for JS, TS and JSON configs; python3 for TOML and INI configs.
MAX_JS_CONFIGS=400
AUDIT_CACHE=$(mktemp "${TMPDIR:-/tmp}/exclusion-audit.XXXXXX" 2> /dev/null) || AUDIT_CACHE=
AUDIT_MARKS=$(mktemp "${TMPDIR:-/tmp}/exclusion-audit-marks.XXXXXX" 2> /dev/null) || AUDIT_MARKS=
trap '[ -z "$AUDIT_CACHE" ] || rm -f "$AUDIT_CACHE"; [ -z "$AUDIT_MARKS" ] || rm -f "$AUDIT_MARKS"' EXIT
export id=exclusion-audit
export level=check
export names="vitest*.config.* vitest.workspace.* vite.config.* jest*.config.* stryker*.conf* .stryker*.conf* karma*.conf* nyc.config.* codecov.yml .codecov.yml .nycrc* .c8rc* .jscpd.json package.json pyproject.toml .coveragerc setup.cfg tox.ini sonar-project*.properties pnpm-workspace.yaml .npmrc Makefile Jenkinsfile *.yml *.yaml"
export template=skills/scaffold/shared/template/scripts/check-exclude-reasons.sh
export desc="an exclude audit entry, listed per file in this order: no reason, hides hand-written source or covers hand-written code, has reason, framework default; the audit exit code stays 0 by design, so the findings are in these lines; a line marked no reason, hides source, covers hand-written code, allow-list, below 80 or cannot be read needs a decision"
export fix="give each exclude a one-line comment above it that starts with reason: and has at least 3 words, remove excludes that hide hand-written code, move command-line excludes into the config file, and keep coverage at 80 or above"

# The rules that decide which entries hide source: a byte copy of the seeded gate's check-exclude-rules.sh.
# shellcheck source=/dev/null
. "$DEFECTS/exclusion-audit/rules.sh" || die "cannot read $DEFECTS/exclusion-audit/rules.sh"

# Print the audit lines of one scanner's output (tab separated records) for FILE, grouped by state:
# no reason (and anything that cannot be read), hides source, has reason, framework default.
# "py" for a coverage.py config file (its omit and include patterns are fnmatch patterns on the absolute path), else nothing.
py_flag() {
  local b=${1##*/}
  case "$b" in
    pyproject.toml | .coveragerc* | setup.cfg | tox.ini | *.toml | *.ini | *.cfg) printf py ;;
  esac
}

audit_records() {
  local tab tag file line kind entry status marker lines_none='' lines_hides='' lines_reason='' lines_default='' text norm root cdir recs
  local unions ufile ukind uline ulist ucdir keep uentry
  tab=$(printf '\t')
  recs=$(cat)
  # Judge each exclude list as a whole too: entries that are narrow alone but together leave out a whole source scope.
  unions=$(printf '%s\n' "$recs" | rules_union_groups)
  while IFS="$tab" read -r ufile ukind uline ulist; do
    [ -n "$ufile" ] || continue
    ucdir=$(dirname "${ufile#"$P"/}")
    keep=
    while IFS= read -r uentry; do
      [ -n "$uentry" ] || continue
      if ! hides_source "$uentry" "$ucdir" "$(py_flag "$ufile")"; then keep="$keep$uentry$NL"; fi
    done <<EOT
$(printf '%s' "$ulist" | tr '\001' '\n')
EOT
    [ "$(printf '%s' "$keep" | grep -c .)" -ge 2 ] || continue
    if hides_union "${keep%?}" "$ucdir" "$(py_flag "$ufile")"; then
      lines_hides="$lines_hides$ufile:$uline the $ukind entries of this list together hide hand-written source (between them they match every source file of the project, of one package or of one top-level source folder, or every source file of one type there, and no reason can cover that)$NL"
    fi
  done <<EOT
$unions
EOT
  while IFS="$tab" read -r tag file line kind entry status <&3; do
    case "$tag" in
      E)
        case "$status" in
          default) marker="framework default" ;;
          reason) marker="has reason" ;;
          shared) marker="no reason (shares its line with another exclude)" ;;
          *) marker="no reason" ;;
        esac
        text="$file:$line $kind '$entry': "
        if [ "$status" = default ]; then
          lines_default="$lines_default$text$marker$NL"
        elif [ "$kind" != sonar-issue-ignore ] && cdir=$(dirname "${file#"$P"/}") && hides_source "$entry" "$cdir" "$(py_flag "$file")"; then
          lines_hides="$lines_hides${text}hides hand-written source (${RULES_WHY:-it matches every source file of the project, of one package or of one top-level source folder, or every source file of one type there}, and no reason can cover that), $marker$NL"
        else
          if [ "$kind" != sonar-issue-ignore ] && root=$(under_source_root "$entry"); then
            lines_hides="$lines_hides${text}covers hand-written code (it sits under the source root $root/, so check that nothing in it is hand-written)$NL"
          fi
          norm=${entry#\!}
          norm=${norm#./}
          norm=${norm#\*\*/}
          if [ "$norm" = "src/components/ui/**" ]; then marker="seeded exclude (templateCentral adds it on purpose), $marker"; fi
          if [ "$status" = reason ]; then lines_reason="$lines_reason$text$marker$NL"; else lines_none="$lines_none$text$marker$NL"; fi
        fi
        ;;
      I)
        cdir=$(dirname "${file#"$P"/}")
        if include_covers "$entry" "$cdir" "$(py_flag "$file")"; then continue; fi
        if [ "$status" = reason ]; then marker="has reason"; else marker="no reason"; fi
        lines_hides="$lines_hides$file:$line $kind list '$entry' is an allow-list: it excludes every file it does not list, $marker$NL"
        ;;
      M)
        text="$file:$line inline coverage marker '$kind': "
        case "$status" in
          reason) lines_reason="$lines_reason${text}has reason$NL" ;;
          file) lines_hides="$lines_hides${text}hides hand-written source (a whole-file marker leaves the file out of coverage, and no reason can cover that), no reason accepted$NL" ;;
          *) lines_none="$lines_none${text}no reason$NL" ;;
        esac
        ;;
      X) lines_none="$lines_none$file:$line cannot be read: $kind$NL" ;;
      T)
        if awk -v v="$entry" 'BEGIN { exit !(v + 0 < 80) }'; then
          lines_none="$lines_none$file:$line coverage threshold $kind is $entry, below 80$NL"
        fi
        ;;
    esac
  done 3<<EOT
$recs
EOT
  printf '%s%s%s%s' "$lines_none" "$lines_hides" "$lines_reason" "$lines_default"
}

# Print the first non-test source file below the project-relative folder DIR ("." for the root) that matches one of the extensions, or nothing.
first_source() {
  local dir=$1 ext
  shift
  for ext in "$@"; do
    printf '%s\n' "$RULES_SRC" | awk -v d="$dir" -v e="$ext" '
      (d == "." || index($0, d "/") == 1) && $0 ~ ("\\." e "$") { print; exit }'
  done | head -n 1
}

# True when DIR holds a coverage config of any supported form. Reads only the config files that sit directly in DIR.
has_coverage_config() {
  local dir=$1 f
  for f in "$dir"/vitest*.config.* "$dir"/vitest.workspace.* "$dir"/vite.config.* "$dir"/jest*.config.* "$dir"/pyproject.toml "$dir"/.coveragerc "$dir"/setup.cfg "$dir"/tox.ini; do
    if [ -f "$f" ] && [ ! -L "$f" ] && grep -qi 'coverage' "$f" 2> /dev/null; then return 0; fi
  done
  f=$dir/package.json
  if [ -f "$f" ] && [ ! -L "$f" ] && grep -qE 'coverageThreshold|collectCoverage|"nyc"|"c8"' "$f" 2> /dev/null; then return 0; fi
  return 1
}

# Print the audit lines for a command-line exclude (F records) in the output of cmd_scan; collect the config pointers (P records).
cmd_lines() {
  local tab ctag cfile cline ctool cpath
  tab=$(printf '\t')
  while IFS="$tab" read -r ctag cfile cline ctool cpath; do
    case "$ctag" in
      F) echo "$cfile:$cline passes an exclude or include on the command line, where it cannot carry a reason: move it into the config file with a reason" ;;
      P) POINTERS="$POINTERS$cfile$tab$cline$tab$ctool$tab$cpath$NL" ;;
    esac
  done
}

# Sort one file into the scanner list for its type; false when the gate and the audit cannot read this type. The lists are kept in
# the strings A_JS, A_PY, A_PROP and A_OTHER (newline separated, absolute paths); a file already listed is not added twice.
add_config() {
  local abs=$1 tool=${2:-} base=${1##*/} jsmode=
  case "$NL$A_SEEN" in *"$NL$abs$NL"*) return 0 ;; esac
  if [ -n "$tool" ]; then
    # The tool word of the command line that pointed at the file decides the scan mode, never the file name.
    case "$tool" in
      jest | vitest | stryker) jsmode=$tool ;;
      nyc | c8) jsmode=nyc ;;
      pytest | py.test | coverage | mutmut)
        case "$base" in
          *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | *.properties | *.yml | *.yaml) return 1 ;;
        esac
        A_PY="$A_PY$abs$NL"
        A_SEEN="$A_SEEN$abs$NL"
        return 0
        ;;
      sonar-scanner | sonar-scanner-cli)
        case "$base" in
          *.properties) A_PROP="$A_PROP$abs$NL" ;;
          *) return 1 ;;
        esac
        A_SEEN="$A_SEEN$abs$NL"
        return 0
        ;;
      *) return 1 ;;
    esac
    case "$base" in
      *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | .nycrc* | .c8rc*) ;;
      *) return 1 ;;
    esac
    A_JS="$A_JS$abs$NL"
    A_MODES="$A_MODES$abs$(printf '\t')$jsmode$NL"
    A_SEEN="$A_SEEN$abs$NL"
    return 0
  fi
  case "$base" in
    *.properties) A_PROP="$A_PROP$abs$NL" ;;
    pyproject.toml | .coveragerc | setup.cfg | tox.ini | *.toml | *.ini | *.cfg) A_PY="$A_PY$abs$NL" ;;
    karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml) A_OTHER="$A_OTHER$abs$NL" ;;
    *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | .nycrc* | .c8rc*) A_JS="$A_JS$abs$NL" ;;
    *) return 1 ;;
  esac
  A_SEEN="$A_SEEN$abs$NL"
  return 0
}

# Print the lines for the Sonar, TOML, INI, properties and other non-JS config FILE.
audit_file() {
  local f=$1 dir base here tools words src out tab hit rel
  tab=$(printf '\t')
  dir=$(dirname "$f")
  base=$(basename "$f")
  here=$DEFECTS/exclusion-audit
  tools=$(cat "$here/defaults.txt") || return 1
  words=$(cat "$here/placeholders.txt") || return 1
  rel=${dir#"$P"}
  rel=${rel#/}
  [ -n "$rel" ] || rel=.
  case "$base" in
    *.properties)
      if is_binary "$f"; then
        echo "$f:1 cannot be read: the file holds a NUL byte, so it is not a text file and its excludes were not audited"
      else
        out=$(TC_EXCLUDE_DEFAULTS=$tools TC_REASON_PLACEHOLDERS=$words awk -v file="$f" -f "$here/scan.awk" "$f" 2>&1) || out="X$tab$f${tab}1${tab}the properties scanner failed${tab}${tab}"
        printf '%s\n' "$out" | audit_records
      fi
      ;;
    pyproject.toml | .coveragerc | setup.cfg | tox.ini | *.toml | *.ini | *.cfg)
      case "$NL$A_POINTED" in *"$NL$f$NL"*) hit=pointed ;; *) hit= ;; esac
      if [ "$base" = .coveragerc ] || [ -n "$hit" ] || grep -qE 'coverage|mutmut' "$f" 2> /dev/null; then
        if [ -n "$A_PYBIN" ]; then
          out=$(TC_EXCLUDE_DEFAULTS=$tools TC_REASON_PLACEHOLDERS=$words "$A_PYBIN" -I "$here/scan.py" "$f" 2>&1) || out="X$tab$f${tab}1${tab}the TOML and INI scanner failed (it needs Python (3.11 or newer) or the tomli package; interpreters tried: $RULES_PY_TRIED)${tab}${tab}"
          printf '%s\n' "$out" | audit_records
        else
          echo "$f:1 cannot be read: python3 is not installed, so this TOML or INI config was not audited"
        fi
      fi
      if [ "$base" = pyproject.toml ] && ! has_coverage_config "$dir"; then
        src=$(first_source "$rel" py)
        if [ -n "$src" ]; then echo "$f:1 no coverage config: the folder has Python source (for example ${src#"$rel"/}) and no coverage config"; fi
      fi
      ;;
    karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml)
      hit=$(unparsed_exclude_line "$f")
      if [ -n "$hit" ]; then echo "$f:${hit%%:*} cannot be read: this file type sets an exclude that the audit does not parse, so its excludes are unaudited"; fi
      ;;
    package.json)
      if grep -q 'minimumReleaseAgeExclude' "$f" 2> /dev/null; then
        awk -v file="$f" -v mode=json -f "$here/scan-pnpm.awk" "$f" | pnpm_records
      fi
      if [ ! -f "$dir/pnpm-workspace.yaml" ] && ! grep -q '"workspaces"' "$f" 2> /dev/null && ! has_coverage_config "$dir"; then
        src=$(first_source "$rel" ts tsx js jsx mjs)
        if [ -n "$src" ]; then echo "$f:1 no coverage config: the folder has source files (for example ${src#"$rel"/}) and no coverage config"; fi
      fi
      ;;
    pnpm-workspace.yaml | .npmrc)
      grep -qE 'minimumReleaseAgeExclude|minimum-release-age-exclude' "$f" 2> /dev/null || return 0
      case "$base" in
        .npmrc) src=npmrc ;;
        *) src=yaml ;;
      esac
      awk -v file="$f" -v mode="$src" -f "$here/scan-pnpm.awk" "$f" | pnpm_records
      ;;
  esac
  return 0
}

# Print the audit lines for every JS, TS and JSON config in A_JS. One node run reads them all (typescript loads once), at most
# MAX_JS_CONFIGS files; a config past that is listed as not read.
js_audit() {
  local cache=$AUDIT_CACHE cands=() c n=0 listed='' words first=
  [ -n "$A_JS" ] || return 0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ -z "$first" ]; then first=$c; fi
    case "$NL$A_POINTED" in
      *"$NL$c$NL"*) ;;
      *)
        case "$c" in
          */package.json) grep -qE '"(jest|nyc|c8|stryker|jscpd)"' "$c" 2> /dev/null || continue ;;
          */.nycrc* | */.c8rc* | */.jscpd.json) ;;
          *) grep -qE 'coverage|mutate|Coverage|ignorePatterns|excludedMutations' "$c" 2> /dev/null || continue ;;
        esac
        ;;
    esac
    n=$((n + 1))
    if [ "$n" -le "$MAX_JS_CONFIGS" ]; then
      cands+=("$c")
      listed="$listed$c$NL"
    else
      echo "$c:1 not read: the audit reads at most $MAX_JS_CONFIGS JS and TS configs per run"
    fi
  done <<< "$A_JS"
  [ "${#cands[@]}" -gt 0 ] || return 0
  if ! command -v node > /dev/null 2>&1; then
    echo "${cands[0]}:1 cannot be read: node is not installed, so this JS or TS config was not audited"
    return 0
  fi
  if [ -z "$cache" ] || [ ! -f "$cache" ]; then
    echo "${cands[0]}:1 cannot be read: no temporary file could be made, so this JS or TS config was not audited"
    return 0
  fi
  words=$(cat "$DEFECTS/exclusion-audit/placeholders.txt") || words=
  local jargs=() jm
  for c in "${cands[@]}"; do
    jm=$(printf '%s' "$A_MODES" | awk -F'\t' -v f="$c" '$1 == f { print $2; exit }')
    jargs+=("--as=$jm" "$c")
  done
  TC_EXCLUDE_DEFAULTS=$(cat "$DEFECTS/exclusion-audit/defaults.txt") TC_REASON_PLACEHOLDERS=$words node "$DEFECTS/exclusion-audit/scan.mjs" --root "$P" "${jargs[@]}" > "$cache" 2>&1 || printf 'X\t%s\t1\tthe JS config scanner failed\n' "${cands[0]}" >> "$cache"
  audit_records < "$cache"
}

# The whole audit, run once: it reads the one shared file list (rules_files), so no folder is skipped by its name and config discovery,
# the command-line scan and the marker scan see the same files.
audit_all() {
  local FILES rel f abs base big tools words tab a_cmd a_mark pfile pline ptool ppath target pdir out cmd_out
  tab=$(printf '\t')
  FILES=$(rules_files "$P")
  rules_init "$FILES"
  big=$(find "$P" \( -name node_modules -o -name .git \) -prune -o -type f -size +"${MAXBYTES:-1048576}"c -print 2> /dev/null)
  A_JS='' A_PY='' A_PROP='' A_OTHER='' A_SEEN='' A_POINTED='' A_MODES=''
  POINTERS=
  a_cmd=() a_mark=()
  local a_pnpm=()
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    abs=$P/$rel
    base=${rel##*/}
    if [ -L "$abs" ]; then
      if [ ! -f "$abs" ]; then echo "$abs:1 is a symlink that is not a link to a regular file, so nothing behind it was audited"; fi
      continue
    fi
    [ -f "$abs" ] || continue
    case "$NL$big$NL" in *"$NL$abs$NL"*) continue ;; esac
    case "$rel" in
      *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.mts | *.cts | *.vue | *.svelte | *.py) a_mark+=("$abs") ;;
    esac
    case "$base" in
      *.properties)
        # Any properties file that holds a sonar. key is a Sonar config, whatever its name.
        if grep -qaE '^[[:space:]]*sonar\.[A-Za-z]' "$abs" 2> /dev/null; then add_config "$abs" || true; fi
        ;;
    esac
    case "$base" in
      vitest*.config.* | vitest.workspace.* | vite.config.* | jest*.config.* | stryker*.conf* | .stryker*.conf* | .nycrc* | .c8rc* | .jscpd.json | sonar-project*.properties | pyproject.toml | .coveragerc | setup.cfg | tox.ini | karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml | package.json) add_config "$abs" || true ;;
      pnpm-workspace.yaml | .npmrc) a_pnpm+=("$abs") ;;
    esac
    case "$rel" in
      package.json | */package.json | *.sh | *.bash | Makefile | */Makefile | Makefile.* | */Makefile.* | *.mk | Taskfile* | */Taskfile* | justfile | */justfile | Justfile | */Justfile | Dockerfile* | */Dockerfile* | *.dockerfile | \
        .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml | .github/actions/*/*.yml | .github/actions/*/*.yaml | \
        lefthook*.yml | */lefthook*.yml | lefthook*.yaml | */lefthook*.yaml | .lefthook*.yml | .gitlab-ci.yml | */.gitlab-ci.yml | .gitlab/*.yml | azure-pipelines*.yml | */azure-pipelines*.yml | bitbucket-pipelines.yml | Jenkinsfile | */Jenkinsfile | \
        pyproject.toml | */pyproject.toml | pytest.ini | */pytest.ini | tox.ini | */tox.ini | setup.cfg | */setup.cfg | \
        .circleci/*.yml | .travis.yml | appveyor.yml | .drone.yml | cloudbuild.y*ml | .buildkite/*.yml | .woodpecker/*.yml | .woodpecker.yml)
        a_cmd+=("$abs")
        ;;
    esac
  done <<EOF
$FILES
EOF
  A_PYBIN=$(resolve_python "$P") || A_PYBIN=
  if [ -z "$A_PYBIN" ] && command -v python3 > /dev/null 2>&1; then A_PYBIN=python3; fi
  if [ "${#a_cmd[@]}" -gt 0 ]; then
    cmd_out=$(cmd_scan "${a_cmd[@]}")
    cmd_lines <<EOF
$cmd_out
EOF
  fi
  # Config pointers: the pointed file is audited too; it is a finding only when it is missing or of a type the audit cannot read.
  while IFS="$tab" read -r pfile pline ptool ppath; do
    [ -n "$pfile" ] || continue
    case "$ppath" in
      *'$'* | *'`'* | /* | ../* | */../* | ..)
        echo "$pfile:$pline points $ptool at '$ppath', a path the audit cannot resolve inside the project, so its excludes are unaudited"
        continue
        ;;
    esac
    ppath=${ppath#./}
    target=
    if [ -f "$P/$ppath" ]; then
      target=$P/$ppath
    else
      pdir=${pfile%/*}
      if [ -f "$pdir/$ppath" ]; then target=$pdir/$ppath; fi
    fi
    if [ -z "$target" ]; then
      echo "$pfile:$pline points $ptool at $ppath, which does not exist, so its excludes are unaudited"
    elif [ -L "$target" ]; then
      echo "$pfile:$pline points $ptool at $target, a symlink the audit does not follow, so its excludes are unaudited"
    elif add_config "$target" "$ptool"; then
      A_POINTED="$A_POINTED$target$NL"
    else
      echo "$pfile:$pline points $ptool at $target, a file type the audit cannot read, so its excludes are unaudited"
    fi
  done <<EOF
$POINTERS
EOF
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    audit_file "$f"
  done <<EOF
$A_PY$A_PROP$A_OTHER$(printf '%s\n' "${a_pnpm[@]+"${a_pnpm[@]}"}")
EOF
  while IFS= read -r f; do
    case "${f##*/}" in package.json) audit_file "$f" ;; esac
  done <<< "$A_JS"
  js_audit
  if [ "${#a_mark[@]}" -gt 0 ]; then
    tools=$(cat "$DEFECTS/exclusion-audit/defaults.txt") || return 0
    words=$(cat "$DEFECTS/exclusion-audit/placeholders.txt") || return 0
    printf '%s\0' "${a_mark[@]}" | TC_EXCLUDE_DEFAULTS=$tools TC_REASON_PLACEHOLDERS=$words xargs -0 awk -v mode=marks -f "$DEFECTS/exclusion-audit/scan.awk" 2> /dev/null | audit_records
  fi
}

# The runner calls check once per candidate file it found. The first call runs the whole audit; later calls have nothing left to do.
check() {
  local here=$DEFECTS/exclusion-audit
  [ -d "$here" ] || return 1
  [ -r "$here/defaults.txt" ] || return 1
  [ -r "$here/rules.sh" ] || return 1
  [ -n "$AUDIT_MARKS" ] || return 0
  [ -f "$AUDIT_MARKS" ] || return 0
  [ ! -s "$AUDIT_MARKS" ] || return 0
  printf '%s' ran > "$AUDIT_MARKS"
  audit_all
  return 0
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
