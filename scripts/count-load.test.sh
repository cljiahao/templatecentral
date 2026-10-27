#!/usr/bin/env bash
# scripts/count-load.test.sh — tests for scripts/count-load.sh.
# Usage: bash scripts/count-load.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT="$REPO_ROOT/scripts/count-load.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# baseline_matches_spec: with-docs totals within 1% of the figures measured on v6.1.2.
# Run against the v6.1.2 tree, so the check stays valid after the scaffold shrinks.
json=$(bash "$COUNT" --json --base v6.1.2 2>/dev/null)
verdict=$(python3 - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
spec = {"nextjs": 57200, "vite-react": 54400, "fastapi": 51200, "nestjs": 50200}
bad = []
for stack, want in spec.items():
    got = data[stack].get("base_total_with_docs")
    if got is None or abs(got - want) / want > 0.01:
        bad.append(f"{stack}={got} want~{want}")
print("ok" if not bad else "; ".join(bad))
PY
)
check ok "$verdict" "baseline_matches_spec"

# the file list is parsed, not hard-coded: every stack loads its own source-files.md and the docs kit
for stack in nextjs vite-react fastapi nestjs; do
  has=$(python3 - "$json" "$stack" <<'PY'
import json, sys
d = json.loads(sys.argv[1])[sys.argv[2]]
f = d["files"]
need = [f"skills/scaffold/{sys.argv[2]}/source-files.md", "skills/scaffold/shared/documentation-kit.md", "skills/scaffold/shared/harness-kit-finalize.md"]
print("yes" if all(n in f for n in need) and d["utilities_total"] > 0 else "no")
PY
)
  check yes "$has" "file list parsed for $stack"
done

# the counter only warns
bash "$COUNT" > /dev/null 2>&1; check 0 $? "exit code is 0"
out=$(bash "$COUNT" --base v6.1.2 2>/dev/null)
case "$out" in *"delta vs v6.1.2"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: --base adds delta column" ;; esac

# a --base ref without a scaffold skill warns on stderr and still exits 0
first=$(git -C "$REPO_ROOT" rev-list --max-parents=0 HEAD | head -1)
warn=$(bash "$COUNT" --base "$first" 2>&1 >/dev/null); ec=$?
check 0 "$ec" "base_without_skill: exit code is 0"
case "$warn" in *"SKILL.md not found"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: base_without_skill warns [$warn]" ;; esac

echo "count-load.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
