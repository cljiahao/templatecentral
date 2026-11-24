# shellcheck shell=bash
# Rules shared by check-exclude-reasons.sh (the seeded gate), the gate's tests and the migrate exclusion audit, which keeps a byte copy in
# exclusion-audit/rules.sh. Sourced, never run; it defines functions only and has no side effects.
#   rules_files ROOT        print every project file, relative to ROOT, one per line. Inside a git work tree it is `git ls-files -co
#                           --exclude-standard` (tracked and untracked, ignored files left out); elsewhere it is every file except
#                           node_modules, .git and a virtual environment folder (outside git only), and a caller that finds rules_in_git ROOT false prints RULES_NOTE.
#                           Config discovery and the marker scan both read this one list: no folder is skipped by its name alone.
#   rules_init LIST         read the project facts from the file list LIST: the non-test source files and the package folders.
#   hides_source ENTRY DIR  true when the exclude ENTRY, written in a config in folder DIR, leaves out every non-test source file of the
#                           project, of one package (a folder with its own package.json or pyproject.toml), or of one top-level folder that holds
#                           half or more of the sources, or every source file of one extension (3 files or more) in any of those. A form the
#                           gate cannot evaluate counts too (RULES_WHY says which). No reason can buy that.
#   include_covers ENTRIES DIR  true when the include list ENTRIES matches every non-test source file below DIR (it narrows nothing).
#   under_source_root E     prints the source root when ENTRY sits inside one without covering all of it (the audit only reports it).
#   is_binary FILE          true when FILE holds a NUL byte, so no text scanner can read it.
#   cmd_scan FILE...        print F<TAB>file<TAB>line for an exclude flag and P<TAB>file<TAB>line<TAB>tool<TAB>path for a config pointer, on a
#                           command line whose command word is a coverage, mutation or Sonar tool.
#   resolve_python DIR      print the interpreter to run the TOML and INI scanner (DIR/.venv/bin/python3, then the highest python3.N on the
#                           path, then python3) that can read TOML: the first with tomllib or tomli. RULES_PY_TRIED lists what was tried.
# Pattern forms handled: {a,b} groups (nested too), a leading ! ./ / or ^, a trailing $ or /, ./ and // inside, ** * ? [set], (a|b), and
# the regex spellings .* and \. . A form with !( @( +( ?( or *( cannot be evaluated and counts as broad.

SOURCE_ROOTS=' src app lib libs pages components server api backend frontend source packages apps services cmd internal pkg modules '
RULES_SRC=
RULES_PKGS=
RULES_NOTE='not inside a git work tree, so files a .gitignore would hide were not filtered; every file except node_modules, .git and virtualenv folders is read'
RULES_WHY=
RULES_PY_TRIED=
export RULES_NOTE RULES_WHY RULES_PY_TRIED

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

# Reduce one entry (no braces) to a plain pattern: no !, ./, ^, leading or trailing / or $, no // or /./, regex spellings turned into globs.
norm_pat() {
  local p=$1
  p=${p#\!}
  p=${p#^}
  p=${p%\$}
  p=${p//\\./.}
  p=${p//.\*/*}
  while :; do
    case "$p" in
      *'//'*) p=${p//\/\//\/} ;;
      *'/./'*) p=${p//\/.\//\/} ;;
      *) break ;;
    esac
  done
  while :; do
    case "$p" in
      ./*) p=${p#./} ;;
      /*) p=${p#/} ;;
      *) break ;;
    esac
  done
  case "$p" in
    . | ./) p= ;;
  esac
  p=${p%/}
  printf '%s' "$p"
}

src_type_glob() {
  case "$1" in
    '*.ts' | '*.tsx' | '*.js' | '*.jsx' | '*.mjs' | '*.cjs' | '*.mts' | '*.cts' | '*.py' | '*.vue' | '*.svelte') return 0 ;;
  esac
  return 1
}

# Succeed when ROOT is inside a git work tree. The caller runs this itself because rules_files runs in a command substitution.
rules_in_git() {
  command -v git > /dev/null 2>&1 && git -C "$1" rev-parse --is-inside-work-tree > /dev/null 2>&1
}

# Print the project files, relative to ROOT, one per line.
rules_files() {
  local root=$1 raw f nogit=0
  if rules_in_git "$root"; then
    raw=$(git -C "$root" -c core.quotepath=off ls-files -co --exclude-standard 2> /dev/null) || raw=
    local keep=
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -f "$root/$f" ] || [ -L "$root/$f" ]; then keep="$keep$f
"; fi
    done <<EOF
$raw
EOF
    raw=$keep
  else
    nogit=1
    raw=$(cd "$root" && find . \( -name node_modules -o -name .git \) -prune -o \( -type f -o -type l \) -print 2> /dev/null | sed 's|^\./||')
  fi
  # Outside git only: a folder is a virtual environment when it holds a pyvenv.cfg and also bin/python*, Scripts/python* or
  # lib/python*/site-packages. A pyvenv.cfg alone (a stray file in src/) hides nothing.
  printf '%s\n' "$raw" | NOGIT=$nogit awk '
    { l[++n] = $0 }
    END {
      if (ENVIRON["NOGIT"] == "1") {
        for (i = 1; i <= n; i++) if (l[i] ~ /\/pyvenv\.cfg$/) { d = l[i]; sub(/\/pyvenv\.cfg$/, "", d); cand[d] = 1 }
        for (i = 1; i <= n; i++) for (d in cand) if (index(l[i], d "/") == 1) {
          r = substr(l[i], length(d) + 2)
          if (r ~ /^bin\/python[^\/]*$/ || r ~ /^Scripts\/python[^\/]*$/ || r ~ /^lib\/python[^\/]*\/site-packages(\/|$)/) ok[d] = 1
        }
      }
      for (i = 1; i <= n; i++) {
        if (l[i] == "" || l[i] ~ /(^|\/)(node_modules|\.git)\//) continue
        hid = 0
        for (d in ok) if (index(l[i], d "/") == 1) hid = 1
        if (!hid) print l[i]
      }
    }'
}

# Read the project facts from the file list $1 (newline separated, relative paths): RULES_SRC holds the non-test source files and
# RULES_PKGS the folders with their own package.json or pyproject.toml, other than the root.
rules_init() {
  RULES_SRC=$(printf '%s\n' "$1" | awk '
    function issrc(p,   b) {
      b = p
      sub(/^.*\//, "", b)
      if (b !~ /\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|py|vue|svelte)$/) return 0
      if (b ~ /\.d\.[cm]?ts$/) return 0
      if (b ~ /\.config\.[a-z]+$/) return 0
      if (b ~ /\.(test|spec)\.[a-z]+$/) return 0
      if (b ~ /^test_.*\.py$/ || b ~ /_test\.py$/ || b == "conftest.py") return 0
      if (p ~ /(^|\/)(test|tests|__tests__)\//) return 0
      # Files the scaffold seeds (the source-type entries of skills/scaffold/shared/template.manifest) are harness, not project source.
      if (p ~ /^scripts\/check-exclude-reasons\.(mjs|py)$/ || p ~ /^\.claude\/hooks\/user-prompt-guard\.(py|cjs)$/) return 0
      return 1
    }
    issrc($0) { print }')
  RULES_PKGS=$(printf '%s\n' "$1" | awk '
    { b = $0; sub(/^.*\//, "", b) }
    b == "package.json" || b == "pyproject.toml" {
      d = $0
      if (index(d, "/") == 0) next
      sub(/\/[^\/]*$/, "", d)
      print d
    }' | LC_ALL=C sort -u)
}

# Evaluate patterns against RULES_SRC. MODE excl: exit 0 when one pattern of RULES_PAT (newline separated) covers a whole scope.
# MODE incl: exit 0 when the union of the patterns covers every source file below DIR. Exit 1 otherwise, 3 when a form cannot be evaluated,
# 4 when there are no source files to judge by.
rules_eval() {
  printf '%s\n' "$RULES_SRC" | RULES_FN=${RULES_FN:-} RULES_PAT=$2 RULES_PKGLIST=$RULES_PKGS awk -v mode="$1" -v cdir="$3" '
    function g2re(g,   i, c, n, r, d, j, depth) {
      r = ""; n = length(g); i = 1; depth = 0
      while (i <= n) {
        c = substr(g, i, 1)
        if (substr(g, i, 3) == "**/") { r = r "(.*/)?"; i += 3; continue }
        if (substr(g, i, 2) == "**") { r = r ".*"; i += 2; continue }
        if (c == "*") { r = r "[^/]*"; i++; continue }
        if (c == "?") { r = r "[^/]"; i++; continue }
        if (c == "[") {
          j = index(substr(g, i + 1), "]")
          if (j == 0) { r = r "\\["; i++; continue }
          d = substr(g, i + 1, j - 1)
          if (substr(d, 1, 1) == "!") d = "^" substr(d, 2)
          r = r "[" d "]"; i += j + 1; continue
        }
        if (c == "(") depth++
        if (c == ")") { depth--; if (depth < 0) return "" }
        if (c == "(" || c == ")" || c == "|") { r = r c; i++; continue }
        if (c == "\\") { r = r "\\" substr(g, i + 1, 1); i += 2; continue }
        if (c == "." || c == "+" || c == "^" || c == "$" || c == "{" || c == "}") { r = r "\\" c; i++; continue }
        r = r c; i++
      }
      if (depth != 0) return ""
      return "^(" r ")(/.*)?$"
    }
    function fn2re(g,   i, c, n, r, j, d) {
      if (substr(g, 1, 1) == "/") return "a^b"
      n = length(g); r = ""; i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*") { r = r ".*"; i++; continue }
        if (c == "?") { r = r "."; i++; continue }
        if (c == "[") {
          j = index(substr(g, i + 1), "]")
          if (j == 0) { r = r "\\["; i++; continue }
          d = substr(g, i + 1, j - 1)
          if (substr(d, 1, 1) == "!") d = "^" substr(d, 2)
          r = r "[" d "]"; i += j + 1; continue
        }
        if (c ~ /[.+^$(){}|\\]/) { r = r "\\" c; i++; continue }
        r = r c; i++
      }
      if (substr(g, 1, 1) !~ /[*?]/) r = "/" r
      return "^" r "$"
    }
    function mt(i, k,   q) {
      if (mode == "excu") {
        for (q = 1; q <= np; q++) if (fs[i] ~ re[q]) return 1
        return 0
      }
      return (fs[i] ~ re[k])
    }
    BEGIN {
      fn = (ENVIRON["RULES_FN"] == "1")
      np = split(ENVIRON["RULES_PAT"], pat, "\n")
      npk = split(ENVIRON["RULES_PKGLIST"], pk, "\n")
      for (k = 1; k <= np; k++) {
        if (fn) { re[k] = fn2re(pat[k]); continue }
        if (pat[k] ~ /[!@+?*]\(/) { bad = 1 }
        re[k] = g2re(pat[k])
        if (re[k] == "") bad = 1
      }
      if (cdir != "") {
        for (k = 1; k <= npk; k++) {
          if (index(pk[k], cdir "/") == 1) pk[k] = substr(pk[k], length(cdir) + 2)
          else pk[k] = ""
        }
      }
    }
    $0 == "" { next }
    {
      p = $0
      if (cdir != "") {
        if (index(p, cdir "/") != 1) next
        p = substr(p, length(cdir) + 2)
      }
      nf++
      f[nf] = p
      fs[nf] = (fn ? "/" p : p)
    }
    END {
      if (bad) exit 3
      if (nf == 0) exit 4
      for (i = 1; i <= nf; i++) {
        p = f[i]
        e = p
        if (e ~ /\.[A-Za-z]+$/) { sub(/^.*\./, "", e) } else e = ""
        top = ""
        if (index(p, "/") > 0) { top = p; sub(/\/.*$/, "", top) }
        best = ""
        for (k = 1; k <= npk; k++) if (pk[k] != "" && index(p, pk[k] "/") == 1 && length(pk[k]) > length(best)) best = pk[k]
        tot["P"]++; tot["P|" e]++
        if (top != "") { tot["T:" top]++; tot["T:" top "|" e]++ }
        if (best != "") { tot["K:" best]++; tot["K:" best "|" e]++ }
        topn[top] = 1
        ptop[i] = top; pbest[i] = best; pe[i] = e
      }
      if (mode == "incl") {
        for (i = 1; i <= nf; i++) {
          ok = 0
          for (k = 1; k <= np; k++) if (fs[i] ~ re[k]) { ok = 1; break }
          if (!ok) exit 1
        }
        exit 0
      }
      nk = (mode == "excu" ? 1 : np)
      for (k = 1; k <= nk; k++) {
        split("", hit)
        for (i = 1; i <= nf; i++) {
          if (!mt(i, k)) continue
          e = pe[i]
          hit["P"]++; hit["P|" e]++
          if (ptop[i] != "") { hit["T:" ptop[i]]++; hit["T:" ptop[i] "|" e]++ }
          if (pbest[i] != "") { hit["K:" pbest[i]]++; hit["K:" pbest[i] "|" e]++ }
        }
        for (s in hit) {
          if (hit[s] != tot[s]) continue
          if (index(s, "|") > 0) { if (tot[s] >= 3) exit 0; continue }
          if (substr(s, 1, 2) == "T:") { if (tot[s] * 2 >= tot["P"]) exit 0; continue }
          exit 0
        }
      }
      exit 1
    }'
}

hide_one() {
  local p=$1 dir=$2 q rc
  RULES_WHY=
  case "$p" in
    '') return 1 ;;
    '*' | '**' | '**/*') return 0 ;;
  esac
  case "$p" in
    *'!('* | *'@('* | *'+('* | *'?('* | *'*('*)
      RULES_WHY="uses the pattern form '$p', which the gate cannot evaluate against the project files"
      return 0
      ;;
  esac
  q=$p
  while :; do
    case "$q" in
      '**/'*) q=${q#\*\*/} ;;
      *) break ;;
    esac
  done
  if src_type_glob "$q"; then return 0; fi
  if [ -z "$RULES_SRC" ]; then return 1; fi
  rules_eval excl "$p" "$dir"
  rc=$?
  case "$rc" in
    0) return 0 ;;
    3)
      RULES_WHY="uses a pattern the gate cannot evaluate against the project files ('$p')"
      return 0
      ;;
  esac
  return 1
}

hides_source() {
  local alt p dir=${2:-} rc
  [ "$dir" != . ] || dir=
  RULES_WHY=
  while IFS= read -r alt; do
    p=$(norm_pat "$alt")
    if hide_one "$p" "$dir"; then return 0; fi
  done <<EOF
$(expand_braces "$1")
EOF
  # A coverage.py omit or include pattern is an fnmatch pattern on the absolute path: * crosses / and a pattern led by * can start anywhere.
  if [ "${3:-}" = py ] && [ -n "$RULES_SRC" ] && [ -n "$1" ]; then
    RULES_FN=1 rules_eval excl "$1" "$dir"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      RULES_WHY="as a coverage.py pattern ('$1', where * also matches /) it matches every source file of the project, of one package or of one top-level source folder"
      return 0
    fi
  fi
  return 1
}

# True when the entries of one exclude list (ENTRIES, newline separated), none of which hides source alone, together leave out every non-test
# source file of the project, of one package or of one top-level folder, or every file of one type there. Splitting a broad pattern into
# narrower ones, each with a reason, hides the same code. PY as the third argument adds the coverage.py reading.
hides_union() {
  local entries=$1 dir=${2:-} e alt p list='' raws='' rc
  [ "$dir" != . ] || dir=
  [ -n "$RULES_SRC" ] || return 1
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    raws="$raws$e
"
    while IFS= read -r alt; do
      p=$(norm_pat "$alt")
      case "$p" in
        '' | *'!('* | *'@('* | *'+('* | *'?('* | *'*('*) continue ;;
      esac
      list="$list$p
"
    done <<EOF
$(expand_braces "$e")
EOF
  done <<EOF
$entries
EOF
  if [ -n "$list" ]; then
    rules_eval excu "${list%?}" "$dir"
    rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
  fi
  if [ "${3:-}" = py ] && [ -n "$raws" ]; then
    RULES_FN=1 rules_eval excu "${raws%?}" "$dir"
    rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
  fi
  return 1
}

# Read E records (tab separated, as the scanners print them) on stdin and print one line per group of exclude entries that has two or more
# entries which are not defaults: file<TAB>group<TAB>first line<TAB>the entries joined by the SOH byte. A group is what is hidden, not where
# it is written: one coverage group per tool and folder across all its config files (Sonar: sonar.exclusions and sonar.coverage.exclusions
# together; sonar.cpd.exclusions and any other sonar.*.exclusions key each on their own), and one mutation group per tool.
rules_union_groups() {
  awk -F'\t' '
    function grp(f, kind,   b, d) {
      b = f; sub(/^.*\//, "", b)
      d = "."
      if (f ~ /\//) { d = f; sub(/\/[^\/]*$/, "", d) }
      if (b ~ /\.properties$/) return ((kind == "sonar-exclude" || kind == "sonar-coverage-exclude") ? "sonar-exclusions" : kind) "\t" d
      if (b ~ /^(pyproject\.toml|setup\.cfg|tox\.ini|\.coveragerc.*)$/ || b ~ /\.(toml|ini|cfg)$/) return (kind ~ /^mutation/ ? "mutmut" : "coverage.py") "\t" d
      if (kind ~ /^mutation/ || b ~ /^\.?stryker/) return "stryker\t" d
      if (b ~ /^vite(st)?[.-]/ || b ~ /^vitest/) return "vitest\t" d
      if (b ~ /^jest/) return "jest\t" d
      if (b ~ /^(\.nycrc|\.c8rc|nyc\.)/) return "nyc\t" d
      return b "\t" d
    }
    $1 == "E" && $6 != "default" && $4 != "sonar-issue-ignore" {
      k = grp($2, $4)
      if (!(k in first)) { first[k] = $3; ffile[k] = $2; order[++n] = k }
      cnt[k]++
      list[k] = list[k] (cnt[k] > 1 ? "\001" : "") $5
    }
    END { for (i = 1; i <= n; i++) { k = order[i]; if (cnt[k] >= 2) { g = k; sub(/\t.*$/, "", g); printf "%s\t%s\t%s\t%s\n", ffile[k], g, first[k], list[k] } } }'
}

include_covers() {
  local list='' raw='' alt p dir=${2:-} item rc
  [ "$dir" != . ] || dir=
  [ -n "$RULES_SRC" ] || return 1
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    raw="$raw$item
"
    while IFS= read -r alt; do
      p=$(norm_pat "$alt")
      # An empty pattern (source = . or ./) is the whole project root.
      if [ -z "$p" ]; then return 0; fi
      case "$p" in
        *'!('* | *'@('* | *'+('* | *'?('* | *'*('*) return 1 ;;
      esac
      list="$list$p
"
    done <<EOF
$(expand_braces "$item")
EOF
  done <<EOF
$(printf '%s\n' "$1" | awk '{ d = 0; o = ""; for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c == "{" || c == "(") d++; if (c == "}" || c == ")") d--; if (c == "," && d <= 0) { print o; o = "" } else o = o c } print o }' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
EOF
  rules_eval incl "${list%?}" "$dir"
  rc=$?
  if [ "$rc" -eq 0 ]; then return 0; fi
  if [ "${3:-}" = py ] && [ -n "$raw" ]; then
    RULES_FN=1 rules_eval incl "${raw%?}" "$dir"
    return $?
  fi
  return "$rc"
}

under_source_root() {
  local alt p root
  while IFS= read -r alt; do
    p=$(norm_pat "$alt")
    p=${p#\*\*/}
    if [ "$p" = "src/components/ui/**" ]; then continue; fi
    root=${p%%/*}
    case "$p" in
      */*) ;;
      *) continue ;;
    esac
    case "$SOURCE_ROOTS" in
      *" $root "*)
        printf '%s' "$root"
        return 0
        ;;
    esac
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

# Print file<TAB>line for each command line that passes an exclude to a coverage, mutation or Sonar tool, and each config pointer.
cmd_scan() {
  [ "$#" -gt 0 ] || return 0
  local out rc tab bad
  tab=$(printf '\t')
  out=$(awk '
    function clean(t) {
      gsub(/^[\042\047\[(@]+/, "", t)
      gsub(/[\042\047\]),]+$/, "", t)
      return t
    }
    function isenv(t) { return (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) }
    function iswrap(t) {
      if (t ~ /^python[0-9.]*$/) return 1
      if (t ~ /^\{(envpython|py)\}$/) return 1
      return (t == "npx" || t == "pnpm" || t == "yarn" || t == "npm" || t == "bunx" || t == "bun" || t == "exec" || t == "run" || t == "dlx" || t == "x" || t == "node" || t == "env" || t == "cross-env" || t == "time" || t == "sudo" || t == "uv" || t == "poetry" || t == "pipx" || t == "-m" || t == "RUN" || t == "CMD" || t == "ENTRYPOINT" || t == "run:" || t == "script:" || t == "command:" || t == "entrypoint:" || t == "-" || t == "sh" || t == "bash" || t == "-c" || t == "$")
    }
    function tool(t) {
      sub(/^.*\//, "", t)
      sub(/\.cmd$/, "", t)
      if (t == "nyc" || t == "c8" || t == "jest" || t == "vitest" || t == "stryker" || t == "mutmut" || t == "coverage" || t == "pytest" || t == "py.test" || t == "sonar-scanner" || t == "sonar-scanner-cli") return t
      return ""
    }
    # An exclude, include or mutate-path flag in S. Plain --exclude and --include count only for the tools that take them, or when GENERIC is set.
    function flagged(s, cmd, generic) {
      if (s ~ /-D[ ]?sonar\.[A-Za-z.]*(exclusions|inclusions)/ || s ~ /sonar\.issue\.ignore/ || s ~ /--coverage\.(exclude|include)/) return 1
      if (s ~ /--(coveragePathIgnorePatterns|collectCoverageFrom|omit|cov-omit|paths-to-exclude|do-not-mutate|mutate|paths-to-mutate)([ =]|$)/) return 1
      if ((generic || cmd == "nyc" || cmd == "c8" || cmd == "coverage" || cmd == "mutmut") && s ~ /--(exclude|include)([ =]|$)/) return 1
      return 0
    }
    function seg(s, ln,   n, t, k, w, cmd, i, v, hasflag, toolk, runner, after, dd) {
      n = split(s, t, /[ \t]+/)
      cmd = ""; toolk = 0; runner = ""
      for (k = 1; k <= n; k++) {
        w = clean(t[k])
        if (w == "" || w == "@") continue
        sub(/^@/, "", w)
        if (runner == "" && (w == "npm" || w == "pnpm" || w == "yarn" || w == "bun")) runner = w
        if (isenv(w) || iswrap(w) || substr(w, 1, 1) == "-") continue
        cmd = tool(w)
        if (cmd != "") toolk = k
        break
      }
      if (cmd == "") {
        # npm run cov -- --coverage.exclude=x: the flags after -- reach whatever tool the script runs.
        if (runner == "") return
        after = ""; dd = 0
        for (k = 1; k <= n; k++) {
          if (dd) after = after " " t[k]
          else if (t[k] == "--") dd = 1
        }
        if (flagged(s, "", 0) || (dd && flagged(after, "", 1))) printf "F\t%s\t%d\n", curfile, ln
        return
      }
      if (flagged(s, cmd, 0)) printf "F\t%s\t%d\n", curfile, ln
      for (k = toolk + 1; k <= n; k++) {
        w = clean(t[k]); v = ""
        if (w ~ /^--(config|cov-config|rcfile|nycrc-path)=/) { v = w; sub(/^[^=]*=/, "", v) }
        else if (w ~ /^-Dproject\.settings=/) { v = w; sub(/^[^=]*=/, "", v) }
        else if (w == "--config" || w == "--cov-config" || w == "--rcfile" || w == "--nycrc-path" || w == "-Dproject.settings" || ((w == "-c") && (cmd == "jest" || cmd == "vitest" || cmd == "pytest"))) { if (k < n) v = clean(t[k + 1]) }
        if (v != "") printf "P\t%s\t%d\t%s\t%s\n", curfile, ln, cmd, v
      }
    }
    function lineseg(line, ln,   n, parts, i) {
      gsub(/&&/, "\001", line)
      gsub(/\|/, "\001", line)
      gsub(/;/, "\001", line)
      n = split(line, parts, "\001")
      for (i = 1; i <= n; i++) seg(parts[i], ln)
    }
    # tox.ini commands: each indented line is a command line (a trailing backslash joins the next one); the key may carry a suffix (commands_pre).
    function toxline(t, ln) {
      if (match(t, /\\[ \t]*$/)) {
        sub(/\\[ \t]*$/, "", t)
        if (tpend == "") tln = ln
        tpend = tpend " " t
        return
      }
      if (tpend != "") { t = tpend " " t; ln = tln; tpend = ""; tln = 0 }
      lineseg(t, ln)
    }
    function endad() { lineseg("pytest " adtext, adln); ad = 0; adtext = "" }
    function finbuf() { if (buf != "") lineseg(buf, bufln); buf = ""; bufln = 0 }
    function fin() {
      if (pend != "") lineseg(pend, pendln)
      pend = ""; pendln = 0
      if (tpend != "") lineseg(tpend, tln)
      tpend = ""; tln = 0; tc = 0
      finbuf(); inblock = 0
      if (ad) endad()
    }
    FNR == 1 {
      fin()
      curfile = FILENAME
      pkg = (FILENAME ~ /package\.json$/)
      bn = FILENAME; sub(/^.*\//, "", bn)
      pyc = (bn == "pyproject.toml" || bn == "pytest.ini" || bn == "tox.ini" || bn == "setup.cfg")
      ad = 0; adtext = ""
    }
    # pytest settings: only addopts is a command line (it may point at a coverage config).
    pyc {
      line = $0
      if (bn == "tox.ini") {
        if (tc) {
          if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*[#;]/) next
          if (line ~ /^[ \t]+[^ \t]/) { toxline(line, FNR); next }
          if (tpend != "") { lineseg(tpend, tln); tpend = ""; tln = 0 }
          tc = 0
        }
        if (match(line, /^[ \t]*commands[A-Za-z_]*[ \t]*[=:]/)) {
          tc = 1
          v = substr(line, RLENGTH + 1)
          if (v ~ /[^ \t]/) toxline(v, FNR)
          next
        }
      }
      if (ad) {
        if (ad == 2) { adtext = adtext " " line; if (line ~ /\]/) endad(); next }
        if (ad == 3) { adtext = adtext " " line; if (line ~ /"""/) endad(); next }
        if (line ~ /^[ \t]+[^ \t]/) { adtext = adtext " " line; next }
        endad()
      }
      if (match(line, /^[ \t]*addopts[ \t]*[=:]/)) {
        v = substr(line, RLENGTH + 1)
        adtext = v; adln = FNR; ad = 1
        tq = v; nq = gsub(/"""/, "", tq)
        if (v ~ /^[ \t]*\[/ && v !~ /\]/) ad = 2
        else if (nq == 1) ad = 3
      }
      next
    }
    {
      line = $0
      if (pkg) {
        while (match(line, /"[^"]*"[ \t]*:[ \t]*"([^"\\]|\\.)*"/)) {
          v = substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
          sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", v)
          sub(/"$/, "", v)
          lineseg(v, FNR)
        }
        next
      }
      pind = (match(line, /[^ \t]/) ? RSTART - 1 : 0)
      # A line ending in a backslash continues on the next line: join them before looking for a tool and its flags.
      if (match(line, /\\[ \t]*$/)) {
        sub(/\\[ \t]*$/, "", line)
        if (pend == "") { pendind = pind; pendln = FNR }
        pend = pend " " line
        next
      }
      if (pend != "") { line = pend " " line; ln = pendln; ind = pendind; pend = ""; pendln = 0 } else { ln = FNR; ind = pind }
      # A YAML block scalar (run: | or run: >) is one command text: join its lines.
      if (inblock) {
        if (line ~ /^[ \t]*$/) next
        if (ind > blockind) { buf = buf " " line; if (!bufln) bufln = ln; next }
        finbuf(); inblock = 0
      }
      lineseg(line, ln)
      if (line ~ /:[ \t]*[|>][-+0-9]*[ \t]*(#.*)?$/) { inblock = 1; blockind = ind; buf = ""; bufln = 0 }
    }
    END { fin() }' "$@" 2>&1)
  rc=$?
  # An awk runtime error prints on stderr and leaves the output short, which would read as a clean file: fail closed with a Q record.
  bad=$(printf '%s\n' "$out" | grep -vE "^([FP]$tab.*)?$" | head -n 1)
  if [ "$rc" -ne 0 ] || [ -n "$bad" ]; then
    printf 'Q\t%s\t0\tthe command-line scanner failed (%s), so no command line was checked\n' "$1" "${bad:-exit status $rc}"
    return 0
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
}

# Print "line:text" for the first line of FILE (a karma, nyc.config or codecov file, which no scanner reads) that sets an exclude, ignore or omit key.
unparsed_exclude_line() {
  grep -nE -e "(^|[^A-Za-z_])(exclude|excludes|ignore|omit|exclusions|coveragePathIgnorePatterns|coverageExclude|ignorePatterns)[A-Za-z]*['\"]?[[:space:]]*[:=]" "$1" 2> /dev/null | head -n 1
}

# Print the interpreter for the TOML and INI scanner: the first of DIR/.venv/bin/python3, the highest python3.N on the path and python3
# that can import tomllib or tomli. Prints nothing when none can; RULES_PY_TRIED then lists what was tried and why each failed.
resolve_python() {
  local dir=${1:-.} cand cands='' n tried='' out
  if [ -x "$dir/.venv/bin/python3" ]; then cands="$dir/.venv/bin/python3
"; fi
  for n in $(compgen -c python3. 2> /dev/null | grep -E '^python3\.[0-9]+$' | sort -t. -k2 -n -r | uniq); do
    cands="$cands$n
"
  done
  if command -v python3 > /dev/null 2>&1; then cands="${cands}python3
"; fi
  RULES_PY_TRIED=
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    out=$("$cand" -I -c 'import sys
try:
    import tomllib
except ImportError:
    import tomli
print(".".join(map(str, sys.version_info[:3])))' 2>&1) && {
      RULES_PY_TRIED="$tried$cand ($out) can read TOML"
      printf '%s' "$cand"
      return 0
    }
    out=$("$cand" -I -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2> /dev/null) || out=unusable
    tried="$tried$cand ($out, no tomllib or tomli); "
  done <<EOF
$cands
EOF
  RULES_PY_TRIED=${tried:-none found: no .venv/bin/python3, no python3.N and no python3 on the path}
  return 1
}
