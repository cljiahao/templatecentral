#!/usr/bin/env bash
# Behavioural test for skills/migrate/general/harness-live.sh.
# Seeds a fixture project from the real template trees, with fake lefthook and gitleaks binaries.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/skills/migrate/general/harness-live.sh"
SH="$ROOT/skills/scaffold/shared"
T=$(mktemp -d "${TMPDIR:-/tmp}/livetest.XXXXXX") || exit 1
trap '[ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in output"; fail=1 ;; esac; }

mkdir -p "$T/bin"
for b in lefthook gitleaks; do printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/$b"; chmod +x "$T/bin/$b"; done
LIVEPATH="$T/bin:/usr/bin:/bin"

# seed <dir>: a fully seeded, wired project
seed() {
  local d=$1
  mkdir -p "$d/.claude/hooks" "$d/.lefthook" "$d/.github/workflows"
  cp -p "$SH"/template/.claude/hooks/* "$SH"/template-ts/.claude/hooks/* "$d/.claude/hooks/"
  cp -p "$SH"/template/.claude/ci-gates.sh "$SH"/template/.claude/verify-harness.sh "$d/.claude/"
  cp "$SH/template-settings-ts/.claude/settings.json" "$d/.claude/settings.json"
  cp "$SH/template-ts/lefthook.yml" "$d/lefthook.yml"
  cp "$SH/template/.gitleaks.toml" "$d/.gitleaks.toml"
  cp "$SH/template-ci/github-ts/.github/workflows/ci.yml" "$d/.github/workflows/ci.yml"
  (cd "$d" && git init -q && printf '#!/bin/sh\nlefthook run pre-commit\n' >.git/hooks/pre-commit \
    && printf '#!/bin/sh\nlefthook run commit-msg\n' >.git/hooks/commit-msg && printf '#!/bin/sh\nlefthook run pre-push\n' >.git/hooks/pre-push \
    && chmod +x .git/hooks/pre-commit .git/hooks/commit-msg .git/hooks/pre-push)
}
run() { PATH="$LIVEPATH" bash "$SCRIPT" "$1" 2>&1; }

bash "$SCRIPT" >/dev/null 2>&1; check "no arguments exits 2" 2 $?
bash "$SCRIPT" "$T/nope" >/dev/null 2>&1; check "missing directory exits 2" 2 $?

# an unseeded project fails on every group
mkdir -p "$T/bare" && (cd "$T/bare" && git init -q)
out=$(run "$T/bare"); check "unseeded project exits 1" 1 $?
contains "unseeded: settings missing" "FAIL .claude/settings.json" "$out"
contains "unseeded: lefthook.yml missing" "FAIL lefthook.yml" "$out"
contains "unseeded: no CI" "FAIL CI workflow" "$out"

seed "$T/ok"
out=$(run "$T/ok"); check "seeded project exits 0" 0 $?
contains "seeded: all hooks registered" "PASS hook stop-checks executable and registered" "$out"
contains "seeded: user-prompt-guard needs no exec bit" "PASS hook user-prompt-guard executable and registered" "$out"
contains "seeded: summary" "OK: harness is live." "$out"
check "seeded project has no FAIL line" 0 "$(printf '%s\n' "$out" | grep -c '^FAIL')"

# each miss is reported and exits 1
seed "$T/m1"; rm -f "$T/m1/.git/hooks/pre-commit"
out=$(run "$T/m1"); check "unwired git hook exits 1" 1 $?
contains "unwired git hook named" "FAIL git hook pre-commit" "$out"

seed "$T/m2"; printf '#!/bin/sh\nexit 0\n' >"$T/m2/.git/hooks/commit-msg"
out=$(run "$T/m2"); check "git hook that skips lefthook exits 1" 1 $?
contains "git hook without lefthook named" "FAIL git hook commit-msg" "$out"

seed "$T/m3"; chmod -x "$T/m3/.claude/hooks/stop-checks.sh"
out=$(run "$T/m3"); check "non-executable hook exits 1" 1 $?
contains "non-executable hook named" "FAIL hook stop-checks" "$out"

seed "$T/m4"; rm "$T/m4/.claude/hooks/subagent-stop.sh"
out=$(run "$T/m4"); check "missing hook exits 1" 1 $?
contains "missing hook named" "FAIL hook subagent-stop: script missing" "$out"

seed "$T/m5"; sed -i.bak 's#session-context.sh#session-context.sh.gone#' "$T/m5/.claude/settings.json"; rm "$T/m5/.claude/settings.json.bak"
out=$(run "$T/m5"); check "unregistered hook exits 1" 1 $?
contains "unregistered hook named" "FAIL hook session-context: not registered" "$out"

seed "$T/m6"; python3 - "$T/m6/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
h = d["hooks"]["Stop"][0]["hooks"][0]; h["command"] = ["bash", h["args"][0]]
json.dump(d, open(p, "w"))
PY
out=$(run "$T/m6"); check "array-form command exits 1" 1 $?
contains "array-form command named" "FAIL settings.json hooks" "$out"

seed "$T/m7"
out=$(PATH="/usr/bin:/bin" bash "$SCRIPT" "$T/m7" 2>&1); check "missing lefthook and gitleaks exits 1" 1 $?
contains "missing lefthook named" "FAIL lefthook binary" "$out"
contains "missing gitleaks named" "FAIL gitleaks binary" "$out"

seed "$T/m8"; : >"$T/m8/.github/workflows/ci.yml"
out=$(run "$T/m8"); check "CI without gates exits 1" 1 $?
contains "CI without ci-gates named" "FAIL CI gates" "$out"
contains "CI without verify-harness named" "FAIL CI harness check" "$out"

seed "$T/m9"; rm -rf "$T/m9/.git"
out=$(run "$T/m9"); check "not a git repository exits 1" 1 $?
contains "not a git repository named" "FAIL git hooks: not a git repository" "$out"

# read-only: no write into the project, and the script never names an env or secret file
seed "$T/ro"; (cd "$T/ro" && git add -A && git -c user.email=t@t -c user.name=t commit -q --no-verify -m init)
before=$(cd "$T/ro" && find . -path ./.git -prune -o -type f -newer "$T/ro/lefthook.yml" -print | sort | tr '\n' ' ')
run "$T/ro" >/dev/null
after=$(cd "$T/ro" && find . -path ./.git -prune -o -type f -newer "$T/ro/lefthook.yml" -print | sort | tr '\n' ' ')
check "the run writes nothing into the project" "$before" "$after"
check "git status stays clean" 0 "$(cd "$T/ro" && git status --porcelain | wc -l | tr -d ' ')"
check "the script names no env or secret file" 0 "$(grep -cE '\.env|\.pem|secrets' "$SCRIPT")"

exit $fail
