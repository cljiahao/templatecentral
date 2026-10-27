#!/bin/bash
# Tiered PreToolUse guard for agent Edit/Write/NotebookEdit (all tiers) and Read/Grep
# (Tier 1 only — reading instruction files needs no approval).
#   Tier 1 HARD-BLOCK (exit 2): secrets, .env*, certs/credentials — never agent-writable.
#   Tier 2 ASK (permissionDecision "ask"): agent-instruction, governance, enforcement and CI
#           files — editable only with explicit per-edit human approval.
#   Tier 3 ALLOW (exit 0): skills, docs, source — everything else.
#   Scratch exemption: Tier 2 is skipped for targets that resolve (symlinks and `..` followed)
#           outside the repo root and inside /tmp or a $TMPDIR that sits in a system temp tree
#           (never $HOME, the repo, or an ancestor of either); Tier 1 still applies there.
#           A target that reaches the repo through a symlink is matched on its resolved path too.
# The *shipped* guard (scaffold/shared/template-{ts,py}/.claude/hooks/protect-files.sh) hard-blocks CI instead: downstream
# projects have a different threat model.

command -v jq >/dev/null 2>&1 || { echo "BLOCKED: jq required for pre-guard.sh" >&2; exit 2; }

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" 2>/dev/null || { echo "BLOCKED: cannot cd to project dir '$ROOT'" >&2; exit 2; }
ROOT_REAL=$(pwd -P)

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if ! FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null); then
  echo "BLOCKED: failed to parse tool_input JSON in pre-guard.sh" >&2
  exit 2
fi
[[ -z "$FILE" ]] && exit 0

# Repo-relative, lexically folded (`.`/`..`), lower-cased: macOS filesystems are
# case-insensitive, so `.ENV` and `Agents.md` must match like their canonical names.
rel="$FILE"
for prefix in "$ROOT_REAL/" "$ROOT/"; do rel="${rel#"$prefix"}"; done
folded=""
IFS='/' read -r -a parts <<< "$rel"
for seg in "${parts[@]}"; do
  case "$seg" in
    ""|.) ;;
    ..) if [[ -n "$folded" && "$folded" != ".." && "$folded" != *"/.." ]]; then
          if [[ "$folded" == */* ]]; then folded="${folded%/*}"; else folded=""; fi
        else
          folded="${folded:+$folded/}.."
        fi ;;
    *) folded="${folded:+$folded/}$seg" ;;
  esac
done
path=$(printf '%s' "$folded" | tr '[:upper:]' '[:lower:]')
base="${path##*/}"

# Physical absolute path of $1 with every symlink and `..` resolved (a symlink leaf is followed
# through readlink, dangling ones included), for a target that may not exist yet. Fails (non-zero)
# when it cannot be resolved with certainty: a link loop or `..` / `.` in the not-yet-existing tail.
resolve_physical() {
  local p="$1" tail="" seg dir t hops=0
  [[ "$p" == /* ]] || p="$ROOT_REAL/$p"
  while :; do
    if [[ -L "$p" ]]; then
      hops=$((hops + 1))
      [[ "$hops" -le 40 ]] || return 1
      t=$(readlink "$p") || return 1
      [[ "$t" == /* ]] || t="${p%/*}/$t"
      p="$t$tail"
      tail=""
    elif [[ -e "$p" ]]; then
      break
    else
      seg="${p##*/}"
      case "$seg" in ""|.|..) return 1 ;; esac
      tail="/$seg$tail"
      p="${p%/*}"
      [[ -n "$p" ]] || p="/"
    fi
  done
  if [[ -d "$p" ]]; then
    dir=$(cd -P "$p" 2>/dev/null && pwd -P) || return 1
  else
    dir=$(cd -P "${p%/*}/" 2>/dev/null && pwd -P) || return 1
    tail="/${p##*/}$tail"
  fi
  [[ "$dir" == "/" ]] && dir=""
  printf '%s%s' "$dir" "$tail"
}

# Tier 1 test on a lower-cased path (repo-relative or absolute) and its basename.
secret_path() {
  local path="$1" base="${1##*/}"
  [[ "$path" =~ (^|/)\.env(\.[^/]*)?$ ]] || \
  [[ "$path" =~ (^|/)\.?secrets(/|$) ]] || \
  [[ "$path" =~ \.(pem|key|p12|pfx|secret|keystore|jks)$ ]] || \
  [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".npmrc" || "$base" == ".pypirc" ]]
}
env_template() {
  case "${1##*/}" in .env.example|.env.default|.env.sample|.env.template) return 0 ;; esac
  return 1
}
block_secret() {
  echo "BLOCKED (secret/credential): $FILE — never read or written by the agent. Put placeholders in .env.example." >&2
  exit 2
}

# Tier 2 reason for a lower-cased repo-relative path; empty when unprotected.
tier2_reason() {
  local path="$1"
  case "$path" in
  agents.md|*/agents.md|claude.md|*/claude.md|gemini.md|*/gemini.md|constitution.md|*/constitution.md|.github/copilot-instructions.md|.cursor/rules/*|.cursorrules)
    echo "agent instruction file — prompt-injection attack surface" ;;
  .claude/rules/*|.claude/skills/*|.claude/commands/*|*/.claude/rules/*|*/.claude/skills/*|*/.claude/commands/*|.claude/keybindings.json|*/.claude/keybindings.json)
    echo "project agent rules/skills — steer every future session" ;;
  .claude/settings.json|.claude/settings.local.json|*/.claude/settings.json|*/.claude/settings.local.json)
    echo "harness config — can disable hooks or widen permissions" ;;
  .claude/hooks/*|.claude/agents/*|*/.claude/hooks/*|*/.claude/agents/*)
    echo "hook script or agent definition — alters enforcement or tool access" ;;
  .claude-plugin/*)
    echo "plugin manifest — shipped to every installer (hooks, metadata)" ;;
  .mcp.json)
    echo "MCP server config — can register an exfiltrating server" ;;
  scripts/pre-guard.sh|scripts/bash-guard.sh|scripts/post-edit-lint.sh)
    echo "this repo's guard layer — editing it can weaken protection" ;;
  .github/workflows/*|.github/actions/*|.azuredevops/*|azure-pipelines*.y*ml|.gitlab-ci.yml|jenkinsfile|*/jenkinsfile)
    echo "CI/CD pipeline — supply-chain / secret-exfiltration surface" ;;
  dockerfile|*/dockerfile|lefthook.yml|.gitleaks.toml|.lefthook/*)
    echo "container or git-hook enforcement config" ;;
  esac
}

# True when the filesystem holding directory $1 ignores case: always on macOS, elsewhere when an
# upper- or lower-cased spelling of the path still names a directory (casefold or vfat mounts).
case_insensitive_fs() {
  local d="$1" v
  [[ "$(uname -s)" == "Darwin" ]] && return 0
  for v in "$(printf '%s' "$d" | tr '[:lower:]' '[:upper:]')" "$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')"; do
    [[ "$v" != "$d" && -d "$v" ]] && return 0
  done
  return 1
}

# Paths are compared folded when the repo, the target's nearest existing ancestor or a scratch base
# lives on a case-insensitive filesystem; folding only widens what counts as inside the repo.
FOLD=0
detect_fold() {
  local anc="$1" base
  while [[ -n "$anc" && ! -d "$anc" ]]; do anc="${anc%/*}"; done
  for base in "$ROOT_REAL" "${anc:-/}" /tmp "${TMPDIR:-}"; do
    [[ -n "$base" && -d "$base" ]] && case_insensitive_fs "$(cd -P "$base" 2>/dev/null && pwd -P)" && { FOLD=1; return; }
  done
}
fold_case() {
  if [[ "$FOLD" == 1 ]]; then printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; else printf '%s' "$1"; fi
}

# True when physical path $1 equals or lies under directory $2 (both already case-folded).
under() { [[ "$1" == "$2" || "$1" == "$2"/* ]]; }

# Physical path of a scratch base directory, or non-zero when it is not an acceptable one.
# /tmp and $TMPDIR qualify only when they are not (and do not contain) $HOME or the repo root; a
# $TMPDIR must also sit inside a system temp tree. An unset or unresolvable $HOME disables the
# exemption.
scratch_base() {
  local base="$1" tmp t home root ok=0 allowed
  [[ -n "$base" && -d "$base" && -n "${HOME:-}" ]] || return 1
  tmp=$(cd -P "$base" 2>/dev/null && pwd -P) || return 1
  [[ "$tmp" == "/" ]] && return 1
  home=$(cd -P "$HOME" 2>/dev/null && pwd -P) || return 1
  tmp=$(fold_case "$tmp")
  if [[ "$base" != /tmp ]]; then
    for allowed in /tmp /private/tmp /var/tmp /private/var/tmp /var/folders /private/var/folders; do
      t=$(cd -P "$allowed" 2>/dev/null && pwd -P) || t="$allowed"
      under "$tmp" "$(fold_case "$t")" && ok=1
    done
    [[ "$ok" == 1 ]] || return 1
  fi
  root=$(fold_case "$ROOT_REAL")
  under "$(fold_case "$home")" "$tmp" && return 1
  under "$root" "$tmp" && return 1
  printf '%s' "$tmp"
}

# True when resolved path $1 is outside the repo root and under /tmp or $TMPDIR.
in_scratch_dir() {
  local resolved root tmp base
  resolved=$(fold_case "$1")
  root=$(fold_case "$ROOT_REAL")
  under "$resolved" "$root" && return 1
  for base in /tmp "${TMPDIR:-}"; do
    tmp=$(scratch_base "$base") || continue
    [[ "$resolved" == "$tmp"/* ]] && return 0
  done
  return 1
}

# Resolved target (empty when it cannot be resolved). A target that is itself a symlink and cannot
# be resolved is never judged on its own name.
resolved=$(resolve_physical "$FILE") || resolved=""
resolved_lc=$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')
root_lc=$(printf '%s' "$ROOT_REAL" | tr '[:upper:]' '[:lower:]')
resolved_rel=""
[[ -n "$resolved_lc" && "$resolved_lc" == "$root_lc"/* ]] && resolved_rel="${resolved_lc#"$root_lc"/}"

# Tier 1 — HARD BLOCK, on the lexical path and again on where the target really lands.
if ! env_template "$path" && secret_path "$path"; then block_secret; fi
if [[ -n "$resolved_lc" ]] && ! env_template "$resolved_lc"; then
  if [[ -n "$resolved_rel" ]]; then
    secret_path "$resolved_rel" && block_secret
  elif [[ "$resolved_lc" != "$root_lc" ]]; then
    secret_path "$resolved_lc" && block_secret
  fi
fi
[[ "$TOOL" == "Read" || "$TOOL" == "Grep" ]] && exit 0

# Committed env templates stay agent-editable.
env_template "$path" && exit 0

if [[ -z "$resolved" ]] && { [[ -L "$FILE" ]] || [[ -L "$ROOT_REAL/$FILE" ]]; }; then
  jq -cn --arg r "PROTECTED (unresolvable symlink): $FILE — confirm this change." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

# Tier 2 — ASK. Matched on the lexical path and, when the target resolves into the repo through a
# symlink, on its resolved repo-relative path too.
detect_fold "$resolved"
if [[ -n "$resolved" ]] && in_scratch_dir "$resolved"; then
  exit 0
fi

reason=$(tier2_reason "$path")
if [[ -z "$reason" && -n "$resolved_rel" ]]; then
  reason=$(tier2_reason "$resolved_rel")
elif [[ -z "$reason" && -n "$resolved_lc" && "$resolved_lc" != "$root_lc" ]]; then
  reason=$(tier2_reason "$resolved_lc")
fi
if [[ -n "$reason" ]]; then
  jq -cn --arg r "PROTECTED ($reason): $FILE — confirm this change." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

exit 0
