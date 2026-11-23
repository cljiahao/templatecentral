#!/usr/bin/env bash
# scripts/check-sonar-parity.sh — prove each Sonar rule mapped in scripts/sonar-parity.tsv is enabled at error level
# in the seeded lint configs (ESLint flat configs of the three TypeScript stacks, ruff in the FastAPI pyproject.toml),
# and that each mapped gate file exists in the template tree.
#
# Usage: bash scripts/check-sonar-parity.sh [--root DIR] [--table FILE]
#   Default root: the repository this script lives in; default table: <root>/scripts/sonar-parity.tsv.
#   Static: no package is installed, no scanner runs, no login, key or network. Preset contents (sonarjs,
#   typescript-eslint, @eslint/js, eslint-config-next) come from scripts/sonar-parity-presets/. A config form
#   the reader cannot resolve fails the row that needs it; a rule is never assumed enabled.
#   Prints covered, partial and not-covered counts per language and the not-covered rows with reasons.
#   Exit 0 when the table is valid and every mapped rule is enabled, 1 on any problem, 2 on bad usage.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
table=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || { echo "check-sonar-parity: --root needs a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    --table) [[ $# -ge 2 ]] || { echo "check-sonar-parity: --table needs a value" >&2; exit 2; }; table="$2"; shift 2 ;;
    *) echo "usage: check-sonar-parity.sh [--root DIR] [--table FILE]" >&2; exit 2 ;;
  esac
done
[[ -d "$root" ]] || { echo "check-sonar-parity: no such root: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
[[ -n "$table" ]] || table="$root/scripts/sonar-parity.tsv"
[[ -f "$table" ]] || { echo "check-sonar-parity: no table: $table" >&2; exit 1; }
command -v python3 > /dev/null 2>&1 || { echo "check-sonar-parity: python3 is required" >&2; exit 2; }
exec python3 -I "$here/check-sonar-parity.py" "$root" "$table"
