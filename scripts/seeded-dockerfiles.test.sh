#!/usr/bin/env bash
# scripts/seeded-dockerfiles.test.sh — every seeded stack Dockerfile passes its own seeded `dockerfile` gate with real hadolint.
# hadolint comes from PATH, or from the pinned download in the seeded ci-gates.sh (Linux x86_64 only, checksum verified).
# Without hadolint the test prints a loud SKIP and exits 0 on a laptop, and fails when CI is set: CI must run it for real.
# Usage: bash scripts/seeded-dockerfiles.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/check-dockerfile.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-df.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

obtain_hadolint() {
  command -v hadolint > /dev/null 2>&1 && return 0
  [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] && command -v sha256sum > /dev/null 2>&1 || return 1
  local ver sha
  ver=$(sed -n 's/^ *HADOLINT_VERSION="\(.*\)"$/\1/p' "$SH/template/.claude/ci-gates.sh" | head -1)
  sha=$(sed -n 's/^ *HADOLINT_SHA256="\(.*\)"$/\1/p' "$SH/template/.claude/ci-gates.sh" | head -1)
  [ -n "$ver" ] && [ -n "$sha" ] || return 1
  curl -fsSL -m 60 -o "$T/hadolint" "https://github.com/hadolint/hadolint/releases/download/v${ver}/hadolint-linux-x86_64" || return 1
  echo "${sha}  $T/hadolint" | sha256sum -c - > /dev/null 2>&1 || { echo "seeded-dockerfiles.test: hadolint checksum mismatch" >&2; return 1; }
  chmod +x "$T/hadolint"
  PATH="$T:$PATH"
}

in_ci=0
for v in "${CI:-}" "${TF_BUILD:-}" "${GITHUB_ACTIONS:-}"; do
  case "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" in "" | false | 0 | no) ;; *) in_ci=1 ;; esac
done

if ! obtain_hadolint; then
  if [ "$in_ci" -eq 1 ]; then
    echo "seeded-dockerfiles.test: FAIL hadolint is not available in CI. The seeded Dockerfiles were not linted." >&2
    exit 1
  fi
  echo "SKIPPED: hadolint is not installed and could not be downloaded here, so the seeded Dockerfiles were NOT linted and the gate was NOT proven. Install hadolint and run again; CI runs this for real."
  exit 0
fi

for d in "$REPO_ROOT"/skills/scaffold/*/template; do
  [ -f "$d/Dockerfile" ] || continue
  s=${d%/template}; s=${s##*/}
  out=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS bash "$GATE" Dockerfile 2>&1)
  check 0 $? "$s Dockerfile passes the seeded dockerfile gate: $out"
done

# run_gate <dir>: run the seeded gate on <dir>/Dockerfile; sets GATE_RC and GATE_OUT.
run_gate() {
  GATE_OUT=$(cd "$1" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS bash "$GATE" Dockerfile 2>&1)
  GATE_RC=$?
}
# fixture <dir> <extra Dockerfile lines>: an otherwise clean Dockerfile, so a failure comes from the extra lines alone.
fixture() {
  mkdir -p "$1"
  printf 'FROM python:3.14.0-slim@sha256:%064d\nHEALTHCHECK CMD ["true"]\n%sUSER 1000\n' 0 "$2" > "$1/Dockerfile"
}
# expect_finding <name> <extra lines, newline-ended> <rule> [rule a project .hadolint.yaml ignores]: the clean control passes, the same fixture plus the extra lines fails with <rule> in the output.
expect_finding() {
  fixture "$T/$1-ok" ""
  run_gate "$T/$1-ok"
  check 0 "$GATE_RC" "$1 control (same Dockerfile without the finding) passes the gate: $GATE_OUT"
  fixture "$T/$1-bad" "$2"
  if [ -n "${4:-}" ]; then printf 'ignored:\n  - %s\n' "$4" > "$T/$1-bad/.hadolint.yaml"; fi
  run_gate "$T/$1-bad"
  check 1 "$GATE_RC" "$1 fails the gate"
  case "$GATE_OUT" in *"$3"*) check yes yes "$1 reports $3" ;; *) check yes no "$1 reports $3 (output: $GATE_OUT)" ;; esac
}

# The gate still fails a real finding, and a project .hadolint.yaml cannot silence it.
expect_finding pip $'RUN pip install flask\n' DL3013 DL3013
for form in ENV ARG; do
  expect_finding "sec-$form" "$form DB_PASSWORD=hunter2"$'\n' DL3064
done

echo "seeded-dockerfiles.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
