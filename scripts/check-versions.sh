#!/usr/bin/env bash
# scripts/check-versions.sh — fail when a file disagrees with skills/scaffold/shared/versions.txt, the
# one place templateCentral keeps a version.
#
# Usage: bash scripts/check-versions.sh [--root DIR]
#   Default root: the repository this script lives in. Prints one `file:line: message` per
#   disagreement and exits 1; exits 0 when every file agrees. Needs python3.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$here/check-versions.py" "$@"
