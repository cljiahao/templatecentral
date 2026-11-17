#!/usr/bin/env bash
# scripts/check-doc-sync.sh [ROOT] — narrative docs must agree with the skills on disk.
#   1. README "<N-word> user-invocable skills" equals the skills whose SKILL.md has YAML frontmatter.
#   2. Every templatecentral:<name> in EXAMPLES.md is a user-invocable skill.
#   3. The AGENTS.md `add` capability row lists exactly the directories under skills/add/.
# Version agreement (README badge, plugin.json, harness.json) is scripts/validate-manifest.sh.
# Exit 0 in sync, 1 drift, 2 unusable ROOT.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -d "$ROOT/skills" && -f "$ROOT/README.md" && -f "$ROOT/AGENTS.md" && -f "$ROOT/EXAMPLES.md" ]] || { echo "check-doc-sync: $ROOT lacks skills/, README.md, AGENTS.md or EXAMPLES.md" >&2; exit 2; }

fail=0
bad() { echo "FAIL: $1"; fail=1; }

invocable=""
for f in "$ROOT"/skills/*/SKILL.md; do
  [[ "$(head -1 "$f")" == "---" ]] && invocable+="$(basename "$(dirname "$f")")"$'\n'
done
invocable=$(LC_ALL=C sort <<<"${invocable%$'\n'}")
count=$(grep -c . <<<"$invocable")

words=(zero one two three four five six seven eight nine ten)
claimed=$(grep -oEi '\b[a-z]+ user-invocable skills\b' "$ROOT/README.md" | head -1 | awk '{print tolower($1)}')
want="${words[$count]:-$count}"
[[ -n "$claimed" ]] || bad "README.md has no '<N> user-invocable skills' sentence"
[[ -z "$claimed" || "$claimed" == "$want" ]] || bad "README.md says '$claimed' user-invocable skills; skills/ has $count ($want)"

while read -r ref; do
  [[ -z "$ref" ]] && continue
  grep -qx "${ref#templatecentral:}" <<<"$invocable" || bad "EXAMPLES.md references $ref, which is not a user-invocable skill"
done < <(grep -oE 'templatecentral:[a-z-]+' "$ROOT/EXAMPLES.md" | sort -u)

row=$(awk '/^## `templatecentral:add` capabilities/{f=1;next} f&&NF{print;exit}' "$ROOT/AGENTS.md" | tr '·' '\n' | tr -d '` ' | grep . | LC_ALL=C sort)
dirs=$(find "$ROOT/skills/add" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort)
[[ -n "$row" ]] || bad "AGENTS.md has no templatecentral:add capabilities row"
if [[ -n "$row" && "$row" != "$dirs" ]]; then
  bad "AGENTS.md add row differs from skills/add/: $(diff <(echo "$row") <(echo "$dirs") | grep '^[<>]' | tr '\n' ' ')"
fi

[[ $fail -eq 0 ]] && echo "doc sync OK: $count skills, $(grep -c . <<<"$dirs") add capabilities"
exit $fail
