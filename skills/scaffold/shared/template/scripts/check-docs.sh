#!/usr/bin/env bash
# Docs check: check-docs.sh [markdown-file ...]. Offline; one `file:line: message` per finding (max 20 lines).
# Exit 0 clean, 1 findings, 2 internal failure (missing tool, unreadable file, failed temp folder) with one line naming the cause.
# Checks README.md, AGENTS.md, docs/**/*.md and boundary READMEs: relative links and backticked repo paths must exist,
# and a README must not carry a `## Contents` heading or a list naming every child of its own folder.
# With arguments only those files are checked (pre-commit); without, the whole project (pre-push, CI).
# An argument is a path from the caller's folder (relative or absolute) and must sit inside the project; one outside it exits 2.
# Path rule: a path a doc names that does not exist is stale and reported, unless it is an example: a placeholder
# (<name>, {a}, *), an ellipsis, a path/to/... prefix, or an extensionless two-part name whose first folder does not exist.
# A link needs an opening bracket, a target and a closing parenthesis on one line; a target with a real scheme
# (scheme://, mailto:, tel:, data: and the like) is external, so name:3 is checked as a path.
set -uo pipefail

# Prints one line naming the cause and exits 2; exit 1 is reserved for findings.
die() {
  printf 'check-docs: %s\n' "$1" >&2
  exit 2
}

# Sets REPLY to an absolute path with . and .. resolved by text, without touching the disk.
abs_path() {
  local p=$1 seg out=
  case "$p" in /*) ;; *) p=$PWD/$p ;; esac
  local IFS=/
  set -f
  for seg in $p; do
    case "$seg" in
      '' | .) ;;
      ..) out=${out%/*} ;;
      *) out=$out/$seg ;;
    esac
  done
  set +f
  REPLY=${out:-/}
}

ABS_ARGS=()
for arg in "$@"; do
  abs_path "$arg"
  ABS_ARGS[${#ABS_ARGS[@]}]=$REPLY
done

case "$0" in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
cd "$here/.." || die "cannot enter the project folder ($here/..)"
root=$PWD
root_phys=$(pwd -P)

# Sets REPLY to the project-relative form of an absolute path, or returns 1 when the path is outside the project.
rel_to_root() {
  local a=$1 dir phys
  case "$a" in
    "$root"/*) REPLY=${a#"$root"/}; return 0 ;;
  esac
  dir=${a%/*}
  [ -n "$dir" ] || dir=/
  phys=$(cd "$dir" 2> /dev/null && pwd -P) || return 1
  case "$phys/${a##*/}" in
    "$root_phys"/*) REPLY=${phys#"$root_phys"}/${a##*/}; REPLY=${REPLY#/}; return 0 ;;
  esac
  return 1
}

args=()
i=0
for arg in "$@"; do
  rel_to_root "${ABS_ARGS[i]}" || die "outside the project: $arg"
  args[${#args[@]}]=$REPLY
  i=$((i + 1))
done
set -- ${args[@]+"${args[@]}"}

for tool in awk mktemp rm; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done

CAP=20
GENERATED='node_modules dist build .next coverage .venv venv __pycache__ .pytest_cache .ruff_cache .mypy_cache .pyright htmlcov .turbo .stryker-tmp .mutmut-cache .git'
SKIPPED_DIRS='.claude .github .azuredevops azure-pipelines .lefthook secrets .secrets'
EXTS='md|mdx|ts|tsx|js|jsx|mjs|cjs|py|json|yml|yaml|toml|sh|css|scss|sql|html|txt|env|example|ini|cfg|lock|svg|png|jpg|gif|ico|prisma'

workdir=
trap '[ -z "$workdir" ] || rm -rf "$workdir"' EXIT
workdir=$(mktemp -d "${TMPDIR:-/tmp}/check-docs.XXXXXX") || die "cannot create a temporary folder (mktemp failed)"
[ -d "$workdir" ] || die "cannot create a temporary folder (mktemp returned no folder)"

in_git=0
if command -v git > /dev/null 2>&1 && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  in_git=1
fi

FINDINGS=()
F_CHK=()
nfind=0

# True when any path segment is one of the space-separated names in the list.
has_segment() {
  local seg rest=$1 list=$2
  while [ -n "$rest" ]; do
    seg=${rest%%/*}
    case " $list " in *" $seg "*) return 0 ;; esac
    case "$rest" in */*) rest=${rest#*/} ;; *) rest= ;; esac
  done
  return 1
}

# True for a file this check reads: root README/AGENTS, docs/**/*.md, or a README.md below the root.
is_target() {
  case "$1" in
    README.md | AGENTS.md) return 0 ;;
    docs/*.md) ;;
    */README.md) ;;
    *) return 1 ;;
  esac
  has_segment "${1%/*}" "$GENERATED $SKIPPED_DIRS" && return 1
  return 0
}

# Writes the NUL-separated list of candidate files to $workdir/files.
list_files() {
  if [ "$#" -gt 0 ]; then
    printf '%s\0' "$@" > "$workdir/files" || die "cannot write the file list"
  elif [ "$in_git" -eq 1 ]; then
    git ls-files -z --cached --others --exclude-standard > "$workdir/files" || die "git ls-files failed"
  else
    command -v find > /dev/null 2>&1 || die "missing tool: find"
    find . \( -name node_modules -o -name .git -o -name .venv -o -name dist -o -name build -o -name .next \) -prune -o -type f -name '*.md' -print0 > "$workdir/files" || die "find failed"
  fi
}

# Reads every Markdown file once and prints `file<TAB>line<TAB>kind<TAB>target` for each link, backticked path,
# README list or table row (as name tokens) and Contents heading outside code fences, indented code, comments and code spans.
# A trailing carriage return and blockquote markers are stripped from each line first, so every rule sees the same text.
# A link starting with a slash is a site route, not a repository path: it is never checked.
scan_all() {
  awk -v EXTS="$EXTS" '
    BEGIN {
      SQ = sprintf("%c", 39)
      BOM = "\357\273\277"
      OPAQUE = " mailto tel sms data javascript urn news magnet geo sip sips xmpp callto facetime skype bitcoin "
    }
    function emit(kind, t) {
      printf "%s\t%d\t%s\t%s\n", file, FNR, kind, t
    }
    function emit_link(t) {
      sub(/#.*$/, "", t)
      sub(/\?.*$/, "", t)
      if (t == "") return
      if (substr(t, 1, 1) == "/" || index(t, "\\") > 0 || has_scheme(t)) return
      emit("link", t)
    }
    function has_scheme(t,   name) {
      if (t ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) return 1
      if (t !~ /^[A-Za-z][A-Za-z0-9+.-]*:[^ ]/) return 0
      name = tolower(substr(t, 1, index(t, ":") - 1))
      return index(OPAQUE, " " name " ") > 0
    }
    function emit_span(t,   base, last, trail) {
      if (index(t, "/") == 0) return
      if (t ~ /[[:space:]<>*{}$|;&:"=?!,~]/ || index(t, SQ) > 0) return
      if (substr(t, 1, 1) == "/" || substr(t, 1, 4) == "http") return
      if (index(t, "...") > 0 || t ~ /^path\/to(\/|$)/) return
      base = t
      sub(/#.*$/, "", base)
      trail = (substr(t, length(t), 1) == "/")
      sub(/\/$/, "", base)
      if (base == "") return
      last = base
      sub(/^.*\//, "", last)
      if (trail || last ~ ("\\.(" EXTS ")$")) emit("span", t)
      else emit("softspan", t)
    }
    function emit_tokens(s,   n, parts, i, tok, out) {
      gsub(/\[/, " ", s)
      gsub(/\]/, " ", s)
      gsub(SQ, " ", s)
      gsub(/[ \t|`*(),;:<>"=\/\\#!?{}~]+/, " ", s)
      n = split(s, parts, " ")
      out = ""
      for (i = 1; i <= n; i++) {
        tok = parts[i]
        sub(/\.+$/, "", tok)
        if (tok != "") out = out tok " "
      }
      if (out != "") emit("tok", out)
    }
    function ticks(r,   out) {
      out = ""
      while (r-- > 0) out = out "`"
      return out
    }
    function split_spans(s,   n, seg, k, r, m, r2, j, out, content, found) {
      n = split(s, seg, "`")
      if (n == 1) return s
      out = seg[1]
      k = 1
      while (k < n) {
        r = 1
        while (k + r < n && seg[k + r] == "") r++
        found = 0
        m = k + r
        while (m < n) {
          r2 = 1
          while (m + r2 < n && seg[m + r2] == "") r2++
          if (r2 == r) { found = 1; break }
          m += r2
        }
        if (found) {
          if (r == 1) {
            content = ""
            for (j = k + r; j < m; j++) content = content seg[j] "`"
            emit_span(content seg[m])
          }
          out = out " " seg[m + r]
          k = m + r
        } else {
          out = out ticks(r) seg[k + r]
          k += r
        }
      }
      return out
    }
    function strip_comments(s,   out, i, n, run, j, m, found, e) {
      out = ""
      n = length(s)
      i = 1
      while (i <= n) {
        if (comment) {
          e = index(substr(s, i), "-->")
          if (e == 0) return out
          comment = 0
          i += e + 2
          continue
        }
        if (substr(s, i, 1) == "`") {
          run = 0
          while (substr(s, i + run, 1) == "`") run++
          j = i + run
          found = 0
          while (j <= n) {
            if (substr(s, j, 1) == "`") {
              m = 0
              while (substr(s, j + m, 1) == "`") m++
              if (m == run) { found = 1; break }
              j += m
            } else j++
          }
          if (found) { out = out substr(s, i, j + run - i); i = j + run }
          else { out = out substr(s, i, run); i += run }
          continue
        }
        if (substr(s, i, 4) == "<!--") { comment = 1; i += 4; continue }
        out = out substr(s, i, 1)
        i++
      }
      return out
    }
    function ref_def(s,   t, first, j) {
      if (s ~ /^[ \t]*\[\^/) return
      if (s !~ /^[ \t]*\[[^]]+\]:[ \t]*[^ \t]/) return
      t = s
      sub(/^[ \t]*\[[^]]+\]:[ \t]*/, "", t)
      if (substr(t, 1, 1) == "<") {
        j = index(t, ">")
        if (j == 0) return
        emit_link(substr(t, 2, j - 2))
        return
      }
      first = t
      sub(/[ \t].*$/, "", first)
      if (first !~ /\/|(^|[^.])\.[A-Za-z0-9]/) return
      emit_link(first)
    }
    function track(t,   i, m, c) {
      esc_end = 0
      m = length(t)
      for (i = 1; i <= m; i++) {
        c = substr(t, i, 1)
        if (c == "\\") {
          if (i == m) esc_end = 1
          i++
          prevc = substr(t, i, 1)
          continue
        }
        if (c == "[") {
          sp++
          wordpre[sp] = (prevc ~ /[A-Za-z0-9_]/)
        } else if (c == "]" && sp > 0) sp--
        prevc = c
      }
    }
    function parse_dest(part,   j, m, c, depth, t) {
      dest_ok = 0
      dest = ""
      rest = part
      if (substr(part, 1, 1) == "<") {
        j = index(part, ">")
        if (j == 0) return
        t = substr(part, 2, j - 2)
        m = index(substr(part, j + 1), ")")
        if (m == 0) return
        dest = t
        dest_ok = 1
        rest = substr(part, j + m + 1)
        return
      }
      depth = 0
      t = ""
      m = length(part)
      for (j = 1; j <= m; j++) {
        c = substr(part, j, 1)
        if (c == "(") depth++
        else if (c == ")") {
          if (depth == 0) { dest = t; dest_ok = 1; rest = substr(part, j + 1); return }
          depth--
        } else if (c == " " || c == "\t") {
          m = index(substr(part, j), ")")
          if (m == 0) return
          dest = t
          dest_ok = 1
          rest = substr(part, j + m)
          return
        }
        t = t c
      }
    }
    function scan_links(s,   n, parts, k, t, op_ok) {
      if (index(s, "](") == 0) return
      n = split(s, parts, "\\]\\(")
      sp = 0
      prevc = ""
      t = parts[1]
      for (k = 2; k <= n; k++) {
        track(t)
        if (sp > 0 && !esc_end) {
          op_ok = !wordpre[sp]
          sp--
          parse_dest(parts[k])
          if (op_ok && dest_ok && dest != "") emit_link(dest)
          t = rest
          prevc = ")"
        } else {
          t = parts[k]
          prevc = "("
        }
      }
    }
    FNR == 1 {
      file = FILENAME
      sub(/^\.\//, "", file)
      isreadme = (file == "README.md" || file ~ /\/README\.md$/)
      fence = 0
      comment = 0
      prevblank = 1
      prevhead = 0
      inlist = 0
      incode = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (FNR == 1 && index(line, BOM) == 1) line = substr(line, length(BOM) + 1)
      while (match(line, /^[ \t]*>[ \t]?/)) line = substr(line, RLENGTH + 1)
      wasblank = prevblank || prevhead
      prevblank = (line ~ /^[ \t]*$/)
      if (!fence) {
        prevhead = (line ~ /^( |  |   )?#+([ \t]|$)/)
        if (!prevblank) {
          indented = (line ~ /^(    |\t)/)
          if (indented && !inlist && (wasblank || incode)) { incode = 1; next }
          incode = 0
          if (!indented) inlist = (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/)
        }
        if (match(line, /^[ \t]*(```+|~~~+)/)) {
          run = substr(line, RSTART, RLENGTH)
          sub(/^[ \t]+/, "", run)
          fchar = substr(run, 1, 1)
          if (!(fchar == "`" && index(substr(line, RSTART + RLENGTH), "`") > 0)) {
            flen = length(run)
            fence = 1
            next
          }
        }
      } else {
        t = line
        sub(/^[ \t]+/, "", t)
        sub(/[ \t]+$/, "", t)
        if (t ~ /^(```+|~~~+)$/ && substr(t, 1, 1) == fchar && length(t) >= flen) fence = 0
        next
      }
      if (comment || index(line, "<!--") > 0) line = strip_comments(line)
      if (isreadme && tolower(line) ~ /^#+[ \t]+contents[ \t]*$/) emit("heading", "")
      ref_def(line)
      if (isreadme && (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ || line ~ /^[ \t]*\|/)) emit_tokens(line)
      scan_links(split_spans(line))
    }
  ' "$@"
}

# Records a finding. chk is a project-relative path to test against the git ignore rules, or empty when the finding is final.
report() {
  FINDINGS[nfind]="$1:$2: $3"
  F_CHK[nfind]=${4:-}
  nfind=$((nfind + 1))
}

# Records a missing path unless it sits in a generated folder; a path leaving the project is never git-ignore tested.
miss() {
  local chk=$4
  if [ -n "$chk" ]; then
    has_segment "$chk" "$GENERATED" && return 0
    case "$chk" in ../* | */../* | .. | */..) chk= ;; esac
  fi
  report "$1" "$2" "$3" "$chk"
}

# True when the target exists relative to the file's folder.
exists_as() {
  local file=$1 target=$2 dir
  dir=${file%/*}
  [ "$dir" = "$file" ] && dir=.
  [ -e "$dir/$target" ]
}

# Sets REPLY to the string with every %XX sequence decoded; a % without two hex digits after it stays as written.
decode_percent() {
  local s=$1 pre rest hex ch out=
  REPLY=$s
  case "$s" in *%*) ;; *) return 0 ;; esac
  while :; do
    case "$s" in
      *%[0-9A-Fa-f][0-9A-Fa-f]*) ;;
      *) break ;;
    esac
    pre=${s%%%[0-9A-Fa-f][0-9A-Fa-f]*}
    rest=${s#"$pre"}
    hex=${rest:1:2}
    printf -v ch '%b' "\\x$hex"
    out=$out$pre$ch
    s=${rest:3}
  done
  REPLY=$out$s
}

# Checks one link target that is already stripped of fragment and query; web links never reach it.
check_link() {
  local file=$1 ln=$2 t chk dir
  decode_percent "$3"
  t=$REPLY
  [ -n "$t" ] || return 0
  exists_as "$file" "$t" && return 0
  dir=${file%/*}
  if [ "$dir" = "$file" ]; then chk=$t; else chk=$dir/$t; fi
  miss "$file" "$ln" "broken link: $t" "$chk"
}

# Checks one backticked repo path. A soft span has no known extension or trailing slash: it counts only when its
# first segment exists, and it passes when a folder of that name or a file with that stem exists.
check_span() {
  local file=$1 ln=$2 t=$3 soft=$4 base dir g
  base=${t%%#*}
  base=${base%/}
  dir=${file%/*}
  [ "$dir" = "$file" ] && dir=.
  if [ "$soft" -eq 1 ]; then
    [ -e "${base%%/*}" ] || return 0
    for g in "$base".* "$dir/$base".*; do
      [ -e "$g" ] && return 0
    done
  fi
  [ -e "$base" ] && return 0
  exists_as "$file" "$base" && return 0
  miss "$file" "$ln" "path does not exist: $t" "$base"
}

# Flags a README whose list items or table rows name every child of its own folder, however the name is marked up
# (link, backticks, bold or plain). Only folders with at least 3 files, or at least 3 subfolders, are checked.
check_listing() {
  local file=$1 toks=$2 dir p name nf=0 nd=0 allf=1 alld=1
  dir=${file%/*}
  [ "$dir" = "$file" ] && dir=.
  for p in "$dir"/*; do
    [ -e "$p" ] || continue
    name=${p##*/}
    if [ -d "$p" ]; then
      case " $GENERATED " in *" $name "*) continue ;; esac
      nd=$((nd + 1))
      case "$toks" in *" $name "*) ;; *) alld=0 ;; esac
    else
      [ "$name" = README.md ] && continue
      nf=$((nf + 1))
      case "$toks" in *" $name "*) ;; *) allf=0 ;; esac
    fi
  done
  if [ "$nf" -ge 3 ] && [ "$allf" -eq 1 ]; then
    report "$file" 1 "README lists every file of its folder; describe the module, not its files"
  elif [ "$nd" -ge 3 ] && [ "$alld" -eq 1 ]; then
    report "$file" 1 "README lists every subfolder of its folder; describe the module, not its layout"
  fi
}

# Drops findings whose path git ignores, with one git call for all of them.
filter_ignored() {
  local i=0 any=0 p rc first ign=$'\n'
  [ "$in_git" -eq 1 ] || return 0
  while [ "$i" -lt "$nfind" ]; do
    if [ -n "${F_CHK[i]}" ]; then
      any=1
      printf '%s\0' "${F_CHK[i]}"
    fi
    i=$((i + 1))
  done > "$workdir/in"
  [ "$any" -eq 1 ] || return 0
  git check-ignore -z --stdin < "$workdir/in" > "$workdir/out" 2> "$workdir/err"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    first=
    read -r first < "$workdir/err"
    die "git check-ignore failed: ${first:-exit $rc}"
  fi
  while IFS= read -r -d '' p; do
    ign=$ign$p$'\n'
  done < "$workdir/out"
  i=0
  while [ "$i" -lt "$nfind" ]; do
    if [ -n "${F_CHK[i]}" ]; then
      case "$ign" in *$'\n'"${F_CHK[i]}"$'\n'*) FINDINGS[i]= ;; esac
    fi
    i=$((i + 1))
  done
}

explicit=$#
list_files "$@"

targets=()
ntargets=0
while IFS= read -r -d '' f; do
  f=${f#./}
  [ -n "$f" ] || continue
  if [ ! -e "$f" ]; then
    [ "$explicit" -eq 0 ] || die "no such file: $f"
    continue
  fi
  is_target "$f" || continue
  [ -f "$f" ] || continue
  [ -r "$f" ] || die "cannot read $f"
  targets[ntargets]=./$f
  ntargets=$((ntargets + 1))
done < "$workdir/files"

if [ "$ntargets" -gt 0 ]; then
  scan_all "${targets[@]}" > "$workdir/cands" || die "cannot read the Markdown files (awk failed)"
  cur=
  toks=" "
  while IFS=$'\t' read -r file ln kind target; do
    if [ "$file" != "$cur" ]; then
      [ -z "$cur" ] || check_listing "$cur" "$toks"
      cur=$file
      toks=" "
    fi
    case "$kind" in
      link) check_link "$file" "$ln" "$target" ;;
      span) check_span "$file" "$ln" "$target" 0 ;;
      softspan) check_span "$file" "$ln" "$target" 1 ;;
      heading) report "$file" "$ln" "README has a Contents heading; a README must not list its folder" ;;
      tok) toks=$toks$target ;;
    esac
  done < "$workdir/cands"
  [ -z "$cur" ] || check_listing "$cur" "$toks"
fi

filter_ignored

total=0
i=0
while [ "$i" -lt "$nfind" ]; do
  [ -z "${FINDINGS[i]}" ] || total=$((total + 1))
  i=$((i + 1))
done
[ "$total" -gt 0 ] || exit 0

limit=$total
[ "$total" -le "$CAP" ] || limit=$((CAP - 1))
shown=0
i=0
while [ "$i" -lt "$nfind" ] && [ "$shown" -lt "$limit" ]; do
  if [ -n "${FINDINGS[i]}" ]; then
    printf '%s\n' "${FINDINGS[i]}"
    shown=$((shown + 1))
  fi
  i=$((i + 1))
done
[ "$total" -le "$CAP" ] || printf 'check-docs: %s more findings not shown\n' $((total - CAP + 1))
exit 1
