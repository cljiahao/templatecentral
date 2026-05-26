#!/usr/bin/env bash
# scripts/validate-manifest.sh — validate .claude-plugin/ manifest files
#
# Run locally:  bash scripts/validate-manifest.sh
# Run in CI:    bash scripts/validate-manifest.sh
#
# Checks that plugin.json and marketplace.json are structurally correct so
# the plugin can be installed and updated without silent failures.
#
# Exit 0 = all checks pass. Exit 1 = one or more failures.

set -euo pipefail

PLUGIN_DIR="${1:-.claude-plugin}"
FAILED=0

fail() { echo "FAIL: $*"; FAILED=1; }
pass() { echo "OK:   $*"; }
header() { echo ""; echo "── $* ──"; }

# ── JSON syntax ────────────────────────────────────────────────────────────────

check_json_syntax() {
  header "JSON syntax"
  for f in "$PLUGIN_DIR/plugin.json" "$PLUGIN_DIR/marketplace.json"; do
    if [[ ! -f "$f" ]]; then
      fail "$(basename "$f") not found at $f"
    elif python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
      pass "$(basename "$f") — valid JSON"
    else
      fail "$(basename "$f") — parse error (run: python3 -m json.tool $f)"
    fi
  done
}

# ── plugin.json ────────────────────────────────────────────────────────────────

check_plugin_required_fields() {
  # Required for the Claude Code plugin loader to register the plugin.
  header "plugin.json required fields"
  local f="$PLUGIN_DIR/plugin.json"
  [[ -f "$f" ]] || { fail "plugin.json not found — skipping field checks"; return; }

  for field in name version description author skills; do
    if python3 -c "
import json, sys
d = json.load(open('$f'))
sys.exit(0 if '$field' in d and d['$field'] not in ('', None) else 1)
" 2>/dev/null; then
      pass "field: $field"
    else
      fail "plugin.json missing or empty required field: $field"
    fi
  done
}

check_plugin_semver() {
  # Claude Code marketplace rejects non-semver version strings.
  header "plugin.json semver version"
  local f="$PLUGIN_DIR/plugin.json"
  [[ -f "$f" ]] || return
  local v
  v=$(python3 -c "import json; print(json.load(open('$f')).get('version',''))" 2>/dev/null || echo "")
  if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "version: $v"
  else
    fail "version '$v' is not semver — expected X.Y.Z (e.g. 4.0.0)"
  fi
}

check_skills_path_exists() {
  # If the skills path is wrong the plugin installs but registers zero skills.
  header "plugin.json skills path"
  local f="$PLUGIN_DIR/plugin.json"
  [[ -f "$f" ]] || return
  local skills_rel skills_abs
  skills_rel=$(python3 -c "import json; print(json.load(open('$f')).get('skills',''))" 2>/dev/null || echo "")
  if [[ -z "$skills_rel" ]]; then
    fail "plugin.json skills field is empty"
    return
  fi
  # Resolve relative to the repo root (parent directory of PLUGIN_DIR)
  skills_abs="$(cd "$(dirname "$PLUGIN_DIR")" && pwd)/${skills_rel#./}"
  if [[ -d "$skills_abs" ]]; then
    pass "skills: $skills_rel → directory exists"
  else
    fail "skills path '$skills_rel' does not exist — plugin will install but register no skills"
  fi
}

# ── marketplace.json ───────────────────────────────────────────────────────────

check_marketplace_required_fields() {
  header "marketplace.json required fields"
  local f="$PLUGIN_DIR/marketplace.json"
  [[ -f "$f" ]] || { fail "marketplace.json not found — skipping field checks"; return; }

  for field in name description owner plugins; do
    if python3 -c "
import json, sys
d = json.load(open('$f'))
sys.exit(0 if '$field' in d and d['$field'] not in ('', None, []) else 1)
" 2>/dev/null; then
      pass "field: $field"
    else
      fail "marketplace.json missing or empty required field: $field"
    fi
  done
}

check_marketplace_plugin_entries() {
  # Each entry in plugins[] must have the fields the marketplace API requires.
  header "marketplace.json plugins[] entries"
  local f="$PLUGIN_DIR/marketplace.json"
  [[ -f "$f" ]] || return

  local result
  result=$(python3 - <<PYEOF
import json, sys
f = "$f"
d = json.load(open(f))
plugins = d.get("plugins", [])
if not plugins:
    print("FAIL: plugins array is empty")
    sys.exit(1)
required = {"name", "description", "source", "category"}
ok = True
for i, p in enumerate(plugins):
    missing = required - set(p.keys())
    if missing:
        print(f"FAIL: plugins[{i}] missing: {', '.join(sorted(missing))}")
        ok = False
if ok:
    print(f"OK:   plugins[]: {len(plugins)} entry/entries — all required fields present")
sys.exit(0 if ok else 1)
PYEOF
  ) || { echo "$result"; FAILED=1; return; }
  echo "$result"
}

# ── cross-file consistency ─────────────────────────────────────────────────────

check_name_consistency() {
  # Name must match exactly — a mismatch can cause update commands to fail.
  header "Name consistency across manifests"
  local pf="$PLUGIN_DIR/plugin.json" mf="$PLUGIN_DIR/marketplace.json"
  [[ -f "$pf" && -f "$mf" ]] || return
  local pname mname
  pname=$(python3 -c "import json; print(json.load(open('$pf')).get('name',''))" 2>/dev/null || echo "")
  mname=$(python3 -c "import json; print(json.load(open('$mf')).get('name',''))" 2>/dev/null || echo "")
  if [[ "$pname" == "$mname" ]]; then
    pass "name consistent: $pname"
  else
    fail "name mismatch — plugin.json: '$pname', marketplace.json: '$mname'"
  fi
}

# ── SKILL.md frontmatter ───────────────────────────────────────────────────────

check_skill_frontmatter() {
  # Missing or oversized frontmatter fields cause the skill loader to reject the skill silently.
  # SKILL.md files without YAML frontmatter (--- delimiters) are intentional internal utilities
  # loaded via `cat` by other skills — they are not registered and are skipped here.
  header "SKILL.md frontmatter (name + description ≤ 150 chars)"
  local pf="$PLUGIN_DIR/plugin.json"
  [[ -f "$pf" ]] || return
  local skills_rel skills_abs
  skills_rel=$(python3 -c "import json; print(json.load(open('$pf')).get('skills',''))" 2>/dev/null || echo "")
  skills_abs="$(cd "$(dirname "$PLUGIN_DIR")" && pwd)/${skills_rel#./}"
  [[ -d "$skills_abs" ]] || return

  local registered=0 unregistered=0 bad=0
  while IFS= read -r sf; do
    local slug
    slug="$(basename "$(dirname "$sf")")/SKILL.md"
    # Skip files without YAML frontmatter — they are internal utilities, not registered skills
    if ! head -1 "$sf" | grep -q '^---'; then
      unregistered=$((unregistered + 1))
      continue
    fi
    registered=$((registered + 1))
    grep -q '^name:'        "$sf" || { fail "$slug — missing 'name:' in frontmatter"; bad=$((bad + 1)); }
    grep -q '^description:' "$sf" || { fail "$slug — missing 'description:' in frontmatter"; bad=$((bad + 1)); }
    local desc
    desc=$(awk '/^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$sf")
    if [[ ${#desc} -gt 150 ]]; then
      fail "$slug — description too long (${#desc} chars, max 150)"
      bad=$((bad + 1))
    fi
  done < <(find "$skills_abs" -name 'SKILL.md' -not -path '*/.*' | sort)

  if [[ $((registered + unregistered)) -eq 0 ]]; then
    fail "No SKILL.md files found under $skills_rel — is the skills path correct?"
  elif [[ $bad -eq 0 ]]; then
    pass "$registered registered skill(s) — all frontmatter valid ($unregistered internal utilities skipped)"
  fi
}

# ── RUN ALL CHECKS ─────────────────────────────────────────────────────────────

echo "=== templateCentral manifest validation ==="
echo "Checking: $PLUGIN_DIR/"

check_json_syntax

echo ""
echo "PLUGIN.JSON"
check_plugin_required_fields
check_plugin_semver
check_skills_path_exists

echo ""
echo "MARKETPLACE.JSON"
check_marketplace_required_fields
check_marketplace_plugin_entries

echo ""
echo "CONSISTENCY"
check_name_consistency
check_skill_frontmatter
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== VALIDATION FAILED — fix manifest errors before publishing ==="
  exit 1
fi

echo "=== All manifest checks passed ==="
