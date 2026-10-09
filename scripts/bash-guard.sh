#!/bin/bash
# PreToolUse(Bash) guard: blocks shell access to secret files, which `permissions.deny` Read
# rules cannot stop (they gate the Read tool, not `cat`). Reads are blocked only when the
# referenced file exists, so commands that merely mention `.env` in text still run; redirects
# or copies that would create a secret file are blocked outright. Env templates stay usable.
# Best-effort tripwire, not a sandbox — determined obfuscation can evade a text match.

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INPUT=$(cat)

json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(d if isinstance(d, str) else "")' "$1" 2>/dev/null
  else
    # Fail open: this guard must never block every Bash call. Read deny rules still apply.
    echo "bash-guard.sh: neither jq nor python3 found — secret check skipped" >&2
    exit 0
  fi
}

CMD=$(json_field '.tool_input.command')
[[ -z "$CMD" ]] && exit 0
CWD=$(json_field '.cwd')
# Heredoc bodies are data, not commands; the opening line (e.g. `cat > .env <<EOF`) is kept.
CMD=$(printf '%s\n' "$CMD" | awk '
  body { t = $0; if (strip) sub(/^\t+/, "", t); if (t == term) body = 0; next }
  { print }
  match($0, /<<-?[ \t]*["\x27]?[A-Za-z_][A-Za-z0-9_]*/) {
    if (substr($0, RSTART, 3) == "<<<") next
    term = substr($0, RSTART, RLENGTH); strip = (term ~ /^<<-/)
    sub(/^<<-?[ \t]*["\x27]?/, "", term); body = 1
  }')
CMD="${CMD//\\/}"

is_secret() {
  local lc
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "${lc##*/}" in
    .env.example|.env.default|.env.sample|.env.template) return 1 ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|credentials.json|.netrc) return 0 ;;
  esac
  case "$lc" in secrets/*|*/secrets/*|.secrets/*|*/.secrets/*) return 0 ;; esac
  return 1
}

block() {
  echo "BLOCKED (secret access): '$1' — never read or written by the agent. Use .env.example for placeholders; ask the user for real values." >&2
  exit 2
}

# True when the command writes to TOKEN: a redirect, `tee`, or TOKEN as the last argument.
writes_to() {
  local t=$1 q
  for q in "" "\"" "'"; do
    case "$CMD" in
      *">$q$t"*|*"> $q$t"*|*"tee $q$t"*|*"tee -a $q$t"*) return 0 ;;
    esac
  done
  [[ "$CMD" =~ (^|[[:space:]])(cp|mv|ln|install|touch)[[:space:]].*[[:space:]\"\']${t}[\"\']?[[:space:]]*($|[;&|]) ]]
}

# Candidate tokens: secret-looking names, or anything with glob characters (`.en?`, `.[e]nv`).
delim="[:space:]\"'\`;|&<>()="
tokens=$(printf '%s' "$CMD" | grep -oiE "[^$delim]*(\\.env|\\.pem|\\.key|\\.p12|\\.pfx|credentials\\.json|\\.netrc|secrets/|[*?[])[^$delim]*" || true)
[[ -z "$tokens" ]] && exit 0

dirs=("$ROOT")
[[ -n "$CWD" && "$CWD" != "$ROOT" ]] && dirs+=("$CWD")

while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue
  tok="${tok/#\~/$HOME}"
  tok="${tok//\$\{HOME\}/$HOME}"
  tok="${tok//\$HOME/$HOME}"
  for d in "${dirs[@]}"; do
    tok_d="${tok//\$\{PWD\}/$d}"
    tok_d="${tok_d//\$PWD/$d}"
    # Unquoted on purpose: expands globs like `.env*` or `secrets/*` against the filesystem.
    # shellcheck disable=SC2086
    hits=$(cd "$d" 2>/dev/null && for f in $tok_d; do [[ -e "$f" ]] && printf '%s\n' "$f"; done)
    while IFS= read -r f; do
      [[ -n "$f" ]] && is_secret "$f" && block "$f"
    done <<< "$hits"
  done
  if [[ "$tok" != *[*?[]* ]] && is_secret "$tok" && writes_to "$tok"; then block "$tok"; fi
done <<< "$tokens"

exit 0
