#!/usr/bin/env bash
# scripts/regen-golden.sh — regenerate tests/golden/*.sha256, and with --fences the fence snapshots.
#
# Usage: bash scripts/regen-golden.sh [--write] [--fences] [COMBO ...]
#   COMBO is <stack>-<ci> as for check-golden.sh; default all 8.
#   Default: print which golden files would change and change nothing (exit 0 either way).
#   --write  write the changed files.
#   --fences also cover tests/golden/fences/*.tsv. Without it the snapshots are never read or written.
#            A snapshot change is a deliberate decision (see check-fences-frozen.sh); check-fences.py
#            refuses once moved.d holds a row, and that refusal is passed on (exit 2).
# It always acts on its own repo root (the folder above scripts/), never on the caller's folder. With --write every
# result is computed first and nothing under tests/golden/ changes unless every step succeeded.
# Hashes come from `check-golden.sh --emit-hashes`, the code path the check compares with. A file keeps its
# leading '#' comment lines. Exit 0 ok, 1 when a golden or snapshot could not be built, 2 on a usage error or a refusal.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="$REPO_ROOT/tests/golden"
WRITE=0
FENCES=0
COMBOS=()
for a in "$@"; do
  case "$a" in
    --write) WRITE=1 ;;
    --fences) FENCES=1 ;;
    -h | --help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "regen-golden: unknown option $a (want --write, --fences)" >&2; exit 2 ;;
    *) COMBOS+=("$a") ;;
  esac
done

T=$(mktemp -d "${TMPDIR:-/tmp}/regen-golden.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

fail=0
STAGED_NEW=()
STAGED_DEST=()

# stage <new> <dest> — queues a file that differs from its regenerated form; nothing is written here.
stage() {
  local new=$1 dest=$2
  if [[ -f "$dest" ]] && cmp -s "$new" "$dest"; then return 0; fi
  STAGED_NEW[${#STAGED_NEW[@]}]=$new
  STAGED_DEST[${#STAGED_DEST[@]}]=$dest
}

mkdir -p "$T/hashes"
if ! bash "$REPO_ROOT/scripts/check-golden.sh" --golden-dir "$GOLDEN" --emit-hashes "$T/hashes" ${COMBOS[@]+"${COMBOS[@]}"} > "$T/emit.out" 2>&1; then
  cat "$T/emit.out" >&2
  echo "regen-golden: check-golden.sh could not build the hashes; nothing changed" >&2
  exit 1
fi

for body in "$T"/hashes/*.sha256; do
  [[ -f "$body" ]] || continue
  name=$(basename "$body")
  old="$GOLDEN/$name"
  { [[ -f "$old" ]] && grep '^#' "$old"; cat "$body"; } > "$T/new-$name"
  stage "$T/new-$name" "$old"
done

if [[ $FENCES -eq 1 ]]; then
  root="$T/fence-root"
  mkdir -p "$root/skills" "$root/tests/golden"
  for s in add migrate standards; do cp -R "$REPO_ROOT/skills/$s" "$root/skills/$s"; done
  cp -R "$GOLDEN/fences" "$root/tests/golden/fences"
  python3 "$REPO_ROOT/scripts/check-fences.py" --root "$root" --snapshot > "$T/fence.out" 2>&1
  rc=$?
  if [[ $rc -ne 0 ]]; then
    cat "$T/fence.out" >&2
    echo "regen-golden: fence snapshot not regenerated" >&2
    exit "$rc"
  fi
  for f in "$root"/tests/golden/fences/*.tsv; do
    stage "$f" "$GOLDEN/fences/$(basename "$f")"
  done
fi

changed=${#STAGED_NEW[@]}
i=0
while [[ $i -lt $changed ]]; do
  name=${STAGED_DEST[i]#"$REPO_ROOT"/}
  if [[ $WRITE -eq 1 ]]; then
    cp "${STAGED_NEW[i]}" "${STAGED_DEST[i]}.regen.$$" || { echo "regen-golden: cannot write $name; nothing changed" >&2; fail=1; break; }
  else
    echo "would change $name"
  fi
  i=$((i + 1))
done

if [[ $WRITE -eq 1 ]]; then
  if [[ $fail -ne 0 ]]; then
    for d in ${STAGED_DEST[@]+"${STAGED_DEST[@]}"}; do rm -f "$d.regen.$$"; done
    exit 1
  fi
  i=0
  while [[ $i -lt $changed ]]; do
    mv -f "${STAGED_DEST[i]}.regen.$$" "${STAGED_DEST[i]}" || fail=1
    echo "wrote ${STAGED_DEST[i]#"$REPO_ROOT"/}"
    i=$((i + 1))
  done
fi

[[ $changed -gt 0 || $WRITE -eq 1 ]] || echo "regen-golden: no golden file would change"
exit $fail
