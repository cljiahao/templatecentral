#!/usr/bin/env bash
# scripts/seeded-remove-harness.test.sh — tests for the seeded remove-harness.sh against fixture projects with a real manifest.
# Usage: bash scripts/seeded-remove-harness.test.sh
# Runs once with CI markers cleared and once with CI=true GITHUB_ACTIONS=true; the script behaves the same in both.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SC="$REPO_ROOT/skills/scaffold/shared/template/scripts"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; fi
}
exists() { # exists <path> <description>
  if [ -e "$D/$1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $2 — $1 is missing"; fi
}
absent() { # absent <path> <description>
  if [ ! -e "$D/$1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $2 — $1 still exists"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/remove-harness.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# sha256 of a file.
sha() {
  if command -v shasum > /dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi
}

# fixture <name>: a project with seeded files, a manifest, and project files that must survive; sets D.
fixture() {
  D="$T/$1"
  rm -rf "$D"
  mkdir -p "$D/scripts" "$D/.claude/hooks" "$D/.claude/agents" "$D/.claude/.harness-base/.claude/hooks" "$D/src"
  cp "$SC/remove-harness.sh" "$D/scripts/"
  echo 'hook' > "$D/.claude/hooks/block.sh"
  echo 'agent' > "$D/.claude/agents/code-reviewer.md"
  echo 'gate' > "$D/scripts/check-docs.sh"
  echo 'lh' > "$D/lefthook.yml"
  echo 'base copy' > "$D/.claude/.harness-base/.claude/hooks/block.sh"
  echo 'code' > "$D/src/main.ts"
  echo 'lock' > "$D/pnpm-lock.yaml"
  echo 'SECRET=1' > "$D/.env"
  echo 'agents' > "$D/AGENTS.md"
  {
    printf '{"seeded_files":{'
    printf '"a":{"path":".claude/hooks/block.sh","origin_hash":"%s"},' "$(sha "$D/.claude/hooks/block.sh")"
    printf '"b":{"path":".claude/agents/code-reviewer.md","origin_hash":"%s"},' "$(sha "$D/.claude/agents/code-reviewer.md")"
    printf '"c":{"path":"scripts/check-docs.sh","origin_hash":"%s"},' "$(sha "$D/scripts/check-docs.sh")"
    printf '"d":{"path":"lefthook.yml","origin_hash":"%s"},' "$(sha "$D/lefthook.yml")"
    printf '"e":{"path":"AGENTS.md","origin_hash":"%s"},' "$(sha "$D/AGENTS.md")"
    printf '"f":{"path":"src/main.ts","origin_hash":"%s"},' "$(sha "$D/src/main.ts")"
    printf '"g":{"path":"pnpm-lock.yaml","origin_hash":"%s"},' "$(sha "$D/pnpm-lock.yaml")"
    printf '"h":{"path":".env","origin_hash":"%s"},' "$(sha "$D/.env")"
    printf '"i":{"path":".claude/hooks/never-created.sh","origin_hash":"abc"}'
    printf '}}\n'
  } > "$D/.claude/harness.json"
}

# run [args]: runs the script in $D under the current mode; sets OUT and EC.
run() {
  OUT=$(cd "$D" && env "${ENVARGS[@]}" bash scripts/remove-harness.sh "$@" 2>&1 < /dev/null)
  EC=$?
}

# Project files that must survive every run.
survivors() {
  exists src/main.ts "$1: source file kept"
  exists pnpm-lock.yaml "$1: lockfile kept"
  exists .env "$1: .env kept"
  exists AGENTS.md "$1: AGENTS.md kept"
  check "SECRET=1" "$(cat "$D/.env")" "$1: .env content unchanged"
}

suite() {
  fixture dry
  before=$(cd "$D" && find . -type f | sort | xargs cat | cksum)
  run
  check 0 "$EC" "dry run exits 0 ($OUT)"
  after=$(cd "$D" && find . -type f | sort | xargs cat | cksum)
  check "$before" "$after" "dry run changes nothing"
  has "would remove .claude/hooks/block.sh" "$OUT" "dry run lists a hook"
  has "dry run, nothing changed" "$OUT" "dry run says so"
  has "KEEP .env: not a seeded harness location" "$OUT" "dry run names .env as kept"
  has "KEEP pnpm-lock.yaml" "$OUT" "dry run names the lockfile as kept"
  has "KEEP src/main.ts" "$OUT" "dry run names source as kept"
  has "already absent 1" "$OUT" "dry run counts the absent file"
  survivors dry

  fixture apply
  run --apply
  check 0 "$EC" "apply exits 0 ($OUT)"
  absent .claude/hooks/block.sh "apply removes the hook"
  absent .claude/agents/code-reviewer.md "apply removes the agent"
  absent scripts/check-docs.sh "apply removes a gate script"
  absent lefthook.yml "apply removes lefthook.yml"
  absent .claude/.harness-base/.claude/hooks/block.sh "apply removes the base copy"
  absent .claude/agents "apply prunes the emptied folder"
  exists scripts/remove-harness.sh "apply leaves unlisted files alone"
  has "removed .claude/hooks/block.sh" "$OUT" "apply reports what it removed"
  has "by hand:" "$OUT" "apply lists the manual steps"
  survivors apply
  absent .claude/harness.json "manifest removed once no seeded file is left"
  run --apply
  check 0 "$EC" "a second run after removal exits 0 ($OUT)"
  has "already removed" "$OUT" "second run says already removed"
  survivors apply-twice

  fixture modified
  echo 'my edit' >> "$D/.claude/hooks/block.sh"
  run --apply
  check 0 "$EC" "apply with a modified file exits 0 ($OUT)"
  exists .claude/hooks/block.sh "modified seeded file is kept"
  check "yes" "$(grep -q 'my edit' "$D/.claude/hooks/block.sh" && echo yes || echo no)" "modified file content untouched"
  has "KEEP .claude/hooks/block.sh: content differs" "$OUT" "modified file is named"
  has "--force .claude/hooks/block.sh" "$OUT" "modified file shows the force flag"
  absent scripts/check-docs.sh "unmodified files still go"
  exists .claude/harness.json "manifest stays while a file is kept"
  has "stays while kept files remain" "$OUT" "manifest-stays message"
  run --apply
  check 0 "$EC" "run twice with a kept file is safe"
  exists .claude/hooks/block.sh "kept file still kept on the second run"
  run --apply --force .claude/hooks/block.sh
  absent .claude/hooks/block.sh "--force removes the named modified file"
  has "forced" "$OUT" "force run says forced"
  survivors modified

  fixture force-protected
  run --apply --force .env --force src/main.ts
  survivors force-protected
  exists .env "force never removes .env"

  fixture nomanifest
  rm "$D/.claude/harness.json"
  run --apply
  check 0 "$EC" "missing manifest exits 0 ($OUT)"
  has "already removed" "$OUT" "missing-manifest message"
  exists .claude/hooks/block.sh "missing manifest removes nothing"

  fixture badjson
  echo 'not json' > "$D/.claude/harness.json"
  run --apply
  check 2 "$EC" "unparsable manifest exits 2"
  exists .claude/hooks/block.sh "unparsable manifest removes nothing"

  fixture escape
  echo victim > "$T/outside.txt"
  printf '{"seeded_files":{"x":{"path":"../outside.txt","origin_hash":"%s"}}}\n' "$(sha "$T/outside.txt")" > "$D/.claude/harness.json"
  run --apply
  check 1 "$([ -e "$T/outside.txt" ] && echo 1 || echo 0)" "path outside the project is never removed"
  has "KEEP ../outside.txt: not a seeded harness location" "$OUT" "escape path message"

  fixture symlink-parent
  mkdir -p "$T/elsewhere/hooks"
  echo precious > "$T/elsewhere/hooks/block.sh"
  rm -rf "$D/.claude/hooks"
  ln -s "$T/elsewhere/hooks" "$D/.claude/hooks"
  run --apply
  check "precious" "$(cat "$T/elsewhere/hooks/block.sh")" "file behind a symlinked parent folder is not deleted"
  has "KEEP .claude/hooks/block.sh: the file or a parent folder is a symbolic link" "$OUT" "symlink-parent message"
  exists .claude/harness.json "manifest stays while a symlink keep remains"

  fixture symlink-scripts
  mkdir -p "$T/realscripts"
  echo precious > "$T/realscripts/check-docs.sh"
  cp "$SC/remove-harness.sh" "$T/realscripts/"
  rm -rf "$D/scripts"
  ln -s "$T/realscripts" "$D/scripts"
  run --apply
  check "precious" "$(cat "$T/realscripts/check-docs.sh")" "file behind a symlinked scripts folder is not deleted"
  has "KEEP scripts/check-docs.sh: the file or a parent folder is a symbolic link" "$OUT" "symlinked scripts message"

  fixture symlink-leaf
  echo victim > "$T/leaf.txt"
  rm -f "$D/lefthook.yml"
  ln -s "$T/leaf.txt" "$D/lefthook.yml"
  run --apply
  check "victim" "$(cat "$T/leaf.txt")" "symlink leaf target is not touched"
  exists lefthook.yml "symlink leaf itself is kept"

  fixture userfile
  echo mine > "$D/notes.md"
  echo mine > "$D/src/app.ts"
  printf '{"seeded_files":{"x":{"path":"notes.md","origin_hash":"%s"},"y":{"path":"src/app.ts","origin_hash":"%s"}}}\n' "$(sha "$D/notes.md")" "$(sha "$D/src/app.ts")" > "$D/.claude/harness.json"
  run --apply
  exists notes.md "manifest line pointing at a user file does not delete it"
  exists src/app.ts "manifest line pointing at a source file does not delete it"
  has "KEEP notes.md: not a seeded harness location" "$OUT" "user-file message"
  run --apply --force notes.md
  exists notes.md "--force does not delete a non-harness file"

  fixture refused
  mkdir -p "$D/.git"
  echo cfg > "$D/.git/config"
  printf '{"seeded_files":{"a":{"path":".git/config","origin_hash":"x"},"b":{"path":"/etc/hosts","origin_hash":"x"},"c":{"path":"scripts/../src/main.ts","origin_hash":"x"},"d":{"path":".claude/hooks/a b.sh","origin_hash":"x"}}}\n' > "$D/.claude/harness.json"
  run --apply
  exists .git/config ".git entry is never removed"
  exists src/main.ts "dot-dot entry is never removed"
  has "KEEP .git/config" "$OUT" ".git entry is named as kept"
  has "KEEP /etc/hosts" "$OUT" "absolute entry is named as kept"
  has "KEEP scripts/../src/main.ts" "$OUT" "dot-dot entry is named as kept"

  fixture tabfield
  printf '{"seeded_files":{"a":{"path":".claude/hooks/block.sh","origin_hash":"x\\ty"}}}\n' > "$D/.claude/harness.json"
  run --apply
  exists .claude/hooks/block.sh "entry with a tab in a field is not removed"

  fixture alldiffer
  for f in .claude/hooks/block.sh .claude/agents/code-reviewer.md scripts/check-docs.sh lefthook.yml; do echo more >> "$D/$f"; done
  run --apply
  has "every seeded file reads as modified" "$OUT" "all-differ summary line"
  has ".claude/.harness-base/" "$OUT" "all-differ line says where to look"
  fixture somediffer
  echo more >> "$D/lefthook.yml"
  run --apply
  lacks "every seeded file reads as modified" "$OUT" "no all-differ line when only one differs"

  fixture newline
  printf '{"seeded_files":{"a":{"path":".claude/hooks/block.sh\\nscripts/check-docs.sh","origin_hash":"x"},"b":{"path":"lefthook.yml","origin_hash":"%s"}}}\n' "$(sha "$D/lefthook.yml")" > "$D/.claude/harness.json"
  run --apply
  check 2 "$EC" "a path with an embedded newline refuses the manifest ($OUT)"
  has "cannot parse" "$OUT" "newline refusal message"
  exists .claude/hooks/block.sh "newline entry removes nothing"
  exists scripts/check-docs.sh "second half of a split newline entry is not removed"
  exists lefthook.yml "valid entry beside a newline entry is not removed"

  fixture usage
  run --bogus
  check 2 "$EC" "unknown flag exits 2"
  lacks "would remove" "$OUT" "usage error removes nothing"
}

for MODE in local ci; do
  if [ "$MODE" = local ]; then
    ENVARGS=(-u CI -u GITHUB_ACTIONS -u TF_BUILD)
  else
    ENVARGS=(-u TF_BUILD CI=true GITHUB_ACTIONS=true)
  fi
  suite
done

echo "seeded-remove-harness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
