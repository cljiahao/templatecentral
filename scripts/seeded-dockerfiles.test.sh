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
  echo "seeded-dockerfiles.test: SKIPPED. hadolint is not installed and could not be downloaded here, so the seeded Dockerfiles were NOT linted. Install hadolint and run again; CI runs this for real."
  exit 0
fi

for d in "$REPO_ROOT"/skills/scaffold/*/template; do
  [ -f "$d/Dockerfile" ] || continue
  s=${d%/template}; s=${s##*/}
  out=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS bash "$GATE" Dockerfile 2>&1)
  check 0 $? "$s Dockerfile passes the seeded dockerfile gate: $out"
done

# The gate still fails a real finding, and a project .hadolint.yaml cannot silence it.
mkdir "$T/bad"
printf 'FROM python:3.14.0-slim@sha256:%064d\nRUN pip install flask\nUSER 1000\n' 0 > "$T/bad/Dockerfile"
printf 'ignored:\n  - DL3013\n' > "$T/bad/.hadolint.yaml"
(cd "$T/bad" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS bash "$GATE" Dockerfile > /dev/null 2>&1)
check 1 $? "unpinned pip install fails the gate even with .hadolint.yaml ignoring DL3013"

echo "seeded-dockerfiles.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
