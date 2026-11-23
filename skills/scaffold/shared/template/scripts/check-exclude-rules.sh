# shellcheck shell=bash
# Rules shared by check-exclude-reasons.sh (the seeded gate) and the migrate exclusion audit, which keeps a byte copy in
# exclusion-audit/rules.sh. Sourced, never run; it defines functions only and has no side effects.
#   hides_source ENTRY   true when ENTRY excludes everything, a whole source root, or every file of a source type. No reason can buy
#                        that, so the gate fails it whatever the comment above it says.
#   under_source_root E  prints the source root when ENTRY sits inside one without covering all of it, and returns 0; else returns 1.
#   is_binary FILE       true when FILE holds a NUL byte, so no text scanner can read it.
# Forms handled: {a,b} groups (nested too), a leading ! ./ / or **/, glob and regex spellings (.* for *, a trailing $).
# Source roots are the folder names below; a source type is the extension list in src_type_glob.

SOURCE_ROOTS=' src app lib libs pages components server api backend frontend source packages apps services cmd internal pkg modules '

# Print each {a,b} alternative of $1 on its own line; the innermost group is expanded first.
expand_braces() {
  local s=$1 pre rest body post alt
  case "$s" in
    *'{'*'}'*) ;;
    *)
      printf '%s\n' "$s"
      return 0
      ;;
  esac
  pre=${s%\{*}
  rest=${s##*\{}
  case "$rest" in
    *'}'*) ;;
    *)
      printf '%s\n' "$s"
      return 0
      ;;
  esac
  body=${rest%%\}*}
  post=${rest#*\}}
  while :; do
    alt=${body%%,*}
    expand_braces "$pre$alt$post"
    case "$body" in
      *,*) body=${body#*,} ;;
      *) break ;;
    esac
  done
}

# Reduce one entry (no braces) to a plain glob: no !, ./, leading /, ^, trailing $ or /, regex spellings, no leading **/ or */.
norm_glob() {
  local p=$1
  p=${p#\!}
  p=${p#./}
  p=${p#^}
  p=${p#/}
  p=${p%\$}
  p=${p//\\./.}
  p=${p//.\*/*}
  p=${p%/}
  while :; do
    case "$p" in
      '**/'*) p=${p#\*\*/} ;;
      '*/'*) p=${p#\*/} ;;
      *) break ;;
    esac
  done
  printf '%s' "$p"
}

src_type_glob() {
  case "$1" in
    '*.ts' | '*.tsx' | '*.js' | '*.jsx' | '*.mjs' | '*.cjs' | '*.mts' | '*.cts' | '*.py' | '*.vue' | '*.svelte') return 0 ;;
  esac
  return 1
}

# Print "root<TAB>rest" for a normalized glob whose first segment is a source root, else nothing.
split_root() {
  local p=$1 root rest
  root=${p%%/*}
  case "$SOURCE_ROOTS" in
    *" $root "*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    */*) rest=${p#*/} ;;
    *) rest= ;;
  esac
  while :; do
    case "$rest" in
      '**/'*) rest=${rest#\*\*/} ;;
      '*/'*) rest=${rest#\*/} ;;
      *) break ;;
    esac
  done
  printf '%s\t%s' "$root" "$rest"
}

hide_one() {
  local p=$1 sr rest
  case "$p" in
    '') return 1 ;;
    '*' | '**' | '**/*') return 0 ;;
  esac
  if src_type_glob "$p"; then return 0; fi
  sr=$(split_root "$p") || return 1
  rest=${sr#*$'\t'}
  case "$rest" in
    '' | '*' | '**' | '**/*') return 0 ;;
  esac
  if src_type_glob "$rest"; then return 0; fi
  return 1
}

hides_source() {
  local alt p
  while IFS= read -r alt; do
    p=$(norm_glob "$alt")
    if hide_one "$p"; then return 0; fi
  done <<EOF
$(expand_braces "$1")
EOF
  return 1
}

under_source_root() {
  local alt p sr
  while IFS= read -r alt; do
    p=$(norm_glob "$alt")
    if [ "$p" = "src/components/ui/**" ]; then continue; fi
    if hide_one "$p"; then continue; fi
    if sr=$(split_root "$p"); then
      printf '%s' "${sr%%$'\t'*}"
      return 0
    fi
  done <<EOF
$(expand_braces "$1")
EOF
  return 1
}

is_binary() {
  local f=$1 kept total
  [ -f "$f" ] || return 1
  kept=$(tr -d '\000' < "$f" | wc -c)
  total=$(wc -c < "$f")
  [ "$kept" -ne "$total" ]
}

# Print, one per line, the find arguments that skip dependencies, VCS data and caches by name, and build output (dist, build, coverage,
# .next) only at ROOT and beside a package.json or pyproject.toml. A folder named build or coverage elsewhere is scanned.
# The caller reads the lines into an array: PRUNE=(); while read -r a; do PRUNE+=("$a"); done; then find ROOT "${PRUNE[@]}" ...
build_prune() {
  local root=$1 pf d b
  local never=(\( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name __pycache__ \) -prune -o)
  local args=(-name node_modules -o -name .git -o -name .venv -o -name venv -o -name __pycache__)
  for b in dist build coverage .next; do
    args+=(-o -path "$root/$b")
  done
  while IFS= read -r pf; do
    [ -n "$pf" ] || continue
    d=$(dirname "$pf")
    for b in dist build coverage .next; do
      args+=(-o -path "$d/$b")
    done
  done <<EOT
$(find "$root" "${never[@]}" -type f \( -name package.json -o -name pyproject.toml \) -print)
EOT
  printf '%s\n' \( "${args[@]}" \) -prune -o
}

# Print file:line:text for every line of the given files that passes an exclude or include to a coverage, Sonar or mutation tool on the
# command line (package.json scripts, CI files, lefthook, Makefile).
cmd_flag_lines() {
  grep -nHE -e '-D[ ]?sonar\.[A-Za-z.]*(exclusions|inclusions)' -e '-D[ ]?sonar\.issue\.ignore' -e '--coverage\.(exclude|include)' \
    -e '--(coveragePathIgnorePatterns|collectCoverageFrom|omit|cov-omit|paths-to-exclude|do-not-mutate|mutate)([ =]|$)' \
    -e '(nyc|c8|jest|coverage|stryker|mutmut|vitest)[^|;&]*[ ]--(exclude|include)([ =]|$)' "$@" 2> /dev/null
}

# Print file:line:text for every line that points a tool at a config file with --config, --cov-config or --rcfile.
cmd_pointer_lines() {
  grep -nHE -e '--(cov-config|rcfile|config)[= ]' "$@" 2> /dev/null
}

# Print the config path of each --config, --cov-config or --rcfile in the line TEXT when the line names a coverage tool; else nothing.
cmd_pointer_paths() {
  case "$1" in
    *nyc* | *c8* | *jest* | *vitest* | *coverage* | *pytest* | *stryker* | *mutmut* | *--cov*) ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$1" | grep -oE -e '--(cov-config|rcfile|config)[= ]+[^ "]+' | sed -E 's/^--[a-z-]+[= ]+//' | tr -d "'\""
}

# Print "line:text" for the first line of FILE (a karma, nyc.config or codecov file, which no scanner reads) that sets an exclude, ignore or omit key.
unparsed_exclude_line() {
  grep -nE -e "(^|[^A-Za-z_])(exclude|excludes|ignore|omit|exclusions|coveragePathIgnorePatterns|coverageExclude|ignorePatterns)[A-Za-z]*['\"]?[[:space:]]*[:=]" "$1" 2> /dev/null | head -n 1
}
