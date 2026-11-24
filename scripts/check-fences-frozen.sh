#!/usr/bin/env bash
# scripts/check-fences-frozen.sh — fail when a change edits the fence snapshot or the deleted-fence record.
#
# Usage: bash scripts/check-fences-frozen.sh BASE_REF
#   Compares HEAD with its merge base against BASE_REF and fails when a file matching
#   tests/golden/fences/*.tsv (the per-skill snapshot, not moved.d/) was added, changed, renamed or
#   deleted, or when any file under tests/golden/fences/deleted.d/ (a deleted-fence row, .gitkeep
#   included) was added, changed, renamed or deleted. It passes when BASE_REF holds no snapshot yet
#   (the initial capture).
#   A slice that moves fences into files edits moved.d/<slice>.tsv only. A deliberate snapshot change
#   (a heading rename, a new fence, a reviewed content change) or a deleted fence is a human decision: set
#   FENCE_SNAPSHOT_CHANGE_OK=1. CI sets it when the pull request carries the label
#   `fence-snapshot-change`; add the label, then re-run the job (a label alone does not start a run).
# Exit 0 ok, 1 snapshot or deleted.d changed, 2 usage error.
set -uo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  echo "usage: check-fences-frozen.sh BASE_REF" >&2
  exit 2
fi
if ! git rev-parse --verify -q "$base^{commit}" > /dev/null; then
  echo "check-fences-frozen: unknown ref $base" >&2
  exit 2
fi
if ! git cat-file -e "$base:tests/golden/fences/add.tsv" 2> /dev/null; then
  echo "check-fences-frozen: $base holds no snapshot; initial capture"
  exit 0
fi
if ! changed=$(git diff --name-only "$base"...HEAD -- ':(glob)tests/golden/fences/*.tsv' ':(glob)tests/golden/fences/deleted.d/**'); then
  echo "check-fences-frozen: git diff against $base failed" >&2
  exit 2
fi
if [[ -z "$changed" ]]; then
  echo "check-fences-frozen: snapshot and deleted.d unchanged"
  exit 0
fi
if [[ "${FENCE_SNAPSHOT_CHANGE_OK:-}" == 1 ]]; then
  echo "check-fences-frozen: snapshot or deleted.d changed with FENCE_SNAPSHOT_CHANGE_OK=1:"
  echo "$changed"
  exit 0
fi
echo "check-fences-frozen: the snapshot or deleted.d changed against $base:"
echo "$changed"
echo "A slice that moves a fence into a file edits tests/golden/fences/moved.d/<slice>.tsv, not the snapshot." >&2
echo "A slice that deletes a fence adds a row to tests/golden/fences/deleted.d/<slice>.tsv; that change takes the same label." >&2
echo "For a deliberate snapshot change or a deleted fence add the label fence-snapshot-change and re-run the job." >&2
exit 1
