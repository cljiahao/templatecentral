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
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required by the job-condition guard: pip install pyyaml==6.0.3")
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
# Only the PR-only gates may carry a job- or stage-level if/condition, and only this exact one: the gates themselves
# skip off-PR runs, so any other if/condition on a job or stage could silently switch a gate off. The templates are
# parsed with PyYAML and walked structurally, so quoting, spacing, indent, flow style and anchors cannot hide a key.
PR_ONLY_JOBS = {"changelog", "readme-freshness", "comment-hygiene"}
PR_ONLY_IF = "github.event_name == 'pull_request'"
# Every step of every job must always run and fail the job: no if/condition/enabled/continue-on-error/continueOnError and
# no non-positive timeout. Allowlist keyed by (template, job, step name, or its exact uses/task/script first line when
# unnamed); the value is the exact key/value allowed, nothing is matched by pattern or prefix.
STEP_NEUTRALISERS = ("if", "condition", "enabled", "continue-on-error", "continueOnError")
STEP_ALLOWLIST = {
    # setup-uv is an install step, not a gate; it is only needed when the project ships uv.lock.
    ("github-py", "quality", "astral-sh/setup-uv@07a047e608db84b3d8c06cd9a7c7dcc9c355c18e"): {"if": "hashFiles('uv.lock') != ''"},
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
for host, (rel, merge) in files.items():
    lines = open(f"{root}/{rel}").read().split("\n")
    try:
        condition_errors(rel, yaml.load(open(f"{root}/{rel}").read(), Loader=UniqueKeyLoader), host)
    except MergeKeyError as e:
        errors.append(f"{rel}: {e}")
    except yaml.YAMLError as e:
        errors.append(f"{rel}: not parseable YAML, so the job-condition guard cannot check it: {e}")
    for i, l in enumerate(lines):
        code = re.sub(r"\s#\s.*$", "", l)
        if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)", code):
            errors.append(f"{rel}:{i + 1}: gate-neutralising construct: {l.strip()}")
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
    if re.search(r"\|\||continue-on-error|succeededOrFailed\(|\balways\(\)", code):
        errors.append(f"{gates}:{i + 1}: gate-neutralising construct: {l.strip()}")
gate_step_checks(gates, open(f"{root}/{gates}").read().split("\n"), "nosonar step", "ci-gates.sh nosonar")
try:
    gate_include_errors(gates, yaml.load(open(f"{root}/{gates}").read(), Loader=UniqueKeyLoader))
except MergeKeyError as e:
    errors.append(f"{gates}: {e}")
except yaml.YAMLError as e:
    errors.append(f"{gates}: not parseable YAML, so the gate guard cannot check it: {e}")
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
mutate "job-level if != pull_request on the coverage job (github-ts)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: test\n' "  coverage:\n    if: github.event_name != 'pull_request'\n    needs: test\n" static
mutate "job-level if != pull_request on the quality job (github-py)" github-py/.github/workflows/ci.yml '  quality:\n    runs-on: ubuntu-latest\n' "  quality:\n    if: github.event_name != 'pull_request'\n    runs-on: ubuntu-latest\n" static
mutate "job-level if: false on a PR-only job (github-ts changelog)" github-ts/.github/workflows/ci.yml "  changelog:\n    if: github.event_name == 'pull_request'" '  changelog:\n    if: false' static
mutate "different condition on a PR-only job (github-py readme-freshness)" github-py/.github/workflows/ci.yml "  readme-freshness:\n    if: github.event_name == 'pull_request'" "  readme-freshness:\n    if: github.event_name != 'push'" static
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
mutate "step-level if: false on the readme step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Require README.md update' '      - if: false\n        name: Require README.md update' static
mutate "step-level if: false on the comment step (github-ts)" github-ts/.github/workflows/ci.yml '      - name: Require no change-narration comments' '      - if: false\n        name: Require no change-narration comments' static
mutate "step-level if: false on Dependency audit (github-py)" github-py/.github/workflows/ci.yml '      - name: Dependency audit' '      - if: false\n        name: Dependency audit' static
mutate "step-level if: false on Secret scan (github-py)" github-py/.github/workflows/ci.yml '      - name: Secret scan' '      - if: false\n        name: Secret scan' static
mutate "step-level if: false on the Tests step (github-py)" github-py/.github/workflows/ci.yml '      - name: Tests (pytest-xdist' '      - if: false\n        name: Tests (pytest-xdist' static
mutate "step-level if: false on the changelog step (github-py)" github-py/.github/workflows/ci.yml '      - name: Require CHANGELOG for src changes' '      - if: false\n        name: Require CHANGELOG for src changes' static
mutate "enabled: false on the merge step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Merge shard reports' '        enabled: false\n        displayName: Merge shard reports' static
mutate "enabled: false on the diff-cover step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Changed-line coverage' '        enabled: false\n        displayName: Changed-line coverage' static
mutate "enabled: false on the diff-cover step (azure-py)" azure-py/azure-pipelines.yml '        displayName: Changed-line coverage' '        enabled: false\n        displayName: Changed-line coverage' static
mutate "condition: false on Assert all shard reports present (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Assert all shard reports present' '        condition: false\n        displayName: Assert all shard reports present' static
mutate "condition: false on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        condition: false\n        displayName: Tests (this shard' static
mutate "continueOnError: true on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        continueOnError: true\n        displayName: Tests (this shard' static
mutate "condition: false on the Tests step (azure-py)" azure-py/azure-pipelines.yml '        displayName: Tests with coverage' '        condition: false\n        displayName: Tests with coverage' static
mutate "timeoutInMinutes: 0 on the Tests step (azure-ts)" azure-ts/azure-pipelines.yml '        displayName: Tests (this shard' '        timeoutInMinutes: 0\n        displayName: Tests (this shard' static
mutate "job-level continue-on-error (github-ts coverage)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: test\n' '  coverage:\n    continue-on-error: true\n    needs: test\n' static
mutate "job-level continueOnError (azure-py quality)" azure-py/azure-pipelines.yml '  - job: quality\n' '  - job: quality\n    continueOnError: true\n' static
mutate "step include of an unchecked template (azure-py)" azure-py/azure-pipelines.yml '      - template: azure-pipelines/templatecentral-gates.yml' '      - template: azure-pipelines/other.yml' static
mutate "allowlisted setup-uv step with a changed if value (github-py)" github-py/.github/workflows/ci.yml "      - if: hashFiles('uv.lock') != ''" "      - if: hashFiles('other.lock') != ''" static
mutate "allowlisted setup-uv step with an extra neutraliser (github-py)" github-py/.github/workflows/ci.yml "      - if: hashFiles('uv.lock') != ''" "      - continue-on-error: true\n        if: hashFiles('uv.lock') != ''" static
mutate "flow-style job mapping with a forbidden if (github-ts coverage)" github-ts/.github/workflows/ci.yml '  coverage:\n    needs: test\n' '  coverage: { needs: test, if: false }\n  extra:\n    needs: test\n' static
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
