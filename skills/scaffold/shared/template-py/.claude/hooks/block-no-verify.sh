#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
# Best-effort tripwire, not a security boundary; the lefthook + CI layers are the backstop.
# Closed list of what this text guard cannot see: variable indirection and command substitution (cat "$f", cat $(echo .env)),
# strings built at run time inside an interpreter ('.e'+'nv', base64 decoded in Python), a script file written first and run second,
# code fed to an interpreter on stdin or from a heredoc (python3 <<EOF, node - <<EOF), argument shapes where the word after git is not the
# subcommand (os.execvp('git', [...]), ['git'] + [...], Deno {args: [...]}, sh.git.commit(...)), file-by-file removal (os.remove loops,
# Path.rmdir, os.removedirs), a secret name with no leading dot or slash inside inline code when the file does not exist, a shell reached
# through a program not known as a wrapper ($SHELL, ssh host sh, docker exec -i c sh, kubectl exec), a command built at run time from a file or
# variable (sh ./x.sh, sh -c "$CMD"), an alias or shell function defined earlier, a binary that calls git itself, edits made outside the agent, runners other than the listed interpreters (npx tsx -e), and a removal target built by a call (path.join(root, 'src')) or an aliased import (from shutil import rmtree as r).
# Everything else on the list below is judged. An unreadable shape (xargs handing a placeholder to sh -c) with a forbidden token anywhere in the command is blocked.
# Shells judged: sh bash zsh dash ksh ash busybox sh. Wrappers judged: sudo doas env nice ionice nohup setsid time timeout stdbuf xargs command exec builtin, alone or stacked; quoted and backslash-escaped tokens count as written.
# A shell in command position that the guard sees fed from a pipe, here-string, heredoc, `-s` or process substitution is blocked outright
# (even `echo hi | sh`), also behind the wrappers sudo, command, exec, nohup, time, nice, builtin, env, timeout, stdbuf, xargs and uv/poetry/pipenv/pdm run,
# a leading FOO=1, ( ) or { }, and with a trailing redirect or comment. xargs sh script passes (the shell gets arguments); xargs sh -c with no readable string is blocked.
# Inline code for python/node/perl/ruby/deno/bun (-c, -e, -p, --eval, eval) is scanned as text with the same checks as a shell command,
# so python3 -c "print('rm -rf src')" and shutil.rmtree('./node_modules') are blocked by design.
# Fallback only: hooks may be spawned from the session's original root, not a worktree.
orig_dir=$PWD
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: block-no-verify.sh cannot cd to the project root — refusing the command." >&2; exit 2; }
input=$(cat)
# One interpreter call yields the cwd (first line) and the command; a missing or failing interpreter blocks instead of passing.
parsed=$(printf '%s' "$input" | python3 -I -c "import json,sys
try: o=json.load(sys.stdin)
except Exception: o={}
o=o if isinstance(o,dict) else {}
t=o.get('tool_input')
t=t if isinstance(t,dict) else {}
sys.stdout.write(str(o.get('cwd') or '').replace('\\r','').replace('\\n','')+'\\n'+str(t.get('command') or ''))" 2>/dev/null) || { echo "BLOCKED: block-no-verify.sh needs python3 to read the hook input and python3 is missing or failed — refusing the command." >&2; exit 2; }
in_cwd=${parsed%%$'\n'*}
cmd=${parsed#*$'\n'}
[ -n "$in_cwd" ] && orig_dir=$in_cwd
[ -z "$cmd" ] && exit 0
# Drop heredoc bodies so commit-message text is not scanned as a command; the opening line is still scanned. Text without << has none, so awk is skipped.
case $cmd in *'<<'*) cmd=$(printf '%s\n' "$cmd" | awk '
  inh { t = $0; if (tabs) sub(/^\t+/, "", t); if (t == w) inh = 0; next }
  { print; l = $0; gsub(/<<</, "", l)
    if (match(l, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      w = substr(l, RSTART, RLENGTH); tabs = (w ~ /^<<-/); sub(/^<<-?[[:space:]]*["\047]?/, "", w); inh = 1 } }') ;;
esac
# A backslash-newline continues the command line, so a flag on the next line is part of it.
cmd=${cmd//\\$'\n'/}
# cut200 <text>: at most 200 bytes, never inside a UTF-8 sequence, in any locale and with any awk (same ucut as every other hook cap).
cut200() { S=$1 LC_ALL=C awk 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } BEGIN { printf "%s", ucut(ENVIRON["S"], 200) }' || printf 'BLOCKED'; }
# block <message>: message capped at 200 bytes.
block() { echo "$(cut200 "BLOCKED: $1")" >&2; exit 2; }
# rx <ere> <text>: grep -qE on one line without a fork; text with a newline still goes through grep, which matches per line.
rx() { case $2 in *$'\n'*) printf '%s\n' "$2" | grep -qE -- "$1" ;; *) [[ $2 =~ $1 ]] ;; esac; }
# words <text>: splits on blanks into the array tw through a pipe, not a here-string, whose temp file can fail to open and read as empty.
words() { read -ra tw < <(printf '%s\n' "$1"); }
protected='main|uat|develop'
root=$PWD
# Shell access to secret files: Read deny rules gate the Read tool, not cat. A read is blocked when the named file exists; a write or copy that would create one is blocked outright. Env templates stay usable.
is_secret() {
  local lc
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "${lc##*/}" in
    .env.example|.env.default|.env.sample|.env.template) return 1 ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|credentials.json|.netrc) return 0 ;;
  esac
  case "$lc" in secrets|*/secrets|.secrets|*/.secrets|secrets/*|*/secrets/*|.secrets/*|*/.secrets/*) return 0 ;; esac
  return 1
}
secret_block() { block "shell access to secret file '$1' is not allowed. Never read or write it; use .env.example for placeholders and ask the user for real values."; }
writes_to_secret() {
  local t=$1 q
  for q in "" "\"" "'"; do
    case "$flat" in
      *">$q$t"*|*"> $q$t"*|*"tee $q$t"*|*"tee -a $q$t"*) return 0 ;;
    esac
  done
  [[ "$flat" =~ (^|[[:space:]])(cp|mv|ln|install|touch)[[:space:]].*[[:space:]\"\']${t}[\"\']?[[:space:]]*($|[;\&\|]) ]]
}
secret_guard() {
  local delim tokens tok d f p b cdt tok_d hits
  local -a sdirs
  flat="${cmd//\\/}"
  flat="${flat//[\"\']/}"
  delim="[:space:]\"'\`;|&<>()="
  tokens=$(printf '%s' "$flat" | grep -oiE "[^$delim]*(\\.env|\\.pem|\\.key|\\.p12|\\.pfx|credentials\\.json|\\.netrc|secrets|[*?[])[^$delim]*" || true)
  [ -n "$tokens" ] || return 0
  sdirs=("$root")
  [ "$orig_dir" != "$root" ] && sdirs+=("$orig_dir")
  while IFS= read -r cdt; do
    cdt="${cdt##*[[:space:]]}"; cdt="${cdt//[\"\']/}"; cdt="${cdt/#\~/$HOME}"
    for b in "$root" "$orig_dir"; do
      case "$cdt" in /*) p="$cdt" ;; *) p="$b/$cdt" ;; esac
      [ -d "$p" ] && sdirs+=("$p")
    done
  done < <(printf '%s\n' "$flat" | grep -oE '(^|[;&|(]|[[:space:]])cd[[:space:]]+[^;&|()[:space:]]+' || true)
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    tok="${tok/#\~/$HOME}"
    tok="${tok//\$\{HOME\}/$HOME}"
    tok="${tok//\$HOME/$HOME}"
    for d in "${sdirs[@]}"; do
      tok_d="${tok//\$\{PWD\}/$d}"
      tok_d="${tok_d//\$PWD/$d}"
      hits=$(cd "$d" 2>/dev/null && compgen -G "$tok_d")
      while IFS= read -r f; do
        [ -n "$f" ] && is_secret "$f" && secret_block "$f"
      done < <(printf '%s\n' "$hits")
    done
    if [[ "$tok" != *[*?[]* ]] && is_secret "$tok" && writes_to_secret "$tok"; then secret_block "$tok"; fi
    if [[ "$tok" == *:* ]] && is_secret "${tok#*:}" && [[ "$flat" =~ (^|[[:space:]\;\&\|\(])git[[:space:]]+([^;&|]*[[:space:]])?(show|cat-file|archive|blame|grep|log|diff)[[:space:]] ]]; then secret_block "${tok#*:}"; fi
  done < <(printf '%s\n' "$tokens")
}
secret_guard
# Directories a bare commit/push may land on: the cwd plus literal cd targets; anything unresolved adds the project root.
cand=("$orig_dir")
redir=0
unresolved() { [[ -z "$1" || "$1" == - || "$1" == Q || "$1" == *[\$\`~]* ]]; }
add_target() {
  local d=$1 c n=0
  local -a new=()
  # With CDPATH set, a bare relative name may resolve through it rather than through a candidate.
  if unresolved "$d" || { [ -n "${CDPATH:-}" ] && [[ "$d" != /* && "$d" != . && "$d" != .. && "$d" != ./* && "$d" != ../* ]]; }; then
    redir=1; return
  fi
  for c in "${cand[@]}"; do
    if [[ "$d" == /* ]]; then c=$d; else c="$c/$d"; fi
    [ -d "$c" ] || continue
    n=1
    c=$(cd "$c" 2>/dev/null && pwd -P) || continue
    # Already a candidate: nothing new, so the repeat passes settle.
    [[ " ${cand[*]} ${new[*]} " == *" $c "* ]] || new+=("$c")
  done
  if [ "$n" -eq 1 ]; then cand+=("${new[@]}"); else redir=1; fi
}
# Prints the first protected branch a bare commit/push may land on, or nothing.
protected_branch() {
  local d b found=0 cd_ok=0
  local -a dirs=("${cand[@]}")
  [ "$redir" -eq 1 ] && dirs+=("$root")
  if [ -n "$cdir" ]; then
    if unresolved "$cdir"; then dirs+=("$root"); else cd_ok=1; fi
  fi
  for d in "${dirs[@]}"; do
    if [ "$cd_ok" -eq 1 ]; then
      if [[ "$cdir" == /* ]]; then d=$cdir; else d="$d/$cdir"; fi
    fi
    b=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
    found=1
    [[ "$b" =~ ^($protected)$ ]] && { echo "$b"; return; }
  done
  [ "$found" -eq 1 ] && return
  # No candidate is inside a git repo: judge the project root, as before.
  if [ "$cd_ok" -eq 1 ]; then b=$(git -C "$cdir" rev-parse --abbrev-ref HEAD 2>/dev/null); else b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); fi
  [[ "$b" =~ ^($protected)$ ]] && echo "$b"
}

# Empty quote pairs glued to a word vanish in the shell (--no-ver""ify, -""n), so they go first; a lone empty argument stays; then bash -c/eval is unwrapped for every POSIX-style shell on the allow-list, single words are unquoted, mask other quoted text as Q; double quotes first so an apostrophe cannot swallow flags.
# A quoted word holding a shell operator stays masked: its pipe, semicolon or redirect is text, not syntax ('x|sh', "a|bash").
sq="'"
scan=$(printf '%s' "$cmd" | sed -E \
  -e "s/([^[:space:]])\"\"/\1/g" -e "s/\"\"([^[:space:]])/\1/g" -e "s/([^[:space:]])${sq}${sq}/\1/g" -e "s/${sq}${sq}([^[:space:]])/\1/g" \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|dash|ksh|ash|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+\"([^\"]*)\"/\1 \4 /g" \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|dash|ksh|ash|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+${sq}([^${sq}]*)${sq}/\1 \4 /g" \
  -e "s/\"([^\"${sq}[:space:]|;\&<>()]+)\"/\1/g" -e "s/\"[^\"]*\"/ Q /g" \
  -e "s/${sq}([^${sq}[:space:]|;\&<>()]+)${sq}/\1/g" -e "s/${sq}[^${sq}]*${sq}/ Q /g" \
  -e 's/\\([A-Za-z0-9_.-])/\1/g')

# Command position: line start, after ; & | ( { or a backtick, or after then/do/else; wrappers that run the next word (sudo, env, xargs, nohup, uv run) may follow.
cpos='(^|[;&|(`{]|(^|[[:space:]])(then|do|else))[[:space:]]*'
# Wrapper tokens, defined once. Leading assignments (FOO=1 cmd) may precede a wrapper chain; a wrapper takes flags, a value after a known value flag (sudo -u root, nice -n 5, xargs -I {}, uv run --with x), a duration (timeout 5) or an assignment.
asg='[A-Za-z_][A-Za-z0-9_]*=([[:space:]]+Q)?[^[:space:]]*'
wnames='sudo|doas|command|exec|nohup|time|nice|ionice|setsid|builtin|env|timeout|stdbuf|(uv|poetry|pipenv|pdm)[[:space:]]+run'
wargs="([[:space:]]+(-[^[:space:]]+|-[uginIPLdsCkUDtEaoe][[:space:]]+[^-[:space:]][^[:space:]]*|--[A-Za-z-]+[[:space:]]+[^-[:space:]][^[:space:]]*|${asg}|[0-9][0-9.]*[smhd]?))*"
wrap_nx="(${asg}[[:space:]]+)*((/[^[:space:]]*/)?(${wnames})${wargs}[[:space:]]+)*"
wrap="(${asg}[[:space:]]+)*((/[^[:space:]]*/)?(${wnames}|xargs)${wargs}[[:space:]]+)*"
# Shells fed from a pipe, stdin, here-string, heredoc or process substitution hide their commands from this guard; the shell must be the command word, not an argument (grep sh < f).
# Runs on the scan, where quoted text cannot contribute operators; a trailing backslash or pipe joins the next line. Behind a pipe the shell may be followed by flags, redirects or a comment; xargs hands the shell its arguments, not stdin, so only xargs sh -c with no readable string is judged.
blind_shell() {
  local w='\\?(/[^[:space:]]*/)?(bash|sh|zsh|dash|ksh|ash|busybox[[:space:]]+sh)' f='([[:space:]]+-[^[:space:]]+)*' joined tl xa
  tl='([[:space:]]+#.*|[[:space:]]*([0-9]*>>?[[:space:]]*[^[:space:]]*|[0-9]*>&[0-9-]*|&>[^[:space:]]*))*[[:space:]]*($|[;&|)}])'
  xa="(/[^[:space:]]*/)?xargs${wargs}[[:space:]]+"
  # Only a newline or a trailing backslash changes the text; the awk is skipped for a plain single line.
  case $scan in
    *$'\n'*|*\\) joined=$(printf '%s\n' "$scan" | awk '{ if (buf != "") $0 = buf " " $0; if ($0 ~ /\\$/) { sub(/\\$/, ""); buf = $0; next } if ($0 ~ /\|[ \t]*$/) { buf = $0; next } print; buf = "" } END { if (buf != "") print buf }') ;;
    *) joined=$scan ;;
  esac
  rx "\\|[[:space:]]*([({][[:space:]]*)?${wrap_nx}${w}${f}${tl}" "$joined" ||
    rx "\\|[[:space:]]*([({][[:space:]]*)?${wrap_nx}${xa}${w}${f}[[:space:]]+-[A-Za-z]*c${tl}" "$joined" ||
    rx "${cpos}${wrap}${w}${f}[[:space:]]*<" "$joined" ||
    rx "${cpos}${wrap}${w}${f}[[:space:]]+(-[A-Za-z]*s[A-Za-z]*|-)([[:space:]]|\$)" "$joined" ||
    rx "${cpos}(source|\\.)[[:space:]]+<\\(" "$joined"
}
if blind_shell; then
  block "a shell fed from a pipe, stdin, here-string, heredoc or process substitution hides its commands from this guard. Run the commands directly."
fi
# A shell or interpreter reached through xargs runs text this guard cannot see (xargs -I{} sh -c '{}'); with a forbidden token anywhere in the command that shape is blocked.
norm=$(printf '%s' "$cmd" | tr -d "\\\\\"'" | tr '[:upper:]' '[:lower:]')
if [[ "$norm" =~ (^|[^a-z0-9_-])xargs([[:space:]]|$) ]] \
  && [[ "$norm" =~ (^|[^a-z0-9_-])(bash|sh|zsh|dash|ksh|ash|eval|python[0-9.]*|node|perl|ruby)[[:space:]]+-[a-z]*[cep]([[:space:]]|$) ]] \
  && rx 'no-veri|hookspath|lefthook(_exclude)?=|git[[:space:]]+([^;&|]*[[:space:]])?(commit|push)[^;&|]*[[:space:]]-[a-z]*n' "$norm"; then
  block "xargs hands text to a shell or interpreter this guard cannot read, and the command names a hook bypass (--no-verify, -n, core.hooksPath, LEFTHOOK). Run the git command directly."
fi
# Inline interpreter code is judged as text: the interpreter must be in command position, so a commit message or grep pattern naming python -c is not code; then quotes and brackets become spaces and the checks below treat it as a command line.
interp=""
interp_norm=""
scan_shell=$scan
inline_re="${cpos}${wrap}(/[^[:space:]]*/)?((python|pypy)[0-9.]*|nodejs|node|bun|perl|ruby|deno)[[:space:]]+(-([A-Za-ln-z]|-)[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*(-[A-Za-z]*[ceEp]|--eval|--print|eval)([[:space:]=]|\$)"
# The scan unwraps eval "…", so a match on the raw command is the fallback (deno eval "…").
if [[ "$scan" =~ $inline_re ]] || [[ "$cmd" =~ $inline_re ]]; then
  interp=${cmd#*"${BASH_REMATCH[0]}"}
  interp_norm=$(printf '%s' "$interp" | sed "s/[]\"${sq}[{}(),]/ /g")
  scan="$scan"$'\n'"$interp_norm"
fi
# A secret-file name in inline code is blocked even when the file does not exist yet (open('.env', 'w')); URLs, bare module and attribute names stay clean.
interp_secret() {
  local tok b
  while IFS= read -r tok; do
    tok="${tok#./}"; b="${tok##*/}"
    case "$b" in ''|.key|.pem|.p12|.pfx) continue ;; esac
    [[ "$b" == .* || "$tok" == */* || "$b" == credentials.json ]] || continue
    is_secret "$tok" && secret_block "$tok"
  done < <(printf '%s' "$interp" | sed -E "s#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]\"${sq})]*# #g" | LC_ALL=C tr -c 'A-Za-z0-9._/~-' '\n')
}
[ -n "$interp" ] && interp_secret

# Hook-layer bypass via environment or a persisted alias/config (whole-command checks).
lower_cmd=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
lh='(^|[^A-Za-z0-9_])LEFTHOOK(_EXCLUDE)?'
if { rx "${lh}=" "$scan" || rx "$lh" "$interp"; } && rx '(^|[^A-Za-z0-9_-])git([[:space:]]|$)' "$scan"; then
  block "LEFTHOOK=0 / LEFTHOOK_EXCLUDE disables the pre-commit hook layer — the same bypass as --no-verify. Fix the failure instead."
fi
if rx 'git_config_(parameters|key_[0-9]+)' "$lower_cmd" && rx 'hookspath' "$lower_cmd"; then
  block "GIT_CONFIG_* overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
fi
if rx 'alias\.' "$lower_cmd" && rx 'no-verify' "$lower_cmd"; then
  block "a git alias wrapping --no-verify is the same bypass as --no-verify. Fix the failure instead."
fi

# Evaluate each simple command separately: split on && || ; | & ( ) ` and newlines.
segments=$(printf '%s\n' "$scan" | tr ';|&()`' '\n\n\n\n\n\n')
# Collect every cd before judging a git word, since a loop or function can cd after it; repeat until the candidates stop growing.
collect_dirs() {
  local seg p q w d n i
  local -a t
  while IFS= read -r seg; do
    words "$seg"
    n=${#tw[@]}; i=0
    while [ "$i" -lt "$n" ]; do
      w="${tw[$i]#\\}"
      [[ "$w" == git || "$w" == */git ]] && break
      i=$((i + 1))
    done
    for ((p = 0; p < i; p++)); do
      w="${tw[$p]#\\}"
      case "$w" in
        cd|pushd)
          d=""
          for ((q = p + 1; q < i; q++)); do [[ "${tw[$q]}" == -?* ]] && continue; d=${tw[$q]}; break; done
          add_target "$d" ;;
        popd|eval|source|function|CDPATH=*|GIT_DIR=*|GIT_WORK_TREE=*) redir=1 ;;
        # `.` sources a script only in command position; elsewhere it is an ordinary argument (`ls .`).
        .) [[ "$p" -eq 0 || "${tw[$((p - 1))]}" =~ ^(then|do|else|if|while|until|!|[{]|time|command|builtin|exec)$ ]] && redir=1 ;;
        env|sudo)
          for ((q = p + 1; q < i; q++)); do
            case "${tw[$q]}" in
              -C|-D|--chdir) add_target "${tw[$((q + 1))]:-}" ;;
              --chdir=*) add_target "${tw[$q]#--chdir=}" ;;
              -C?*|-D?*) add_target "${tw[$q]:2}" ;;
            esac
          done ;;
      esac
    done
  done < <(printf '%s\n' "$segments")
}
# `name() { … }` defines a function whose body may cd where this check cannot follow.
rx '(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*\(\)' "$scan" && redir=1
settled=0
for _ in 1 2 3 4; do
  before=${#cand[@]}
  collect_dirs
  [ "${#cand[@]}" -eq "$before" ] && { settled=1; break; }
done
# Still growing at the cap: judge the project root too.
[ "$settled" -eq 1 ] || redir=1
# In a strict && chain each git runs only after every earlier cd succeeded, so judge exactly those directories, not the whole set.
chain_dirs() {
  local chk seg w d cur first sawgit=0
  local -a t out=()
  chk=$(printf '%s' "$scan" | sed -E 's/[0-9]*>&[0-9-]*//g; s/&>>?//g; s/&&/ /g')
  [[ "$chk" == *[\;\|\&\(\)\`]* || "$chk" == *$'\n'* ]] && return 1
  cur=$orig_dir
  while IFS= read -r seg; do
    words "$seg"
    [ "${#tw[@]}" -eq 0 ] && continue
    first="${tw[0]#\\}"
    if [[ "$first" == cd || "$first" == pushd ]]; then
      d=""
      for w in "${tw[@]:1}"; do [[ "$w" == -?* ]] && continue; d=$w; break; done
      unresolved "$d" && return 1
      [[ "$d" == /* ]] || d="$cur/$d"
      cur=$(cd "$d" 2>/dev/null && pwd -P) || return 1
      continue
    fi
    for w in "${tw[@]}"; do
      case "${w#\\}" in cd|pushd|popd|env|sudo|command|builtin|exec) return 1 ;; esac
    done
    if [[ "$first" == git || "$first" == */git ]]; then
      sawgit=1
      [[ " ${out[*]} " == *" $cur "* ]] || out+=("$cur")
    else
      for w in "${tw[@]}"; do [[ "${w#\\}" == git || "${w#\\}" == */git ]] && return 1; done
    fi
  done < <(printf '%s\n' "${scan//&&/$'\n'}")
  [ "$sawgit" -eq 1 ] || return 1
  printf '%s\n' "${out[@]}"
}
if [ "$redir" -eq 0 ] && chain_out=$(chain_dirs); then
  cand=()
  while IFS= read -r d; do cand+=("$d"); done < <(printf '%s\n' "$chain_out")
fi
while IFS= read -r seg; do
  words "$seg"
  n=${#tw[@]}; i=0
  while [ "$i" -lt "$n" ]; do
    w="${tw[$i]#\\}"
    [[ "$w" == git || "$w" == */git ]] && break
    i=$((i + 1))
  done
  [ "$i" -ge "$n" ] && continue
  i=$((i + 1)); cdir=""
  while [ "$i" -lt "$n" ] && [[ "${tw[$i]}" == -* ]]; do
    o="${tw[$i]}"
    case "$o" in
      -C)
        # git applies every -C in turn, each relative to the one before.
        x="${tw[$((i + 1))]:-}"
        if [ -z "$cdir" ] || [[ "$x" == /* ]]; then cdir=$x; else cdir="$cdir/$x"; fi
        i=$((i + 2)); continue ;;
      -c|--config-env)
        printf '%s' "${tw[$((i + 1))]:-}" | grep -qi 'core\.hookspath' && block "'git -c core.hooksPath=…' disables the git-hook layer, the same bypass as --no-verify. Fix the failure instead."
        i=$((i + 2)); continue ;;
      --git-dir|--work-tree) redir=1; i=$((i + 2)); continue ;;
      --git-dir=*|--work-tree=*) redir=1 ;;
      --namespace|--exec-path|--super-prefix) i=$((i + 2)); continue ;;
    esac
    printf '%s' "$o" | grep -qi 'core\.hookspath' && block "overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
    i=$((i + 1))
  done
  sub="${tw[$i]:-}"; i=$((i + 1))
  args=("${tw[@]:$i}")

  case "$sub" in
    commit|push|merge|am|rebase|cherry-pick|revert|pull)
      for a in "${args[@]}"; do
        [ "$a" = "--" ] && break
        [[ "$a" == --no-veri* ]] && block "--no-verify on 'git $sub' bypasses the git hooks. Fix the failure instead."
      done ;;
  esac

  case "$sub" in
    commit)
      skip=0
      for a in "${args[@]}"; do
        [ "$a" = "--" ] && break
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$a" in
          --*) ;;
          -?*)
            f="${a#-}"
            while [ -n "$f" ]; do
              c="${f:0:1}"; f="${f:1}"
              case "$c" in
                n) block "-n (--no-verify) on git commit bypasses the pre-commit hooks. Fix the failure instead." ;;
                m|F|c|C|t|S|u) [ -z "$f" ] && [ "$c" != "S" ] && [ "$c" != "u" ] && skip=1; break ;;
              esac
            done ;;
        esac
      done
      branch=$(protected_branch)
      if [ -n "$branch" ]; then
        if rx 'git[[:space:]]+(checkout[[:space:]]+(-[bB]|--orphan)|switch[[:space:]]+(-[cC]|--create))' "$scan"; then
          block "commit chained after a branch switch while '$branch' is checked out. Run 'git checkout -b <name>' alone first, then run 'git commit' as a separate command."
        fi
        block "direct commit to protected branch '$branch'. Run 'git checkout -b <feature-branch>' first, then commit again."
      fi
      ;;
    push)
      force=0; target=0; explicit=0; pos=0
      for a in "${args[@]}"; do
        case "$a" in
          --force|--force=*|--force-with-lease|--force-with-lease=*|--force-if-includes|--mirror) force=1 ;;
          --delete) force=1 ;;
          --*) ;;
          -*) [[ "${a#-}" == *[fd]* ]] && force=1 ;;
          *)
            pos=$((pos + 1))
            [ "$pos" -eq 1 ] && continue
            explicit=1
            [[ "$a" == +* || "$a" == :* ]] && force=1
            [[ "$a" =~ ^\+?((refs/heads/)?($protected)|[^:]*:(refs/heads/)?($protected))$ ]] && target=1
            # `HEAD` / `@` (no `:dst`) pushes the current branch to its same-named remote branch
            if [[ "$a" =~ ^\+?(HEAD|@)$ ]]; then [ -n "$(protected_branch)" ] && target=1; fi ;;
        esac
      done
      if [ "$explicit" -eq 0 ]; then
        [ -n "$(protected_branch)" ] && target=1
      fi
      [ "$force" -eq 1 ] && [ "$target" -eq 1 ] && block "force-push/delete on a protected branch (--force, -f, +refspec, HEAD:main). Open a PR instead."
      ;;
    config)
      if printf '%s ' "${args[@]}" | grep -qi 'core\.hookspath' && ! printf ' %s ' "${args[@]}" | grep -qE ' (--get|--get-all|--get-regexp|get|-l|--list) '; then
        block "'git config core.hooksPath' re-points or disables the git-hook layer. Confirm with a human first."
      fi ;;
    checkout|restore)
      if printf ' %s' "${args[@]}" | grep -qE '[[:space:]](\./)?(\.claude/|\.claude([[:space:]]|$)|\.lefthook/|\.github/|lefthook\.yml|\.gitleaks\.toml|AGENTS\.md|CLAUDE\.md|docs/CONSTITUTION\.md)'; then
        block "'git checkout/restore' on a guard-layer file discards enforcement config. Confirm with a human first."
      fi ;;
  esac
done < <(printf '%s\n' "$segments")

# Guarded source directories, defined once for the rm check and the interpreter removal check.
srcnames='src|app|lib|test|\.claude|\.lefthook|\.git|node_modules'
srcdirs="(^|[[:space:]/\"])(${srcnames})([[:space:]/\"]|\$)"
# rm_src <text>: rm -rf on a guarded directory in one text; run on the raw command, on the unwrapped scan (sh -c "rm -rf src") and on each segment of inline code.
rm_src() {
  rx '(^|[[:space:]])rm([[:space:]]|$)' "$1" && rx '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' "$1" && rx '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' "$1" && rx "$srcdirs" "$1"
}
# interp_removes: inline code calls a recursive remover (shutil.rmtree, fs.rmSync with recursive, FileUtils.rm_rf) whose target is a guarded directory.
interp_removes() {
  local tgt="[[:space:]]+(\\./)?(${srcnames})(/|[[:space:]]|\$)"
  rx "(rmtree|rimraf|rm_rf|rm_r|remove_entry|remove_dir|removeSync|emptyDirSync)${tgt}" "$interp_norm" && return 0
  rx 'recursive' "$interp_norm" || return 1
  rx "(rmSync|rmdirSync|fs\\.rm|rmdir)${tgt}" "$interp_norm"
}
if rm_src "$cmd" || rm_src "$scan_shell"; then
  block "recursive rm on a source directory. Confirm with a human first."
fi
if [ -n "$interp" ]; then
  while IFS= read -r seg; do
    rm_src "$seg" && block "recursive rm on a source directory. Confirm with a human first."
  done < <(printf '%s\n' "$interp_norm" | tr ';|&' '\n\n\n')
  interp_removes && block "recursive removal of a source directory through an interpreter. Confirm with a human first."
fi
exit 0
