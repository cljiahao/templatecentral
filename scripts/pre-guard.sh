#!/bin/bash
# Tiered PreToolUse guard for agent Edit/Write in this repo.
#   Tier 1 HARD-BLOCK (exit 2): secrets, .env*, certs/credentials — never agent-writable.
#   Tier 2 ASK (permissionDecision "ask"): governance, enforcement, and CI files —
#           the agent may edit, but only with explicit per-edit human approval.
#   Tier 3 ALLOW (exit 0): skills, docs, source — everything else.
# Note: the *shipped* guard (skills/scaffold/shared/harness-kit.md -> protect-files.sh)
# stays stricter (CI hard-blocked) — different threat model for downstream projects.

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0

base="${FILE##*/}"

# Always allow the committed env templates.
if [[ "$base" == ".env.example" || "$base" == ".env.default" ]]; then exit 0; fi

# Tier 1 — HARD BLOCK (secrets / env / certs / credentials).
if [[ "$FILE" =~ (^|/)\.env(\.[^/]*)?$ ]] || \
   [[ "$FILE" =~ (^|/)\.?secrets/ ]] || \
   [[ "$FILE" =~ \.(pem|key|p12|pfx|secret)$ ]] || \
   [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED (secret/credential): $FILE — never written by the agent. Put placeholders in .env.example." >&2
  exit 2
fi

# Tier 2 — ASK (human approves the exact edit). Matches relative and absolute paths.
reason=""
case "$FILE" in
  AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md)                  reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md|*/docs/CONSTITUTION.md)                  reason="binding invariants document" ;;
  .claude/settings.json|*/.claude/settings.json)               reason="harness config — can silently disable every hook" ;;
  .claude/hooks/*|*/.claude/hooks/*)                           reason="enforcement hook script" ;;
  scripts/pre-guard.sh|*/scripts/pre-guard.sh)                 reason="this guard itself — editing it can weaken the protection layer" ;;
  .github/workflows/*|*/.github/workflows/*)                   reason="CI/CD pipeline — supply-chain / secret-exfiltration surface" ;;
  Dockerfile|*/Dockerfile)                                     reason="container image definition" ;;
  lefthook.yml|*/lefthook.yml|.gitleaks.toml|*/.gitleaks.toml) reason="git-hook enforcement config" ;;
  .lefthook/*|*/.lefthook/*)                                   reason="git-hook script" ;;
esac
if [[ -n "$reason" ]]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"PROTECTED (%s): %s — confirm this change."}}\n' "$reason" "$FILE"
  exit 0
fi

# Tier 3 — ALLOW
exit 0
