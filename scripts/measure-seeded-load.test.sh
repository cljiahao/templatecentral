#!/usr/bin/env bash
# scripts/measure-seeded-load.test.sh — tests for scripts/measure-seeded-load.sh.
# Usage: bash scripts/measure-seeded-load.test.sh
set -uo pipefail
export TC_TEST=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/measure-seeded-load.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/measure-load-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# fresh_root <name>: a copy of the scaffold tree to plant files in.
fresh_root() {
  mkdir -p "$T/$1/skills"
  cp -Rp "$REPO_ROOT/skills/scaffold" "$T/$1/skills/scaffold"
}

# run <root>: exit code and output of the measure script against that root.
run() { OUT=$(bash "$MEASURE" --root "$1" 2>&1); EC=$?; }

run "$REPO_ROOT"
check 0 "$EC" "the repository is within budget"
check 4 "$(printf '%s\n' "$OUT" | grep -c '^[a-z-]* *CLAUDE ')" "one table row per stack"

fresh_root big
printf '%s\n' "$(python3 -c 'print("Filler words that bloat the always-loaded file. " * 120)')" >> "$T/big/skills/scaffold/nextjs/template-agents/AGENTS.md"
run "$T/big"
check 1 "$EC" "an over-budget AGENTS.md fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: nextjs: always-loaded')" "the over-budget stack is named"

fresh_root dup
SENT="Every migration needs a rollback plan written before the first deploy."
printf '\n%s\n' "$SENT" >> "$T/dup/skills/scaffold/vite-react/template-agents/AGENTS.md"
python3 - "$T/dup/skills/scaffold/vite-react/template/.claude/skills/vite-verify/SKILL.md.tmpl" "$SENT" <<'PY'
import re, sys
p, s = sys.argv[1:]
t = open(p).read()
open(p, "w").write(re.sub(r"^description:.*$", lambda m: "description: " + s + " " + m.group(0)[len("description:"):].lstrip(), t, count=1, flags=re.M))
PY
run "$T/dup"
check 1 "$EC" "a sentence in two always-loaded files fails"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'FAIL: vite-react: sentence in')" "the duplicated sentence is reported"

echo "measure-seeded-load.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
