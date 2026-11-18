#!/usr/bin/env bash
# Harness live check: prove the seeded harness is wired in a project, not only present. Read-only.
# Usage: harness-live.sh <project-dir>
# Prints PASS or FAIL per item; exits 1 when any item fails, 2 on a usage error. It reads no environment or key file.
# Needs bash 3.2+, git, and python3 or node to read .claude/settings.json.
set -u

[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: harness-live.sh <project-dir>" >&2; exit 2; }
P=$(cd "$1" && pwd -P) || exit 2

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a tool from the project first, then PATH.
resolve() {
  local d
  for d in node_modules/.bin .venv/bin; do
    [ -x "$P/$d/$1" ] && { echo "$P/$d/$1"; return 0; }
  done
  command -v "$1"
}

# settings_hooks: one "<event> <command> <first-arg>" line per registered hook; command is ARRAY when not a string.
settings_hooks() {
  if have python3; then
    python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for ev, groups in d.get("hooks", {}).items():
    for g in groups:
        for h in g.get("hooks", []):
            c = h.get("command"); a = h.get("args") or [""]
            print(ev, c if isinstance(c, str) else "ARRAY", a[0])
PY
  elif have node; then
    node - "$P/.claude/settings.json" <<'JS'
const d = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
for (const [ev, groups] of Object.entries(d.hooks || {}))
  for (const g of groups) for (const h of g.hooks || []) {
    const a = h.args && h.args.length ? h.args[0] : "";
    console.log(ev, typeof h.command === "string" ? h.command : "ARRAY", a);
  }
JS
  else return 3; fi
}

# 1. lefthook binary, config and wired git hooks
lh=$(resolve lefthook)
if [ -n "$lh" ]; then pass "lefthook binary ($lh)"; else fail "lefthook binary" "not in node_modules/.bin, .venv/bin or PATH"; fi
if [ -f "$P/lefthook.yml" ]; then
  if git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hooks_dir=$(git -C "$P" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)
    for h in pre-commit commit-msg pre-push; do
      grep -Eq "^$h:" "$P/lefthook.yml" || continue
      if [ -f "$hooks_dir/$h" ] && grep -qi lefthook "$hooks_dir/$h"; then pass "git hook $h wired to lefthook"
      else fail "git hook $h" "lefthook.yml defines it but $hooks_dir/$h does not call lefthook; run lefthook install"; fi
    done
  else fail "git hooks" "not a git repository"; fi
else fail "lefthook.yml" "missing"; fi

# 2. gitleaks and its config
gl=$(resolve gitleaks)
if [ -n "$gl" ]; then pass "gitleaks binary ($gl)"; else fail "gitleaks binary" "not resolvable; install it"; fi
if [ -f "$P/.gitleaks.toml" ]; then pass ".gitleaks.toml present"; else fail ".gitleaks.toml" "missing"; fi

# 3. agent hooks: seeded, executable when run as scripts, registered in settings.json in exec form
if [ -f "$P/.claude/settings.json" ]; then
  reg=$(settings_hooks) || reg=FAILED
  if [ "$reg" = FAILED ]; then fail ".claude/settings.json" "unreadable, or neither python3 nor node is available"; reg=; fi
  if printf '%s\n' "$reg" | grep -q ' ARRAY '; then fail "settings.json hooks" "an array-valued command never runs; use exec form (command + args)"; fi
  for name in protect-files block-no-verify user-prompt-guard post-edit-typecheck post-edit-comment-check stop-checks subagent-stop session-context skill-usage-log; do
    file=$(find "$P/.claude/hooks" -maxdepth 1 -name "$name.*" 2>/dev/null | head -1)
    if [ -z "$file" ]; then fail "hook $name" "script missing under .claude/hooks"; continue; fi
    case "$file" in
      *.sh) [ -x "$file" ] || { fail "hook $name" "$(basename "$file") is not executable"; continue; } ;;
    esac
    want="/.claude/hooks/$(basename "$file")"
    if printf '%s\n' "$reg" | awk -v w="$want" '{ n = length($NF) - length(w) + 1; if (n > 0 && substr($NF, n) == w) f = 1 } END { exit !f }'; then pass "hook $name executable and registered"
    else fail "hook $name" "not registered in .claude/settings.json"; fi
  done
else fail ".claude/settings.json" "missing"; fi

# 4. CI workflow runs the gates
ci=()
for f in "$P"/.github/workflows/*.yml "$P"/.github/workflows/*.yaml "$P"/azure-pipelines.yml "$P"/azure-pipelines/*.yml; do
  [ -f "$f" ] && ci+=("$f")
done
if [ "${#ci[@]}" -eq 0 ]; then fail "CI workflow" "no .github/workflows or azure-pipelines file"
else
  if grep -qs 'ci-gates.sh' "${ci[@]}"; then pass "CI runs .claude/ci-gates.sh"; else fail "CI gates" "no workflow runs .claude/ci-gates.sh"; fi
  if grep -qs 'verify-harness.sh' "${ci[@]}"; then pass "CI runs .claude/verify-harness.sh"; else fail "CI harness check" "no workflow runs .claude/verify-harness.sh"; fi
fi
[ -f "$P/.claude/ci-gates.sh" ] || fail ".claude/ci-gates.sh" "missing"

if [ "$FAILS" -gt 0 ]; then echo "FAIL: $FAILS item(s) not live."; exit 1; fi
echo "OK: harness is live."
