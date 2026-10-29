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

# The spec baseline is read from this tag; a checkout without it cannot run the test.
BASELINE_REF="${COUNT_LOAD_BASELINE_REF:-v6.1.2}"
if ! git -C "$REPO_ROOT" rev-parse --verify -q "$BASELINE_REF^{commit}" > /dev/null; then
  echo "count-load.test: environment error: git ref $BASELINE_REF not found; fetch full history and tags (CI: fetch-depth 0 and fetch-tags true; locally: git fetch --tags)" >&2
  exit 2
fi

# baseline_matches_spec: with-docs totals within 1% of the figures measured on v6.1.2.
# Run against the v6.1.2 tree, so the check stays valid after the scaffold shrinks.
json=$(bash "$COUNT" --json --base "$BASELINE_REF" 2>/dev/null)
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
out=$(bash "$COUNT" --base "$BASELINE_REF" 2>/dev/null)
case "$out" in *"delta vs $BASELINE_REF"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: --base adds delta column" ;; esac

# a --base ref without a scaffold skill warns on stderr and still exits 0
first=$(git -C "$REPO_ROOT" mktree < /dev/null)
warn=$(bash "$COUNT" --base "$first" 2>&1 >/dev/null); ec=$?
check 0 "$ec" "base_without_skill: exit code is 0"
case "$warn" in *"SKILL.md not found"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: base_without_skill warns [$warn]" ;; esac

# --entry: one invocation of add, migrate or standards, parsed from the cat lines and the router rules
entry_json() { bash "$COUNT" --json "$@" 2>/dev/null; }
entry_check() { # entry_check <json> <spec> <python expression over d (the entry), f (its files), u (its utilities)>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
d = json.loads(sys.argv[1])[sys.argv[2]]
f, u = d["files"], d["utilities"]
print("yes" if eval(sys.argv[3]) else "no")
PY
}
j=$(entry_json --entry add:auth/nestjs)
check yes "$(entry_check "$j" add:auth/nestjs '"skills/add/SKILL.md" in f and "skills/add/auth/nestjs.md" in f and "skills/add/auth/fastapi.md" not in f')" "add auth leaf loads SKILL.md and its own leaf only"
check yes "$(entry_check "$j" add:auth/nestjs '"skills/build/SKILL.md" in u and "skills/review/SKILL.md" in u')" "add auth leaf follows the build and review cats as utilities"
check yes "$(entry_check "$j" add:auth/nestjs 'd["total_tokens"] > d["skill_tokens"] > 0 and d["skill_tokens"] == round(sum(v["bytes"] for v in f.values()) / 4)')" "entry totals are bytes/4"
j=$(entry_json --entry add:database/typescript/nestjs-kysely --entry add:database/python/sqlalchemy)
check yes "$(entry_check "$j" add:database/typescript/nestjs-kysely '"skills/add/database/typescript.md" in f and "skills/add/database/typescript/nestjs-drizzle.md" not in f')" "add database leaf loads its router, not the sibling leaves"
check yes "$(entry_check "$j" add:database/python/sqlalchemy '"skills/add/database/python.md" in f and "skills/add/database/python/beanie.md" not in f')" "add python database leaf loads its router"
j=$(entry_json --entry standards:code-standards/nextjs --entry standards:validation-patterns/nestjs)
check yes "$(entry_check "$j" standards:code-standards/nextjs '"skills/standards/code-standards/comments.md" in f and "skills/standards/code-standards/nextjs.md" in f')" "standards code-standards loads comments.md first"
check yes "$(entry_check "$j" standards:validation-patterns/nestjs '"skills/standards/validation-patterns/patterns.md" in f')" "standards validation-patterns loads patterns.md"
j=$(entry_json --entry migrate:general/phase-4-upgrade --entry migrate:general/implementation --entry migrate:nextjs-backend-extraction/nestjs --entry migrate:portal-frame-ancestors --entry migrate:portal-frame-ancestors@fastapi)
check yes "$(entry_check "$j" migrate:general/phase-4-upgrade '"skills/migrate/general/implementation.md" in f and "skills/migrate/general/phase-4-upgrade.md" in f and "skills/migrate/general/phase-5-health-check.md" not in f')" "migrate phase leaf loads the router without following its cat lines"
check yes "$(entry_check "$j" migrate:general/implementation '"skills/migrate/general/phase-5-health-check.md" in f and "skills/scaffold/shared/harness-kit.md" in u')" "migrate general/implementation follows its own cat lines"
check yes "$(entry_check "$j" migrate:nextjs-backend-extraction/nestjs '"skills/migrate/nextjs-backend-extraction/common.md" in f and not any(p.startswith("skills/add/") for p in list(f) + list(u))')" "migrate extraction follows common.md and no add leaf"
check yes "$(entry_check "$j" migrate:portal-frame-ancestors '"skills/scaffold/fastapi/source-files.md" not in u and "skills/scaffold/nextjs/template/src/proxy.ts" in u')" "<stack> cat lines are skipped without @STACK"
check yes "$(entry_check "$j" migrate:portal-frame-ancestors@fastapi '"skills/scaffold/fastapi/source-files.md" in u')" "@STACK fills <stack>"

# --summary lists every leaf of the skill and no router
for skill in add migrate standards; do
  want=$(cd "$REPO_ROOT/skills/$skill" && find . -name '*.md' ! -path ./SKILL.md | while IFS= read -r f; do [[ -d "${f%.md}" ]] || echo "$f"; done | wc -l | tr -d ' ')
  got=$(bash "$COUNT" --summary "$skill" 2>/dev/null | grep -c "^$skill:[^@ ]*[[:space:]]")
  check "$want" "$got" "summary lists every $skill leaf"
done
sum=$(bash "$COUNT" --summary add 2>/dev/null)
case "$sum" in *"add:auth/nestjs "*"add:database/typescript/nestjs-kysely "*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: summary names add leaves" ;; esac
case "$sum" in *"add:database/typescript "*) FAIL=$((FAIL + 1)); echo "FAIL: summary lists a router" ;; *) PASS=$((PASS + 1)) ;; esac
all=$(bash "$COUNT" --summary all 2>/dev/null)
case "$all" in *"migrate:general/phase-4-upgrade "*"standards:code-standards/nextjs "*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: summary all spans the three skills" ;; esac

# --entry with --base: the delta column against the baseline tag
out=$(bash "$COUNT" --entry add:auth/nestjs --base "$BASELINE_REF" 2>/dev/null)
case "$out" in *"delta vs $BASELINE_REF"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: --entry --base adds a delta line" ;; esac
j=$(entry_json --entry add:auth/nestjs --base "$BASELINE_REF")
check yes "$(entry_check "$j" add:auth/nestjs 'd["base_total_tokens"] > 0 and d["delta_tokens"] == d["total_tokens"] - d["base_total_tokens"]')" "--entry --base json carries base total and delta"
out=$(bash "$COUNT" --summary standards --base "$BASELINE_REF" 2>/dev/null)
case "$out" in *"vs $BASELINE_REF"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: --summary --base adds a delta column" ;; esac

# a bad or missing entry warns on stderr, prints nothing for it and exits 0
warn=$(bash "$COUNT" --entry add:nope/none --entry bogus 2>&1 >/dev/null); ec=$?
check 0 "$ec" "bad_entry: exit code is 0"
case "$warn" in *"not found"*"bad entry bogus"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: bad_entry warns [$warn]" ;; esac

echo "count-load.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
