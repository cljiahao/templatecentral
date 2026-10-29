#!/usr/bin/env bash
# scripts/check-fences.sh — compare the copy-verbatim fences of skills/add, skills/migrate and
# skills/standards against the hash snapshot in tests/golden/fences/.
#
# Usage: bash scripts/check-fences.sh [--root DIR] [--from-templates | --has-mappings | --snapshot]
#   Default: every snapshot fence must still be in the markdown with the same bytes, or be mapped
#   in tests/golden/fences/moved.tsv to a file under a skills/**/template*/ directory whose bytes
#   match and whose fence is gone from the markdown. A fence or file with no snapshot row fails (EXTRA).
#   --from-templates hashes only the mapped fences, from their files (the mode of
#   check-golden.sh --from-templates); it fails when nothing is mapped.
#   --has-mappings exits 0 when moved.tsv has a row. --snapshot writes the snapshot (initial capture only).
#   Moving a fence into a file: write the file with the fence body's exact bytes, replace the fence in
#   the markdown with a pointer, and add one row to moved.tsv. Leave the snapshot rows alone.
# Details: scripts/check-fences.py. Exit 0 ok, 1 differences, 2 usage or parse error.
set -uo pipefail

exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-fences.py" "$@"
