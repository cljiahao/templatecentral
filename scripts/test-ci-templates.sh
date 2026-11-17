#!/usr/bin/env bash
# scripts/test-ci-templates.sh — regression tests for the seeded CI templates (skills/scaffold/shared/template-ci):
#   1. every multi-line `bash: |` / `run: |` block starts with `set -euo pipefail` (Azure `bash:` reports only the
#      last command's status; without it an earlier failure is swallowed);
#   2. the Azure shard-count assertion really fails when a shard report is missing.
# Usage: bash scripts/test-ci-templates.sh   (needs bash, python3)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_DIR="$REPO_ROOT/skills/scaffold/shared/template-ci"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1" >&2; fail=1; }

# 1. set -euo pipefail at the top of every multi-line script block
while IFS= read -r f; do
  out=$(python3 - "$f" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
for i, line in enumerate(lines):
    m = re.match(r"^(\s*)(?:- )?(?:bash|script|run):\s*\|\s*$", line)
    if not m:
        continue
    body = next((l for l in lines[i + 1:] if l.strip()), "")
    if body.strip() != "set -euo pipefail":
        print(f"{sys.argv[1]}:{i + 1}: multi-line script block must start with `set -euo pipefail`")
PY
)
  if [[ -n "$out" ]]; then bad "$out"; else ok "strict shell: ${f#"$REPO_ROOT"/}"; fi
done < <(find "$CI_DIR" -type f \( -name 'azure-pipelines.yml' -o -name 'ci.yml' \) | sort)

# 2. Azure shard assertion: extract the step script, run it with a shard report missing
PIPE="$CI_DIR/azure-ts/azure-pipelines.yml"
python3 - "$PIPE" "$T/assert.sh" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
idx = next(i for i, l in enumerate(lines) if l.strip() == "displayName: Assert all shard reports present")
start = max(i for i in range(idx) if re.match(r"^\s*- bash: \|\s*$", lines[i]))
body = lines[start + 1:idx]
indent = len(body[0]) - len(body[0].lstrip())
text = "\n".join(l[indent:] for l in body) + "\n"
open(sys.argv[2], "w").write(text.replace("$(shardCount)", "2"))
PY
mkdir -p "$T/run/blob"
echo '[]' > "$T/run/blob/a.json"
rc=0; ( cd "$T/run" && bash "$T/assert.sh" ) >"$T/missing.log" 2>&1 || rc=$?
if [[ $rc -ne 0 ]]; then ok "azure assertion fails with a missing shard (exit $rc)"; else bad "azure assertion passed with one of two shard reports missing"; fi
echo '[]' > "$T/run/blob/b.json"
rc=0; ( cd "$T/run" && bash "$T/assert.sh" ) >"$T/full.log" 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then ok "azure assertion passes with all shards"; else bad "azure assertion failed with all shard reports present"; fi

# 3. Azure collect step: cp with no matching blob must fail the step
python3 - "$PIPE" "$T/collect.sh" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
idx = next(i for i, l in enumerate(lines) if l.strip() == "displayName: Collect shard reports")
start = max(i for i in range(idx) if re.match(r"^\s*- bash: \|\s*$", lines[i]))
body = lines[start + 1:idx]
indent = len(body[0]) - len(body[0].lstrip())
text = "\n".join(l[indent:] for l in body) + "\n"
open(sys.argv[2], "w").write(text.replace("$(Pipeline.Workspace)", "$WS"))
PY
mkdir -p "$T/ws/blobs/vitest-blob-1" "$T/empty"
rc=0; ( cd "$T/empty" && WS="$T/ws" bash "$T/collect.sh" ) >"$T/collect-none.log" 2>&1 || rc=$?
if [[ $rc -ne 0 ]]; then ok "azure collect step fails when no blob matches (exit $rc)"; else bad "azure collect step passed with no blob"; fi
echo '[]' > "$T/ws/blobs/vitest-blob-1/a.json"
rm -rf "$T/empty" && mkdir -p "$T/empty"
rc=0; ( cd "$T/empty" && WS="$T/ws" bash "$T/collect.sh" ) >"$T/collect-ok.log" 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then ok "azure collect step passes with a blob"; else bad "azure collect step failed with a blob present"; fi

[[ $fail -eq 0 ]] && echo "test-ci-templates: all passed" || { echo "test-ci-templates: failures" >&2; exit 1; }
