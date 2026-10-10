#!/bin/bash
# Tiered PreToolUse guard for agent Edit/Write/NotebookEdit (all tiers) and Read/Grep
# (Tier 1 only — reading instruction files needs no approval).
#   Tier 1 HARD-BLOCK (exit 2): secrets, .env*, certs/credentials — never agent-writable.
#   Tier 2 ASK (permissionDecision "ask"): agent-instruction, governance, enforcement and CI
#           files — editable only with explicit per-edit human approval.
#   Tier 3 ALLOW (exit 0): skills, docs, source — everything else.
# The *shipped* guard (harness-kit-{ts,fastapi}.md -> protect-files.sh) hard-blocks CI instead: downstream
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

# Committed env templates stay agent-editable.
case "$base" in .env.example|.env.default|.env.sample|.env.template) exit 0 ;; esac

# Tier 1 — HARD BLOCK.
if [[ "$path" =~ (^|/)\.env(\.[^/]*)?$ ]] || \
   [[ "$path" =~ (^|/)\.?secrets(/|$) ]] || \
   [[ "$path" =~ \.(pem|key|p12|pfx|secret|keystore|jks)$ ]] || \
   [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".npmrc" || "$base" == ".pypirc" ]]; then
  echo "BLOCKED (secret/credential): $FILE — never read or written by the agent. Put placeholders in .env.example." >&2
  exit 2
fi
[[ "$TOOL" == "Read" || "$TOOL" == "Grep" ]] && exit 0

# Tier 2 — ASK.
reason=""
case "$path" in
  agents.md|*/agents.md|claude.md|*/claude.md|gemini.md|*/gemini.md|constitution.md|*/constitution.md|.github/copilot-instructions.md|.cursor/rules/*|.cursorrules)
    reason="agent instruction file — prompt-injection attack surface" ;;
  .claude/rules/*|.claude/skills/*|.claude/commands/*)
    reason="project agent rules/skills — steer every future session" ;;
  .claude/settings.json|.claude/settings.local.json|*/.claude/settings.json|*/.claude/settings.local.json)
    reason="harness config — can disable hooks or widen permissions" ;;
  .claude/hooks/*|.claude/agents/*|*/.claude/hooks/*|*/.claude/agents/*)
    reason="hook script or agent definition — alters enforcement or tool access" ;;
  .claude-plugin/*)
    reason="plugin manifest — shipped to every installer (hooks, metadata)" ;;
  .mcp.json)
    reason="MCP server config — can register an exfiltrating server" ;;
  scripts/pre-guard.sh|scripts/bash-guard.sh|scripts/post-edit-lint.sh)
    reason="this repo's guard layer — editing it can weaken protection" ;;
  .github/workflows/*|.github/actions/*|.azuredevops/*|azure-pipelines*.y*ml|.gitlab-ci.yml|jenkinsfile|*/jenkinsfile)
    reason="CI/CD pipeline — supply-chain / secret-exfiltration surface" ;;
  dockerfile|*/dockerfile|lefthook.yml|.gitleaks.toml|.lefthook/*)
    reason="container or git-hook enforcement config" ;;
esac
if [[ -n "$reason" ]]; then
  jq -cn --arg r "PROTECTED ($reason): $FILE — confirm this change." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

exit 0
