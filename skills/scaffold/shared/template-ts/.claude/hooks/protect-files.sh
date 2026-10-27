#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) — block secrets and certs; ask before CI and governance edits.
# Exit 2 = hard block (stderr → model); permissionDecision "ask" JSON (exit 0) = require human approval; plain exit 0 = allow.
# Fail closed: a guard that cannot locate the project root blocks rather than guessing.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: protect-files.sh cannot cd to the project root — refusing the write." >&2; exit 2; }
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.notebook_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$file" ] && exit 0
shopt -s nocasematch   # .ENV, Dockerfile vs dockerfile, AGENTS.md vs agents.md — case-insensitive filesystems make these the same file
while [[ "$file" == ./* ]]; do file="${file#./}"; done
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

# Resolve to a project-relative path: physical root (pwd -P — macOS /tmp is really /private/tmp),
# relative paths anchored at the root, the longest existing ancestor canonicalised (symlinked
# parents), and `.`/`..` in the not-yet-existing remainder folded lexically — so neither
# `src/../.github/…` (no src/) nor a symlinked parent can disguise the target.
root=$(pwd -P)
case "$file" in /*) abs="$file" ;; *) abs="$root/$file" ;; esac
canon() {
  local d="${1%/*}" r="" n="" s p
  while [ -n "$d" ] && [ ! -d "$d" ]; do r="/${d##*/}$r"; d="${d%/*}"; done
  p=$(cd "${d:-/}" 2>/dev/null && pwd -P) && d="$p"
  r="${r#/}"
  while [ -n "$r" ]; do
    s="${r%%/*}"; case "$r" in */*) r="${r#*/}" ;; *) r="" ;; esac
    case "$s" in ""|.) ;; ..) if [ -n "$n" ]; then n="${n%/*}"; else d="${d%/*}"; fi ;; *) n="$n/$s" ;; esac
  done
  printf '%s' "${d%/}$n/${1##*/}"
}
abs=$(canon "$abs"); abs=$(canon "$abs")   # 2nd pass: the folded path may now cross an existing (symlinked) dir
rel="${abs#"$root"/}"

if [[ "$rel" == secrets/* || "$rel" == .secrets/* ]]; then
  echo "BLOCKED: $rel is inside a secrets directory — must never be written by the agent." >&2
  exit 2
elif [[ "$base" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md|*/docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json|*/.claude/settings.json|.claude/settings.local.json|*/.claude/settings.local.json) reason="harness config — editing it can silently disable every hook or add permissive perms (settings.local.json takes precedence over settings.json)" ;;
  .claude/hooks/*|*/.claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  .claude/agents/*|*/.claude/agents/*) reason="agent definition — editing it can alter subagent tool access/behavior" ;;
  .mcp.json|*/.mcp.json) reason="MCP server config — editing it can register a malicious/exfiltrating server" ;;
  .claude/harness.json|*/.claude/harness.json|.claude/verify-harness.sh|*/.claude/verify-harness.sh|.claude/regen-harness.sh|*/.claude/regen-harness.sh|.claude/ci-gates.sh|*/.claude/ci-gates.sh) reason="harness integrity baseline/verifier or CI gate script — editing it can defeat drift detection or a merge gate" ;;
  .claude/dep-audit-allow.txt|*/.claude/dep-audit-allow.txt) reason="dependency-audit allowlist — editing it can silently suppress a known vulnerability" ;;
  .claude/.harness-base/*|*/.claude/.harness-base/*) reason="merge base snapshot — editing it can poison harness re-sync merges" ;;
  Dockerfile|*/Dockerfile) reason="container image definition" ;;
  lefthook.yml|*/lefthook.yml|.gitleaks.toml|*/.gitleaks.toml) reason="git-hook enforcement config — editing it can weaken commit-time guards" ;;
  .claude/comment-hygiene-patterns.txt|*/.claude/comment-hygiene-patterns.txt) reason="comment-hygiene enforcement pattern list — editing it can silently weaken the CI hard gate" ;;
  .lefthook/*|*/.lefthook/*) reason="git-hook script — editing it can weaken commit-time guards" ;;
  .github/workflows/*|.github/actions/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*) reason="CI/CD pipeline definition — changes skip or weaken the merge gates" ;;
esac
if [[ -z "$reason" && ( "$base" == azure-pipelines*.yml || "$base" == azure-pipelines*.yaml \
   || "$base" == ".gitlab-ci.yml" || "$base" == "Jenkinsfile" ) ]]; then
  reason="CI/CD pipeline definition — changes skip or weaken the merge gates"
fi
if [ -n "$reason" ]; then
  # Emit permissionDecision "ask" so Claude Code prompts for human approval before the write.
  # (`exit 1` + stderr is NON-blocking on PreToolUse — the edit goes through and the warning
  # never reaches the model. Only "ask" actually gates the write.) JSON is built by the runtime,
  # never by printf, so a path containing quotes/backslashes can't break or inject into it.
  node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"PROTECTED FILE: "+process.argv[1]+" — "+process.argv[2]+". Confirm human approval and note it in the PR."}})+"\n")' "$rel" "$reason" \
    || { echo "BLOCKED: $rel is protected ($reason) and the approval prompt could not be built." >&2; exit 2; }
  exit 0
fi
exit 0
