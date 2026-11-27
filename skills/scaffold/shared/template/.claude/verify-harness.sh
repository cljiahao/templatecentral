#!/usr/bin/env bash
# Harness integrity sensor: read-only; exits 1 on hash drift, 2 on a bad manifest. Bless changes with regen-harness.sh.
set -euo pipefail
# Paths below are project-relative: run from the project root, whatever directory the caller is in.
here=$(cd "$(dirname "$0")" && pwd)
[ "$(basename "$here")" = .claude ] && cd "$here/.."
manifest=".claude/harness.json"
[ -f "$manifest" ] || { echo "verify-harness: $manifest missing" >&2; exit 2; }

# Enforcement layer only — AGENTS.md / CLAUDE.md / *-verify skills legitimately evolve.
# Enforcement layer: the files gate-ratchet.sh --list-guarded marks enforced; no list is kept here.
if ! listing=$(bash scripts/gate-ratchet.sh --list-guarded HEAD 2>/dev/null) || [ -z "$listing" ]; then
  echo "verify-harness: cannot derive the enforcement layer (scripts/gate-ratchet.sh --list-guarded HEAD failed); run it in a committed project" >&2
  exit 2
fi
guarded=$(printf '%s\n' "$listing" | awk -F'\t' '$3 == 1 { print $2 }')

read_manifest() {
  if command -v jq >/dev/null 2>&1; then
    jq -er '.seeded_files | to_entries[] | "\(.value.path)\t\(.value.origin_hash)"' "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const m=JSON.parse(require("fs").readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(m.seeded_files))console.log(v.path+"\t"+v.origin_hash)'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json;m=json.load(open(".claude/harness.json"));[print(str(v["path"])+"\t"+str(v["origin_hash"])) for v in m["seeded_files"].values()]'
  else echo "verify-harness: need jq, node, or python3" >&2; return 3; fi
}

# Capture first: a parse failure must fail the run, not silently yield zero entries.
entries=$(read_manifest) || { echo "verify-harness: cannot parse $manifest" >&2; exit 2; }

drift=0; checked=0; unfilled=0
# Exact line match over a newline-delimited list, in the shell: no fork, no here-string, no pipe.
nl=$'\n'
guarded_nl="$nl$guarded$nl"
entries_paths_nl="$nl$(printf '%s\n' "$entries" | awk -F'\t' '{ print $1 }')$nl" || { echo "verify-harness: awk failed listing the manifest paths" >&2; exit 2; }
in_list() { case "$1" in *"$nl$2$nl"*) return 0 ;; esac; return 1; }
hash_paths=(); hash_origins=()
while IFS=$'\t' read -r path origin; do
  [ -n "$path" ] || continue
  case "$origin" in ""|null|undefined|None|"<"*) echo "UNFILLED: $path (origin_hash is a placeholder)" >&2; unfilled=1; continue ;; esac
  in_list "$guarded_nl" "$path" || continue
  checked=$((checked + 1))
  if [ ! -f "$path" ]; then echo "MISSING:  $path" >&2; drift=1; continue; fi
  hash_paths+=("./$path"); hash_origins+=("$origin")
done < <(printf '%s\n' "$entries")
# One hash call for every file: the hasher is a script, so a start per file is the cost.
if [ "${#hash_paths[@]}" -gt 0 ]; then
  if command -v shasum >/dev/null 2>&1; then hashes=$(shasum -a 256 -- "${hash_paths[@]}") || { echo "verify-harness: cannot hash the enforcement files" >&2; exit 2; }
  else hashes=$(sha256sum -- "${hash_paths[@]}") || { echo "verify-harness: cannot hash the enforcement files" >&2; exit 2; }; fi
  hi=0
  while IFS= read -r hline; do
    if [ "$hi" -ge "${#hash_paths[@]}" ] || [ "${hline%% *}" != "${hash_origins[$hi]}" ]; then echo "MODIFIED: ${hash_paths[$hi]#./}" >&2; drift=1; fi
    hi=$((hi + 1))
  done < <(printf '%s\n' "$hashes")
  [ "$hi" -eq "${#hash_paths[@]}" ] || { echo "verify-harness: the hasher returned $hi lines for ${#hash_paths[@]} files" >&2; exit 2; }
fi

# Gate manifest: every gate in .claude/gates.txt must be run by lefthook (when it names a command) and by each CI host's files.
gates=".claude/gates.txt"
[ -f "$gates" ] || { echo "verify-harness: $gates missing" >&2; exit 2; }
code_of() { for f in "$@"; do if [ -f "$f" ]; then grep -vE '^[[:space:]]*#' "$f" || true; fi; done; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# Every gate id this harness ships. A deleted gates.txt row cannot drop a gate, and test-harness-kit pins this list to the seeded gates.txt.
required_gates="harness docs testbudget nosonar secrets deps changelog comments commentshape duptests exclusions ratchet supplychain workflows envexample dockerfile workarounds review licences sbom changesize bundle diffcover"
# A gate script a hook or CI step runs must be a regular file, not a link, and hold content: an empty script exits 0 and passes.
gate_file_ok() {
  local gf=$1 gid=$2 grc=0 gl
  if [ -L "$gf" ]; then echo "GATE FILE SYMLINK: $gid reads $gf, which is a symlink; replace it with the file itself (git checkout <merge-base> -- $gf)" >&2; return 1; fi
  if [ ! -f "$gf" ]; then echo "GATE FILE MISSING: $gid reads $gf, which is not a file; restore it from git (git checkout <merge-base> -- $gf)" >&2; return 1; fi
  case "$gf" in *.sh|*.mjs|*.py|*.awk) ;; *) return 0 ;; esac
  [ -r "$gf" ] || { echo "verify-harness: cannot read $gf" >&2; exit 2; }
  grc=1
  while IFS= read -r gl || [ -n "$gl" ]; do
    case "$gl" in *[![:space:]]*) grc=0; break ;; esac
  done < "$gf"
  if [ "$grc" -eq 1 ]; then echo "GATE FILE BLANK: $gid reads $gf, which holds no content; restore it from git (git checkout <merge-base> -- $gf)" >&2; return 1; fi
}
hook_text=$(code_of lefthook.yml)
gh_text=$(code_of .github/workflows/ci.yml)
az_text=$(code_of azure-pipelines.yml azure-pipelines/templatecentral-gates.yml)
listed=0
for rg in $required_gates; do
  rgrc=0
  awk -F'|' -v g="$rg" '$1 == g { f = 1 } END { exit !f }' "$gates" || rgrc=$?
  [ "$rgrc" -le 1 ] || { echo "verify-harness: awk failed reading $gates (exit $rgrc)" >&2; exit 2; }
  if [ "$rgrc" -eq 1 ]; then echo "GATE ROW MISSING: $rg is a required gate but $gates has no row for it; restore the row" >&2; drift=1; fi
done
while IFS='|' read -r gid lh ci || [ -n "$gid" ]; do
  case "$gid" in ""|"#"*) continue ;; esac
  if [ -z "$lh" ] || [ -z "$ci" ]; then echo "verify-harness: $gates line for '$gid' needs three | separated fields" >&2; exit 2; fi
  listed=$((listed + 1))
  # A gate whose lefthook needle is a seeded path, and the config files its script reads, must be hashed entries of harness.json, so removing an entry cannot hide the file.
  need=''
  case "$lh" in scripts/*|.claude/*) need=${lh%% *} ;; esac
  case "$gid" in
    licences) need="$need .claude/allowed-licences.txt .claude/licence-exceptions.txt scripts/py-env.py" ;;
    sbom) need="$need scripts/py-env.py" ;;
    bundle) need="$need .claude/bundle-budget.txt" ;;
    duptests) need="$need scripts/duplicate-tests-ts.mjs scripts/duplicate_tests_py.py" ;;
    exclusions) need="$need $(printf '%s\n' "$guarded" | awk -v self="${lh%% *}" 'index($0, "scripts/check-exclude-") == 1 && $0 != self')" ;;
    commentshape) need="$need scripts/check-comments.mjs scripts/check-comments.py scripts/check-comments.licences.txt" ;;
    changesize) need="$need .claude/change-size-exclude.txt" ;;
  esac
  for nf in $need; do
    if ! in_list "$entries_paths_nl" "$nf"; then echo "GATE FILE UNREGISTERED: $gid reads $nf, which $manifest does not list as a seeded file; restore the entry with regen-harness.sh" >&2; drift=1; fi
    gate_file_ok "$nf" "$gid" || drift=1
  done
  if [ "$lh" != "-" ] && [ -n "$hook_text" ] && ! has "$hook_text" "$lh"; then echo "GATE MISSING: $gid is not run by lefthook.yml (expects '$lh')" >&2; drift=1; fi
  if [ "$ci" != "-" ] && [ -n "$gh_text" ] && ! has "$gh_text" "$ci"; then echo "GATE MISSING: $gid is not run by .github/workflows/ci.yml (expects '$ci')" >&2; drift=1; fi
  if [ "$ci" != "-" ] && [ -n "$az_text" ] && ! has "$az_text" "$ci"; then echo "GATE MISSING: $gid is not run by the Azure pipeline files (expects '$ci')" >&2; drift=1; fi
done < "$gates"
# Every gate a CI file invokes by id must still be listed, so deleting a manifest row cannot silently drop a gate.
used_rc=0
used=$(printf '%s\n%s\n' "$gh_text" "$az_text" | grep -ohE 'bash \.claude/ci-gates\.sh [a-z]+') || used_rc=$?
[ "$used_rc" -le 1 ] || { echo "verify-harness: grep failed reading the CI files (exit $used_rc)" >&2; exit 2; }
while read -r _ _ uid; do
  [ -n "$uid" ] || continue
  if ! awk -F'|' -v g="$uid" '$1 == g { f = 1 } END { exit !f }' "$gates"; then echo "GATE UNLISTED: CI runs gate '$uid' but $gates has no row for it; restore the row" >&2; drift=1; fi
done < <(printf '%s\n' "$used")
# Review gate files: when gates.txt lists the review gate and lefthook exists, every seeded file with review in its path must hold non-whitespace content.
if [ -n "$hook_text" ]; then
  review_files=$(printf '%s\n' "$entries" | awk -F'\t' '$1 ~ /review/ { print $1 }') || { echo "verify-harness: awk failed listing the review gate files" >&2; exit 2; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$f" ] || ! grep '[^[:space:]]' "$f" >/dev/null; then echo "REVIEW GATE FILE MISSING: $f is missing or blank; restore it from git (git checkout <merge-base> -- $f)" >&2; drift=1; fi
  done < <(printf '%s\n' "$review_files")
fi
# Agent permission baseline: a blessed hash must not hide a deleted deny or ask rule.
settings=".claude/settings.json"
rule_in_list() {
  awk -v list="$2" -v rule="$3" '
    $0 ~ "\"" list "\"[[:space:]]*:[[:space:]]*\\[" { on = 1; next }
    on && /\]/ { on = 0 }
    on && index($0, "\"" rule "\"") { found = 1 }
    END { exit !found }
  ' "$1"
}
if [ -f "$settings" ]; then
  for rule in 'Read(**/.env)' 'Read(**/.env.local)' 'Read(**/*.pem)' 'Read(**/*.key)' 'Read(./secrets/**)' 'Bash(sh)' 'Bash(bash)' 'Bash(bash -s *)' 'Bash(sh -s *)' 'Bash(eval *)'; do
    if ! rule_in_list "$settings" deny "$rule"; then echo "DENY RULE MISSING: $rule is not in $settings permissions.deny; restore it from the scaffold" >&2; drift=1; fi
  done
  for rule in 'Bash(curl *)' 'Bash(wget *)'; do
    if ! rule_in_list "$settings" ask "$rule"; then echo "ASK RULE MISSING: $rule is not in $settings permissions.ask; restore it from the scaffold" >&2; drift=1; fi
  done
  for rule in 'Bash(curl *)' 'Bash(wget *)'; do
    if rule_in_list "$settings" allow "$rule"; then echo "ASK RULE WEAKENED: $rule is in $settings permissions.allow; remove it so the agent asks first" >&2; drift=1; fi
  done
fi
[ "$listed" -gt 0 ] || { echo "verify-harness: $gates lists no gate" >&2; exit 2; }

[ "$unfilled" -eq 0 ] || { echo "❌ $manifest still has unfilled origin_hash placeholders — finish Step E" >&2; exit 2; }
[ "$checked" -gt 0 ] || { echo "❌ verify-harness checked zero enforcement-layer entries — manifest empty or malformed" >&2; exit 2; }
if [ "$drift" -ne 0 ]; then
  echo "❌ harness integrity drift. Restore each file listed above from git (git checkout <merge-base> -- <file>). If the change is intentional, a human runs: bash .claude/regen-harness.sh" >&2
  exit 1
fi
echo "✓ harness integrity OK ($checked enforcement files)"
