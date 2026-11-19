#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): block secrets and certs, ask before CI and governance edits; fails closed.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: protect-files.sh cannot cd to the project root — refusing the write." >&2; exit 2; }
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.notebook_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$file" ] && exit 0
# shortp <path> <bytes>: path cut to <bytes> on a UTF-8 boundary with a trailing …, so a hostile long path cannot bloat a block message.
shortp() { S=$1 LC_ALL=C awk -v n="$2" 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } BEGIN { s = ENVIRON["S"]; t = ucut(s, n); printf "%s%s", t, (t == s ? "" : "…") }' || printf '%s' "$1"; }
# Case-insensitive: macOS treats .ENV and .env as one file.
shopt -s nocasematch
while [[ "$file" == ./* ]]; do file="${file#./}"; done
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $(shortp "$base" 80) is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

# Canonicalise: physical root, symlinked parents and ./.. folded, so no path can disguise the target.
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
# Second pass: the folded path may now cross a symlinked dir.
abs=$(canon "$abs"); abs=$(canon "$abs")
rel="${abs#"$root"/}"

if [[ "$rel" == secrets/* || "$rel" == .secrets/* ]]; then
  echo "BLOCKED: $(shortp "$rel" 80) is inside a secrets directory — must never be written by the agent." >&2
  exit 2
elif [[ "$base" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $(shortp "$rel" 80) is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md|*/docs/CONSTITUTION.md) reason="binding invariants — changes affect every agent" ;;
  .claude/settings.json|*/.claude/settings.json|.claude/settings.local.json|*/.claude/settings.local.json) reason="harness config — an edit can silently disable hooks or add permissions" ;;
  .claude/hooks/*|*/.claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  .claude/agents/*|*/.claude/agents/*) reason="agent definition — editing it can alter subagent tool access/behavior" ;;
  .mcp.json|*/.mcp.json) reason="MCP server config — editing it can register a malicious/exfiltrating server" ;;
  .claude/harness.json|*/.claude/harness.json|.claude/verify-harness.sh|*/.claude/verify-harness.sh|.claude/regen-harness.sh|*/.claude/regen-harness.sh|.claude/ci-gates.sh|*/.claude/ci-gates.sh) reason="harness integrity or CI gate script — an edit can defeat drift detection" ;;
  scripts/check-docs.sh|*/scripts/check-docs.sh|scripts/test-budget.sh|*/scripts/test-budget.sh) reason="seeded gate script — an edit can defeat the docs or test-budget gate" ;;
  .claude/dep-audit-allow.txt|*/.claude/dep-audit-allow.txt) reason="dependency-audit allowlist — an edit can suppress a known vulnerability" ;;
  .claude/.harness-base/*|*/.claude/.harness-base/*) reason="merge base snapshot — editing it can poison harness re-sync merges" ;;
  Dockerfile|*/Dockerfile) reason="container image definition" ;;
  lefthook.yml|*/lefthook.yml|.gitleaks.toml|*/.gitleaks.toml) reason="git-hook enforcement config — editing it can weaken commit-time guards" ;;
  .claude/comment-hygiene-patterns.txt|*/.claude/comment-hygiene-patterns.txt) reason="comment-hygiene pattern list — an edit can weaken the CI gate" ;;
  .lefthook/*|*/.lefthook/*) reason="git-hook script — editing it can weaken commit-time guards" ;;
  .github/workflows/*|.github/actions/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*) reason="CI/CD pipeline definition — changes skip or weaken the merge gates" ;;
esac
if [[ -z "$reason" && ( "$base" == azure-pipelines*.yml || "$base" == azure-pipelines*.yaml \
   || "$base" == ".gitlab-ci.yml" || "$base" == "Jenkinsfile" ) ]]; then
  reason="CI/CD pipeline definition — changes skip or weaken the merge gates"
fi
if [ -n "$reason" ]; then
  # Emit "ask": exit 1 on PreToolUse never blocks, and runtime-built JSON cannot be broken by a hostile path.
  node -e 'const cp=s=>Array.from(s),head="PROTECTED FILE: ",tail=" — "+process.argv[2]+". Human approval needed.";let a=cp(process.argv[1]);const room=Math.max(0,200-cp(head).length-cp(tail).length);if(a.length>room){const k=Math.max(0,room-1),h=Math.ceil(k/2);a=a.slice(0,h).concat(["…"],a.slice(a.length-(k-h)))}process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:cp(head+a.join("")+tail).slice(0,200).join("")}})+"\n")' "$rel" "$reason" \
    || { echo "BLOCKED: $(shortp "$rel" 80) is protected ($reason) and the approval prompt could not be built." >&2; exit 2; }
  exit 0
fi
exit 0
