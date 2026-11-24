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

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
read_manifest() {
  if command -v jq >/dev/null 2>&1; then
    jq -er '.seeded_files | to_entries[] | "\(.value.path)\t\(.value.origin_hash)"' "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const m=JSON.parse(require("fs").readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(m.seeded_files))console.log(v.path+"\t"+v.origin_hash)'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json;m=json.load(open(".claude/harness.json"));[print(str(v["path"])+"\t"+str(v["origin_hash"])) for v in m["seeded_files"].values()]'
  else echo "verify-harness: need jq, node, or python3" >&2; return 3; fi
}

# Capture first: a parse failure must fail the run, not silently yield zero entries.
entries=$(read_manifest) || { echo "verify-harness: cannot parse $manifest" >&2; exit 2; }

drift=0; checked=0; unfilled=0
while IFS=$'\t' read -r path origin; do
  [ -n "$path" ] || continue
  case "$origin" in ""|null|undefined|None|"<"*) echo "UNFILLED: $path (origin_hash is a placeholder)" >&2; unfilled=1; continue ;; esac
  grep -qxF -- "$path" <<< "$guarded" || continue
  checked=$((checked + 1))
  if [ ! -f "$path" ]; then echo "MISSING:  $path" >&2; drift=1; continue; fi
  [ "$(sha "$path")" = "$origin" ] || { echo "MODIFIED: $path" >&2; drift=1; }
done <<< "$entries"

# Gate manifest: every gate in .claude/gates.txt must be run by lefthook (when it names a command) and by each CI host's files.
gates=".claude/gates.txt"
[ -f "$gates" ] || { echo "verify-harness: $gates missing" >&2; exit 2; }
code_of() { for f in "$@"; do if [ -f "$f" ]; then grep -vE '^[[:space:]]*#' "$f" || true; fi; done; }
has() { grep -qF -- "$2" <<< "$1"; }
hook_text=$(code_of lefthook.yml)
gh_text=$(code_of .github/workflows/ci.yml)
az_text=$(code_of azure-pipelines.yml azure-pipelines/templatecentral-gates.yml)
listed=0
while IFS='|' read -r gid lh ci || [ -n "$gid" ]; do
  case "$gid" in ""|"#"*) continue ;; esac
  if [ -z "$lh" ] || [ -z "$ci" ]; then echo "verify-harness: $gates line for '$gid' needs three | separated fields" >&2; exit 2; fi
  listed=$((listed + 1))
  if [ "$lh" != "-" ] && [ -n "$hook_text" ] && ! has "$hook_text" "$lh"; then echo "GATE MISSING: $gid is not run by lefthook.yml (expects '$lh')" >&2; drift=1; fi
  if [ "$ci" != "-" ] && [ -n "$gh_text" ] && ! has "$gh_text" "$ci"; then echo "GATE MISSING: $gid is not run by .github/workflows/ci.yml (expects '$ci')" >&2; drift=1; fi
  if [ "$ci" != "-" ] && [ -n "$az_text" ] && ! has "$az_text" "$ci"; then echo "GATE MISSING: $gid is not run by the Azure pipeline files (expects '$ci')" >&2; drift=1; fi
done < "$gates"
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
