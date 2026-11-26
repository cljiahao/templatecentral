#!/usr/bin/env bash
# scripts/workflow-job-ids.sh — print the job ids of a workflow file, one per line, in file order.
# Usage: bash scripts/workflow-job-ids.sh <workflow file>
# A job id is a key at two spaces of indent under the top-level `jobs:` key: letters, digits, `_` and `-`,
# then `:`, then optional blanks and an optional `# comment`. Any other non-comment line at that indent
# (a quoted key, a flow mapping, a tab) is an error: it is named on stderr and the exit status is 1, so an id
# this reader cannot parse never drops out of the list unnoticed. No `jobs:` key, or no job id, is an error too.
# Will not catch: a job key written in a form YAML allows but this reader does not look for (a key that
# continues on another line); those lines fail as unreadable only when they sit at two spaces of indent.
set -uo pipefail

[[ $# -eq 1 && -f "$1" ]] || { echo "usage: bash scripts/workflow-job-ids.sh <workflow file>" >&2; exit 2; }

awk '
  /^jobs:/ { on = 1; seen = 1; next }
  on && /^[^ #]/ { on = 0 }
  on && /^  [^ #]/ {
    if ($0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/) {
      id = $0
      sub(/^  /, "", id)
      sub(/:.*/, "", id)
      print id
      n++
    } else {
      print "workflow-job-ids: unreadable line under jobs: " $0 > "/dev/stderr"
      bad = 1
    }
  }
  END {
    if (!seen) { print "workflow-job-ids: no jobs: key" > "/dev/stderr"; exit 1 }
    if (!n) { print "workflow-job-ids: no job id found" > "/dev/stderr"; exit 1 }
    exit bad
  }
' "$1"
