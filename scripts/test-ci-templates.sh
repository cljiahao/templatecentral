#!/usr/bin/env bash
# scripts/test-ci-templates.sh — regression tests for the seeded CI templates (skills/scaffold/shared/template-ci):
#   1. every multi-line `bash: |` / `run: |` block starts with `set -euo pipefail` (Azure `bash:` reports only the
#      last command's status; without it an earlier failure is swallowed);
#   2. the Azure and GitHub shard-count assertions really fail when a shard report is missing;
#   3. no gate step can be neutralised (`|| true`, continue-on-error, always()/succeededOrFailed(), if/condition), and
#      every template keeps its merge command and `diff-cover --fail-under=80` unguarded;
#   4. each of those static checks and the GitHub assertion is proven by mutating a copy of the templates.
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


# 4. GitHub shard assertion: extract the one-line `run:` of the step, run it with a shard report missing
gh_assert() { # gh_assert <ci-dir> <out-script>
  python3 - "$1/github-ts/.github/workflows/ci.yml" "$2" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
idx = next(i for i, l in enumerate(lines) if "name: Require one blob report per shard" in l)
run = next(l for l in lines[idx + 1:idx + 4] if l.strip().startswith("run:"))
value = run.split("run:", 1)[1].strip()
if value.startswith("'") and value.endswith("'"):
    value = value[1:-1].replace("''", "'")
open(sys.argv[2], "w").write("set -euo pipefail\n" + value + "\n")
PY
}
gh_behaviour() { # gh_behaviour <ci-dir> — prints "missing=<rc> full=<rc>"
  gh_assert "$1" "$T/gh-assert.sh"
  rm -rf "$T/ghrun" && mkdir -p "$T/ghrun/blob" && echo '[]' > "$T/ghrun/blob/a.json"
  local missing=0 full=0
  ( cd "$T/ghrun" && SHARD_COUNT=2 bash "$T/gh-assert.sh" ) >/dev/null 2>&1 || missing=$?
  echo '[]' > "$T/ghrun/blob/b.json"
  ( cd "$T/ghrun" && SHARD_COUNT=2 bash "$T/gh-assert.sh" ) >/dev/null 2>&1 || full=$?
  echo "missing=$missing full=$full"
}
res=$(gh_behaviour "$CI_DIR")
if [[ "$res" =~ ^missing=[1-9][0-9]*\ full=0$ ]]; then ok "github assertion fails with a missing shard and passes with all ($res)"; else bad "github assertion behaviour wrong: $res"; fi

# 5. static guards over all four templates
cat > "$T/static.py" <<'PY'
import re, sys
root = sys.argv[1]
files = {
    "github-ts": ("github-ts/.github/workflows/ci.yml", "--merge-reports=blob --coverage"),
    "azure-ts": ("azure-ts/azure-pipelines.yml", "--merge-reports=blob --coverage"),
    "github-py": ("github-py/.github/workflows/ci.yml", "--cov=src --cov-report=xml"),
    "azure-py": ("azure-py/azure-pipelines.yml", "--cov=src --cov-report=xml"),
}
GUARD = re.compile(r"\|\|\s*(true|:)|continue-on-error|condition:|succeededOrFailed\(|\balways\(\)|\bcancelled\(\)|\bfailure\(\)")
errors = []
for host, (rel, merge) in files.items():
    lines = open(f"{root}/{rel}").read().split("\n")
    for i, l in enumerate(lines):
        code = re.sub(r"\s#\s.*$", "", l)
        if re.search(r"\|\|\s*(true|:)\s*($|['\"])|continue-on-error|succeededOrFailed\(|\balways\(\)", code):
            errors.append(f"{rel}:{i + 1}: gate-neutralising construct: {l.strip()}")
        if re.match(r"^\s*condition:\s*(always|succeededOrFailed)", l):
            errors.append(f"{rel}:{i + 1}: condition that runs after failure: {l.strip()}")
    def step_bounds(n):
        start = n
        while start > 0 and not re.match(r"^\s*- ", lines[start]):
            start -= 1
        indent = len(lines[start]) - len(lines[start].lstrip())
        end = n + 1
        while end < len(lines) and not (re.match(r"^\s*- ", lines[end]) and len(lines[end]) - len(lines[end].lstrip()) <= indent) and not re.match(r"^\s{0,2}\S", lines[end]):
            end += 1
        return start, end
    def job_has_condition(n):
        j = n
        while j > 0 and not re.match(r"^  (-\s+job:\s*\S+|[A-Za-z_-]+:)\s*$", lines[j]):
            j -= 1
        k = j + 1
        while k < len(lines) and not re.match(r"^  (-\s+job:|[A-Za-z_-]+:\s*$)", lines[k]) and not re.match(r"^\S", lines[k]):
            if re.match(r"^    (if|condition):", lines[k]) and not re.search(r"pull_request", lines[k]):
                return lines[k].strip()
            k += 1
        return None
    for what, needle in (("merge command", merge), ("diff-cover", "diff-cover")):
        hits = [i for i, l in enumerate(lines) if needle in l and not l.lstrip().startswith("#")]
        if not hits:
            errors.append(f"{rel}: missing {what} ({needle})")
            continue
        for n in hits:
            if re.search(r"\|\||;\s*\S|\bif\b.*\bthen\b", re.sub(r"\s#\s.*$", "", lines[n])):
                errors.append(f"{rel}:{n + 1}: {what} is guarded inline: {lines[n].strip()}")
            a, b = step_bounds(n)
            for k in range(a, b):
                if re.match(r"^\s*(- )?(if|condition|continueOnError):", lines[k]):
                    errors.append(f"{rel}:{k + 1}: {what} step has a run condition: {lines[k].strip()}")
            c = job_has_condition(n)
            if c:
                errors.append(f"{rel}:{n + 1}: {what} job has a run condition: {c}")
    if not any("diff-cover" in l and "--fail-under=80" in l for l in lines):
        errors.append(f"{rel}: diff-cover must run with --fail-under=80")
print("\n".join(errors))
sys.exit(1 if errors else 0)
PY
static_check() { python3 "$T/static.py" "$1"; }
if out=$(static_check "$CI_DIR" 2>&1); then ok "static guards: no gate-neutralising construct, merge and diff-cover present and unguarded"; else bad "static guards flagged the shipped templates: $out"; fi

# 6. mutation proof: each mutation of a copy must be caught
mutate() { # mutate <label> <relative file> <old text> <new text> <static|github>; \n in the texts is a newline
  local label=$1 rel=$2 kind=$5
  rm -rf "$T/mut" && cp -R "$CI_DIR" "$T/mut"
  python3 - "$T/mut/$rel" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2].replace("\\n", "\n"), sys.argv[3].replace("\\n", "\n")
s = open(p).read()
if old not in s:
    sys.exit("mutation target not found: " + old)
open(p, "w").write(s.replace(old, new))
PY
  if [[ $kind == static ]]; then
    if out=$(static_check "$T/mut" 2>&1); then bad "mutation not caught: $label"; else ok "mutation caught: $label -> $(head -1 <<<"$out")"; fi
  else
    res=$(gh_behaviour "$T/mut")
    if [[ "$res" =~ ^missing=0 ]]; then ok "mutation caught: $label -> $res"; else bad "mutation not caught: $label ($res)"; fi
  fi
}
mutate "|| true after diff-cover (github-ts)" github-ts/.github/workflows/ci.yml '--fail-under=80' '--fail-under=80 || true' static
mutate "continueOnError on the merge step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Merge shard reports' '        displayName: Merge shard reports\n        continueOnError: true' static
mutate "condition: always() on the diff-cover step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Changed-line coverage' '        condition: always()\n        displayName: Changed-line coverage' static
mutate "if: always() on the diff-cover step (github-py)" github-py/.github/workflows/ci.yml '      - name: Changed-line coverage (>= 80%)' '      - if: always()\n        name: Changed-line coverage (>= 80%)' static
mutate "--fail-under=80 removed (azure-py)" azure-py/azure-pipelines.yml ' --fail-under=80' '' static
mutate "merge command removed (github-ts)" github-ts/.github/workflows/ci.yml '--merge-reports=blob --coverage' '--coverage' static
mutate "job-level if: always() on the coverage job (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: test\n' '  coverage:\n    if: always()\n    needs: test\n' static
mutate "|| true inside the Azure merge script (azure-ts)" azure-ts/azure-pipelines.yml 'vitest run --merge-reports=blob --coverage' 'vitest run --merge-reports=blob --coverage || true' static
mutate "GitHub shard assertion replaced by a no-op" github-ts/.github/workflows/ci.yml "run: '[ \"\$(find blob" "run: 'true || [ \"\$(find blob" github

if [[ $fail -eq 0 ]]; then
  echo "test-ci-templates: all passed"
else
  echo "test-ci-templates: failures" >&2
  exit 1
fi
