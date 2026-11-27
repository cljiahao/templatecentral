#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): block secrets and certs, ask before CI and governance edits; fails closed.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || { echo "BLOCKED: protect-files.sh cannot cd to the project root — refusing the write." >&2; exit 2; }
input=$(cat)
file=$(printf '%s' "$input" | python3 -I -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('notebook_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
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
  .claude/agents/code-reviewer.md|*/.claude/agents/code-reviewer.md) reason="review gate reviewer definition — an edit can weaken the review the push gate relies on" ;;
  .claude/agents/*|*/.claude/agents/*) reason="agent definition — editing it can alter subagent tool access/behavior" ;;
  .mcp.json|*/.mcp.json) reason="MCP server config — editing it can register a malicious/exfiltrating server" ;;
  .claude/harness.json|*/.claude/harness.json|.claude/verify-harness.sh|*/.claude/verify-harness.sh|.claude/regen-harness.sh|*/.claude/regen-harness.sh|.claude/ci-gates.sh|*/.claude/ci-gates.sh|.claude/gate-budget.sh|*/.claude/gate-budget.sh|.claude/gates.txt|*/.claude/gates.txt) reason="harness integrity or CI gate script — an edit can defeat drift detection" ;;
  vitest.config.*|*/vitest.config.*|vite.config.*|*/vite.config.*|eslint.config.*|*/eslint.config.*|pyproject.toml|*/pyproject.toml|.jscpd.json|*/.jscpd.json|vitest.workspace.*|*/vitest.workspace.*|sonar-project.properties|*/sonar-project.properties) reason="coverage, lint, Sonar or duplication config — a lower threshold or a wider exclude hides untested or unchecked code; the ratchet gate reports it" ;;
  tsconfig.json|*/tsconfig.json|tsconfig.*.json|*/tsconfig.*.json|pyrightconfig.json|*/pyrightconfig.json) reason="type-check config — loosening strictness hides type errors; the ratchet gate reports it" ;;
  pnpm-workspace.yaml|*/pnpm-workspace.yaml|.npmrc|*/.npmrc|.github/dependabot.yml|*/.github/dependabot.yml|.hadolint.yaml|*/.hadolint.yaml|.hadolint.yml|*/.hadolint.yml) reason="supply-chain or lint config — an edit can shorten the release-age wait, allow install scripts, change the registry or silence a Dockerfile rule" ;;
  .claude/registry-hosts.txt|*/.claude/registry-hosts.txt) reason="registry host allow-list — adding a host lets a lockfile pull packages from it" ;;
  .claude/dep-audit-allow.txt|*/.claude/dep-audit-allow.txt) reason="dependency-audit allowlist — an edit can suppress a known vulnerability" ;;
  .claude/gate-baseline.txt|*/.claude/gate-baseline.txt) reason="gate baseline — an edit can hide known findings from the lint and type gates" ;;
  scripts/gate-baseline.sh|*/scripts/gate-baseline.sh) reason="gate baseline helper — an edit can make the gates pass without checking" ;;
  .claude/allowed-licences.txt|*/.claude/allowed-licences.txt|.claude/licence-exceptions.txt|*/.claude/licence-exceptions.txt) reason="licence allow-list — adding a line lets a dependency with that licence ship" ;;
  .claude/change-size-exclude.txt|*/.claude/change-size-exclude.txt) reason="change-size exclude list — a line stops the matching files counting toward the review size budget" ;;
  scripts/check-comments.mjs|*/scripts/check-comments.mjs|scripts/check-comments.py|*/scripts/check-comments.py|scripts/check-comments.licences.txt|*/scripts/check-comments.licences.txt) reason="comment gate helper or licence text list — an edit can let a long or disabled comment pass" ;;
  scripts/duplicate-tests-ts.mjs|*/scripts/duplicate-tests-ts.mjs|scripts/duplicate_tests_py.py|*/scripts/duplicate_tests_py.py) reason="duplicate-test gate helper — an edit can hide a copied test" ;;
  scripts/check-exclude-rules.sh|*/scripts/check-exclude-rules.sh|scripts/check-exclude-reasons.awk|*/scripts/check-exclude-reasons.awk|scripts/check-exclude-reasons.mjs|*/scripts/check-exclude-reasons.mjs|scripts/check-exclude-reasons.py|*/scripts/check-exclude-reasons.py) reason="exclude-reason gate helper — an edit can let an exclude pass without a reason" ;;
  .claude/bundle-budget.txt|*/.claude/bundle-budget.txt) reason="bundle-size budget — raising it lets the shipped bundle grow" ;;
  .claude/.harness-base/*|*/.claude/.harness-base/*) reason="merge base snapshot — editing it can poison harness re-sync merges" ;;
  Dockerfile|*/Dockerfile) reason="container image definition" ;;
  lefthook.yml|*/lefthook.yml|.gitleaks.toml|*/.gitleaks.toml) reason="git-hook enforcement config — editing it can weaken commit-time guards" ;;
  .claude/comment-hygiene-patterns.txt|*/.claude/comment-hygiene-patterns.txt) reason="comment-hygiene pattern list — an edit can weaken the CI gate" ;;
  .lefthook/*|*/.lefthook/*|.hus[k]y/*|*/.hus[k]y/*) reason="git-hook script — editing it can weaken commit-time guards" ;;
  .github/workflows/*|.github/actions/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*) reason="CI/CD pipeline definition — changes skip or weaken the merge gates" ;;
esac
# Gate scripts and runners are whatever gate-ratchet.sh --list-guarded derives from the tracked tree, run from the project folder or else the git top level; nothing is listed here.
if [[ -z "$reason" ]]; then
  case "$rel" in
    scripts/* | */scripts/* | .claude/* | */.claude/*)
      if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
        gdir=$root
        if [ ! -f scripts/gate-ratchet.sh ]; then gdir=$(cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P); fi
        if guarded=$(cd "$gdir" 2>/dev/null && bash scripts/gate-ratchet.sh --list-guarded HEAD 2>/dev/null) && [ -n "$guarded" ]; then
          if printf '%s\n' "$guarded" | awk -F'\t' -v p="${abs#"$gdir"/}" '$2 == p { hit = 1 } END { exit !hit }'; then reason="gate script or runner the ratchet guards — an edit can defeat a merge gate"; fi
        else
          reason="the guarded set cannot be derived (scripts/gate-ratchet.sh failed or is missing) — approve each edit here"
        fi
      fi
      ;;
  esac
fi
if [[ -z "$reason" && ( "$base" == azure-pipelines*.yml || "$base" == azure-pipelines*.yaml \
   || "$base" == ".gitlab-ci.yml" || "$base" == "Jenkinsfile" ) ]]; then
  reason="CI/CD pipeline definition — changes skip or weaken the merge gates"
fi
if [ -n "$reason" ]; then
  # Emit "ask": exit 1 on PreToolUse never blocks, and runtime-built JSON cannot be broken by a hostile path.
  python3 -I -c 'import json,sys,os; d=lambda s: os.fsencode(s).decode("utf-8","replace"); head="PROTECTED FILE: "; tail=" — "+d(sys.argv[2])+". Human approval needed."; a=d(sys.argv[1]); room=max(0,200-len(head)-len(tail)); k=max(0,room-1); h=-(-k//2); a=a if len(a)<=room else a[:h]+"…"+(a[len(a)-(k-h):] if k>h else ""); print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":(head+a+tail)[:200]}}))' "$rel" "$reason" \
    || { echo "BLOCKED: $(shortp "$rel" 80) is protected ($reason) and the approval prompt could not be built." >&2; exit 2; }
  exit 0
fi
exit 0
