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
def step_bounds(lines, n):
    start = n
    while start > 0 and not re.match(r"^\s*- ", lines[start]):
        start -= 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = n + 1
    while end < len(lines) and not (re.match(r"^\s*- ", lines[end]) and len(lines[end]) - len(lines[end].lstrip()) <= indent) and not re.match(r"^\s{0,2}\S", lines[end]):
        end += 1
    return start, end
def job_has_condition(lines, n):
    j = n
    while j > 0 and not re.match(r"^  (-\s+job:\s*\S+|[A-Za-z_-]+:)\s*$", lines[j]):
        j -= 1
    k = j + 1
    while k < len(lines) and not re.match(r"^  (-\s+job:|[A-Za-z_-]+:\s*$)", lines[k]) and not re.match(r"^\S", lines[k]):
        if re.match(r"^    (if|condition):", lines[k]) and not re.search(r"pull_request", lines[k]):
            return lines[k].strip()
        k += 1
    return None
# Gate steps (merge, diff-cover, jscpd, nosonar) must always run and must fail the job: no step-level or job-level
# if/condition/continueOnError, no inline guard. Allowed conditions elsewhere: `if: hashFiles('uv.lock') != ''` on the
# optional setup-uv step (not a gate) and the job-level `github.event_name == 'pull_request'` on the PR-only gates.
def gate_step_checks(rel, lines, what, needle, required=True):
    hits = [i for i, l in enumerate(lines) if needle in l and not l.lstrip().startswith("#")]
    if not hits:
        if required:
            errors.append(f"{rel}: missing {what} ({needle})")
        return
    for n in hits:
        if re.search(r"\|\||;\s*\S|\bif\b.*\bthen\b", re.sub(r"\s#\s.*$", "", lines[n])):
            errors.append(f"{rel}:{n + 1}: {what} is guarded inline: {lines[n].strip()}")
        a, b = step_bounds(lines, n)
        for k in range(a, b):
            if re.match(r"^\s*(- )?(if|condition|continueOnError):", lines[k]):
                errors.append(f"{rel}:{k + 1}: {what} step has a run condition: {lines[k].strip()}")
        c = job_has_condition(lines, n)
        if c:
            errors.append(f"{rel}:{n + 1}: {what} job has a run condition: {c}")
for host, (rel, merge) in files.items():
    lines = open(f"{root}/{rel}").read().split("\n")
    for i, l in enumerate(lines):
        code = re.sub(r"\s#\s.*$", "", l)
        if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)", code):
            errors.append(f"{rel}:{i + 1}: gate-neutralising construct: {l.strip()}")
        if re.match(r"^\s*condition:\s*(always|succeededOrFailed)", l):
            errors.append(f"{rel}:{i + 1}: condition that runs after failure: {l.strip()}")
    for what, needle in (("merge command", merge), ("diff-cover", "diff-cover"), ("jscpd step", "jscpd")):
        gate_step_checks(rel, lines, what, needle)
    if host.startswith("github"):
        gate_step_checks(rel, lines, "nosonar step", "ci-gates.sh nosonar")
    code_lines = [l for l in lines if not l.lstrip().startswith("#")]
    for n, l in enumerate(lines):
        if re.search(r"pipx run\s+(\"?)diff-cover", l) and not re.search(r"pipx run\s+\"diff-cover==(\$\{DIFF_COVER_VERSION\}|\$\(diffCoverVersion\)|\$\(DIFF_COVER_VERSION\))\"", l):
            errors.append(f"{rel}:{n + 1}: diff-cover must run pinned as \"diff-cover==<version variable>\": {l.strip()}")
    pins = [(n, l) for n, l in enumerate(lines) if re.match(r"^\s*(DIFF_COVER_VERSION|diffCoverVersion|JSCPD_VERSION):", l)]
    if not any("diff" in l.lower() for _, l in pins):
        errors.append(f"{rel}: missing the diff-cover version variable")
    for n, l in pins:
        if not re.match(r"^\s*\w+:\s*\"\d+\.\d+\.\d+\"(\s|$)", l):
            errors.append(f"{rel}:{n + 1}: tool version must be an exact x.y.z string: {l.strip()}")
    if not any(re.search(r"(pnpm exec jscpd|npx --yes jscpd@)", l) for l in code_lines):
        errors.append(f"{rel}: missing the jscpd duplication step")
    nosonar_file = rel if host.startswith("github") else "azure/azure-pipelines/templatecentral-gates.yml"
    if "ci-gates.sh nosonar" not in open(f"{root}/{nosonar_file}").read():
        errors.append(f"{nosonar_file}: missing the `ci-gates.sh nosonar` step (used by {rel})")
    for n, l in enumerate(lines):
        if "upload-artifact" in l and "uses:" in l:
            a, b = step_bounds(lines, n)
            if not any(re.match(r"^\s*if-no-files-found:\s*error\s*$", lines[k]) for k in range(a, b)):
                errors.append(f"{rel}:{n + 1}: upload-artifact step must keep `if-no-files-found: error`")
    if not any("diff-cover" in l and "--fail-under=80" in l for l in lines):
        errors.append(f"{rel}: diff-cover must run with --fail-under=80")
gates = "azure/azure-pipelines/templatecentral-gates.yml"
for i, l in enumerate(open(f"{root}/{gates}").read().split("\n")):
    code = re.sub(r"\s#\s.*$", "", l)
    if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)|^\s*condition:", code):
        errors.append(f"{gates}:{i + 1}: gate-neutralising construct: {l.strip()}")
gate_step_checks(gates, open(f"{root}/{gates}").read().split("\n"), "nosonar step", "ci-gates.sh nosonar")
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
mutate "|| true mid-command before a following command (github-ts nosonar)" github-ts/.github/workflows/ci.yml 'run: bash .claude/ci-gates.sh nosonar' 'run: bash .claude/ci-gates.sh nosonar || true; echo done' static
mutate "|| : mid-command (azure gates nosonar)" azure/azure-pipelines/templatecentral-gates.yml 'bash .claude/ci-gates.sh nosonar' 'bash .claude/ci-gates.sh nosonar || : ; echo done' static
mutate "|| exit 0 after the jscpd step (github-ts)" github-ts/.github/workflows/ci.yml 'run: pnpm exec jscpd' 'run: pnpm exec jscpd || exit 0' static
mutate "|| echo after diff-cover (azure-py)" azure-py/azure-pipelines.yml '--fail-under=80' '--fail-under=80 || echo ignored' static
mutate "|| exit 0 after nosonar (azure gates)" azure/azure-pipelines/templatecentral-gates.yml 'bash .claude/ci-gates.sh nosonar' 'bash .claude/ci-gates.sh nosonar || exit 0' static
mutate "|| echo after the merge command (github-py pytest is the merge) " github-py/.github/workflows/ci.yml '--cov-report=xml -q' '--cov-report=xml -q || echo ignored' static
mutate "if: false on the jscpd step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Duplication (production source <= 3%, per .jscpd.json)\n        run: pnpm exec jscpd' '      - if: false\n        name: Duplication (production source <= 3%, per .jscpd.json)\n        run: pnpm exec jscpd' static
mutate "if: false on the nosonar step (github-py)" github-py/.github/workflows/ci.yml '      - name: No NOSONAR suppression markers' '      - if: false\n        name: No NOSONAR suppression markers' static
mutate "if: false on the merge step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Merge shard reports (writes coverage/cobertura-coverage.xml)' '      - if: false\n        name: Merge shard reports (writes coverage/cobertura-coverage.xml)' static
mutate "if: false on the diff-cover step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Changed-line coverage (>= 80%)' '      - if: false\n        name: Changed-line coverage (>= 80%)' static
mutate "condition: false on the jscpd step (azure-py)" azure-py/azure-pipelines.yml '        displayName: Duplication (production source <= 3%, per .jscpd.json)' '        condition: false\n        displayName: Duplication (production source <= 3%, per .jscpd.json)' static
mutate "condition: false on the nosonar step (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '    displayName: No NOSONAR suppression markers' '    condition: false\n    displayName: No NOSONAR suppression markers' static
mutate "if-no-files-found: ignore on the shard upload (github-ts)" github-ts/.github/workflows/ci.yml 'if-no-files-found: error' 'if-no-files-found: ignore' static
mutate "if-no-files-found removed from the shard upload (github-ts)" github-ts/.github/workflows/ci.yml '          if-no-files-found: error\n' '' static
mutate "jscpd step replaced (github-ts)" github-ts/.github/workflows/ci.yml 'run: pnpm exec jscpd' 'run: echo skipped' static
mutate "jscpd step replaced (github-py)" github-py/.github/workflows/ci.yml 'npx --yes jscpd@' 'echo skipped #' static
mutate "jscpd step replaced (azure-ts)" azure-ts/azure-pipelines.yml '- bash: pnpm exec jscpd' '- bash: echo skipped' static
mutate "jscpd step replaced (azure-py)" azure-py/azure-pipelines.yml 'npx --yes jscpd@' 'echo skipped #' static
mutate "unpinned diff-cover (github-ts)" github-ts/.github/workflows/ci.yml "pipx run \"diff-cover==\${DIFF_COVER_VERSION}\"" 'pipx run diff-cover' static
mutate "unpinned diff-cover (azure-py)" azure-py/azure-pipelines.yml "pipx run \"diff-cover==\$(DIFF_COVER_VERSION)\"" 'pipx run diff-cover' static
mutate "diff-cover version range instead of exact (github-py)" github-py/.github/workflows/ci.yml 'DIFF_COVER_VERSION: "11.0.3"' 'DIFF_COVER_VERSION: ">=11"' static
mutate "diff-cover version variable removed (azure-ts)" azure-ts/azure-pipelines.yml '  diffCoverVersion: "11.0.3"' '  unusedVar: "1"' static
mutate "jscpd version range instead of exact (azure-py)" azure-py/azure-pipelines.yml 'JSCPD_VERSION: "5.4.3"' 'JSCPD_VERSION: "^5"' static
mutate "nosonar step removed (github-py)" github-py/.github/workflows/ci.yml 'run: bash .claude/ci-gates.sh nosonar' 'run: echo skipped' static
mutate "nosonar step removed (azure gates, used by azure-ts and azure-py)" azure/azure-pipelines/templatecentral-gates.yml 'bash .claude/ci-gates.sh nosonar' 'echo skipped' static

# 7. passWithNoTests must not appear anywhere in the seeded templates (a shard with no test files would pass silently)
nopass_check() { # nopass_check <scaffold dir>
  local hits
  hits=$(grep -rIn -e 'passWithNoTests' "$1" 2>/dev/null | grep '/template' || true)
  if [[ -n "$hits" ]]; then echo "$hits"; return 1; fi
}
if out=$(nopass_check "$REPO_ROOT/skills/scaffold" 2>&1); then ok "no passWithNoTests in any template"; else bad "passWithNoTests found in a template: $out"; fi
nopass_mutate() { # nopass_mutate <label> <source file> <old> <new>; copies one template file into a scratch tree
  local label=$1 src=$2 d="$T/np/x/template"
  rm -rf "$T/np" && mkdir -p "$d" && cp "$REPO_ROOT/$src" "$d/$(basename "$src")"
  python3 - "$d/$(basename "$src")" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit("mutation target not found: " + old)
open(p, "w").write(s.replace(old, new, 1))
PY
  if out=$(nopass_check "$T/np" 2>&1); then bad "mutation not caught: $label"; else ok "mutation caught: $label -> $(head -1 <<<"$out")"; fi
}
nopass_mutate "passWithNoTests: true in vitest.config.ts" skills/scaffold/nestjs/template/vitest.config.ts 'test: {' 'test: { passWithNoTests: true,'
nopass_mutate "--passWithNoTests in a package.json script" skills/scaffold/nestjs/template/package.json '"test": "vitest --run' '"test": "vitest --run --passWithNoTests'

# 8. Python lint scope: CI and the lefthook pre-push gate check the same paths (src/ and test/)
py_scope_check() { # py_scope_check <template-ci dir> <lefthook.yml>
  local f
  for f in "$1/github-py/.github/workflows/ci.yml" "$1/azure-py/azure-pipelines.yml"; do
    grep -qF 'ruff check src/ test/ && ruff format --check src/ test/' "$f" || { echo "$f: ruff must check src/ and test/"; return 1; }
  done
  grep -qF 'ruff check src/ test/ &&' "$2" || { echo "$2: pre-push ruff must check src/ and test/"; return 1; }
}
LEFTHOOK_PY="$REPO_ROOT/skills/scaffold/shared/template-py/lefthook.yml"
if out=$(py_scope_check "$CI_DIR" "$LEFTHOOK_PY" 2>&1); then ok "python lint scope: CI and lefthook both check src/ and test/"; else bad "python lint scope drifted: $out"; fi
rm -rf "$T/mut" && cp -R "$CI_DIR" "$T/mut" && sed -i.bak 's#ruff check src/ test/ \&\&#ruff check src/ \&\&#' "$T/mut/github-py/.github/workflows/ci.yml"
if out=$(py_scope_check "$T/mut" "$LEFTHOOK_PY" 2>&1); then bad "mutation not caught: CI ruff scope narrowed to src/"; else ok "mutation caught: CI ruff scope narrowed to src/ -> $out"; fi
cp "$LEFTHOOK_PY" "$T/lefthook.bad" && sed -i.bak 's#ruff check src/ test/ &&#ruff check src/ \&\&#' "$T/lefthook.bad"
if out=$(py_scope_check "$CI_DIR" "$T/lefthook.bad" 2>&1); then bad "mutation not caught: lefthook ruff scope narrowed to src/"; else ok "mutation caught: lefthook ruff scope narrowed to src/ -> $out"; fi

if [[ $fail -eq 0 ]]; then
  echo "test-ci-templates: all passed"
else
  echo "test-ci-templates: failures" >&2
  exit 1
fi
