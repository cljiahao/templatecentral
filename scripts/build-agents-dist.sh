#!/usr/bin/env bash
# scripts/build-agents-dist.sh — generate a tool-agnostic Agent-Skills distribution.
#
# templateCentral ships as a Claude Code plugin, so its registered skills are named with the
# `templatecentral:` namespace (e.g. `name: templatecentral:scaffold`). That namespacing is a
# Claude Code convention. The open Agent-Skills standard (agentskills.io) — which OpenCode, Codex,
# and Antigravity implement — requires each skill's `name` to be lowercase-hyphen AND to match its
# directory name. This script copies skills/ into a distribution dir and strips the
# `templatecentral:` prefix so `name:` == the folder name, making the skills load cleanly in those
# tools. The <skill-dir> reference mechanism is unchanged and already portable (every compliant
# tool surfaces the skill's base directory at invocation — see docs/CROSS-TOOL.md).
#
# Usage:  bash scripts/build-agents-dist.sh [SRC_DIR] [OUT_DIR]
#   SRC_DIR  default: skills
#   OUT_DIR  default: dist/agents-skills   (gitignored build artifact)
#
# Then point your tool's skill path at OUT_DIR — see docs/CROSS-TOOL.md for per-tool config.
set -euo pipefail

SRC="${1:-skills}"
OUT="${2:-dist/agents-skills}"

if [[ ! -d "$SRC" ]]; then
  echo "error: source skills dir '$SRC' not found (run from the repo root)" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$SRC/." "$OUT/"

# Un-namespace registered skill names: `name: templatecentral:<x>` -> `name: <x>`.
# Agent-utility SKILL.md files (build/test/review/cleanup) carry a <!-- ref: --> header instead of
# `name:` frontmatter, so they are untouched — they remain catted-by-path, which still resolves.
renamed=0
while IFS= read -r f; do
  if grep -qE '^name:[[:space:]]*templatecentral:' "$f"; then
    perl -i -pe 's/^name:\s*templatecentral:(\S+)/name: $1/' "$f"
    renamed=$((renamed + 1))
  fi
done < <(find "$OUT" -name 'SKILL.md')

echo "Wrote tool-agnostic skills to $OUT/ ($renamed registered skill(s) un-namespaced)."
echo "Point your agent tool's skill path at: $OUT/  (see docs/CROSS-TOOL.md)"
