#!/usr/bin/env bash
# scripts/check-fences.sh — compare the copy-verbatim fences of skills/add, skills/migrate and
# skills/standards against the hash snapshot in tests/golden/fences/.
#
# Usage: bash scripts/check-fences.sh [--root DIR] [--from-templates | --has-mappings | --snapshot]
#   Default: every snapshot fence must still be in the markdown with the same bytes, or be mapped
#   in tests/golden/fences/moved.d/<slice>.tsv to a file under a skills/**/template*/ directory whose
#   bytes match and whose fence is gone from the markdown. A fence or file with no snapshot row fails (EXTRA).
#   --from-templates hashes only the mapped fences, from their files (the mode of
#   check-golden.sh --from-templates); it fails when nothing is mapped.
#   --has-mappings exits 0 when moved.d holds a row, 1 when it holds none and 2 on an error: a caller
#   must treat 2 as a failure. --snapshot writes the snapshot (initial capture only).
#
# Moving a fence into a file (one slice, one file moved.d/<slice>.tsv):
#   1. write the file with the fence body's exact bytes;
#   2. replace the fence in the markdown with a pointer;
#   3. add one row to moved.d/<slice>.tsv: file, heading, index, template path, and indent=N when
#      the markdown fence is indented by N spaces (the file holds it without the indentation).
#   A slice never edits <skill>.tsv: the snapshot keeps its keys, and the check pairs the unmapped
#   rows of a heading with the live fences of that heading in order, so moving a fence does not
#   renumber its siblings. The same fence in two slice files fails.
#
# What counts as the same bytes: the lines of the fence exactly as written, each ended by a newline.
# A carriage return and the indentation are part of the line; a file without a final newline does not
# match. Fences tagged bash, sh, shell, zsh or console are not tracked.
# Details: scripts/check-fences.py. Exit 0 ok, 1 differences, 2 usage or parse error.
set -uo pipefail

exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-fences.py" "$@"
