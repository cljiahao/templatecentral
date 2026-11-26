#!/usr/bin/env bash
# scripts/check-tests-wired.sh — fail when a repo test script is not run by a workflow that runs on pull requests.
# Usage: bash scripts/check-tests-wired.sh [scripts dir] [workflow dir]   (defaults: this repo's)
#
# Tests in scope (the repo root is the parent of the scripts dir): scripts/*.test.sh, scripts/test-*.sh and
# adapters/*/*.test.mjs. Out of scope: the *.test.* files inside skills/**/template*/ (they are scaffold
# output that runs in a scaffolded project, not in this repo) and the test fixtures under tests/.
#
# A workflow is read as YAML (python3 with PyYAML). It counts only when `on` holds pull_request. Only the `run:`
# value of a step counts, and only a command line that starts with one of these exact forms, followed by plain
# arguments (no pipe, list operator, `;`, `&`, or redirect):
#   bash scripts/<name>              for the .sh tests
#   node adapters/<dir>/<name>       for the .test.mjs tests
# Comments are stripped by the shell tokenizer, so echo text, a `name:` text, a trailing comment, `: bash ...`
# and `... || true` do not count. A step does not count when its run block has `set +e`, or when the step or
# its job has continue-on-error set to anything but false. A step or job `if:` removes the step from the count
# unless it is on this allow-list: a job `if: github.event_name == 'pull_request'`, which is true in every run
# of a workflow that is counted.
#
# It fails closed: no test file, no workflow file, a workflow that cannot be parsed (even one that does not run
# on pull requests), no workflow that runs on pull requests, or no python3 with PyYAML (python3 first, then /usr/bin/python3).
# Will not catch: a command that is earlier masked by `exit 0` in the same run block, a test script that runs
# but asserts nothing, or a workflow that this repo's `paths:` filters keep from starting.
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
for cand in python3 /usr/bin/python3; do
  if "$cand" -c 'import yaml' >/dev/null 2>&1; then PY=$cand; break; fi
done
[[ -n "$PY" ]] || { echo "FAIL: no python3 with PyYAML (python3 or /usr/bin/python3); install python3-yaml"; exit 1; }

"$PY" - "$REPO" "${#workflows[@]}" "${workflows[@]}" "${tests[@]}" <<'PY'
import os
import shlex
import sys

import yaml

repo, nwf = sys.argv[1], int(sys.argv[2])
workflow_files = sys.argv[3:3 + nwf]
tests = sys.argv[3 + nwf:]

ALLOWED_JOB_IF = "github.event_name == 'pull_request'"
PUNCT = set(";&|<>()")


def triggers(doc):
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        return {on}
    if isinstance(on, list):
        return {str(x) for x in on}
    if isinstance(on, dict):
        return {str(k) for k in on}
    return set()


def continue_on_error(node):
    value = node.get("continue-on-error", False)
    return value not in (False, "false", "False")


def command_lines(run):
    lines = []
    for raw in str(run).splitlines():
        lex = shlex.shlex(raw, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = "#"
        try:
            lines.append(list(lex))
        except ValueError:
            lines.append(None)
    return lines


def has_set_plus_e(lines):
    for toks in lines:
        if toks and toks[0] == "set":
            for t in toks[1:]:
                if t.startswith("+") and "e" in t:
                    return True
    return False


def wired_commands(run):
    lines = command_lines(run)
    if has_set_plus_e(lines):
        return set()
    found = set()
    for toks in lines:
        if not toks or len(toks) < 2:
            continue
        if toks[0] not in ("bash", "node"):
            continue
        if any(set(t) <= PUNCT for t in toks[2:]):
            continue
        found.add((toks[0], toks[1]))
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
    if "pull_request" not in triggers(doc):
        continue
    counted += 1
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        continue
    for job in jobs.values():
        if not isinstance(job, dict):
            continue
        if "if" in job and str(job["if"]).strip() != ALLOWED_JOB_IF:
            continue
        if continue_on_error(job):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for step in steps:
            if not isinstance(step, dict) or "run" not in step:
                continue
            if "if" in step or continue_on_error(step):
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
