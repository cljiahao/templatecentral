#!/usr/bin/env bash
# scripts/lint-skills.test.sh — negative tests for the lint checks that read the scaffold
# template trees (skills/scaffold/shared/template*/).
#
# Usage: bash scripts/lint-skills.test.sh   (run from anywhere; needs python3)
#
# Each case copies skills/ to a scratch dir, damages it, runs scripts/lint-skills.sh on the copy
# and asserts that one named check section reports FAIL. A check that scans a path glob must fail
# when the glob matches nothing (<check>_fails_on_empty_match) and when the code it anchors on is
# gone (<check>_fails_when_anchor_deleted); otherwise moving code out of markdown would let it
# pass while verifying nothing.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# section <output> <header substring> — the lines of one check's section.
section() {
  awk -v h="$2" '/^── / { on = (index($0, h) > 0); next } on { print }' <<<"$1"
}

# lint_after <mutation function> — run the linter on a damaged copy; sets OUT.
lint_after() {
  rm -rf "$T/skills"
  cp -R skills "$T/skills"
  # Some skill references climb out of skills/ (<skill-dir>/../../.claude/rules); mirror the repo root.
  for f in .claude .claude-plugin CHANGELOG.md; do [[ -e "$T/$f" ]] || ln -s "$REPO_ROOT/$f" "$T/$f"; done
  S="$T/skills"
  SH="$S/scaffold/shared"
  "$1"
  OUT=$(bash scripts/lint-skills.sh "$T/skills" 2>&1 || true)
}

# fails <test name> <header substring> <mutation function> — ONLY=<regex> runs just the matching tests.
fails() {
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  lint_after "$3"
  local sec
  sec=$(section "$OUT" "$2")
  if [[ -z "$sec" ]]; then
    FAIL=$((FAIL + 1)); echo "FAIL: $1 — no section '$2' in the lint output"
  elif grep -q '^FAIL:' <<<"$sec"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $1 — '$2' did not fail: $(tail -1 <<<"$sec")"
  fi
}

# ── mutations ────────────────────────────────────────────────────────────────
no_templates() { rm -rf "$SH"/template "$SH"/template-ts "$SH"/template-py "$SH"/template-ci "$SH"/template.manifest; }
no_hooks() { rm -rf "$SH"/template/.claude/hooks "$SH"/template-ts/.claude/hooks "$SH"/template-py/.claude/hooks; }
no_yaml() { find "$SH"/template* -name '*.yml' -delete; }
no_template_sh() { find "$SH"/template* -name '*.sh' -delete; }
no_patterns() { rm -f "$SH/template/.claude/comment-hygiene-patterns.txt"; }
no_ts_overlay() { rm -rf "$SH/template-ts"; }
no_py_overlay() { rm -rf "$SH/template-py"; }

narration_in_template_sh() { printf '\n# Added a retry loop\n' >> "$SH/template/.claude/hooks/session-context.sh"; }
# strip_token <token> <replacement> <file or dir>... — rewrite every occurrence, so no other file
# keeps the anchor.
strip_token() {
  python3 - "$@" <<'PY'
import os, sys
tok, repl, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
files = []
for p in paths:
    if os.path.isdir(p):
        files += [os.path.join(dp, f) for dp, _, fs in os.walk(p) for f in fs]
    else:
        files.append(p)
for f in files:
    t = open(f, encoding="utf-8").read()
    if tok in t:
        open(f, "w", encoding="utf-8").write(t.replace(tok, repl))
PY
}
no_stop_hook_guard() { strip_token stop_hook_active sha_active "$SH/template-ts" "$SH/harness-kit-ts.md"; }
no_akia_in_py_guard() { strip_token AKIA AKXX "$SH/template-py" "$SH/harness-kit-fastapi.md"; }
array_command_in_settings() { python3 - "$SH/harness-kit-ts.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert '"command": "node"' in t
open(p, "w", encoding="utf-8").write(t.replace('"command": "node"', '"command": ["node"]', 1))
PY
}
no_settings_hooks() { sed -i.bak 's#"args"\(.*\)\.claude/hooks/#"argz"\1.claude/hx/#' "$SH/harness-kit-ts.md" && rm "$SH/harness-kit-ts.md.bak"; }
no_py_lefthook() { rm -f "$SH/template-py/lefthook.yml"; }
new_hook_in_template() { printf '#!/usr/bin/env bash\nexit 0\n' > "$SH/template/.claude/hooks/zz-new-hook.sh"; }
migrate_forgets_a_hook() { sed -i.bak 's/skill-usage-log/skill-log-x/g' "$S/migrate/general/phase-4-upgrade.md" && rm "$S/migrate/general/phase-4-upgrade.md.bak"; }
broken_lefthook_yaml() { printf '  bad:\n- not: [valid\n' >> "$SH/template-ts/lefthook.yml"; }
broken_ci_yaml() { printf '  bad:\n- not: [valid\n' >> "$SH/template-ci/github-ts/.github/workflows/ci.yml"; }
no_copy_instruction() { sed -i.bak 's#<skill-dir>/shared/template#<skill-dir>/shared/templat#g' "$SH/harness-kit.md" && rm "$SH/harness-kit.md.bak"; }
no_deps_step_github() { sed -i.bak '/ci-gates.sh deps$/d' "$SH/template-ci/github-ts/.github/workflows/ci.yml" && rm "$SH/template-ci/github-ts/.github/workflows/ci.yml.bak"; }
no_deps_step_github_py() { sed -i.bak '/ci-gates.sh deps$/d' "$SH/template-ci/github-py/.github/workflows/ci.yml" && rm "$SH/template-ci/github-py/.github/workflows/ci.yml.bak"; }
no_deps_step_azure() { sed -i.bak '/ci-gates.sh deps$/d' "$SH/template-ci/azure/azure-pipelines/templatecentral-gates.yml" && rm "$SH/template-ci/azure/azure-pipelines/templatecentral-gates.yml.bak"; }
no_deps_case() { sed -i.bak 's/^  deps)$/  depz)/' "$SH/template/.claude/ci-gates.sh" && rm "$SH/template/.claude/ci-gates.sh.bak"; }
no_ci_gates() { rm -f "$SH/template/.claude/ci-gates.sh"; }
bcrypt_in_template() { printf '\n# uses bcrypt\n' >> "$SH/template/.claude/hooks/session-context.sh"; }
pin_in_template() { printf 'left-pad@1.3.0\n' > "$SH/template/.claude/pinned.txt"; }
secret_in_template() { printf 'password = "hunter2hunter2"\n' > "$SH/template/.claude/leak.txt"; }
unlisted_template_file() { printf 'x\n' > "$SH/template/.claude/unlisted.txt"; }
manifest_lists_missing() { printf 'template/.claude/ghost.sh 755 - -\n' >> "$SH/template.manifest"; }
none() { :; }

# ── baseline ─────────────────────────────────────────────────────────────────
lint_after none
[[ "$OUT" == *"=== All checks passed ==="* ]]; check 0 $? "baseline_passes: lint passes on the unmodified tree (${OUT##*$'\n'})"

# ── template trees ───────────────────────────────────────────────────────────
fails template_trees_fail_on_empty_match "Template trees are complete" no_templates
fails template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" manifest_lists_missing
fails template_trees_fail_when_file_unlisted "Template trees are complete" unlisted_template_file
fails template_trees_fail_when_overlay_deleted_ts "Template trees are complete" no_ts_overlay
fails template_trees_fail_when_overlay_deleted_py "Template trees are complete" no_py_overlay

# ── check_no_comment_narration ───────────────────────────────────────────────
fails comment_narration_fails_on_empty_match "Change-narration comments" no_template_sh
fails comment_narration_fails_when_anchor_deleted "Change-narration comments" no_patterns
fails comment_narration_scans_template_sh "Change-narration comments" narration_in_template_sh

# ── check_scaffold_seeds_complete_harness ────────────────────────────────────
fails scaffold_seeds_fails_on_empty_match "Scaffold/migrate templates seed the complete harness" no_templates
fails scaffold_seeds_fails_when_anchor_deleted "Scaffold/migrate templates seed the complete harness" no_stop_hook_guard
fails scaffold_seeds_fails_when_variant_token_deleted "Scaffold/migrate templates seed the complete harness" no_akia_in_py_guard
fails scaffold_seeds_fails_when_variant_lefthook_deleted "Scaffold/migrate templates seed the complete harness" no_py_lefthook
fails scaffold_seeds_fails_when_copy_instruction_deleted "Scaffold/migrate templates seed the complete harness" no_copy_instruction

# ── check_hook_command_uses_args_array (anchors stay in the variant kits' settings.json fences) ──
fails hook_args_array_fails_on_empty_match "Hook commands use exec form" no_settings_hooks
fails hook_args_array_fails_when_anchor_deleted "Hook commands use exec form" array_command_in_settings

# ── check_migrate_hook_inventory_matches_kit ─────────────────────────────────
fails migrate_inventory_fails_on_empty_match "migrate hook inventory matches" no_hooks
fails migrate_inventory_fails_when_anchor_deleted "migrate hook inventory matches" migrate_forgets_a_hook
fails migrate_inventory_fails_when_hook_added "migrate hook inventory matches" new_hook_in_template

# ── check_yaml_fences_parse ──────────────────────────────────────────────────
if python3 -c 'import yaml' >/dev/null 2>&1; then
  fails yaml_parse_fails_on_empty_match "template yaml files parse" no_yaml
  fails yaml_parse_fails_when_lefthook_broken "template yaml files parse" broken_lefthook_yaml
  fails yaml_parse_fails_when_ci_broken "template yaml files parse" broken_ci_yaml
else
  echo "SKIP: yaml parse tests (PyYAML not installed)"
fi

# ── check_skilldir_refs_resolve ──────────────────────────────────────────────
fails skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" no_copy_instruction
fails skilldir_refs_fails_when_anchor_deleted "<skill-dir> references resolve" no_py_overlay

# ── check_security_seeds_present ─────────────────────────────────────────────
fails security_seeds_fails_on_empty_match "Deps gate and deny-by-default authz seeds" no_templates
fails security_seeds_fails_when_ci_gates_missing "Deps gate and deny-by-default authz seeds" no_ci_gates
fails security_seeds_fails_when_deps_case_deleted "Deps gate and deny-by-default authz seeds" no_deps_case
fails security_seeds_fails_when_github_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_github
fails security_seeds_fails_when_github_py_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_github_py
fails security_seeds_fails_when_azure_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_azure

# ── scan() rules cover template files ────────────────────────────────────────
fails scan_bcrypt_includes_templates "bcrypt references" bcrypt_in_template
fails scan_version_pins_includes_templates "Version pins in skills" pin_in_template
fails scan_hardcoded_secrets_includes_templates "Hardcoded secrets" secret_in_template

echo "lint-skills.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
