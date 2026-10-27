#!/usr/bin/env bash
# Harness integrity sensor. Recomputes sha256 of the enforcement-layer seeded files and
# compares to the origin_hash baseline in .claude/harness.json. Read-only; exits non-zero
# on drift (1) or on an unreadable/unfilled manifest (2). Wired into CI and lefthook pre-push.
# Bless intentional changes with regen-harness.sh.
set -euo pipefail
manifest=".claude/harness.json"
[ -f "$manifest" ] || { echo "verify-harness: $manifest missing" >&2; exit 2; }

# Enforcement layer only — AGENTS.md / CLAUDE.md / *-verify skills legitimately evolve.
guard='^(\.claude/hooks/|\.claude/settings\.json$|\.claude/(verify|regen)-harness\.sh$|\.claude/comment-hygiene-patterns\.txt$|lefthook\.yml$|\.lefthook/|\.gitleaks\.toml$|\.github/workflows/|\.claude/ci-gates\.sh$|azure-pipelines/templatecentral-gates\.yml$)'

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
  printf '%s' "$path" | grep -qE "$guard" || continue   # enforcement layer only
  checked=$((checked + 1))
  if [ ! -f "$path" ]; then echo "MISSING:  $path" >&2; drift=1; continue; fi
  [ "$(sha "$path")" = "$origin" ] || { echo "MODIFIED: $path" >&2; drift=1; }
done <<< "$entries"

[ "$unfilled" -eq 0 ] || { echo "❌ $manifest still has unfilled origin_hash placeholders — finish Step E" >&2; exit 2; }
[ "$checked" -gt 0 ] || { echo "❌ verify-harness checked zero enforcement-layer entries — manifest empty or malformed" >&2; exit 2; }
if [ "$drift" -ne 0 ]; then
  echo "❌ harness integrity drift. If intentional, a human runs: bash .claude/regen-harness.sh" >&2
  exit 1
fi
echo "✓ harness integrity OK ($checked enforcement files)"
