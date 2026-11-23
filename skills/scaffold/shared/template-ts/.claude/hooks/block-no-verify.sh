#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
# Best-effort tripwire, not a security boundary; the lefthook + CI layers are the backstop.
# A text guard cannot see variable indirection or command substitution (cat "$f", cat $(echo .env)); those stay open.
# Fallback only: hooks may be spawned from the session's original root, not a worktree.
orig_dir=$PWD
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: block-no-verify.sh cannot cd to the project root — refusing the command." >&2; exit 2; }
input=$(cat)
cmd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(((JSON.parse(b||'{}').tool_input)||{}).command||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
# The hook input's cwd is where the command runs, so a bare git commit resolves that worktree's branch.
in_cwd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').cwd||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -n "$in_cwd" ] && orig_dir=$in_cwd
[ -z "$cmd" ] && exit 0
# Drop heredoc bodies so commit-message text is not scanned as a command; the opening line is still scanned.
cmd=$(printf '%s\n' "$cmd" | awk '
  inh { t = $0; if (tabs) sub(/^\t+/, "", t); if (t == w) inh = 0; next }
  { print; l = $0; gsub(/<<</, "", l)
    if (match(l, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      w = substr(l, RSTART, RLENGTH); tabs = (w ~ /^<<-/); sub(/^<<-?[[:space:]]*["\047]?/, "", w); inh = 1 } }')
# cut200 <text>: at most 200 bytes, never inside a UTF-8 sequence, in any locale and with any awk (same ucut as every other hook cap).
cut200() { S=$1 LC_ALL=C awk 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } BEGIN { printf "%s", ucut(ENVIRON["S"], 200) }' || printf 'BLOCKED'; }
# block <message>: message capped at 200 bytes.
block() { echo "$(cut200 "BLOCKED: $1")" >&2; exit 2; }
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
      done <<< "$hits"
    done
    if [[ "$tok" != *[*?[]* ]] && is_secret "$tok" && writes_to_secret "$tok"; then secret_block "$tok"; fi
    if [[ "$tok" == *:* ]] && is_secret "${tok#*:}" && [[ "$flat" =~ (^|[[:space:]\;\&\|\(])git[[:space:]]+([^;&|]*[[:space:]])?(show|cat-file|archive|blame|grep|log|diff)[[:space:]] ]]; then secret_block "${tok#*:}"; fi
  done <<< "$tokens"
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

# Unwrap bash -c/eval, unquote single words, mask other quoted text as Q; double quotes first so an apostrophe cannot swallow flags.
sq="'"
scan=$(printf '%s' "$cmd" | sed -E \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+\"([^\"]*)\"/\1 \4 /g" \
  -e "s/(^|[[:space:];&|(])(bash|sh|zsh|eval)([[:space:]]+-[a-z]*c)?[[:space:]]+${sq}([^${sq}]*)${sq}/\1 \4 /g" \
  -e "s/\"([^\"${sq}[:space:]]+)\"/\1/g" -e "s/\"[^\"]*\"/ Q /g" \
  -e "s/${sq}([^${sq}[:space:]]+)${sq}/\1/g" -e "s/${sq}[^${sq}]*${sq}/ Q /g")

# Hook-layer bypass via environment or a persisted alias/config (whole-command checks).
lower_cmd=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
if printf '%s' "$scan" | grep -qE '(^|[^A-Za-z0-9_])LEFTHOOK(_EXCLUDE)?=' && printf '%s' "$scan" | grep -qE '(^|[^A-Za-z0-9_-])git([[:space:]]|$)'; then
  block "LEFTHOOK=0 / LEFTHOOK_EXCLUDE disables the pre-commit hook layer — the same bypass as --no-verify. Fix the failure instead."
fi
if printf '%s' "$lower_cmd" | grep -qE 'git_config_(parameters|key_[0-9]+)' && printf '%s' "$lower_cmd" | grep -q 'hookspath'; then
  block "GIT_CONFIG_* overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
fi
if printf '%s' "$lower_cmd" | grep -q 'alias\.' && printf '%s' "$lower_cmd" | grep -q 'no-verify'; then
  block "a git alias wrapping --no-verify is the same bypass as --no-verify. Fix the failure instead."
fi

# Evaluate each simple command separately: split on && || ; | & ( ) ` and newlines.
segments=$(printf '%s\n' "$scan" | tr ';|&()`' '\n\n\n\n\n\n')
# Collect every cd before judging a git word, since a loop or function can cd after it; repeat until the candidates stop growing.
collect_dirs() {
  local seg p q w d n i
  local -a t
  while IFS= read -r seg; do
    read -ra t <<< "$seg"
    n=${#t[@]}; i=0
    while [ "$i" -lt "$n" ]; do
      w="${t[$i]#\\}"
      [[ "$w" == git || "$w" == */git ]] && break
      i=$((i + 1))
    done
    for ((p = 0; p < i; p++)); do
      w="${t[$p]#\\}"
      case "$w" in
        cd|pushd)
          d=""
          for ((q = p + 1; q < i; q++)); do [[ "${t[$q]}" == -?* ]] && continue; d=${t[$q]}; break; done
          add_target "$d" ;;
        popd|eval|source|function|CDPATH=*|GIT_DIR=*|GIT_WORK_TREE=*) redir=1 ;;
        # `.` sources a script only in command position; elsewhere it is an ordinary argument (`ls .`).
        .) [[ "$p" -eq 0 || "${t[$((p - 1))]}" =~ ^(then|do|else|if|while|until|!|[{]|time|command|builtin|exec)$ ]] && redir=1 ;;
        env|sudo)
          for ((q = p + 1; q < i; q++)); do
            case "${t[$q]}" in
              -C|-D|--chdir) add_target "${t[$((q + 1))]:-}" ;;
              --chdir=*) add_target "${t[$q]#--chdir=}" ;;
              -C?*|-D?*) add_target "${t[$q]:2}" ;;
            esac
          done ;;
      esac
    done
  done <<< "$segments"
}
# `name() { … }` defines a function whose body may cd where this check cannot follow.
printf '%s' "$scan" | grep -qE '(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*\(\)' && redir=1
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
    read -ra t <<< "$seg"
    [ "${#t[@]}" -eq 0 ] && continue
    first="${t[0]#\\}"
    if [[ "$first" == cd || "$first" == pushd ]]; then
      d=""
      for w in "${t[@]:1}"; do [[ "$w" == -?* ]] && continue; d=$w; break; done
      unresolved "$d" && return 1
      [[ "$d" == /* ]] || d="$cur/$d"
      cur=$(cd "$d" 2>/dev/null && pwd -P) || return 1
      continue
    fi
    for w in "${t[@]}"; do
      case "${w#\\}" in cd|pushd|popd|env|sudo|command|builtin|exec) return 1 ;; esac
    done
    if [[ "$first" == git || "$first" == */git ]]; then
      sawgit=1
      [[ " ${out[*]} " == *" $cur "* ]] || out+=("$cur")
    else
      for w in "${t[@]}"; do [[ "${w#\\}" == git || "${w#\\}" == */git ]] && return 1; done
    fi
  done <<< "${scan//&&/$'\n'}"
  [ "$sawgit" -eq 1 ] || return 1
  printf '%s\n' "${out[@]}"
}
if [ "$redir" -eq 0 ] && chain_out=$(chain_dirs); then
  cand=()
  while IFS= read -r d; do cand+=("$d"); done <<< "$chain_out"
fi
while IFS= read -r seg; do
  read -ra t <<< "$seg"
  n=${#t[@]}; i=0
  while [ "$i" -lt "$n" ]; do
    w="${t[$i]#\\}"
    [[ "$w" == git || "$w" == */git ]] && break
    i=$((i + 1))
  done
  [ "$i" -ge "$n" ] && continue
  i=$((i + 1)); cdir=""
  while [ "$i" -lt "$n" ] && [[ "${t[$i]}" == -* ]]; do
    o="${t[$i]}"
    case "$o" in
      -C)
        # git applies every -C in turn, each relative to the one before.
        x="${t[$((i + 1))]:-}"
        if [ -z "$cdir" ] || [[ "$x" == /* ]]; then cdir=$x; else cdir="$cdir/$x"; fi
        i=$((i + 2)); continue ;;
      -c|--config-env)
        printf '%s' "${t[$((i + 1))]:-}" | grep -qi 'core\.hookspath' && block "'git -c core.hooksPath=…' disables the git-hook layer, the same bypass as --no-verify. Fix the failure instead."
        i=$((i + 2)); continue ;;
      --git-dir|--work-tree) redir=1; i=$((i + 2)); continue ;;
      --git-dir=*|--work-tree=*) redir=1 ;;
      --namespace|--exec-path|--super-prefix) i=$((i + 2)); continue ;;
    esac
    printf '%s' "$o" | grep -qi 'core\.hookspath' && block "overriding core.hooksPath disables the git-hook layer. Fix the failure instead."
    i=$((i + 1))
  done
  sub="${t[$i]:-}"; i=$((i + 1))
  args=("${t[@]:$i}")

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
        if printf '%s' "$scan" | grep -qE 'git[[:space:]]+(checkout[[:space:]]+(-[bB]|--orphan)|switch[[:space:]]+(-[cC]|--create))'; then
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
done <<< "$segments"

if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/"])(src|app|lib|test|\.claude|\.lefthook|\.git|node_modules)([[:space:]/"]|$)'; then
  block "recursive rm on a source directory. Confirm with a human first."
fi
exit 0
