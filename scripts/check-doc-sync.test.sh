#!/usr/bin/env bash
# scripts/check-doc-sync.test.sh — check-doc-sync.sh passes on a synced fixture and fails on each drift.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
t() { # t <name> <want rc> <mutation cmd>
  local w="$T/$1"; mkdir -p "$w/skills/add/auth" "$w/skills/add/page" "$w/skills/scaffold"
  printf -- '---\nname: add\n---\n' > "$w/skills/add/SKILL.md"
  printf -- '---\nname: scaffold\n---\n' > "$w/skills/scaffold/SKILL.md"
  printf 'Two user-invocable skills:\n' > "$w/README.md"
  printf 'Run templatecentral:add and templatecentral:scaffold.\n' > "$w/EXAMPLES.md"
  # shellcheck disable=SC2016  # literal backticks are fixture text
  printf '## `templatecentral:add` capabilities\n\n`auth` · `page`\n' > "$w/AGENTS.md"
  (cd "$w" && eval "$3")
  bash "$REPO/scripts/check-doc-sync.sh" "$w" >/dev/null 2>&1; local rc=$?
  if [[ $rc -eq $2 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc"; fi
}
t synced 0 true
t readme_count_drift 1 "sed -i.bak 's/Two/Three/' README.md"
t readme_sentence_missing 1 "echo none > README.md"
t examples_unknown_skill 1 "echo 'templatecentral:ghost' >> EXAMPLES.md"
t add_row_missing_dir 1 "mkdir skills/add/extra"
t add_row_stale_entry 1 "rmdir skills/add/page"
t add_row_missing 1 "echo x > AGENTS.md"
t bad_root 2 "rm -rf skills"
echo "check-doc-sync.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
