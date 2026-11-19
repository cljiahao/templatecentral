#!/usr/bin/env bash
# scripts/test-ci-templates.sh — regression tests for the seeded CI templates (skills/scaffold/shared/template-ci):
#   1. every multi-line `bash: |` / `run: |` block starts with `set -euo pipefail` (Azure `bash:` reports only the
#      last command's status; without it an earlier failure is swallowed);
#   2. the Azure and GitHub shard-count assertions really fail when a shard report is missing;
#   3. no gate step can be neutralised (`|| true`, continue-on-error, always()/succeededOrFailed(), if/condition), and
#      every template keeps its merge command and `diff-cover --fail-under=80` unguarded;
#   4. each of those static checks and the GitHub assertion is proven by mutating a copy of the templates.
# Usage: bash scripts/test-ci-templates.sh   (needs bash, python3 and PyYAML)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_DIR="$REPO_ROOT/skills/scaffold/shared/template-ci"
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
python3 -c 'import yaml' 2>/dev/null || { echo "test-ci-templates: PyYAML is required: pip install pyyaml==6.0.3" >&2; exit 1; }
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


# 4. GitHub shard assertion: extract the `run:` of the step, run it with a shard report missing
gh_assert() { # gh_assert <ci-dir> <out-script>
  python3 - "$1/github-ts/.github/workflows/ci.yml" "$2" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d["jobs"]["coverage"]["steps"]
open(sys.argv[2], "w").write(next(x["run"] for x in steps if str(x.get("name", "")).startswith("Require one blob report per shard")))
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

# 4b. test-count equality step: run the real step script of each template against fixture reports
python3 - "$CI_DIR" "$T" <<'PY2'
import sys, yaml
root, out = sys.argv[1:3]
gh = yaml.safe_load(open(f"{root}/github-ts/.github/workflows/ci.yml"))
steps = gh["jobs"]["coverage"]["steps"]
open(f"{out}/count-gh.sh", "w").write(next(x["run"] for x in steps if x.get("name") == "Require the merged test count to equal the unsharded count"))
az = yaml.safe_load(open(f"{root}/azure-ts/azure-pipelines.yml"))
steps = next(j for j in az["jobs"] if j["job"] == "coverage")["steps"]
open(f"{out}/count-az.sh", "w").write(next(x["bash"] for x in steps if x.get("displayName") == "Require the merged test count to equal the unsharded count"))
PY2
count_case() { # count_case <script> <merged-total> <merged-failed> <collected-total> -> exit code
  rm -rf "$T/cnt" && mkdir -p "$T/cnt/report"
  printf '{"numTotalTests":%s,"numFailedTests":%s,"success":%s}' "$2" "$3" "${5:-true}" > "$T/cnt/report/merged.json"
  printf '{"numTotalTests":%s}' "$4" > "$T/cnt/report/collected.json"
  local rc=0
  ( cd "$T/cnt" && bash "$1" ) >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
for host in gh az; do
  if [[ "$(count_case "$T/count-$host.sh" 28 0 28)" == 0 ]]; then ok "$host count step passes when merged equals unsharded"; else bad "$host count step failed on equal counts"; fi
  if [[ "$(count_case "$T/count-$host.sh" 27 0 28)" != 0 ]]; then ok "$host count step fails when a test is missing from the merge"; else bad "$host count step passed with 27 of 28 tests"; fi
  if [[ "$(count_case "$T/count-$host.sh" 28 1 28)" != 0 ]]; then ok "$host count step fails on a failed test"; else bad "$host count step passed with a failed test"; fi
  if [[ "$(count_case "$T/count-$host.sh" 0 0 0)" != 0 ]]; then ok "$host count step fails on zero tests"; else bad "$host count step passed with zero tests"; fi
  if [[ "$(count_case "$T/count-$host.sh" 28 0 28 false)" != 0 ]]; then ok "$host count step fails when the merged report says success is false"; else bad "$host count step passed with success: false"; fi
done
# 4c. shard plan: run the real plan script of each template against a stub `vitest list` with N test files
python3 - "$CI_DIR" "$T" <<'PY3'
import sys, yaml
root, out = sys.argv[1:3]
gh = yaml.safe_load(open(f"{root}/github-ts/.github/workflows/ci.yml"))
open(f"{out}/plan-gh.sh", "w").write(next(x["run"] for x in gh["jobs"]["plan"]["steps"] if x.get("id") == "shards"))
az = yaml.safe_load(open(f"{root}/azure-ts/azure-pipelines.yml"))
steps = next(j for j in az["jobs"] if j["job"] == "plan")["steps"]
open(f"{out}/plan-az.sh", "w").write(next(x["bash"] for x in steps if x.get("name") == "shards").replace("$(shardMax)", "4"))
PY3
mkdir -p "$T/planbin"
cat > "$T/planbin/pnpm" <<'STUB'
#!/usr/bin/env bash
node -p 'JSON.stringify(Array.from({ length: Number(process.env.STUB_FILES) }, (_, i) => ({ file: "/p/t" + i + ".test.ts" })))'
STUB
chmod +x "$T/planbin/pnpm"
plan_case() { # plan_case <host> <files> -> "<rc> <count> <matrix-or-list size>"
  local out="$T/plan-out" rc=0
  : > "$out"
  ( PATH="$T/planbin:$PATH" STUB_FILES="$2" SHARD_MAX=4 GITHUB_OUTPUT="$out" bash "$T/plan-$1.sh" ) > "$T/plan-log" 2>&1 || rc=$?
  if [[ "$1" == gh ]]; then
    echo "$rc $(sed -n 's/^count=//p' "$out") $(sed -n 's/^list=//p' "$out")"
  else
    echo "$rc $(sed -n 's/^##vso\[task.setvariable variable=count;isOutput=true\]//p' "$T/plan-log") $(sed -n 's/^##vso\[task.setvariable variable=matrix;isOutput=true\]//p' "$T/plan-log" | node -p 'Object.keys(JSON.parse(require("fs").readFileSync(0, "utf8") || "{}")).length')"
  fi
}
for host in gh az; do
  for pair in "1 1" "3 3" "4 4" "9 4"; do
    read -r files shards <<<"$pair"
    got=$(plan_case "$host" "$files")
    if [[ "$host" == gh ]]; then want="0 $shards $(node -p "JSON.stringify(Array.from({ length: $shards }, (_, i) => i + 1))")"; else want="0 $shards $shards"; fi
    if [[ "$got" == "$want" ]]; then ok "$host plan: $files test files give $shards shards"; else bad "$host plan: $files test files should give $shards shards, got: $got"; fi
  done
  got=$(plan_case "$host" 0)
  if [[ "$got" =~ ^[1-9] ]]; then ok "$host plan fails when vitest resolves no test files"; else bad "$host plan passed with zero test files: $got"; fi
done
# 4d. a shard count that is empty or not a positive integer must fail every step that consumes it, not pass silently
python3 - "$CI_DIR" "$T" <<'PY4'
import sys, yaml
root, out = sys.argv[1:3]
gh = yaml.safe_load(open(f"{root}/github-ts/.github/workflows/ci.yml"))
name = lambda x: str(x.get("name", ""))
open(f"{out}/valid-gh.sh", "w").write(next(x["run"] for x in gh["jobs"]["test"]["steps"] if name(x).startswith("Require a valid shard count")))
open(f"{out}/assert-gh.sh", "w").write(next(x["run"] for x in gh["jobs"]["coverage"]["steps"] if name(x).startswith("Require one blob report per shard")))
az = yaml.safe_load(open(f"{root}/azure-ts/azure-pipelines.yml"))
jobs = {j["job"]: j["steps"] for j in az["jobs"]}
disp = lambda x: str(x.get("displayName", ""))
open(f"{out}/valid-az.sh", "w").write(next(x["bash"] for x in jobs["test"] if disp(x).startswith("Require a valid shard count")))
open(f"{out}/assert-az.sh", "w").write(next(x["bash"] for x in jobs["coverage"] if disp(x) == "Assert all shard reports present"))
PY4
count_run() { # count_run <script> <value> -> exit code; blob holds two reports
  rm -rf "$T/cv" && mkdir -p "$T/cv/blob" && echo '[]' > "$T/cv/blob/a.json" && echo '[]' > "$T/cv/blob/b.json"
  local rc=0 script
  script=$(sed "s/\$(shardCount)/$2/g" "$1")
  ( cd "$T/cv" && SHARD_COUNT="$2" bash -c "$script" ) >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
for script in valid-gh valid-az assert-gh assert-az; do
  for value in "" abc 1.5 -1 0 03 99999999999999999999 9223372036854775808; do
    if [[ "$(count_run "$T/$script.sh" "$value")" != 0 ]]; then ok "$script fails on shard count '$value'"; else bad "$script passed on shard count '$value'"; fi
  done
  if [[ "$(count_run "$T/$script.sh" 2)" == 0 ]]; then ok "$script passes on shard count 2 with two reports"; else bad "$script failed on shard count 2 with two reports"; fi
done
if grep -q 'SHARD_MAX: "4"' "$CI_DIR/github-ts/.github/workflows/ci.yml" && grep -q 'shardMax: 4' "$CI_DIR/azure-ts/azure-pipelines.yml"; then ok "both TS templates cap the shards at four"; else bad "a TS template does not cap the shards at four"; fi
if grep -rq -- ' -n auto' "$CI_DIR/github-py" "$CI_DIR/azure-py"; then bad "a Python CI template runs pytest with xdist"; else ok "Python CI templates run pytest serially"; fi

# 5. static guards over all four templates
cat > "$T/static.py" <<'PY'
import re, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required by the job-condition guard: pip install pyyaml==6.0.3")
root = sys.argv[1]
files = {
    "github-ts": "github-ts/.github/workflows/ci.yml",
    "azure-ts": "azure-ts/azure-pipelines.yml",
    "github-py": "github-py/.github/workflows/ci.yml",
    "azure-py": "azure-py/azure-pipelines.yml",
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
# Only the PR-only gates may carry a job- or stage-level if/condition, and only this exact one: the gates themselves
# skip off-PR runs, so any other if/condition on a job or stage could silently switch a gate off. The templates are
# parsed with PyYAML and walked structurally, so quoting, spacing, indent, flow style and anchors cannot hide a key.
PR_ONLY_JOBS = {"changelog", "comment-hygiene", "gate-ratchet", "dependency-review"}
PR_ONLY_IF = "github.event_name == 'pull_request'"
# Every step of every job must always run and fail the job: no if/condition/enabled/continue-on-error/continueOnError and
# no non-positive timeout. Allowlist keyed by (template, job, step name, or its exact uses/task/script first line when
# unnamed); the value is the exact key/value allowed, nothing is matched by pattern or prefix.
STEP_NEUTRALISERS = ("if", "condition", "enabled", "continue-on-error", "continueOnError")
STEP_ALLOWLIST = {
    # setup-uv is an install step, not a gate; it is only needed when the project ships uv.lock.
    ("github-py", "quality", "astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2"): {"if": "hashFiles('uv.lock') != ''"},
}
GATES_INCLUDE = "azure-pipelines/templatecentral-gates.yml"
class MergeKeyError(yaml.YAMLError):
    pass
class UniqueKeyLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        if any(k.tag == "tag:yaml.org,2002:merge" for k, _ in node.value):
            raise MergeKeyError("YAML merge keys are not allowed in CI templates")
        keys = [self.construct_object(k, deep=True) for k, _ in node.value]
        dupes = sorted({str(k) for k in keys if keys.count(k) > 1})
        if dupes:
            raise yaml.constructor.ConstructorError(None, None, "duplicate key " + ", ".join(dupes), node.start_mark)
        return super().construct_mapping(node, deep)
def condition_errors(rel, doc, tmpl):
    def step_ident(step):
        for key in ("name", "displayName"):
            if isinstance(step.get(key), str):
                return step[key]
        for key in ("uses", "task", "script", "bash", "run", "template"):
            if isinstance(step.get(key), str):
                return step[key].split("\n")[0]
        return "?"
    def check_steps(job, steps):
        if steps is None:
            return
        if not isinstance(steps, list):
            errors.append(f"{rel}: job {job} steps is not a list the step guard can read")
            return
        for step in steps:
            if not isinstance(step, dict):
                errors.append(f"{rel}: job {job} has a step that is not a mapping the step guard can read")
                continue
            ident = step_ident(step)
            if "template" in step and step["template"] != GATES_INCLUDE:
                errors.append(f"{rel}: job {job} step includes template {step['template']}; only {GATES_INCLUDE} is checked")
            allowed = STEP_ALLOWLIST.get((tmpl, job, ident), {})
            for key in STEP_NEUTRALISERS:
                if key in step and not (key in allowed and step[key] == allowed[key]):
                    errors.append(f"{rel}: job {job} step {ident} has {key}: {step[key]}")
            for key in ("timeout-minutes", "timeoutInMinutes"):
                if key in step and not (isinstance(step[key], int) and not isinstance(step[key], bool) and step[key] > 0):
                    errors.append(f"{rel}: job {job} step {ident} has {key}: {step[key]}")
    def check(kind, name, node, allowed):
        if not isinstance(node, dict):
            errors.append(f"{rel}: {kind} {name} is not a mapping the job-condition guard can read")
            return
        for key in ("if", "condition"):
            if key in node and not (allowed and key == "if" and node[key] == PR_ONLY_IF):
                errors.append(f"{rel}: {kind} {name} has a run condition: {key}: {node[key]}")
        for key in ("continue-on-error", "continueOnError"):
            if key in node:
                errors.append(f"{rel}: {kind} {name} has {key}: {node[key]}")
        if kind == "job":
            check_steps(name, node.get("steps"))
    count = [0]
    def azure_jobs(owner, jobs):
        if isinstance(jobs, list):
            count[0] += len(jobs)
        if not isinstance(jobs, list):
            errors.append(f"{rel}: {owner} jobs is not a list the job-condition guard can read")
            return
        for entry in jobs:
            name = entry.get("job") or entry.get("deployment") or entry.get("template") if isinstance(entry, dict) else None
            check("job", name or "?", entry, False)
    if not isinstance(doc, dict):
        errors.append(f"{rel}: not a YAML mapping the job-condition guard can read")
        return
    seen = False
    if "steps" in doc:
        seen = True
        count[0] += 1
        check_steps("(top-level)", doc["steps"])
    jobs = doc.get("jobs")
    if isinstance(jobs, dict):
        seen = True
        count[0] += len(jobs)
        for name, node in jobs.items():
            check("job", name, node, name in PR_ONLY_JOBS)
    elif jobs is not None:
        seen = True
        azure_jobs("top-level", jobs)
    stages = doc.get("stages")
    if stages is not None:
        seen = True
        if not isinstance(stages, list):
            errors.append(f"{rel}: stages is not a list the job-condition guard can read")
        else:
            for stage in stages:
                check("stage", stage.get("stage", "?") if isinstance(stage, dict) else "?", stage, False)
                if isinstance(stage, dict) and "jobs" in stage:
                    azure_jobs("stage " + str(stage.get("stage", "?")), stage["jobs"])
    if not seen:
        errors.append(f"{rel}: no jobs or stages the job-condition guard can read")
    elif count[0] == 0:
        errors.append(f"{rel}: the template yields zero jobs, so the job-condition guard has nothing to check")
def gate_include_errors(rel, doc):
    steps = doc.get("steps") if isinstance(doc, dict) else None
    if not isinstance(steps, list) or not steps:
        errors.append(f"{rel}: expected a non-empty top-level steps list")
        return
    for step in steps:
        name = step.get("displayName", "?") if isinstance(step, dict) else "?"
        if not isinstance(step, dict):
            errors.append(f"{rel}: step {name} is not a mapping the gate guard can read")
            continue
        for key in ("condition", "enabled", "continueOnError", "if"):
            if key in step:
                errors.append(f"{rel}: gate step {name} has {key}: {step[key]}; every step in the gates include must always run and fail the job")
# Required-gate manifest, one entry per template: for each required gate the job it lives in and the exact `run`/`bash`/
# `uses`/`task`/`template` value of its step (compared on the parsed value, trailing whitespace trimmed), plus the exact
# needs/dependsOn edges of every job. A missing step, a changed command, a step in the wrong job, an unlisted job or a
# missing edge fails and names the gate. Exact text also rules out `set +e`, `exit 0` and `|| true` in a gate command.
# The github and azure variants differ only where the platform differs (task vs uses, $(var) vs ${VAR}), each recorded.
COUNT_CHECK = ('set -euo pipefail\n'
               "node -e '\n"
               'const fs = require("node:fs");\n'
               'const read = (f) => JSON.parse(fs.readFileSync(f, "utf8"));\n'
               'const merged = read("report/merged.json");\n'
               'const collected = read("report/collected.json");\n'
               'console.log("merged " + merged.numTotalTests + ", unsharded " + collected.numTotalTests + ", failed " + merged.numFailedTests);\n'
               'const ok = merged.numTotalTests === collected.numTotalTests && merged.numTotalTests > 0 && merged.numFailedTests === 0 && merged.success === true;\n'
               'process.exit(ok ? 0 : 1);\n'
               "'\n")
PLAN_BODY = ("node -e '\n"
             'const fs = require("node:fs");\n'
             'const files = JSON.parse(fs.readFileSync(0, "utf8")).length;\n'
             'if (files < 1) {\n'
             '  console.error("vitest resolved no test files");\n'
             '  process.exit(1);\n'
             '}\n'
             'const count = Math.min(Number(process.env.SHARD_MAX), files);\n')
GH_PLAN = ('set -euo pipefail\n'
           'pnpm exec vitest list --filesOnly --json | ' + PLAN_BODY +
           'const list = Array.from({ length: count }, (_, i) => i + 1);\n'
           'fs.appendFileSync(process.env.GITHUB_OUTPUT, "count=" + count + "\\nlist=" + JSON.stringify(list) + "\\n");\n'
           'console.log(files + " test files, " + count + " shards");\n'
           "'\n")
AZ_PLAN = ('set -euo pipefail\n'
           'pnpm exec vitest list --filesOnly --json | SHARD_MAX="$(shardMax)" ' + PLAN_BODY +
           'const matrix = {};\n'
           'for (let i = 1; i <= count; i++) matrix["shard" + i] = { shard: String(i) };\n'
           'console.log(files + " test files, " + count + " shards");\n'
           'console.log("##vso[task.setvariable variable=count;isOutput=true]" + count);\n'
           'console.log("##vso[task.setvariable variable=matrix;isOutput=true]" + JSON.stringify(matrix));\n'
           "'\n")
def case_check(v):
    return ('case "' + v + '" in\n'
            "  ''|*[!0-9]*|0*|??????????*)\n"
            '    echo "invalid shard count: \'' + v + '\'" >&2\n'
            '    exit 1\n'
            '    ;;\n'
            'esac\n')
GH_VALID = 'set -euo pipefail\n' + case_check('$SHARD_COUNT')
AZ_VALID = 'set -euo pipefail\n' + case_check('$(shardCount)')
GH_ASSERT = (GH_VALID + 'found=$(find blob -name "*.json" | wc -l | tr -d \' \')\n'
             'if [ "$found" != "$SHARD_COUNT" ]; then\n'
             '  echo "expected $SHARD_COUNT shard reports, found $found" >&2\n'
             '  exit 1\n'
             'fi\n')
AZ_ASSERT = ('set -euo pipefail\n' + case_check('$(shardCount)') +
             "count=$(find blob -name '*.json' | wc -l | tr -d ' ')\n"
             'if [ "$count" != "$(shardCount)" ]; then\n'
             '  echo "expected $(shardCount) shard reports, found $count" >&2\n'
             '  exit 1\n'
             'fi\n')
MANIFEST = {'github-ts': {'file': 'github-ts/.github/workflows/ci.yml',
               'needs': {'plan': [],
                         'quality': [],
                         'test': ['plan'],
                         'coverage': ['plan', 'test'],
                         'changelog': [],
                         'comment-hygiene': [], 'gate-ratchet': [],
                         'dependency-review': []},
               'gates': [('shard plan', 'plan', 'run', GH_PLAN),
                         ('dependency audit', 'quality', 'run', 'bash .claude/ci-gates.sh deps'),
                         ('harness integrity', 'quality', 'run', 'bash .claude/verify-harness.sh'),
                         ('docs check', 'quality', 'run', 'bash scripts/check-docs.sh'),
                         ('test budget', 'quality', 'run', 'bash .claude/ci-gates.sh testbudget'),
                         ('nosonar', 'quality', 'run', 'bash .claude/ci-gates.sh nosonar'),
                         ('format, lint and typecheck', 'quality', 'run', 'pnpm run check'),
                         ('jscpd', 'quality', 'run', 'pnpm exec jscpd'),
                         ('secret scan', 'quality', 'run', 'bash .claude/ci-gates.sh secrets "$BASE_REF"'),
                         ('tests',
                          'test',
                          'run',
                          'pnpm exec vitest run --coverage --reporter=default --reporter=blob --outputFile.blob="blob/shard-${{ '
                          'matrix.shard }}.json" --shard="${{ matrix.shard }}/${{ needs.plan.outputs.count }}"'),
                         ('shard upload', 'test', 'uses', 'actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9'),
                         ('shard download', 'coverage', 'uses', 'actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333'),
                         ('shard count assertion', 'coverage', 'run', GH_ASSERT),
                         ('shard count valid', 'test', 'run', GH_VALID),
                         ('coverage merge', 'coverage', 'run', 'pnpm exec vitest run --merge-reports=blob --coverage'),
                         ('merged test report',
                          'coverage',
                          'run',
                          'pnpm exec vitest run --merge-reports=blob --reporter=json --outputFile.json=report/merged.json'),
                         ('unsharded test count',
                          'coverage',
                          'run',
                          "pnpm exec vitest run -t '^$' --reporter=json --outputFile.json=report/collected.json"),
                         ('test count equality', 'coverage', 'run', COUNT_CHECK),
                         ('diff-cover at 80',
                          'coverage',
                          'run',
                          'pipx run "diff-cover==${DIFF_COVER_VERSION}" coverage/cobertura-coverage.xml '
                          '--compare-branch="origin/${BASE_REF:-main}" --fail-under=80'),
                         ('changelog check', 'changelog', 'run', 'bash .claude/ci-gates.sh changelog "$BASE_REF"'),
                         ('comment check', 'comment-hygiene', 'run', 'bash .claude/ci-gates.sh comments "$BASE_REF"'),
                         ('gate ratchet', 'gate-ratchet', 'run', 'bash .claude/ci-gates.sh ratchet "$BASE_REF"'),
                         ('dependency review at high',
                          'dependency-review',
                          'uses',
                          'actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294')]},
 'github-py': {'file': 'github-py/.github/workflows/ci.yml',
               'needs': {'quality': [], 'changelog': [], 'comment-hygiene': [], 'gate-ratchet': [], 'dependency-review': []},
               'gates': [('dependency audit', 'quality', 'run', 'bash .claude/ci-gates.sh deps'),
                         ('harness integrity', 'quality', 'run', 'bash .claude/verify-harness.sh'),
                         ('docs check', 'quality', 'run', 'bash scripts/check-docs.sh'),
                         ('test budget', 'quality', 'run', 'bash .claude/ci-gates.sh testbudget'),
                         ('nosonar', 'quality', 'run', 'bash .claude/ci-gates.sh nosonar'),
                         ('lint and format', 'quality', 'run', 'ruff check src/ test/ && ruff format --check src/ test/'),
                         ('typecheck', 'quality', 'run', 'python -m pyright src/'),
                         ('jscpd', 'quality', 'run', 'npx --yes jscpd@${JSCPD_VERSION}'),
                         ('tests', 'quality', 'run', 'python -m pytest test/ --cov=src --cov-report=xml -q'),
                         ('diff-cover at 80',
                          'quality',
                          'run',
                          'pipx run "diff-cover==${DIFF_COVER_VERSION}" coverage.xml --compare-branch="origin/${BASE_REF:-main}" '
                          '--fail-under=80'),
                         ('secret scan', 'quality', 'run', 'bash .claude/ci-gates.sh secrets "$BASE_REF"'),
                         ('changelog check', 'changelog', 'run', 'bash .claude/ci-gates.sh changelog "$BASE_REF"'),
                         ('comment check', 'comment-hygiene', 'run', 'bash .claude/ci-gates.sh comments "$BASE_REF"'),
                         ('gate ratchet', 'gate-ratchet', 'run', 'bash .claude/ci-gates.sh ratchet "$BASE_REF"'),
                         ('dependency review at high',
                          'dependency-review',
                          'uses',
                          'actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294')]},
 'azure-ts': {'file': 'azure-ts/azure-pipelines.yml',
              'needs': {'plan': [], 'quality': [], 'test': ['plan'], 'coverage': ['plan', 'test']},
              'gates': [('shard plan', 'plan', 'bash', AZ_PLAN),
                        ('format, lint and typecheck', 'quality', 'bash', 'pnpm run check'),
                        ('jscpd', 'quality', 'bash', 'pnpm exec jscpd'),
                        ('gates include', 'quality', 'template', 'azure-pipelines/templatecentral-gates.yml'),
                        ('tests',
                         'test',
                         'bash',
                         'pnpm exec vitest run --coverage --reporter=default --reporter=blob '
                         '--outputFile.blob="blob/shard-$(shard).json" '
                         '--shard="$(shard)/$(shardCount)"'),
                        ('shard upload', 'test', 'task', 'PublishPipelineArtifact@1'),
                        ('shard download', 'coverage', 'task', 'DownloadPipelineArtifact@2'),
                        ('shard collect',
                         'coverage',
                         'bash',
                         'set -euo pipefail\n'
                         '# No artifact name, so the task puts each artifact in its own subfolder: <path>/<artifact>/*.json.\n'
                         'mkdir -p blob\n'
                         'cp "$(Pipeline.Workspace)"/blobs/*/*.json blob/\n'),
                        ('shard count assertion', 'coverage', 'bash', AZ_ASSERT),
                        ('shard count valid', 'test', 'bash', AZ_VALID),
                        ('coverage merge',
                         'coverage',
                         'bash',
                         'set -euo pipefail\n'
                         '# writes coverage/cobertura-coverage.xml\n'
                         'pnpm exec vitest run --merge-reports=blob --coverage\n'),
                        ('merged test report',
                         'coverage',
                         'bash',
                         'pnpm exec vitest run --merge-reports=blob --reporter=json --outputFile.json=report/merged.json'),
                        ('unsharded test count',
                         'coverage',
                         'bash',
                         "pnpm exec vitest run -t '^$' --reporter=json --outputFile.json=report/collected.json"),
                        ('test count equality', 'coverage', 'bash', COUNT_CHECK),
                        ('diff-cover at 80',
                         'coverage',
                         'bash',
                         'set -euo pipefail\n'
                         'target=${SYSTEM_PULLREQUEST_TARGETBRANCH:-main}\n'
                         'pipx run "diff-cover==$(diffCoverVersion)" coverage/cobertura-coverage.xml '
                         '--compare-branch="origin/${target#refs/heads/}" --fail-under=80\n')]},
 'azure-py': {'file': 'azure-py/azure-pipelines.yml',
              'needs': {'quality': []},
              'gates': [('lint and format', 'quality', 'bash', 'ruff check src/ test/ && ruff format --check src/ test/'),
                        ('typecheck', 'quality', 'bash', 'python -m pyright src/'),
                        ('jscpd', 'quality', 'bash', 'npx --yes jscpd@$(JSCPD_VERSION)'),
                        ('gates include', 'quality', 'template', 'azure-pipelines/templatecentral-gates.yml'),
                        ('tests', 'quality', 'bash', 'python -m pytest test/ --cov=src --cov-report=xml -q'),
                        ('diff-cover at 80',
                         'quality',
                         'bash',
                         'set -euo pipefail\n'
                         'target=${SYSTEM_PULLREQUEST_TARGETBRANCH:-main}\n'
                         'pipx run "diff-cover==$(DIFF_COVER_VERSION)" coverage.xml --compare-branch="origin/${target#refs/heads/}" '
                         '--fail-under=80\n')]},
 'azure-gates': {'file': 'azure/azure-pipelines/templatecentral-gates.yml',
                 'gates': [('Harness integrity', '(gates include)', 'bash', 'bash .claude/verify-harness.sh'),
                           ('Docs check (links and paths in README.md, AGENTS.md, docs/)',
                            '(gates include)',
                            'bash',
                            'bash scripts/check-docs.sh'),
                           ('Test budget (test code <= 35 lines per 100 source lines, ADR-0001)',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh testbudget'),
                           ('Secret scan (gitleaks CLI, checksum-verified)',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh secrets "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"'),
                           ('Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh deps'),
                           ('No NOSONAR suppression markers', '(gates include)', 'bash', 'bash .claude/ci-gates.sh nosonar'),
                           ('Changelog gate',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh changelog "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"'),
                           ('Comment hygiene gate',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh comments "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"'),
                           ('Gate ratchet (no gate weaker than the base branch)',
                            '(gates include)',
                            'bash',
                            'bash .claude/ci-gates.sh ratchet "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"')]}}

# Full pin of every job and step: for each job the exact non-step keys (runs-on, timeout, strategy, outputs, needs, if,
# permissions, defaults, env, container) and the full ordered list of steps with every key except name/displayName; a
# `uses` is compared by action name, its SHA is checked separately. Anything added, removed, reordered or changed,
# so an inserted rewrite step, a gate-step env/working-directory/target or a shorter hard-coded shard list, fails.
PINNED = {'github-ts': {'jobs': {'plan': {'runs-on': 'ubuntu-latest',
                                 'timeout-minutes': 5,
                                 'outputs': {'shards': '${{ steps.shards.outputs.list }}',
                                             'count': '${{ steps.shards.outputs.count }}'}},
                        'quality': {'runs-on': 'ubuntu-latest', 'timeout-minutes': 20},
                        'test': {'needs': 'plan',
                                 'runs-on': 'ubuntu-latest',
                                 'timeout-minutes': 20,
                                 'strategy': {'fail-fast': False,
                                              'matrix': {'shard': '${{ fromJSON(needs.plan.outputs.shards) }}'}}},
                        'coverage': {'needs': ['plan', 'test'], 'runs-on': 'ubuntu-latest', 'timeout-minutes': 10},
                        'changelog': {'if': "github.event_name == 'pull_request'",
                                      'runs-on': 'ubuntu-latest',
                                      'timeout-minutes': 5},
                        'comment-hygiene': {'if': "github.event_name == 'pull_request'",
                                            'runs-on': 'ubuntu-latest',
                                            'timeout-minutes': 5},
                        'gate-ratchet': {'if': "github.event_name == 'pull_request'",
                                         'runs-on': 'ubuntu-latest',
                                         'timeout-minutes': 5},
                        'dependency-review': {'if': "github.event_name == 'pull_request'",
                                              'runs-on': 'ubuntu-latest',
                                              'timeout-minutes': 5}},
               'steps': {'plan': [{'uses': 'actions/checkout'},
                                  {'uses': 'pnpm/action-setup'},
                                  {'uses': 'actions/setup-node', 'with': {'node-version': '26', 'cache': 'pnpm'}},
                                  {'run': 'pnpm install --frozen-lockfile'},
                                  {'id': 'shards', 'run': GH_PLAN}],
                         'quality': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                     {'uses': 'pnpm/action-setup'},
                                     {'uses': 'actions/setup-node', 'with': {'node-version': '26', 'cache': 'pnpm'}},
                                     {'run': 'pnpm install --frozen-lockfile'},
                                     {'run': 'bash .claude/ci-gates.sh deps'},
                                     {'run': 'bash .claude/verify-harness.sh'},
                                     {'run': 'bash scripts/check-docs.sh'},
                                     {'run': 'bash .claude/ci-gates.sh testbudget'},
                                     {'run': 'bash .claude/ci-gates.sh nosonar'},
                                     {'run': 'pnpm run check'},
                                     {'run': 'pnpm exec jscpd'},
                                     {'env': {'BASE_REF': '${{ github.base_ref }}'},
                                      'run': 'bash .claude/ci-gates.sh secrets "$BASE_REF"'}],
                         'test': [{'uses': 'actions/checkout'},
                                  {'uses': 'pnpm/action-setup'},
                                  {'uses': 'actions/setup-node', 'with': {'node-version': '26', 'cache': 'pnpm'}},
                                  {'run': 'pnpm install --frozen-lockfile'},
                                  {'env': {'SHARD_COUNT': '${{ needs.plan.outputs.count }}'}, 'run': GH_VALID},
                                  {'run': 'pnpm exec vitest run --coverage --reporter=default --reporter=blob '
                                          '--outputFile.blob="blob/shard-${{ matrix.shard }}.json" --shard="${{ '
                                          'matrix.shard }}/${{ needs.plan.outputs.count }}"'},
                                  {'uses': 'actions/upload-artifact',
                                   'with': {'name': 'vitest-blob-${{ matrix.shard }}',
                                            'path': 'blob',
                                            'if-no-files-found': 'error',
                                            'retention-days': 1}}],
                         'coverage': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                      {'uses': 'pnpm/action-setup'},
                                      {'uses': 'actions/setup-node', 'with': {'node-version': '26', 'cache': 'pnpm'}},
                                      {'run': 'pnpm install --frozen-lockfile'},
                                      {'uses': 'actions/download-artifact',
                                       'with': {'pattern': 'vitest-blob-*', 'path': 'blob', 'merge-multiple': True}},
                                      {'env': {'SHARD_COUNT': '${{ needs.plan.outputs.count }}'}, 'run': GH_ASSERT},
                                      {'run': 'pnpm exec vitest run --merge-reports=blob --coverage'},
                                      {'run': 'pnpm exec vitest run --merge-reports=blob --reporter=json '
                                              '--outputFile.json=report/merged.json'},
                                      {'run': "pnpm exec vitest run -t '^$' --reporter=json "
                                              '--outputFile.json=report/collected.json'},
                                      {'run': COUNT_CHECK},
                                      {'env': {'BASE_REF': '${{ github.base_ref }}'},
                                       'run': 'pipx run "diff-cover==${DIFF_COVER_VERSION}" '
                                              'coverage/cobertura-coverage.xml '
                                              '--compare-branch="origin/${BASE_REF:-main}" --fail-under=80'}],
                         'changelog': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                       {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' ') "
                                                          '}}'},
                                        'run': 'bash .claude/ci-gates.sh changelog "$BASE_REF"'}],
                         'comment-hygiene': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                             {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                      'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' "
                                                                "') }}"},
                                              'run': 'bash .claude/ci-gates.sh comments "$BASE_REF"'}],
                         'gate-ratchet': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                          {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                   'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' "
                                                             "') }}"},
                                           'run': 'bash .claude/ci-gates.sh ratchet "$BASE_REF"'}],
                         'dependency-review': [{'uses': 'actions/dependency-review-action',
                                                'with': {'fail-on-severity': 'high'}}]}},
 'azure-ts': {'jobs': {'plan': {'timeoutInMinutes': 5},
                       'quality': {'timeoutInMinutes': 20},
                       'test': {'dependsOn': 'plan',
                                'timeoutInMinutes': 20,
                                'variables': {'shardCount': "$[ dependencies.plan.outputs['shards.count'] ]"},
                                'strategy': {'matrix': "$[ dependencies.plan.outputs['shards.matrix'] ]"}},
                       'coverage': {'dependsOn': ['plan', 'test'],
                                    'timeoutInMinutes': 10,
                                    'variables': {'shardCount': "$[ dependencies.plan.outputs['shards.count'] ]"}}},
              'steps': {'plan': [{'checkout': 'self'},
                                 {'task': 'NodeTool@0', 'inputs': {'versionSpec': '26.x'}},
                                 {'bash': 'npm install -g "$(node -p '
                                          '"require(\'./package.json\').packageManager.split(\'+\')[0]")"'},
                                 {'bash': 'pnpm install --frozen-lockfile'},
                                 {'bash': AZ_PLAN}],
                        'quality': [{'checkout': 'self', 'fetchDepth': 0},
                                    {'task': 'NodeTool@0', 'inputs': {'versionSpec': '26.x'}},
                                    {'bash': 'npm install -g "$(node -p '
                                             '"require(\'./package.json\').packageManager.split(\'+\')[0]")"'},
                                    {'bash': 'pnpm install --frozen-lockfile'},
                                    {'template': 'azure-pipelines/templatecentral-gates.yml'},
                                    {'bash': 'pnpm run check'},
                                    {'bash': 'pnpm exec jscpd'}],
                        'test': [{'checkout': 'self'},
                                 {'task': 'NodeTool@0', 'inputs': {'versionSpec': '26.x'}},
                                 {'bash': 'npm install -g "$(node -p '
                                          '"require(\'./package.json\').packageManager.split(\'+\')[0]")"'},
                                 {'bash': 'pnpm install --frozen-lockfile'},
                                 {'bash': AZ_VALID},
                                 {'bash': 'pnpm exec vitest run --coverage --reporter=default --reporter=blob '
                                          '--outputFile.blob="blob/shard-$(shard).json" '
                                          '--shard="$(shard)/$(shardCount)"'},
                                 {'task': 'PublishPipelineArtifact@1',
                                  'inputs': {'targetPath': 'blob',
                                             'artifact': 'vitest-blob-$(shard)'}}],
                        'coverage': [{'checkout': 'self', 'fetchDepth': 0},
                                     {'task': 'NodeTool@0', 'inputs': {'versionSpec': '26.x'}},
                                     {'bash': 'npm install -g "$(node -p '
                                              '"require(\'./package.json\').packageManager.split(\'+\')[0]")"'},
                                     {'bash': 'pnpm install --frozen-lockfile'},
                                     {'task': 'DownloadPipelineArtifact@2',
                                      'inputs': {'patterns': 'vitest-blob-*/**',
                                                 'path': '$(Pipeline.Workspace)/blobs'}},
                                     {'bash': 'set -euo pipefail\n'
                                              '# No artifact name, so the task puts each artifact in its own '
                                              'subfolder: <path>/<artifact>/*.json.\n'
                                              'mkdir -p blob\n'
                                              'cp "$(Pipeline.Workspace)"/blobs/*/*.json blob/\n'},
                                     {'bash': AZ_ASSERT},
                                     {'bash': 'set -euo pipefail\n'
                                              '# writes coverage/cobertura-coverage.xml\n'
                                              'pnpm exec vitest run --merge-reports=blob --coverage\n'},
                                     {'bash': 'pnpm exec vitest run --merge-reports=blob --reporter=json '
                                              '--outputFile.json=report/merged.json'},
                                     {'bash': "pnpm exec vitest run -t '^$' --reporter=json "
                                              '--outputFile.json=report/collected.json'},
                                     {'bash': COUNT_CHECK},
                                     {'bash': 'set -euo pipefail\n'
                                              'target=${SYSTEM_PULLREQUEST_TARGETBRANCH:-main}\n'
                                              'pipx run "diff-cover==$(diffCoverVersion)" '
                                              'coverage/cobertura-coverage.xml '
                                              '--compare-branch="origin/${target#refs/heads/}" --fail-under=80\n'}]}},
 'github-py': {'jobs': {'quality': {'runs-on': 'ubuntu-latest', 'timeout-minutes': 20},
                        'changelog': {'if': "github.event_name == 'pull_request'",
                                      'runs-on': 'ubuntu-latest',
                                      'timeout-minutes': 5},
                        'comment-hygiene': {'if': "github.event_name == 'pull_request'",
                                            'runs-on': 'ubuntu-latest',
                                            'timeout-minutes': 5},
                        'gate-ratchet': {'if': "github.event_name == 'pull_request'",
                                         'runs-on': 'ubuntu-latest',
                                         'timeout-minutes': 5},
                        'dependency-review': {'if': "github.event_name == 'pull_request'",
                                              'runs-on': 'ubuntu-latest',
                                              'timeout-minutes': 5}},
               'steps': {'quality': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                     {'uses': 'actions/setup-python',
                                      'with': {'python-version': '3.14',
                                               'cache': 'pip',
                                               'cache-dependency-path': 'requirements*.txt'}},
                                     {'if': "hashFiles('uv.lock') != ''", 'uses': 'astral-sh/setup-uv'},
                                     {'run': 'set -euo pipefail\n'
                                             'pip install -r requirements.txt\n'
                                             'if [ -f requirements-dev.txt ]; then pip install -r '
                                             'requirements-dev.txt; fi\n'},
                                     {'run': 'bash .claude/ci-gates.sh deps'},
                                     {'run': 'bash .claude/verify-harness.sh'},
                                     {'run': 'bash scripts/check-docs.sh'},
                                     {'run': 'bash .claude/ci-gates.sh testbudget'},
                                     {'run': 'bash .claude/ci-gates.sh nosonar'},
                                     {'run': 'ruff check src/ test/ && ruff format --check src/ test/'},
                                     {'run': 'python -m pyright src/'},
                                     {'run': 'npx --yes jscpd@${JSCPD_VERSION}'},
                                     {'run': 'python -m pytest test/ --cov=src --cov-report=xml -q'},
                                     {'env': {'BASE_REF': '${{ github.base_ref }}'},
                                      'run': 'pipx run "diff-cover==${DIFF_COVER_VERSION}" coverage.xml '
                                             '--compare-branch="origin/${BASE_REF:-main}" --fail-under=80'},
                                     {'env': {'BASE_REF': '${{ github.base_ref }}'},
                                      'run': 'bash .claude/ci-gates.sh secrets "$BASE_REF"'}],
                         'changelog': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                       {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' ') "
                                                          '}}'},
                                        'run': 'bash .claude/ci-gates.sh changelog "$BASE_REF"'}],
                         'comment-hygiene': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                             {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                      'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' "
                                                                "') }}"},
                                              'run': 'bash .claude/ci-gates.sh comments "$BASE_REF"'}],
                         'gate-ratchet': [{'uses': 'actions/checkout', 'with': {'fetch-depth': 0}},
                                          {'env': {'BASE_REF': '${{ github.base_ref }}',
                                                   'LABELS': "${{ join(github.event.pull_request.labels.*.name, ' "
                                                             "') }}"},
                                           'run': 'bash .claude/ci-gates.sh ratchet "$BASE_REF"'}],
                         'dependency-review': [{'uses': 'actions/dependency-review-action',
                                                'with': {'fail-on-severity': 'high'}}]}},
 'azure-py': {'jobs': {'quality': {'timeoutInMinutes': 20}},
              'steps': {'quality': [{'checkout': 'self', 'fetchDepth': 0},
                                    {'task': 'UsePythonVersion@0', 'inputs': {'versionSpec': '3.14'}},
                                    {'bash': 'set -euo pipefail\n'
                                             'python -m pip install -r requirements.txt\n'
                                             'if [ -f requirements-dev.txt ]; then python -m pip install -r '
                                             'requirements-dev.txt; fi\n'
                                             '# the deps gate exports uv.lock with uv\n'
                                             'if [ -f uv.lock ]; then python -m pip install uv; fi\n'},
                                    {'template': 'azure-pipelines/templatecentral-gates.yml'},
                                    {'bash': 'ruff check src/ test/ && ruff format --check src/ test/'},
                                    {'bash': 'python -m pyright src/'},
                                    {'bash': 'npx --yes jscpd@$(JSCPD_VERSION)'},
                                    {'bash': 'python -m pytest test/ --cov=src --cov-report=xml -q'},
                                    {'bash': 'set -euo pipefail\n'
                                             'target=${SYSTEM_PULLREQUEST_TARGETBRANCH:-main}\n'
                                             'pipx run "diff-cover==$(DIFF_COVER_VERSION)" coverage.xml '
                                             '--compare-branch="origin/${target#refs/heads/}" --fail-under=80\n'}]}},
 'azure-gates': {'steps': {'(gates include)': [{'bash': 'bash .claude/verify-harness.sh'},
                                               {'bash': 'bash scripts/check-docs.sh'},
                                               {'bash': 'bash .claude/ci-gates.sh testbudget'},
                                               {'bash': 'bash .claude/ci-gates.sh secrets '
                                                        '"${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"'},
                                               {'bash': 'bash .claude/ci-gates.sh deps'},
                                               {'bash': 'bash .claude/ci-gates.sh nosonar'},
                                               {'bash': 'bash .claude/ci-gates.sh changelog '
                                                        '"${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"',
                                                'env': {'LABELS': '$(LABELS)'}},
                                               {'bash': 'bash .claude/ci-gates.sh comments '
                                                        '"${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"',
                                                'env': {'LABELS': '$(LABELS)'}},
                                               {'bash': 'bash .claude/ci-gates.sh ratchet '
                                                        '"${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"',
                                                'env': {'LABELS': '$(LABELS)'}}]}}}

for _h, _p in PINNED.items():
    MANIFEST[_h]["pins"] = _p
def norm_step(st):
    if not isinstance(st, dict):
        return st
    d = {k: v for k, v in st.items() if k not in ("name", "displayName")}
    if isinstance(d.get("uses"), str):
        d["uses"] = d["uses"].split("@")[0]
    return d
def manifest_errors(rel, doc, entry, needs_key, gate_file=False):
    if gate_file:
        jobs = {"(gates include)": {"steps": doc.get("steps") if isinstance(doc, dict) else None}}
    elif isinstance(doc.get("jobs"), dict):
        jobs = doc["jobs"]
    elif isinstance(doc.get("jobs"), list):
        jobs = {j.get("job"): j for j in doc["jobs"] if isinstance(j, dict)}
    else:
        jobs = {}
    if not gate_file:
        for name, node in jobs.items():
            if name not in entry["needs"]:
                errors.append(f"{rel}: job {name} is not in the required-gate manifest")
        for name, expected in entry["needs"].items():
            node = jobs.get(name)
            if node is None:
                errors.append(f"{rel}: required job {name} is missing")
                continue
            got = node.get(needs_key) or []
            got = [got] if isinstance(got, str) else got
            if sorted(got) != sorted(expected):
                errors.append(f"{rel}: job {name} must have {needs_key} {expected}, found {got}")
    pins = entry["pins"]
    for name, node in jobs.items():
        if not gate_file and isinstance(node, dict) and name in pins["jobs"]:
            meta = {k: v for k, v in node.items() if k not in ("steps", "job")}
            want = pins["jobs"][name]
            for k in sorted(set(meta) | set(want), key=str):
                if meta.get(k) != want.get(k):
                    errors.append(f"{rel}: job {name} key {k} must be {want.get(k)!r}, found {meta.get(k)!r}")
    for name, want in pins["steps"].items():
        node = jobs.get(name)
        steps = node.get("steps") if isinstance(node, dict) else None
        if not isinstance(steps, list):
            continue
        got = [norm_step(st) for st in steps]
        if got != want:
            at = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), min(len(got), len(want)))
            errors.append(f"{rel}: job {name} steps differ from the pinned ordered list at step {at + 1}: expected {want[at] if at < len(want) else 'end of list'}, found {got[at] if at < len(got) else 'end of list'}")
    for gate, job, key, text in entry["gates"]:
        node = jobs.get(job)
        steps = node.get("steps") if isinstance(node, dict) else None
        found = [st for st in steps if isinstance(st, dict) and isinstance(st.get(key), str) and st[key].rstrip() == text.rstrip()] if isinstance(steps, list) else []
        if not found:
            errors.append(f"{rel}: required gate '{gate}' is missing from job {job}: expected {key}: {text.splitlines()[0] if text else text}")
        for st in found:
            if "shell" in st:
                errors.append(f"{rel}: required gate '{gate}' in job {job} must not set shell: {st['shell']}")
GH_ENV_KEYS = {"DIFF_COVER_VERSION", "JSCPD_VERSION", "SHARD_MAX", "NODE_OPTIONS"}
USES_LINE = re.compile(r"^\s*(?:-\s+)?uses:")
USES_PINNED = re.compile(r"^\s*(?:-\s+)?uses:\s*[\w.-]+/[\w./-]+@[0-9a-f]{40} # v\d[\w.+-]*\s*$")
def workflow_errors(rel, doc, lines):
    if "defaults" in doc:
        errors.append(f"{rel}: workflow-level defaults is not allowed: {doc['defaults']}")
    if doc.get("permissions") != {"contents": "read"}:
        errors.append(f"{rel}: workflow permissions must be exactly {{contents: read}}, found {doc.get('permissions')!r}")
    triggers = doc.get(True, doc.get("on"))
    if not isinstance(triggers, dict) or set(triggers) != {"pull_request", "push"}:
        errors.append(f"{rel}: workflow triggers must be exactly pull_request and push, found {triggers!r}")
    env = doc.get("env")
    if not isinstance(env, dict) or not set(env) <= GH_ENV_KEYS:
        errors.append(f"{rel}: workflow env keys must be within {sorted(GH_ENV_KEYS)}, found {env!r}")
    for i, l in enumerate(lines):
        if "pull_request_target" in l:
            errors.append(f"{rel}:{i + 1}: pull_request_target is not allowed: {l.strip()}")
        if USES_LINE.match(l) and not USES_PINNED.match(l):
            errors.append(f"{rel}:{i + 1}: uses must be pinned to a full commit SHA with the version in a trailing comment: {l.strip()}")
    for name, job in (doc.get("jobs") or {}).items():
        for st in (job.get("steps") or []) if isinstance(job, dict) else []:
            run = st.get("run") if isinstance(st, dict) else None
            if isinstance(run, str) and re.search(r"\$\{\{\s*(secrets\.|github\.token)|\b(echo|printf)\b[^\n]*(TOKEN|SECRET|PASSWORD|API_KEY)", run):
                errors.append(f"{rel}: job {name} step prints or interpolates a secret in run: {run.splitlines()[0]}")
def load_yaml(rel, path):
    try:
        return yaml.load(open(path).read(), Loader=UniqueKeyLoader)
    except MergeKeyError as e:
        errors.append(f"{rel}: {e}")
    except yaml.YAMLError as e:
        errors.append(f"{rel}: not parseable YAML, so the guards cannot check it: {e}")
    return None
for host, rel in files.items():
    lines = open(f"{root}/{rel}").read().split("\n")
    doc = load_yaml(rel, f"{root}/{rel}")
    if doc is not None:
        condition_errors(rel, doc, host)
        manifest_errors(rel, doc, MANIFEST[host], "needs" if host.startswith("github") else "dependsOn")
        if host.startswith("github"):
            workflow_errors(rel, doc, lines)
    for i, l in enumerate(lines):
        code = re.sub(r"\s#\s.*$", "", l)
        if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)", code):
            errors.append(f"{rel}:{i + 1}: gate-neutralising construct: {l.strip()}")
    pins = [(n, l) for n, l in enumerate(lines) if re.match(r"^\s*(DIFF_COVER_VERSION|diffCoverVersion|JSCPD_VERSION):", l)]
    if not any("diff" in l.lower() for _, l in pins):
        errors.append(f"{rel}: missing the diff-cover version variable")
    for n, l in pins:
        if not re.match(r"^\s*\w+:\s*\"\d+\.\d+\.\d+\"(\s|$)", l):
            errors.append(f"{rel}:{n + 1}: tool version must be an exact x.y.z string: {l.strip()}")
    for n, l in enumerate(lines):
        if "upload-artifact" in l and "uses:" in l:
            a, b = step_bounds(lines, n)
            if not any(re.match(r"^\s*if-no-files-found:\s*error\s*$", lines[k]) for k in range(a, b)):
                errors.append(f"{rel}:{n + 1}: upload-artifact step must keep `if-no-files-found: error`")
gates = "azure/azure-pipelines/templatecentral-gates.yml"
for i, l in enumerate(open(f"{root}/{gates}").read().split("\n")):
    code = re.sub(r"\s#\s.*$", "", l)
    if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)", code):
        errors.append(f"{gates}:{i + 1}: gate-neutralising construct: {l.strip()}")
gate_doc = load_yaml(gates, f"{root}/{gates}")
if gate_doc is not None:
    gate_include_errors(gates, gate_doc)
    if set(gate_doc) != {"steps"}:
        errors.append(f"{gates}: the gates include must hold only a steps list (a parameters block can switch a gate off), found keys {sorted(map(str, gate_doc))}")
    manifest_errors(gates, gate_doc, MANIFEST["azure-gates"], None, True)
print("\n".join(errors))
sys.exit(1 if errors else 0)
PY
static_check() { python3 "$T/static.py" "$1"; }
if out=$(static_check "$CI_DIR" 2>&1); then ok "static guards: no gate-neutralising construct, merge and diff-cover present and unguarded"; else bad "static guards flagged the shipped templates: $out"; fi

# 6. mutation proof: each mutation of a copy must be caught
mutate() { # mutate <label> <relative file> <old text> <new text> <static|github> [expected message substring]; \n in the texts is a newline
  local label=$1 rel=$2 kind=$5 want=${6:-}
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
    if out=$(static_check "$T/mut" 2>&1); then bad "mutation not caught: $label"
    elif [[ -n "$want" && "$out" != *"$want"* ]]; then bad "mutation caught by the wrong check, expected '$want': $label -> $(head -1 <<<"$out")"
    else ok "mutation caught: $label -> $(head -1 <<<"$out")"; fi
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
mutate "job-level if: always() on the coverage job (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' '  coverage:\n    if: always()\n    needs: [plan, test]\n' static
mutate "|| true inside the Azure merge script (azure-ts)" azure-ts/azure-pipelines.yml 'vitest run --merge-reports=blob --coverage' 'vitest run --merge-reports=blob --coverage || true' static
mutate "GitHub shard assertion replaced by a no-op" github-ts/.github/workflows/ci.yml "found=\$(find blob -name \"*.json\" | wc -l | tr -d ' ')" "found=\$SHARD_COUNT" github
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
mutate "job-level if != pull_request on the coverage job (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' "  coverage:\n    if: github.event_name != 'pull_request'\n    needs: [plan, test]\n" static
mutate "job-level if != pull_request on the quality job (github-py)" github-py/.github/workflows/ci.yml '  quality:\n    runs-on: ubuntu-latest\n' "  quality:\n    if: github.event_name != 'pull_request'\n    runs-on: ubuntu-latest\n" static
mutate "job-level if: false on a PR-only job (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" '  changelog:\n    if: false' static
mutate "different condition on a PR-only job (github-py comment-hygiene)" github-py/.github/workflows/ci.yml "  comment-hygiene:\n    if: github.event_name == 'pull_request'" "  comment-hygiene:\n    if: github.event_name != 'push'" static
mutate "PR-only condition on a non-PR-only job (github-ts quality)" github-ts/.github/workflows/ci.yml '  quality:\n    runs-on: ubuntu-latest\n' "  quality:\n    if: github.event_name == 'pull_request'\n    runs-on: ubuntu-latest\n" static
mutate "job-level condition: false on the coverage job (azure-ts)" azure-ts/azure-pipelines.yml '  - job: coverage\n' '  - job: coverage\n    condition: false\n' static
mutate "job-level condition on the quality job (azure-py)" azure-py/azure-pipelines.yml '  - job: quality\n' "  - job: quality\n    condition: ne(variables['Build.Reason'], 'PullRequest')\n" static
mutate "explicit if: github.event_name != pull_request on the diff-cover (coverage) job (github-py)" github-py/.github/workflows/ci.yml '    timeout-minutes: 20\n' "    timeout-minutes: 20\n    if: github.event_name != 'pull_request'\n" static
mutate "job head with a trailing comment and a forbidden if (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" '  changelog: # PR only\n    if: false' static
mutate "job head with a trailing comment and a forbidden condition (azure-ts coverage)" azure-ts/azure-pipelines.yml '  - job: coverage\n' '  - job: coverage # merge\n    condition: false\n' static
mutate "Azure stages: template with a stage-level condition (azure-py)" azure-py/azure-pipelines.yml 'trigger:' "stages:\n  - stage: s\n    condition: false\n    jobs:\n      - job: x\n        steps: []\ntrigger:" static
mutate "quoted \"stages\" key with a stage-level condition (azure-py)" azure-py/azure-pipelines.yml 'trigger:' '"stages":\n  - stage: s\n    "condition": false\n    jobs:\n      - job: x\n        steps: []\ntrigger:' static
mutate "space before the colon in stages : and a stage condition (azure-py)" azure-py/azure-pipelines.yml 'trigger:' 'stages :\n  - stage: s\n    condition : false\n    jobs:\n      - job: x\n        steps: []\ntrigger:' static
mutate "double-quoted \"if\" key on a job (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" '  changelog:\n    "if": false' static
mutate "single-quoted 'if' key on a job (github-py)" github-py/.github/workflows/ci.yml '    timeout-minutes: 20\n' "    timeout-minutes: 20\n    'if': false\n" static
mutate "space before the colon in if : false on a job (github-py)" github-py/.github/workflows/ci.yml '    timeout-minutes: 20\n' '    timeout-minutes: 20\n    if : false\n' static
mutate "job key at column 6 after -   job: with a condition (azure-ts)" azure-ts/azure-pipelines.yml '  - job: coverage\n' '  -   job: zz\n      condition: false\n      steps: []\n  - job: coverage\n' static
mutate "duplicate if key hiding a forbidden value (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" "  changelog:\n    if: false\n    if: github.event_name == 'pull_request'" static
mutate "merge key giving a job if: false (github-ts)" github-ts/.github/workflows/ci.yml 'jobs:\n' 'jobs:\n  base: &off\n    if: false\n  merged:\n    <<: *off\n' static
mutate "merge key in a job mapping (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" "  changelog:\n    <<: {if: false}" static
mutate "empty jobs mapping (github-py)" github-py/.github/workflows/ci.yml 'jobs:\n  quality:' 'jobs: {}\nx-unused:\n  quality:' static
mutate "empty jobs list (azure-py)" azure-py/azure-pipelines.yml 'jobs:\n  - job: quality\n' 'jobs: []\nx-unused:\n  - job: quality\n' static
mutate "empty stages list and no jobs (azure-ts)" azure-ts/azure-pipelines.yml 'jobs:\n' 'stages: []\nx-unused:\n' static
mutate "condition: false on the secrets step (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '    displayName: Secret scan (gitleaks CLI, checksum-verified)' '    condition: false\n    displayName: Secret scan (gitleaks CLI, checksum-verified)' static
mutate "enabled: false on the dependency step (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '    displayName: Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)' '    enabled: false\n    displayName: Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)' static
mutate "quoted \"condition\" on the secrets step (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '    displayName: Secret scan (gitleaks CLI, checksum-verified)' '    "condition": false\n    displayName: Secret scan (gitleaks CLI, checksum-verified)' static
mutate "continueOnError on the changelog step (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '    displayName: Changelog gate' '    continueOnError: true\n    displayName: Changelog gate' static
mutate "step-level if: false on Dependency audit (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Dependency audit' '      - if: false\n        name: Dependency audit' static
mutate "step-level if: false on Harness integrity (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Harness integrity' '      - if: false\n        name: Harness integrity' static
mutate "step-level if: false on Secret scan (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Secret scan' '      - if: false\n        name: Secret scan' static
mutate "step-level if: false on Require one blob report per shard (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Require one blob report per shard' '      - if: false\n        name: Require one blob report per shard' static
mutate "step-level if: false on the Tests step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Tests (shard' '      - if: false\n        name: Tests (shard' static
mutate "step-level if: false on the changelog step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Require CHANGELOG for src changes' '      - if: false\n        name: Require CHANGELOG for src changes' static
mutate "step-level if: false on the docs check step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Docs check (links and paths in README.md, AGENTS.md, docs/)' '      - if: false\n        name: Docs check (links and paths in README.md, AGENTS.md, docs/)' static
mutate "step-level if: false on the comment step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Require no change-narration comments' '      - if: false\n        name: Require no change-narration comments' static
mutate "step-level if: false on Dependency audit (github-py)" github-py/.github/workflows/ci.yml '      - name: Dependency audit' '      - if: false\n        name: Dependency audit' static
mutate "step-level if: false on Secret scan (github-py)" github-py/.github/workflows/ci.yml '      - name: Secret scan' '      - if: false\n        name: Secret scan' static
mutate "step-level if: false on the Tests step (github-py)" github-py/.github/workflows/ci.yml '      - name: Tests (serial' '      - if: false\n        name: Tests (serial' static
mutate "step-level if: false on the changelog step (github-py)" github-py/.github/workflows/ci.yml '      - name: Require CHANGELOG for src changes' '      - if: false\n        name: Require CHANGELOG for src changes' static
mutate "enabled: false on the merge step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Merge shard reports' '        enabled: false\n        displayName: Merge shard reports' static
mutate "enabled: false on the diff-cover step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Changed-line coverage' '        enabled: false\n        displayName: Changed-line coverage' static
mutate "enabled: false on the diff-cover step (azure-py)" azure-py/azure-pipelines.yml '        displayName: Changed-line coverage' '        enabled: false\n        displayName: Changed-line coverage' static
mutate "condition: false on Assert all shard reports present (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Assert all shard reports present' '        condition: false\n        displayName: Assert all shard reports present' static
mutate "condition: false on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        condition: false\n        displayName: Tests (this shard' static
mutate "continueOnError: true on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        continueOnError: true\n        displayName: Tests (this shard' static
mutate "condition: false on the Tests step (azure-py)" azure-py/azure-pipelines.yml '        displayName: Tests with coverage' '        condition: false\n        displayName: Tests with coverage' static
mutate "timeoutInMinutes: 0 on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        timeoutInMinutes: 0\n        displayName: Tests (this shard' static
mutate "job-level continue-on-error (github-ts coverage)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' '  coverage:\n    continue-on-error: true\n    needs: [plan, test]\n' static
mutate "job-level continueOnError (azure-py quality)" azure-py/azure-pipelines.yml '  - job: quality\n' '  - job: quality\n    continueOnError: true\n' static
mutate "step include of an unchecked template (azure-py)" azure-py/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml' '      - template: azure-pipelines/other.yml' static
mutate "allowlisted setup-uv step with a changed if value (github-py)" github-py/.github/workflows/ci.yml "      - if: hashFiles('uv.lock') != ''" "      - if: hashFiles('other.lock') != ''" static
mutate "allowlisted setup-uv step with an extra neutraliser (github-py)" github-py/.github/workflows/ci.yml "      - if: hashFiles('uv.lock') != ''" "      - continue-on-error: true\n        if: hashFiles('uv.lock') != ''" static
mutate "secret scan deleted (github-ts)" github-ts/.github/workflows/ci.yml "      - name: Secret scan (gitleaks CLI, checksum-verified)\\n        env:\\n          BASE_REF: \${{ github.base_ref }}\\n        run: bash .claude/ci-gates.sh secrets \"\$BASE_REF\"\\n" "" static
mutate "dependency audit deleted (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)\n        run: bash .claude/ci-gates.sh deps\n' '' static
mutate "harness integrity deleted (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Harness integrity\n        run: bash .claude/verify-harness.sh\n' '' static
mutate "secret scan deleted (azure gates)" azure/azure-pipelines/templatecentral-gates.yml "  - bash: bash .claude/ci-gates.sh secrets \"\${SYSTEM_PULLREQUEST_TARGETBRANCH:-}\"\\n    displayName: Secret scan (gitleaks CLI, checksum-verified)\\n" "" static
mutate "harness integrity deleted (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '  - bash: bash .claude/verify-harness.sh\n    displayName: Harness integrity\n' '' static
mutate "docs check deleted (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Docs check (links and paths in README.md, AGENTS.md, docs/)\n        run: bash scripts/check-docs.sh\n' '' static
mutate "docs check deleted (github-py)" github-py/.github/workflows/ci.yml '      - name: Docs check (links and paths in README.md, AGENTS.md, docs/)\n        run: bash scripts/check-docs.sh\n' '' static
mutate "docs check deleted (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '  - bash: bash scripts/check-docs.sh\n    displayName: Docs check (links and paths in README.md, AGENTS.md, docs/)\n' '' static
mutate "test budget deleted (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Test budget (test code <= 35 lines per 100 source lines, ADR-0001)\n        run: bash .claude/ci-gates.sh testbudget\n' '' static
mutate "test budget deleted (github-py)" github-py/.github/workflows/ci.yml '      - name: Test budget (test code <= 35 lines per 100 source lines, ADR-0001)\n        run: bash .claude/ci-gates.sh testbudget\n' '' static
mutate "test budget deleted (azure gates)" azure/azure-pipelines/templatecentral-gates.yml '  - bash: bash .claude/ci-gates.sh testbudget\n    displayName: Test budget (test code <= 35 lines per 100 source lines, ADR-0001)\n' '' static
mutate "test budget made non-failing (github-py)" github-py/.github/workflows/ci.yml 'run: bash .claude/ci-gates.sh testbudget' 'run: bash .claude/ci-gates.sh testbudget || true' static
mutate "docs check made non-failing (github-ts)" github-ts/.github/workflows/ci.yml 'run: bash scripts/check-docs.sh' 'run: bash scripts/check-docs.sh || true' static
mutate "Tests step deleted (azure-ts)" azure-ts/azure-pipelines.yml "      - bash: pnpm exec vitest run --coverage --reporter=default --reporter=blob --outputFile.blob=\"blob/shard-\$(shard).json\" --shard=\"\$(shard)/\$(shardCount)\"\\n        displayName: Tests (this shard, coverage in the blob report)\\n" "" static
mutate "needs removed from coverage (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' '  coverage:\n' static
mutate "dependsOn removed from coverage (azure-ts)" azure-ts/azure-pipelines.yml '    dependsOn: [plan, test]\n' '' static
mutate "set +e prefixed to the Tests command (github-ts)" github-ts/.github/workflows/ci.yml 'run: pnpm exec vitest run --coverage --reporter=default' 'run: set +e; pnpm exec vitest run --coverage --reporter=default' static
mutate "&& exit 0 appended to the Tests command (github-ts)" github-ts/.github/workflows/ci.yml "--shard=\"\${{ matrix.shard }}/\${{ needs.plan.outputs.count }}\"\\n" "--shard=\"\${{ matrix.shard }}/\${{ needs.plan.outputs.count }}\" && exit 0\\n" static
mutate "shell: bash {0} on the dependency audit (github-ts)" github-ts/.github/workflows/ci.yml '        run: bash .claude/ci-gates.sh deps\n' '        run: bash .claude/ci-gates.sh deps\n        shell: bash {0}\n' static
mutate "dependency audit run replaced by echo skip (github-ts)" github-ts/.github/workflows/ci.yml 'run: bash .claude/ci-gates.sh deps' 'run: echo skip' static
mutate "needs edge removed from test (github-ts)" github-ts/.github/workflows/ci.yml '  test:\n    needs: plan\n' '  test:\n' static
mutate "unlisted extra job (github-py)" github-py/.github/workflows/ci.yml '  changelog:\n' '  extra:\n    runs-on: ubuntu-latest\n    steps: []\n  changelog:\n' static
mutate "gates include removed from the quality job (azure-py)" azure-py/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml\n' '' static
mutate "flow-style job mapping with a forbidden if (github-ts coverage)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' '  coverage: { needs: [plan, test], if: false }\n  extra:\n    needs: test\n' static
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

# 6b. pinned step options, defaults, step order, shard matrix, gate-include parameters
mutate "working-directory on the diff-cover step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Changed-line coverage (>= 80%)\n        env:' '      - name: Changed-line coverage (>= 80%)\n        working-directory: docs\n        env:' static "differ from the pinned ordered list"
mutate "BASE_REF env changed on the diff-cover step (github-ts)" "github-ts/.github/workflows/ci.yml" "          BASE_REF: \${{ github.base_ref }}\n        run: pipx run" "          BASE_REF: HEAD\n        run: pipx run" "static" "differ from the pinned ordered list"
mutate "env added on the tests step (github-py)" github-py/.github/workflows/ci.yml '      - name: Tests (serial; pytest-cov writes coverage.xml)\n' '      - name: Tests (serial; pytest-cov writes coverage.xml)\n        env: { PYTEST_ADDOPTS: --co }\n' static "differ from the pinned ordered list"
mutate "workingDirectory on the diff-cover step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Changed-line coverage (>= 80%)' '        workingDirectory: docs\n        displayName: Changed-line coverage (>= 80%)' static "differ from the pinned ordered list"
mutate "count comparison neutered (github-ts)" github-ts/.github/workflows/ci.yml "process.exit(ok ? 0 : 1);" "process.exit(0);" static "required gate 'test count equality'"
mutate "|| true on the unsharded count step (azure-ts)" azure-ts/azure-pipelines.yml "outputFile.json=report/collected.json" "outputFile.json=report/collected.json || true" static
mutate "|| true on the merged report step (github-ts)" github-ts/.github/workflows/ci.yml "outputFile.json=report/merged.json" "outputFile.json=report/merged.json || true" static
mutate "target on the merge step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Merge shard reports' '        target: host\n        displayName: Merge shard reports' static "differ from the pinned ordered list"
mutate "LABELS env changed on the changelog gate (azure gates)" "azure/azure-pipelines/templatecentral-gates.yml" "    displayName: Changelog gate\n    env: { LABELS: \$(LABELS) }" "    displayName: Changelog gate\n    env: { LABELS: skip-changelog }" "static" "differ from the pinned ordered list"
mutate "workflow-level defaults with a working-directory (github-ts)" github-ts/.github/workflows/ci.yml 'permissions: { contents: read }\n' 'permissions: { contents: read }\ndefaults:\n  run:\n    working-directory: docs\n' static "workflow-level defaults"
mutate "job-level defaults with a working-directory (github-py quality)" github-py/.github/workflows/ci.yml '  quality:\n    runs-on: ubuntu-latest\n' '  quality:\n    defaults:\n      run:\n        working-directory: docs\n    runs-on: ubuntu-latest\n' static "key defaults must be None"
mutate "job-level env added to the coverage job (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: [plan, test]\n' '  coverage:\n    env: { BASE_REF: HEAD }\n    needs: [plan, test]\n' static "key env must be None"
mutate "step inserted before the first gate (github-ts quality)" github-ts/.github/workflows/ci.yml '      - name: Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)\n        run: bash .claude/ci-gates.sh deps\n' '      - run: echo "{}" > .claude/dep-audit-allow.txt\n      - name: Dependency audit (high/critical; allowlist .claude/dep-audit-allow.txt)\n        run: bash .claude/ci-gates.sh deps\n' static "differ from the pinned ordered list"
mutate "step inserted between install and the gates (azure-py)" azure-py/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml\n' '      - bash: rm -f .jscpd.json\n      - template: azure-pipelines/templatecentral-gates.yml\n' static "differ from the pinned ordered list"
mutate "gates reordered (azure gates, harness integrity after secret scan)" "azure/azure-pipelines/templatecentral-gates.yml" "  - bash: bash .claude/verify-harness.sh\n    displayName: Harness integrity\n  - bash: bash scripts/check-docs.sh\n    displayName: Docs check (links and paths in README.md, AGENTS.md, docs/)\n  - bash: bash .claude/ci-gates.sh testbudget\n    displayName: Test budget (test code <= 35 lines per 100 source lines, ADR-0001)\n  - bash: bash .claude/ci-gates.sh secrets \"\${SYSTEM_PULLREQUEST_TARGETBRANCH:-}\"\n    displayName: Secret scan (gitleaks CLI, checksum-verified)\n" "  - bash: bash scripts/check-docs.sh\n    displayName: Docs check (links and paths in README.md, AGENTS.md, docs/)\n  - bash: bash .claude/ci-gates.sh testbudget\n    displayName: Test budget (test code <= 35 lines per 100 source lines, ADR-0001)\n  - bash: bash .claude/ci-gates.sh secrets \"\${SYSTEM_PULLREQUEST_TARGETBRANCH:-}\"\n    displayName: Secret scan (gitleaks CLI, checksum-verified)\n  - bash: bash .claude/verify-harness.sh\n    displayName: Harness integrity\n" "static" "differ from the pinned ordered list"
mutate "gates reordered (github-py, secret scan before tests)" "github-py/.github/workflows/ci.yml" "      # PR: the PR's commits; push: full history\n      - name: Secret scan (gitleaks CLI, checksum-verified)\n        env:\n          BASE_REF: \${{ github.base_ref }}\n        run: bash .claude/ci-gates.sh secrets \"\$BASE_REF\"\n" "" "static"
mutate "hard-coded shorter shard list (github-ts)" "github-ts/.github/workflows/ci.yml" "shard: \${{ fromJSON(needs.plan.outputs.shards) }}" "shard: [1]" "static" "key strategy must be"
mutate "hard-coded matrix (azure-ts)" "azure-ts/azure-pipelines.yml" "matrix: \$[ dependencies.plan.outputs['shards.matrix'] ]" "matrix: { shard1: { shard: 1 } }" "static" "key strategy must be"
mutate "constant shard count restored, larger than the file count (github-ts)" github-ts/.github/workflows/ci.yml "Math.min(Number(process.env.SHARD_MAX), files)" "Number(process.env.SHARD_MAX)" static "required gate 'shard plan'"
mutate "constant shard count restored, larger than the file count (azure-ts)" azure-ts/azure-pipelines.yml "Math.min(Number(process.env.SHARD_MAX), files)" "Number(process.env.SHARD_MAX)" static "required gate 'shard plan'"
mutate "empty shard count allowed (github-ts)" github-ts/.github/workflows/ci.yml "''|*[!0-9]*|0*|??????????*)" "*[!0-9]*|0*|??????????*)" static "shard count"
mutate "oversized shard count allowed (github-ts)" github-ts/.github/workflows/ci.yml "|0*|??????????*)" "|0*)" static "shard count"
mutate "empty shard count allowed (azure-ts)" azure-ts/azure-pipelines.yml "''|*[!0-9]*|0*|??????????*)" "*[!0-9]*|0*|??????????*)" static "shard count"
mutate "oversized shard count allowed (azure-ts)" azure-ts/azure-pipelines.yml "|0*|??????????*)" "|0*)" static "shard count"
mutate "zero test files no longer fails the plan (github-ts)" github-ts/.github/workflows/ci.yml "if (files < 1) {" "if (files < 0) {" static "required gate 'shard plan'"
mutate "parameters passed to the gates include (azure-ts)" azure-ts/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml\n' '      - template: azure-pipelines/templatecentral-gates.yml\n        parameters: { skipDeps: true }\n' static "differ from the pinned ordered list"
mutate "parameters passed to the gates include (azure-py)" azure-py/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml\n' '      - template: azure-pipelines/templatecentral-gates.yml\n        parameters: { runDeps: false }\n' static "differ from the pinned ordered list"
mutate "parameters block declared in the gates include" azure/azure-pipelines/templatecentral-gates.yml 'steps:\n' 'parameters:\n  - name: runDeps\n    default: true\nsteps:\n' static "only a steps list"

# 6c. supply chain: SHA pins, least-privilege token, no pull_request_target, no secret output, dependency review
mutate "action pinned by tag instead of SHA (github-ts)" github-ts/.github/workflows/ci.yml 'uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0' 'uses: actions/setup-node@v7' static "full commit SHA"
mutate "SHA pin without a version comment (github-py)" github-py/.github/workflows/ci.yml 'actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0' 'actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0' static "full commit SHA"
mutate "workflow permissions raised to write (github-ts)" github-ts/.github/workflows/ci.yml 'permissions: { contents: read }' 'permissions: { contents: write }' static "permissions must be exactly"
mutate "workflow permissions removed (github-py)" github-py/.github/workflows/ci.yml 'permissions: { contents: read }\n' '' static "permissions must be exactly"
mutate "pull_request_target trigger (github-ts)" github-ts/.github/workflows/ci.yml '  pull_request: { branches: [main, uat, develop] }' '  pull_request_target: { branches: [main, uat, develop] }' static "pull_request_target"
mutate "secret echoed in a run step (github-py)" "github-py/.github/workflows/ci.yml" "        run: bash .claude/ci-gates.sh nosonar" "        run: bash .claude/ci-gates.sh nosonar && echo \"\${{ secrets.DEPLOY_TOKEN }}\"" "static" "secret in run"
mutate "dependency-review job removed (github-ts)" github-ts/.github/workflows/ci.yml '  dependency-review:\n    if: github.event_name == '"'"'pull_request'"'"'\n    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n      # fails the PR when it adds a dependency with a high or critical advisory\n      - uses: actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0\n        with: { fail-on-severity: high }\n' '' static "required job dependency-review is missing"
mutate "dependency-review threshold lowered to critical (github-py)" github-py/.github/workflows/ci.yml 'fail-on-severity: high' 'fail-on-severity: critical' static "differ from the pinned ordered list"
mutate "dependency-review warn-only (github-ts)" github-ts/.github/workflows/ci.yml 'with: { fail-on-severity: high }' 'with: { fail-on-severity: high, warn-only: true }' static "differ from the pinned ordered list"
mutate "dependency-review action swapped for echo (github-py)" github-py/.github/workflows/ci.yml 'uses: actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0\n        with: { fail-on-severity: high }' 'run: echo skipped' static "dependency review at high"

# 9. Dependabot templates: version 2, the stack's ecosystem plus github-actions, weekly, minor and patch grouped
dependabot_check() { # dependabot_check <template-ci dir>
  python3 - "$1" <<'PY'
import sys
import yaml
want = {"github-ts": "npm", "github-py": "pip"}
bad = []
for host, eco in want.items():
    rel = f"{sys.argv[1]}/{host}/.github/dependabot.yml"
    try:
        doc = yaml.safe_load(open(rel))
    except (OSError, yaml.YAMLError) as e:
        bad.append(f"{rel}: unreadable: {e}")
        continue
    ups = doc.get("updates") if isinstance(doc, dict) else None
    if not isinstance(doc, dict) or doc.get("version") != 2 or not isinstance(ups, list):
        bad.append(f"{rel}: expected version 2 and an updates list")
        continue
    if sorted(u.get("package-ecosystem") for u in ups if isinstance(u, dict)) != sorted([eco, "github-actions"]):
        bad.append(f"{rel}: updates must cover exactly {eco} and github-actions")
    for u in ups:
        if not isinstance(u, dict):
            continue
        grp = (u.get("groups") or {}).get("minor-and-patch") or {}
        if (u.get("schedule") or {}).get("interval") != "weekly" or u.get("directory") != "/":
            bad.append(f"{rel}: {u.get('package-ecosystem')} must update / weekly")
        if sorted(grp.get("update-types") or []) != ["minor", "patch"] or grp.get("patterns") != ["*"]:
            bad.append(f"{rel}: {u.get('package-ecosystem')} must group minor and patch updates over *")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
if out=$(dependabot_check "$CI_DIR" 2>&1); then ok "dependabot templates: stack ecosystem plus github-actions, weekly, minor and patch grouped"; else bad "dependabot templates drifted: $out"; fi
dep_mutate() { # dep_mutate <label> <host> <old> <new>
  rm -rf "$T/mut" && cp -R "$CI_DIR" "$T/mut"
  python3 - "$T/mut/$2/.github/dependabot.yml" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2].replace("\\n", "\n"), sys.argv[3].replace("\\n", "\n")
s = open(p).read()
if old not in s:
    sys.exit("mutation target not found: " + old)
open(p, "w").write(s.replace(old, new))
PY
  if out=$(dependabot_check "$T/mut" 2>&1); then bad "mutation not caught: $1"; else ok "mutation caught: $1 -> $(head -1 <<<"$out")"; fi
}
dep_mutate "github-actions ecosystem removed (github-ts)" github-ts '  - package-ecosystem: github-actions' '  - package-ecosystem: docker'
dep_mutate "daily instead of weekly (github-py)" github-py 'interval: weekly' 'interval: daily'
dep_mutate "major updates grouped (github-ts)" github-ts 'update-types: [minor, patch]' 'update-types: [minor, patch, major]'
dep_mutate "stack ecosystem changed (github-py)" github-py 'package-ecosystem: pip' 'package-ecosystem: npm'

# 7. passWithNoTests must not appear anywhere in the seeded templates (it would let a project with no test files pass).
# Vitest itself fails a shard that gets no file (--shard=i/N with N above the file count), so the plan job derives N
# from the project: min(4, test files), and fails when there are none.
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

# 9. Gate manifest: verify-harness fails when lefthook or any CI file of a stack omits a gate listed in .claude/gates.txt
SHARED="$REPO_ROOT/skills/scaffold/shared"
gate_fixture() { # gate_fixture <dir> <ts|py> <github|azure>
  local d="$1" st="$2" host="$3" h
  rm -rf "$d" && mkdir -p "$d/.claude/hooks"
  cp "$SHARED/template/.claude/gates.txt" "$SHARED/template/.claude/verify-harness.sh" "$d/.claude/"
  cp "$SHARED/template-$st/lefthook.yml" "$d/lefthook.yml"
  if [[ "$host" == github ]]; then
    mkdir -p "$d/.github/workflows" && cp "$CI_DIR/github-$st/.github/workflows/ci.yml" "$d/.github/workflows/ci.yml"
  else
    mkdir -p "$d/azure-pipelines" && cp "$CI_DIR/azure-$st/azure-pipelines.yml" "$d/azure-pipelines.yml"
    cp "$CI_DIR/azure/azure-pipelines/templatecentral-gates.yml" "$d/azure-pipelines/templatecentral-gates.yml"
  fi
  echo x > "$d/.claude/hooks/a.sh"
  h=$(shasum -a 256 "$d/.claude/hooks/a.sh" | cut -d' ' -f1)
  printf '{"seeded_files":{"a":{"path":".claude/hooks/a.sh","origin_hash":"%s"}}}' "$h" > "$d/.claude/harness.json"
}
gate_verify() { (cd "$1" && bash .claude/verify-harness.sh 2>&1); }
for st in ts py; do
  for host in github azure; do
    gate_fixture "$T/gm" "$st" "$host"
    if out=$(gate_verify "$T/gm"); then ok "gate manifest: $st/$host lefthook and CI run every listed gate"; else bad "gate manifest: $st/$host omits a listed gate: $out"; fi
    while IFS='|' read -r gid lh ci; do
      [[ -z "$gid" || "$gid" == \#* ]] && continue
      files=(lefthook.yml); [[ "$host" == github ]] && files+=(.github/workflows/ci.yml) || files+=(azure-pipelines/templatecentral-gates.yml azure-pipelines.yml)
      for f in "${files[@]}"; do
        want=$ci; [[ "$f" == lefthook.yml ]] && want=$lh
        [[ "$want" == "-" ]] && continue
        grep -qF -- "$want" "$T/gm/$f" || continue
        gate_fixture "$T/gmm" "$st" "$host"
        sed -i.bak "s#$want#removed-gate#g" "$T/gmm/$f"
        if out=$(gate_verify "$T/gmm"); then bad "mutation not caught: $st/$host $f drops gate $gid"; else ok "mutation caught: $st/$host $f drops gate $gid"; fi
      done
    done < "$SHARED/template/.claude/gates.txt"
  done
done

if [[ $fail -eq 0 ]]; then
  echo "test-ci-templates: all passed"
else
  echo "test-ci-templates: failures" >&2
  exit 1
fi
