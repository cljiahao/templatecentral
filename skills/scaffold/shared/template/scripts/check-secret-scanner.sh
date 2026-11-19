#!/usr/bin/env bash
# Secret scanner presence check: a missing scanner warns loudly locally and fails in CI, never a silent skip.
# Usage: bash scripts/check-secret-scanner.sh
set -uo pipefail

if command -v gitleaks > /dev/null 2>&1; then
  exit 0
fi
echo "WARNING check-secret-scanner: gitleaks is not installed, so this commit was NOT scanned for secrets." >&2
echo "WARNING check-secret-scanner: install it with: brew install gitleaks   (Linux: https://github.com/gitleaks/gitleaks/releases)" >&2
if [ -n "${CI:-}${TF_BUILD:-}${GITHUB_ACTIONS:-}" ]; then
  echo "check-secret-scanner: CI never skips the secret scan. Install gitleaks on the runner, or run ci-gates.sh secrets, which installs the pinned release." >&2
  exit 1
fi
exit 0
