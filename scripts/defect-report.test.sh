#!/usr/bin/env bash
# scripts/defect-report.test.sh — tests for skills/migrate/general/defect-report.sh and its checks in defects/*.sh.
# Each check flags its "old" fixture, stays quiet on the current template file copied from the real template tree,
# counts an absent file as "not installed", ignores dependency folders, never writes into the project and exits as documented.
# Usage: bash scripts/defect-report.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/skills/migrate/general/defect-report.sh"
DEFECTS="$REPO_ROOT/skills/migrate/general/defects"
FIXTURES="$REPO_ROOT/tests/fixtures/defects"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; else PASS=$((PASS + 1)); fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/dr.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# run <dir> [args]: sets OUT and EC from running the report with the CI markers cleared.
run() {
  local d=$1
  shift
  OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$RUNNER" "$d" "$@" 2>&1)
  EC=$?
}

# sig <dir>: a hash of the file list and every file's content, so any write shows as a difference.
sig() {
  (
    cd "$1" || exit 1
    find . | LC_ALL=C sort
    find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$f"; else sha256sum -- "$f"; fi
    done
  ) | if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi
}

# meta <file> <variable>: print one variable from a check file, read in a subshell.
meta() {
  (
    id='' level='' template=''
    # shellcheck source=/dev/null
    . "$1"
    case "$2" in id) echo "$id" ;; level) echo "$level" ;; template) echo "$template" ;; esac
  )
}

NCHECKS=0
for def in "$DEFECTS"/*.sh; do NCHECKS=$((NCHECKS + 1)); done
SUMMARY_TAIL="This is a list of known older template patterns, not an audit."

# ── every check: old fixture is flagged, current template is clean ───────────

for def in "$DEFECTS"/*.sh; do
  id=$(meta "$def" id)
  level=$(meta "$def" level)
  template=$(meta "$def" template)
  old="$FIXTURES/$id/old"
  check 1 "$([[ -d "$old" ]] && echo 1 || echo 0)" "fixture exists for $id"
  [[ -d "$old" ]] || continue

  run "$old"
  want=0
  if [[ "$level" == high ]]; then want=1; fi
  check "$want" "$EC" "$id: exit code for level $level"
  has "  $id  $level  matches an older template pattern: " "$OUT" "$id: flagged with its id and level"
  has "Current template: $template" "$OUT" "$id: names the current template"
  has "Fix: " "$OUT" "$id: carries a fix"

  # The control: the same layout with the current template file in place of each old file.
  clean="$T/clean-$id"
  rm -rf "$clean"
  mkdir -p "$clean"
  cp -R "$old/." "$clean/"
  while IFS= read -r f; do
    base=$(basename "$f")
    src=
    if [[ "$base" == "$(basename "$template")" && -f "$REPO_ROOT/$template" ]]; then src="$REPO_ROOT/$template"; fi
    if [[ "$base" == redact_sensitive_output.py ]]; then src="$REPO_ROOT/skills/add/redaction/hook-python/template/.claude/hooks/redact_sensitive_output.py"; fi
    if [[ -n "$src" ]]; then
      [[ -f "$src" ]] || { FAIL=$((FAIL + 1)); echo "FAIL: $id: template file missing: $src"; continue; }
      cp "$src" "$clean/$f"
    fi
  done < <(cd "$old" && find . -type f | sed 's|^\./||')
  if [[ "$id" == argon2-dummy-hash-literal ]]; then
    # The current template is a fence in a leaf, so the control is: no template text carries the literal, and the old fixture files are removed.
    rm -rf "$clean"
    mkdir -p "$clean"
    lit=$(grep -rlF 'c29tZXNhbHRzb21lc2E' "$REPO_ROOT/skills" | grep -v '/defects/\|UPGRADE-NOTES' || true)
    check "" "$lit" "$id: no current template contains the older literal"
    printf 'const DUMMY_HASH = argon2.hash(randomUUID());\n' > "$clean/auth.service.ts"
  fi
  run "$clean"
  check 0 "$EC" "$id: current template is clean (exit)"
  lacks "  $id  " "$OUT" "$id: current template is not flagged"
done

# ── runner behaviour ─────────────────────────────────────────────────────────

# An absent file is "not installed", not clean.
mkdir -p "$T/empty"
run "$T/empty"
check 0 "$EC" "empty project exits 0"
check "$NCHECKS checks run, 0 matched, $NCHECKS not installed. $SUMMARY_TAIL" "$OUT" "empty project: every check counts as not installed"

# One installed target: the others stay "not installed".
run "$FIXTURES/mongoose-client-promise-retry/old"
has "$NCHECKS checks run, 2 matched, $((NCHECKS - 2)) not installed. $SUMMARY_TAIL" "$OUT" "summary line: checks, matches, not installed"

# A match inside a dependency folder is ignored.
for skip in node_modules .venv venv .next dist build coverage .git __pycache__; do
  d="$T/skip-$skip/$skip/pkg"
  mkdir -p "$d"
  cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$d/"
  run "$T/skip-$skip"
  check 0 "$EC" "a match inside $skip is ignored (exit)"
  check "$NCHECKS checks run, 0 matched, $NCHECKS not installed. $SUMMARY_TAIL" "$OUT" "a match inside $skip counts as not installed"
done

# A file over 1 MB is skipped; a symlink is not followed.
mkdir -p "$T/big/src/integrations/database"
cp "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/big/src/integrations/database/"
head -c 1100000 /dev/zero | tr '\0' ' ' >> "$T/big/src/integrations/database/mongoose-client.ts"
run "$T/big"
check 0 "$EC" "a file over 1 MB is skipped"
mkdir -p "$T/link/src"
ln -s "$FIXTURES/mongoose-client-promise-retry/old/src/integrations/database/mongoose-client.ts" "$T/link/src/mongoose-client.ts"
run "$T/link"
check 0 "$EC" "a symlink is not followed"

# A path with spaces works.
mkdir -p "$T/with space/my proj"
cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/with space/my proj/"
run "$T/with space/my proj"
check 1 "$EC" "path with spaces: flagged (exit)"
has "src/integrations/database/mongoose-client.ts:35  mongoose-client-promise-retry  high" "$OUT" "path with spaces: relative file:line printed"

# No version filter: a project that records the current version is still flagged.
mkdir -p "$T/ver/.claude"
cp -R "$FIXTURES/mongoose-client-promise-retry/old/." "$T/ver/"
printf '{"templatecentral_version":"999.0.0"}\n' > "$T/ver/.claude/harness.json"
printf '<!-- templateCentral: nextjs@6.0.0 -->\n' > "$T/ver/AGENTS.md"
run "$T/ver"
check 1 "$EC" "a recorded current version does not hide a match"

# The default project is the current directory.
OUT=$(cd "$FIXTURES/sqlalchemy-tls-verify/old" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$RUNNER" 2>&1)
EC=$?
check 0 "$EC" "no argument scans the current directory (check level exits 0)"
has "sqlalchemy-tls-verify  check" "$OUT" "no argument: match printed"

# The project is byte-identical before and after a run.
for def in "$DEFECTS"/*.sh; do
  id=$(meta "$def" id)
  d="$T/ro-$id"
  mkdir -p "$d"
  cp -R "$FIXTURES/$id/old/." "$d/"
  before=$(sig "$d")
  run "$d"
  after=$(sig "$d")
  check "$before" "$after" "$id: project is byte-identical after a run"
done

# Exit codes.
run "$FIXTURES/mongoose-client-promise-retry/old"
check 1 "$EC" "exit 1 when a high level check matched"
run "$FIXTURES/sqlalchemy-tls-verify/old"
check 0 "$EC" "exit 0 when only a check level matched"
has "sqlalchemy-tls-verify" "$OUT" "check level matches are still printed"
run "$T/empty"
check 0 "$EC" "exit 0 when nothing matched"
run "$T/does-not-exist"
check 2 "$EC" "exit 2 for a missing directory"
has "not a directory" "$OUT" "bad directory names the cause"
run "$T/empty" --bogus
check 2 "$EC" "exit 2 for an unknown option"
run "$T/empty" "$T/empty"
check 2 "$EC" "exit 2 for two directories"
printf 'x\n' > "$T/afile"
run "$T/afile"
check 2 "$EC" "exit 2 for a file argument"

# A broken check file fails closed.
cp -R "$REPO_ROOT/skills/migrate/general" "$T/gen"
printf 'id=broken\nlevel=bogus\nnames=x\ntemplate=t\ndesc=d\nfix=f\ncheck() { :; }\n' > "$T/gen/defects/broken.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen/defect-report.sh" "$T/empty" 2>&1)
check 2 "$?" "a check file with a bad level makes the run exit 2"
has "bad level" "$OUT" "bad level is named"
rm -f "$T/gen/defects/broken.sh"
printf 'id=partial\nlevel=high\n' > "$T/gen/defects/partial.sh"
OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash "$T/gen/defect-report.sh" "$T/empty" 2>&1)
check 2 "$?" "an incomplete check file makes the run exit 2"

# Neutral wording: no alarm words in the messages or the notes.
all=$(cat "$DEFECTS"/*.sh "$REPO_ROOT/skills/migrate/general/UPGRADE-NOTES.md")
for word in vulnerab critical exploit; do
  lacks "$word" "$(printf '%s' "$all" | tr '[:upper:]' '[:lower:]')" "wording stays neutral: no '$word'"
done

echo "defect-report.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
