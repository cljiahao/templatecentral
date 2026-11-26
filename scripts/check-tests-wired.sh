#!/usr/bin/env bash
# scripts/check-tests-wired.sh — fail when a repo test script is not run by a workflow that runs on pull requests.
# Usage: bash scripts/check-tests-wired.sh [scripts dir] [workflow dir]   (defaults: this repo's)
#
# Tests in scope (the repo root is the parent of the scripts dir): scripts/*.test.sh, scripts/test-*.sh and
# adapters/*/*.test.mjs. Out of scope: the *.test.* files inside skills/**/template*/ (they are scaffold
# output that runs in a scaffolded project, not in this repo) and the test fixtures under tests/.
#
# A workflow is read as YAML (python3 with PyYAML, python3 first, then /usr/bin/python3; WIRED_PYTHONS can
# name other interpreters, for the self-test). It counts only when its `on` holds pull_request and that
# trigger carries no filter that can skip a pull request: no `branches`, `branches-ignore`, `paths` or
# `paths-ignore` (each one means "not every pull request"), no other key but `types`, and `types` only when
# it is absent or equals (in any order) the one list that holds opened, synchronize and reopened that the
# repo uses today: opened, synchronize, reopened, labeled, unlabeled (validate-skills.yml).
#
# A run block wires a test only when EVERY line of it is on this allow-list, matched whole:
#   a blank line
#   bash <path> [plain arguments]    for the .sh tests
#   node <path> [plain arguments]    for the .test.mjs tests
# where <path> is the repo-relative path (scripts/<name> or adapters/<dir>/<name>, no ./ and no quotes) and
# a plain argument uses only letters, digits and _ . / = : @ % + , -. There is no setup form on the list, since
# none of the real workflows needs one before a test. Any other line (a comment, an echo, a quote, a pipe, a
# list operator, a redirect, a heredoc, a function, a loop, a branch, a continuation, an exit or trap or
# `set`) makes the whole block wire nothing: all or nothing, never line by line. A fix for a workflow that
# fails this rule is to split the step so the test command stands in its own block.
# A step wires nothing when it has `if`, `shell`, `working-directory`, or `continue-on-error` other than
# false, or an `env` that is not a mapping or holds a name off the closed list below. A job wires nothing
# when it has `shell`, `continue-on-error` other than false, an `if` other than exactly
# `github.event_name == 'pull_request'`, `defaults.run`, or such an `env`. A workflow with `defaults.run` or
# such an `env` wires nothing. The closed list is the env names validate-skills.yml uses today: BASE_REF,
# EVENT, FENCE_SNAPSHOT_CHANGE_OK, NEEDS, STRICT_DOC_SYNC (BASH_ENV, ENV, SHELLOPTS and the rest are out).
# A block folded with `>` is one line, so only its first command counts.
#
# It fails closed: no test file, no workflow file, a workflow that cannot be parsed (even one that does not
# run on pull requests) or is not a mapping, no workflow that counts, or no python3 with PyYAML.
# Will not catch: a test script that runs but asserts nothing or skips itself on its arguments; an allowed
# env name set to a value that changes what the script does; a non-test step in the same job that writes
# $GITHUB_ENV or $GITHUB_PATH and so changes the shell or the PATH of a later test step; a job `needs` chain, a job `container`, a
# `matrix` or a `timeout-minutes` that keeps the step from running or ends it early; a `uses` step that
# edits the tree before the run; and a test that only a `workflow_run`, schedule or manual trigger runs,
# which is not counted.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${1:-$ROOT/scripts}"
WORKFLOWS="${2:-$ROOT/.github/workflows}"
REPO="$(cd "$SCRIPTS/.." && pwd)"

shopt -s nullglob
tests=("$SCRIPTS"/*.test.sh "$SCRIPTS"/test-*.sh "$REPO"/adapters/*/*.test.mjs)
workflows=("$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml)
shopt -u nullglob

[[ ${#tests[@]} -gt 0 ]] || { echo "FAIL: no test file in $SCRIPTS or $REPO/adapters"; exit 1; }
[[ ${#workflows[@]} -gt 0 ]] || { echo "FAIL: no workflow file in $WORKFLOWS"; exit 1; }

PY=
read -r -a cands <<<"${WIRED_PYTHONS-python3 /usr/bin/python3}"
for cand in ${cands[@]+"${cands[@]}"}; do
  if "$cand" -c 'import yaml' >/dev/null 2>&1; then PY=$cand; break; fi
done
[[ -n "$PY" ]] || { echo "FAIL: no python3 with PyYAML (python3 or /usr/bin/python3); install python3-yaml"; exit 1; }

"$PY" - "$REPO" "${#workflows[@]}" "${workflows[@]}" "${tests[@]}" <<'PY'
import os
import re
import sys

import yaml

repo, nwf = sys.argv[1], int(sys.argv[2])
workflow_files = sys.argv[3:3 + nwf]
tests = sys.argv[3 + nwf:]

ALLOWED_JOB_IF = "github.event_name == 'pull_request'"
ALLOWED_PR_KEYS = {"types"}
ALLOWED_PR_TYPES = [
    ["labeled", "opened", "reopened", "synchronize", "unlabeled"],
]
ALLOWED_ENV = {"BASE_REF", "EVENT", "FENCE_SNAPSHOT_CHANGE_OK", "NEEDS", "STRICT_DOC_SYNC"}
BLANK = re.compile(r" *")
INVOKE = re.compile(r"(bash|node) ([A-Za-z0-9_][A-Za-z0-9_./-]*)((?: [A-Za-z0-9_./=:@%+,-]+)*) *")


def triggers(doc):
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {str(x): None for x in on}
    if isinstance(on, dict):
        return {str(k): v for k, v in on.items()}
    return {}


def pull_request_counts(doc):
    trig = triggers(doc)
    if "pull_request" not in trig:
        return False
    value = trig["pull_request"]
    if value is None:
        return True
    if not isinstance(value, dict):
        return False
    if not set(value) <= ALLOWED_PR_KEYS:
        return False
    if "types" in value:
        types = value["types"]
        if not isinstance(types, list) or sorted(str(t) for t in types) not in ALLOWED_PR_TYPES:
            return False
    return True


def continue_on_error(node):
    value = node.get("continue-on-error", False)
    return value not in (False, "false", "False")


def has_default_run(node):
    if "defaults" not in node:
        return False
    defaults = node["defaults"]
    return not isinstance(defaults, dict) or "run" in defaults


def env_ok(node):
    if "env" not in node:
        return True
    env = node["env"]
    return isinstance(env, dict) and all(str(k) in ALLOWED_ENV for k in env)


def wired_commands(run):
    found = set()
    for line in str(run).split("\n"):
        if BLANK.fullmatch(line):
            continue
        m = INVOKE.fullmatch(line)
        if m is None:
            return set()
        found.add((m.group(1), m.group(2)))
    return found


wired = set()
counted = 0
for path in workflow_files:
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as exc:
        print("FAIL: cannot parse workflow %s (%s)" % (path, str(exc).splitlines()[0] if str(exc) else exc.__class__.__name__))
        sys.exit(1)
    if not isinstance(doc, dict):
        print("FAIL: workflow %s is not a YAML mapping" % path)
        sys.exit(1)
    if not pull_request_counts(doc):
        continue
    counted += 1
    if has_default_run(doc) or not env_ok(doc):
        continue
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        continue
    for job in jobs.values():
        if not isinstance(job, dict):
            continue
        if "if" in job and str(job["if"]).strip() != ALLOWED_JOB_IF:
            continue
        if continue_on_error(job) or "shell" in job or has_default_run(job) or not env_ok(job):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for step in steps:
            if not isinstance(step, dict) or "run" not in step:
                continue
            if "if" in step or "shell" in step or "working-directory" in step or continue_on_error(step) or not env_ok(step):
                continue
            wired |= wired_commands(step["run"])

if counted == 0:
    print("FAIL: no workflow file runs on pull_request, so no test is wired")
    sys.exit(1)

missing = 0
for t in tests:
    rel = os.path.relpath(t, repo)
    kind = "node" if t.endswith(".mjs") else "bash"
    if (kind, rel) not in wired:
        print("FAIL: %s is not run by any workflow step" % rel)
        missing += 1

if missing:
    sys.exit(1)
print("OK: all %d test files are run by a workflow step" % len(tests))
PY
