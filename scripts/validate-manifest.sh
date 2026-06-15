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

check_plugin_extended_fields() {
  # These fields are required by the Claude Code marketplace extended schema.
  # Replicates the inline node check that was previously in CI's plugin-validate job.
  header "plugin.json extended fields"
  local f="$PLUGIN_DIR/plugin.json"
  [[ -f "$f" ]] || { fail "plugin.json not found — skipping extended field checks"; return; }

  for field in displayName homepage repository license; do
    if python3 -c "
import json, sys
d = json.load(open('$f'))
sys.exit(0 if '$field' in d and d['$field'] not in ('', None) else 1)
" 2>/dev/null; then
      pass "field: $field"
    else
      fail "plugin.json missing or empty extended field: $field"
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

check_marketplace_version_and_source_consistency() {
  # The marketplace plugin entry's version (if present) must match plugin.json,
  # and the source path must reference the same repo root ("./" or "./").
  # Replicates part of what the CI inline node check previously validated.
  header "marketplace.json plugin entry — version + source consistency with plugin.json"
  local pf="$PLUGIN_DIR/plugin.json" mf="$PLUGIN_DIR/marketplace.json"
  [[ -f "$pf" && -f "$mf" ]] || return

  local result
  result=$(python3 - <<PYEOF
import json, sys
pf = "$pf"
mf = "$mf"
pdata = json.load(open(pf))
mdata = json.load(open(mf))
pv = pdata.get("version", "")
plugins = mdata.get("plugins", [])
if not plugins:
    print("FAIL: marketplace.json plugins array is empty — cannot check consistency")
    sys.exit(1)
ok = True
for i, p in enumerate(plugins):
    # Version consistency: if the marketplace entry carries a version field it must match plugin.json
    mv = p.get("version", None)
    if mv is not None and mv != pv:
        print(f"FAIL: plugins[{i}].version ({mv}) does not match plugin.json version ({pv})")
        ok = False
    # Source path: must point to the repo/plugin root (accepted values: "./" or ".")
    src = p.get("source", "")
    if src not in ("./", "."):
        print(f"FAIL: plugins[{i}].source ('{src}') does not point to repo root — expected './' or '.'")
        ok = False
    else:
        print(f"OK:   plugins[{i}].source='{src}'" + (f", version consistent ({pv})" if mv is not None else ", no version field (OK)"))
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

# ── doc sync (repo-level version markers track plugin.json) ─────────────────────

# Repo files that must track the plugin's semver. Resolved relative to the repo root
# (parent of PLUGIN_DIR). README badge + harness.json provenance drift silently otherwise —
# this is the exact failure that left AGENTS.md/harness.json stale across four releases.
_repo_root() { cd "$(dirname "$PLUGIN_DIR")" && pwd; }
_plugin_version() {
  python3 -c "import json; print(json.load(open('$PLUGIN_DIR/plugin.json')).get('version',''))" 2>/dev/null || echo ""
}

check_readme_badge_matches_plugin() {
  header "README version badge matches plugin.json"
  local root pv readme badge
  root="$(_repo_root)"; pv="$(_plugin_version)"; readme="$root/README.md"
  [[ -f "$readme" && -n "$pv" ]] || { pass "README.md or version absent — skipping"; return; }
  badge=$(grep -oE 'badge/version-[0-9]+\.[0-9]+\.[0-9]+' "$readme" | head -1 | sed 's/badge\/version-//')
  if [[ -z "$badge" ]]; then
    pass "No version badge found in README — skipping"
  elif [[ "$badge" == "$pv" ]]; then
    pass "README badge: $badge"
  else
    fail "README version badge ($badge) does not match plugin.json ($pv) — update the badge"
  fi
}

check_repo_harness_version_matches_plugin() {
  header "Repo .claude/harness.json templatecentral_version matches plugin.json"
  local root pv hj hv
  root="$(_repo_root)"; pv="$(_plugin_version)"; hj="$root/.claude/harness.json"
  [[ -f "$hj" && -n "$pv" ]] || { pass ".claude/harness.json or version absent — skipping"; return; }
  hv=$(python3 -c "import json; print(json.load(open('$hj')).get('templatecentral_version',''))" 2>/dev/null || echo "")
  if [[ "$hv" == "$pv" ]]; then
    pass "harness.json templatecentral_version: $hv"
  else
    fail "Repo .claude/harness.json templatecentral_version ($hv) does not match plugin.json ($pv) — update it"
  fi
}

check_changelog_has_current_version() {
  # CHANGELOG.md must contain a heading for the current plugin.json version so
  # a release-gating step can confirm the changelog is up to date.
  header "CHANGELOG.md has heading for current plugin.json version"
  local root pv cl
  root="$(_repo_root)"; pv="$(_plugin_version)"; cl="$root/CHANGELOG.md"
  [[ -f "$cl" && -n "$pv" ]] || { pass "CHANGELOG.md or version absent — skipping"; return; }
  if grep -qE "^## \[${pv}\]" "$cl"; then
    pass "CHANGELOG.md contains heading: ## [$pv]"
  else
    fail "CHANGELOG.md is missing a heading '## [$pv]' — add a release entry before publishing"
  fi
}

check_doc_version_stamps() {
  # Detects bare version stamps (e.g. "v4.5", "v5.0") in prose docs that drift silently
  # when the plugin version advances.
  #
  # Exclusions:
  #   - Lines containing img.shields.io/badge/version (README badge — intentional version pin)
  #   - Lines containing "changelog" (case-insensitive — version refs in changelogs are valid)
  #
  # Toggle:
  #   STRICT_DOC_SYNC=1 → hard FAIL (used by release pipeline after the docs cleanup task lands)
  #   default (unset/0)  → WARN only (CI runs without this flag until existing stamps are removed)
  header "Doc version stamps (bare v-stamps in prose docs)"
  local root
  root="$(_repo_root)"
  local stamps
  stamps=$(grep -nE '\bv[0-9]+\.[0-9]+' \
    "$root/README.md" "$root/EXAMPLES.md" "$root/CONTRIBUTING.md" "$root/FUTURE.md" "$root/SECURITY.md" \
    2>/dev/null \
    | grep -v 'img.shields.io/badge/version' | grep -vi 'changelog' || true)

  if [[ -z "$stamps" ]]; then
    pass "No bare version stamps found in prose docs"
    return
  fi

  local count
  count=$(echo "$stamps" | wc -l | tr -d ' ')
  if [[ "${STRICT_DOC_SYNC:-0}" == "1" ]]; then
    echo "FAIL: $count bare version stamp(s) found (STRICT_DOC_SYNC=1 — hard fail):"
    # shellcheck disable=SC2001  # per-line ^ anchor; parameter expansion can't prefix every line
    echo "$stamps" | sed 's/^/  /'
    FAILED=1
  else
    echo "WARN: $count bare version stamp(s) found (set STRICT_DOC_SYNC=1 to hard-fail):"
    # shellcheck disable=SC2001  # per-line ^ anchor; parameter expansion can't prefix every line
    echo "$stamps" | sed 's/^/  /'
  fi
}

check_repo_agents_marker_not_semver() {
  # The repo AGENTS.md line-1 marker (`<!-- templateCentral: plugin@X.Y.Z -->`) is a harness schema
  # floor, not plugin semver — it must equal HARNESS_SCHEMA_VERSION in scripts/lint-skills.sh.
  # Guard: the marker must equal the schema floor. A marker below the floor means a missed bump;
  # a marker above the floor means unintentional drift. The plugin semver is NOT the reference —
  # using plugin semver would false-fail when floor == plugin semver (e.g. both at 5.0.0 on release).
  header "Repo AGENTS.md marker equals HARNESS_SCHEMA_VERSION (schema floor)"
  local root marker mv lint_sh floor
  root="$(_repo_root)"; marker="$root/AGENTS.md"
  lint_sh="$root/scripts/lint-skills.sh"
  [[ -f "$marker" && -f "$lint_sh" ]] || { pass "AGENTS.md or lint-skills.sh absent — skipping"; return; }
  # Source HARNESS_SCHEMA_VERSION from lint-skills.sh rather than hardcoding it here.
  floor=$(grep -oE 'HARNESS_SCHEMA_VERSION="[0-9]+\.[0-9]+\.[0-9]+"' "$lint_sh" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [[ -n "$floor" ]] || { pass "HARNESS_SCHEMA_VERSION not found in lint-skills.sh — skipping"; return; }
  mv=$(head -1 "$marker" | grep -oE '@[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d '@')
  if [[ -z "$mv" ]]; then
    pass "No versioned marker on AGENTS.md line 1 — skipping"
  elif [[ "$mv" == "$floor" ]]; then
    pass "AGENTS.md marker (@$mv) equals HARNESS_SCHEMA_VERSION ($floor)"
  else
    fail "Repo AGENTS.md marker (@$mv) does not equal HARNESS_SCHEMA_VERSION ($floor) — update the marker or bump the schema floor in scripts/lint-skills.sh"
  fi
}

# ── RUN ALL CHECKS ─────────────────────────────────────────────────────────────

echo "=== templateCentral manifest validation ==="
echo "Checking: $PLUGIN_DIR/"

check_json_syntax

echo ""
echo "PLUGIN.JSON"
check_plugin_required_fields
check_plugin_extended_fields
check_plugin_semver
check_skills_path_exists

echo ""
echo "MARKETPLACE.JSON"
check_marketplace_required_fields
check_marketplace_plugin_entries
check_marketplace_version_and_source_consistency

echo ""
echo "CONSISTENCY"
check_name_consistency
check_skill_frontmatter

echo ""
echo "DOC SYNC"
check_readme_badge_matches_plugin
check_repo_harness_version_matches_plugin
check_repo_agents_marker_not_semver
check_changelog_has_current_version
check_doc_version_stamps
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== VALIDATION FAILED — fix manifest errors before publishing ==="
  exit 1
fi

echo "=== All manifest checks passed ==="
