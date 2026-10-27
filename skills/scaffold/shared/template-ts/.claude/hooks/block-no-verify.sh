#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
# Best-effort tripwire, not a security boundary: a determined shell can always obfuscate.
# The lefthook + CI layers are the backstop.
orig_dir=$PWD   # fallback only — Claude Code may spawn hooks from the session's original root, not a worktree
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: block-no-verify.sh cannot cd to the project root — refusing the command." >&2; exit 2; }
input=$(cat)
cmd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(((JSON.parse(b||'{}').tool_input)||{}).command||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
# The hook input's `cwd` is the directory the command actually runs in, so a bare `git commit` from a
# worktree resolves that worktree's branch rather than the main checkout's.
in_cwd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').cwd||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -n "$in_cwd" ] && orig_dir=$in_cwd
[ -z "$cmd" ] && exit 0
# Drop heredoc bodies (a commit message saying "git push --force origin main" is text, not a command):
# from a line opening `<<WORD` / `<<-'WORD'` / `<<"WORD"` (not the `<<<` here-string) through the
# line equal to WORD (leading tabs allowed for `<<-`). The opening line itself is still scanned.
cmd=$(printf '%s\n' "$cmd" | awk '
  inh { t = $0; if (tabs) sub(/^\t+/, "", t); if (t == w) inh = 0; next }
  { print; l = $0; gsub(/<<</, "", l)
    if (match(l, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      w = substr(l, RSTART, RLENGTH); tabs = (w ~ /^<<-/); sub(/^<<-?[[:space:]]*["\047]?/, "", w); inh = 1 } }')
block() { echo "BLOCKED: $1" >&2; exit 2; }
protected='main|uat|develop'
root=$PWD
# Directories a bare commit/push in this command may land on: the command's cwd, plus each literal
# cd/pushd/env -C/sudo -D target resolved against every candidate so far. The real directory is always a
# candidate or one literal step from one, so a cd the shell undoes (subshell, `&`, `|`) or that fails
# cannot hide it, and ANY protected candidate blocks. Anything this check cannot resolve exactly sets
# redir, which adds the project root, the directory it judged before it knew the cwd. A construct the
# parser misses therefore never leaves it weaker than that.
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

# Normalise before flag-matching:
#  1. unwrap `bash|sh|zsh -c "…"` / `eval "…"` so a wrapped command is scanned, not scrubbed away;
#  2. unquote quoted single words ("--no-verify", "main") — the shell strips those quotes too;
#  3. replace remaining (multi-word or empty) quoted strings with a placeholder (Q) so text inside
#     -m "…" can't false-trigger. Double quotes are handled before single quotes so an
#     apostrophe inside "it's done" can't pair with a later ' and swallow real flags.
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
# Collect directory changes before judging any git invocation: a loop or a function can run a cd that
# appears after the git word. Words before each segment's git executable (all words, when there is none)
# are scanned wherever they sit — `if cd x`, `\cd x`, `env -C x git …` — not only at the segment start.
# Passes repeat until the candidate set stops growing, so a relative target is resolved against every
# directory the command can reach.
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
[ "$settled" -eq 1 ] || redir=1   # still growing at the cap: judge the project root too
# A strict `&&` chain (no ; || | lone & ( ) ` or newline once N>&M redirections are set aside) reaches
# each git only after every cd before it succeeded, so the directories its git words run in are known
# exactly: judge those instead of the whole candidate set. That is what lets `cd repo && git commit`
# through from a protected checkout. A cd that is not a plain literal at the start of a segment, a git
# that is not the first word of its segment, or any redir leaves the candidate set as it is.
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
  while [ "$i" -lt "$n" ]; do              # locate the git executable (git, /usr/bin/git, \git)
    w="${t[$i]#\\}"
    [[ "$w" == git || "$w" == */git ]] && break
    i=$((i + 1))
  done
  [ "$i" -ge "$n" ] && continue
  i=$((i + 1)); cdir=""
  while [ "$i" -lt "$n" ] && [[ "${t[$i]}" == -* ]]; do   # git global options precede the subcommand
    o="${t[$i]}"
    case "$o" in
      -C)
        # git applies every -C in turn, each relative to the one before.
        x="${t[$((i + 1))]:-}"
        if [ -z "$cdir" ] || [[ "$x" == /* ]]; then cdir=$x; else cdir="$cdir/$x"; fi
        i=$((i + 2)); continue ;;
      -c|--config-env)
        printf '%s' "${t[$((i + 1))]:-}" | grep -qi 'core\.hookspath' && block "'git -c core.hooksPath=…' disables the git-hook layer — the same bypass as --no-verify. Fix the failure instead."
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
          -?*)   # short-flag cluster: walk letters; a value-taking flag consumes the rest (or the next word)
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
      [ -n "$branch" ] && block "direct commit to protected branch '$branch'. Create a feature branch first."
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
            [ "$pos" -eq 1 ] && continue   # first positional is the remote
            explicit=1
            [[ "$a" == +* || "$a" == :* ]] && force=1   # +refspec forces; :branch deletes
            [[ "$a" =~ ^\+?((refs/heads/)?($protected)|[^:]*:(refs/heads/)?($protected))$ ]] && target=1
            # `HEAD` / `@` (no `:dst`) pushes the current branch to its same-named remote branch
            if [[ "$a" =~ ^\+?(HEAD|@)$ ]]; then [ -n "$(protected_branch)" ] && target=1; fi ;;
        esac
      done
      if [ "$explicit" -eq 0 ]; then
        [ -n "$(protected_branch)" ] && target=1
      fi
      [ "$force" -eq 1 ] && [ "$target" -eq 1 ] && block "force-push/delete on a protected branch (--force, --force-with-lease, -f, +refspec, HEAD:main). Open a PR instead."
      ;;
    config)
      if printf '%s ' "${args[@]}" | grep -qi 'core\.hookspath' && ! printf ' %s ' "${args[@]}" | grep -qE ' (--get|--get-all|--get-regexp|get|-l|--list) '; then
        block "'git config core.hooksPath' re-points or disables the git-hook layer. Confirm with a human first."
      fi ;;
    checkout|restore)
      if printf ' %s' "${args[@]}" | grep -qE '[[:space:]](\./)?(\.claude/|\.claude([[:space:]]|$)|\.lefthook/|\.github/|lefthook\.yml|\.gitleaks\.toml|AGENTS\.md|CLAUDE\.md|docs/CONSTITUTION\.md)'; then
        block "'git checkout/restore' on a guard-layer file discards enforcement config (this is how settings.json gets silently wiped). Confirm with a human first."
      fi ;;
  esac
done <<< "$segments"

if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/"])(src|app|lib|test|\.claude|\.lefthook|\.git|node_modules)([[:space:]/"]|$)'; then
  block "recursive rm on a source directory. Confirm with a human first."
fi
exit 0
