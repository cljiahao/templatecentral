#!/usr/bin/env bash
# scripts/lint-skills.test.sh — negative tests for the lint checks that read the scaffold
# template trees (skills/scaffold/shared/template*/) and the guards that stop a check passing
# on nothing.
#
# Usage: bash scripts/lint-skills.test.sh   (run from anywhere; needs python3)
#   ONLY=<regex> runs just the tests whose name matches; JOBS=<n> sets the parallelism (default 4);
#   LINT=<path> runs the tests against another copy of the linter.
#
# Each case copies skills/ to a scratch dir, damages it, runs scripts/lint-skills.sh on the copy
# and asserts that one named check section reports the expected FAIL message. A check that scans a
# path glob must fail when the glob matches nothing (<check>_fails_on_empty_match) and when the code
# it anchors on is gone (<check>_fails_when_anchor_deleted); otherwise moving code out of markdown
# would let it pass while verifying nothing.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
JOBS="${JOBS:-4}"
LINT="${LINT:-scripts/lint-skills.sh}"

PASS=0
FAIL=0
NJOB=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# section <output> <header substring> — the lines of one check's section.
section() {
  awk -v h="$2" '/^── / { on = (index($0, h) > 0); next } on { print }' <<<"$1"
}

# damage_and_lint <work dir> <mutation function> — run the linter on a damaged copy; sets OUT.
damage_and_lint() {
  local w=$1 f
  rm -rf "$w"; mkdir -p "$w"
  cp -R skills "$w/skills"
  # Some skill references climb out of skills/ (<skill-dir>/../../.claude/rules); mirror the repo root.
  for f in .claude .claude-plugin CHANGELOG.md; do ln -s "$REPO_ROOT/$f" "$w/$f"; done
  S="$w/skills"
  SH="$S/scaffold/shared"
  "$2"
  OUT=$(bash "$LINT" "$w/skills" 2>&1 || true)
}

# fails <test name> <header substring> <mutation function> <expected FAIL text> — the section must
# report FAIL and the text must be in it. Tests run JOBS at a time; ONLY=<regex> selects by name.
fails() {
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  NJOB=$((NJOB + 1))
  (
    damage_and_lint "$T/w$NJOB" "$3"
    sec=$(section "$OUT" "$2")
    if [[ -z "$sec" ]]; then
      echo "FAIL: $1 — no section '$2' in the lint output" > "$T/r$NJOB"
    elif ! grep -q '^FAIL:' <<<"$sec"; then
      echo "FAIL: $1 — '$2' did not fail: $(tail -1 <<<"$sec")" > "$T/r$NJOB"
    elif [[ "$sec" != *"$4"* ]]; then
      echo "FAIL: $1 — '$2' failed without the expected text [$4]: $(grep -v '^FAIL:' <<<"$sec" | head -3)" > "$T/r$NJOB"
    else
      echo PASS > "$T/r$NJOB"
    fi
    rm -rf "$T/w$NJOB"
  ) &
  if (( NJOB % JOBS == 0 )); then wait; fi
}

collect() {
  wait
  local f
  for f in "$T"/r*; do
    [[ -f "$f" ]] || continue
    if [[ "$(cat "$f")" == PASS ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); cat "$f"; fi
  done
}

# ── mutations ────────────────────────────────────────────────────────────────
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
    try:
        t = open(f, encoding="utf-8").read()
    except UnicodeDecodeError:
        continue
    if tok in t:
        open(f, "w", encoding="utf-8").write(t.replace(tok, repl))
PY
}
no_templates() { rm -rf "$SH"/template "$SH"/template-ts "$SH"/template-py "$SH"/template-ci "$SH"/template.manifest; }
no_shared() { rm -rf "$SH"; }
no_hooks() { rm -rf "$SH"/template/.claude/hooks "$SH"/template-ts/.claude/hooks "$SH"/template-py/.claude/hooks; }
no_yaml() { find "$SH"/template* "$S/scaffold/nextjs/template" "$S/scaffold/nextjs/template-agents" \( -name '*.yml' -o -name '*.yaml' \) -delete; }
no_scannable() { find "$SH"/template* "$S/scaffold/nextjs/template" "$S/scaffold/nextjs/template-agents" -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete; }
no_patterns() { rm -f "$SH/template/.claude/comment-hygiene-patterns.txt"; }
no_ts_overlay() { rm -rf "$SH/template-ts"; }
no_py_overlay() { rm -rf "$SH/template-py"; }
empty_dir_in_tree() { mkdir -p "$SH/template/zz-empty"; }
exec_bit_lost() { chmod -x "$SH/template/.claude/ci-gates.sh"; }

narration_in_template_sh() { printf '\n# Added a retry loop\n' >> "$SH/template/.claude/hooks/session-context.sh"; }
narration_in_template_yml() { printf '\n# Removed the old gate\n' >> "$SH/template-ts/lefthook.yml"; }
narration_in_template_toml() { printf '\n# Renamed from old\n' >> "$SH/template/.gitleaks.toml"; }
narration_in_template_py() { printf '\n# Updated for python\n' >> "$SH/template-py/.claude/hooks/user-prompt-guard.py"; }
narration_in_template_cjs() { printf '\n// Moved the check here\n' >> "$SH/template-ts/.claude/hooks/user-prompt-guard.cjs"; }
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
no_settings_hooks() { python3 - "$SH/harness-kit-ts.md" "$SH/harness-kit-fastapi.md" <<'PY'
import re, sys
for p in sys.argv[1:]:
    t = open(p, encoding="utf-8").read()
    open(p, "w", encoding="utf-8").write(re.sub(r'"args"(.*)\.claude/hooks/', r'"argz"\1.claude/hx/', t))
PY
}
no_py_lefthook() { rm -f "$SH/template-py/lefthook.yml"; }
new_hook_in_template() { printf '#!/usr/bin/env bash\nexit 0\n' > "$SH/template/.claude/hooks/zz-new-hook.sh"; }
migrate_forgets_a_hook() { strip_token skill-usage-log skill-log-x "$S/migrate/general/phase-4-upgrade.md"; }
broken_lefthook_yaml() { printf '  bad:\n- not: [valid\n' >> "$SH/template-ts/lefthook.yml"; }
broken_ci_yaml() { printf '  bad:\n- not: [valid\n' >> "$SH/template-ci/github-ts/.github/workflows/ci.yml"; }
no_copy_instruction() { strip_token '<skill-dir>/shared/template' '<skill-dir>/shared/templat' "$SH/harness-kit.md"; }
# shellcheck disable=SC2016  # the anchor is literal text, not an expansion
no_cp_line() { strip_token 'cp -- "$SK/$t/$p" "$TGT/$p"' 'true' "$SH/harness-kit.md"; }
# shellcheck disable=SC2016
no_ci_cp_line() { strip_token 'cp -- "$SK/$t/$p" "$TGT/$p"' 'true' "$SH/harness-kit-enforcement.md"; }
no_deps_step_github() { strip_token 'ci-gates.sh deps' 'ci-gates.sh depz' "$SH/template-ci/github-ts"; }
no_deps_step_github_py() { strip_token 'ci-gates.sh deps' 'ci-gates.sh depz' "$SH/template-ci/github-py"; }
no_deps_step_azure() { strip_token 'ci-gates.sh deps' 'ci-gates.sh depz' "$SH/template-ci/azure"; }
no_deps_case() { python3 - "$SH/template/.claude/ci-gates.sh" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert "\n  deps)\n" in t
open(p, "w", encoding="utf-8").write(t.replace("\n  deps)\n", "\n  depz)\n", 1))
PY
}
no_ci_gates() { rm -f "$SH/template/.claude/ci-gates.sh"; }
bcrypt_in_template() { printf '\n# uses bcrypt\n' >> "$SH/template/.claude/hooks/session-context.sh"; }
pin_in_template() { printf 'left-pad@1.3.0\n' > "$SH/template/.claude/pinned.txt"; }
secret_in_template() { printf 'password = "hunter2hunter2"\n' > "$SH/template/.claude/leak.txt"; }
unlisted_template_file() { printf 'x\n' > "$SH/template/.claude/unlisted.txt"; }
manifest_lists_missing() { printf 'template/.claude/ghost.sh 755 - -\n' >> "$SH/template.manifest"; }
no_verify_skill_paths() { strip_token '-verify/SKILL.md' '-verify/SKILLX.md' "$S"; }
no_tool_input_in_hooks() { strip_token tool_input tool_inpux "$SH/template" "$SH/template-ts" "$SH/template-py"; }
no_prepare_script() { strip_token '"prepare":' '"prepar3":' "$S"; }
no_posttooluse() { strip_token '"PostToolUse"' '"PostToolUs3"' "$S"; }
install_before_step0() { printf 'pnpm install\n\n' | cat - "$S/scaffold/nextjs/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/nextjs/source-files.md"; }
no_step0_line() { strip_token 'Step **0**' 'Step **O**' "$S/scaffold/nextjs/source-files.md"; }
install_before_step0_nestjs() { printf 'pnpm install\n\n' | cat - "$S/scaffold/nestjs/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/nestjs/source-files.md"; }
install_before_step0_vite() { printf 'pnpm install\n\n' | cat - "$S/scaffold/vite-react/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/vite-react/source-files.md"; }
no_step0_line_fastapi() { strip_token 'Step **0**' 'Step **O**' "$S/scaffold/fastapi/source-files.md"; }
wrong_stack_value() { strip_token 'STACK=nestjs' 'STACK=nextjs' "$S/scaffold/nestjs/source-files.md"; }
wrong_stack_value_fastapi() { strip_token 'STACK=fastapi' 'STACK=nestjs' "$S/scaffold/fastapi/source-files.md"; }
no_stack_value_vite() { strip_token 'STACK=vite-react' 'STACK-vite-react' "$S/scaffold/vite-react/source-files.md"; }
sh_not_755() { chmod 644 "$SH/template/.claude/hooks/session-context.sh"; python3 - "$SH/template.manifest" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
open(p, 'w').write(t.replace('template/.claude/hooks/session-context.sh 755', 'template/.claude/hooks/session-context.sh 644'))
PY
}

# nextjs stack trees (skills/scaffold/nextjs/template, template-agents, template.manifest)
NXD() { echo "$S/scaffold/nextjs"; }
no_nx_templates() { rm -rf "$(NXD)/template" "$(NXD)/template-agents" "$(NXD)/template.manifest"; }
no_nx_manifest() { rm -f "$(NXD)/template.manifest"; }
no_nx_agents_tree() { rm -rf "$(NXD)/template-agents"; }
no_nx_main_tree() { rm -rf "$(NXD)/template"; }
nx_manifest_lists_missing() { printf 'template/zz-ghost.txt 644 - -\n' >> "$(NXD)/template.manifest"; }
nx_unlisted_file() { printf 'x\n' > "$(NXD)/template/zz-unlisted.txt"; }
nx_exec_bit_lost() { chmod -x "$(NXD)/template/docker-entrypoint.sh"; }
nx_empty_dir() { mkdir -p "$(NXD)/template/zz-empty"; }
nx_narration_in_sh() { printf '\n# Added a retry loop\n' >> "$(NXD)/template/docker-entrypoint.sh"; }
nx_narration_in_yaml() { printf '\n# Removed the old setting\n' >> "$(NXD)/template/pnpm-workspace.yaml"; }
nx_broken_yaml() { printf '  bad:\n- not: [valid\n' >> "$(NXD)/template/pnpm-workspace.yaml"; }
nx_no_stack_copy() { strip_token 'PART=stack' 'PART=stac' "$(NXD)/source-files.md"; }
nx_no_base_copy() { strip_token 'PART=base' 'PART=bas' "$(NXD)/source-files.md"; }
nx_no_agents_copy() { strip_token 'PART=agents' 'PART=agent' "$(NXD)/source-files.md"; }
nx_no_manifest_ref() { strip_token '<skill-dir>/nextjs/template.manifest' '<skill-dir>/nextjs/template.manifes' "$(NXD)/source-files.md"; }
nx_wrong_stack() { strip_token 'STACK=nextjs' 'STACK=nestjs' "$(NXD)/source-files.md"; }
nx_no_stack_value() { strip_token 'STACK=nextjs' 'STACK-nextjs' "$(NXD)/source-files.md"; }
no_ref_md() { find "$S" -name '*.md' ! -name 'SKILL.md' ! -name 'CONVENTIONS.md' -delete; }
nx_ref_header_deleted() { sed -i.bak '1d' "$(NXD)/config-files.md" && rm -f "$(NXD)/config-files.md.bak"; }
headerless_md_beside_template() { printf 'no header\n' > "$(NXD)/zz-note.md"; }
headerless_md_named_template() { printf 'no header\n' > "$(NXD)/template-notes.md"; }
headerless_md_in_shared_next_to_trees() { printf 'no header\n' > "$SH/zz-note.md"; }
middleware_in_nx_template() { printf '\n// see middleware.ts\n' >> "$(NXD)/template/next.config.ts"; }
middleware_in_other_template_md() { printf '\nmiddleware.ts\n' > "$(NXD)/template/zz-other.md"; }
middleware_in_nx_source_files() { printf '\nmiddleware.ts\n' >> "$(NXD)/source-files.md"; }
pin_in_nx_template() { printf 'left-pad@1.3.0\n' >> "$(NXD)/template/.npmrc"; }
secret_in_nx_template() { printf 'password = "hunter2hunter2"\n' >> "$(NXD)/template/.npmrc"; }
bare_handler_in_nx_template() { printf '\nexport async function GET() {}\n' >> "$(NXD)/template/src/app/api/health/route.ts"; }
marker_drift_in_nx_template() { strip_token 'nextjs@6.0.0' 'nextjs@99.0.0' "$(NXD)/template-agents/AGENTS.md"; }
none() { :; }

# ── baseline ─────────────────────────────────────────────────────────────────
if [[ -z "${ONLY:-}" ]]; then
  damage_and_lint "$T/base" none
  [[ "$OUT" == *"=== All checks passed ==="* ]]; check 0 $? "baseline_passes: lint passes on the unmodified tree (${OUT##*$'\n'})"
fi

# ── template trees ───────────────────────────────────────────────────────────
fails template_trees_fail_on_empty_match "Template trees are complete" no_templates "tree is missing or empty"
fails template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" manifest_lists_missing "which is not in the tree"
fails template_trees_fail_when_file_unlisted "Template trees are complete" unlisted_template_file "is in the tree but not listed"
fails template_trees_fail_when_overlay_deleted_ts "Template trees are complete" no_ts_overlay "tree is missing or empty"
fails template_trees_fail_when_overlay_deleted_py "Template trees are complete" no_py_overlay "tree is missing or empty"
fails template_trees_fail_on_empty_directory "Template trees are complete" empty_dir_in_tree "empty directory in a template tree"
fails template_trees_fail_when_exec_bit_lost "Template trees are complete" exec_bit_lost "is mode 644 but listed as 755"

# ── check_no_comment_narration ───────────────────────────────────────────────
fails comment_narration_fails_on_empty_match "Change-narration comments" no_scannable "nothing to scan"
fails comment_narration_fails_when_anchor_deleted "Change-narration comments" no_patterns "Missing"
fails comment_narration_does_not_abort_without_shared_dir "Change-narration comments" no_shared "Missing"
fails comment_narration_scans_template_sh "Change-narration comments" narration_in_template_sh "Added a retry loop"
fails comment_narration_scans_template_yml "Change-narration comments" narration_in_template_yml "Removed the old gate"
fails comment_narration_scans_template_toml "Change-narration comments" narration_in_template_toml "Renamed from old"
fails comment_narration_scans_template_py "Change-narration comments" narration_in_template_py "Updated for python"
fails comment_narration_scans_template_cjs "Change-narration comments" narration_in_template_cjs "Moved the check here"

# ── check_scaffold_seeds_complete_harness ────────────────────────────────────
fails scaffold_seeds_fails_on_empty_match "Scaffold/migrate templates seed the complete harness" no_templates "template file not found"
fails scaffold_seeds_fails_when_anchor_deleted "Scaffold/migrate templates seed the complete harness" no_stop_hook_guard "missing token: stop_hook_active"
fails scaffold_seeds_fails_when_variant_token_deleted "Scaffold/migrate templates seed the complete harness" no_akia_in_py_guard "missing token: AKIA"
fails scaffold_seeds_fails_when_variant_lefthook_deleted "Scaffold/migrate templates seed the complete harness" no_py_lefthook "lefthook.yml — template file not found"
fails scaffold_seeds_fails_when_cp_line_deleted "Scaffold/migrate templates seed the complete harness" no_cp_line "Step 0 copy instruction missing"
fails scaffold_seeds_fails_when_ci_cp_line_deleted "Scaffold/migrate templates seed the complete harness" no_ci_cp_line "Step B3 CI copy instruction missing"

# ── check_migrate_hook_inventory_matches_kit ─────────────────────────────────
fails migrate_inventory_fails_on_empty_match "migrate hook inventory matches" no_hooks "nothing to compare"
fails migrate_inventory_fails_when_anchor_deleted "migrate hook inventory matches" migrate_forgets_a_hook "migrate is missing hook: skill-usage-log"
fails migrate_inventory_fails_when_hook_added "migrate hook inventory matches" new_hook_in_template "migrate is missing hook: zz-new-hook"

# ── check_yaml_fences_parse ──────────────────────────────────────────────────
if python3 -c 'import yaml' >/dev/null 2>&1; then
  fails yaml_parse_fails_on_empty_match "template yaml files parse" no_yaml "no yaml files under any template tree"
  fails yaml_parse_fails_when_lefthook_broken "template yaml files parse" broken_lefthook_yaml "lefthook.yml:"
  fails yaml_parse_fails_when_ci_broken "template yaml files parse" broken_ci_yaml "ci.yml:"
elif [[ "${CI:-}" == true ]]; then
  FAIL=$((FAIL + 1)); echo "FAIL: PyYAML is not installed but CI=true; the yaml parse tests must run in CI"
else
  echo "SKIP: yaml parse tests (PyYAML not installed)"
fi

# ── check_skilldir_refs_resolve ──────────────────────────────────────────────
fails skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" no_cp_line "copy instruction"
fails skilldir_refs_fails_when_anchor_deleted "<skill-dir> references resolve" no_py_overlay "template-py"
fails skilldir_refs_fails_when_reference_broken "<skill-dir> references resolve" no_copy_instruction "Broken <skill-dir> reference"

# ── check_security_seeds_present ─────────────────────────────────────────────
fails security_seeds_fails_on_empty_match "Deps gate and deny-by-default authz seeds" no_templates "file not found"
fails security_seeds_fails_when_ci_gates_missing "Deps gate and deny-by-default authz seeds" no_ci_gates "ci-gates.sh: file not found"
fails security_seeds_fails_when_deps_case_deleted "Deps gate and deny-by-default authz seeds" no_deps_case "ci-gates.sh has no deps case"
fails security_seeds_fails_when_github_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_github "GitHub pipeline step"
fails security_seeds_fails_when_github_py_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_github_py "GitHub pipeline step"
fails security_seeds_fails_when_azure_step_deleted "Deps gate and deny-by-default authz seeds" no_deps_step_azure "Azure pipeline step"

# ── check_hook_command_uses_args_array (anchors stay in the variant kits' settings.json fences) ──
fails hook_args_array_fails_on_empty_match "Hook commands use exec form" no_settings_hooks "no hook definition found"
fails hook_args_array_fails_when_anchor_deleted "Hook commands use exec form" array_command_in_settings '"command": ["node"]'

# ── checks that must not pass on nothing ─────────────────────────────────────
fails seeded_skill_paths_fails_on_empty_match "Seeded project skills use directory form" no_verify_skill_paths "would scan nothing"
fails toplevel_command_fails_on_empty_match "Top-level d.command access" no_tool_input_in_hooks "No template hook reads tool_input"
fails husky_fails_when_lefthook_layer_deleted "No husky references" no_py_lefthook "Missing"
fails lefthook_prepare_fails_on_empty_match "lefthook prepare script has Docker-safe fallback" no_prepare_script "would scan nothing"
fails posttooluse_full_suite_fails_on_empty_match "Full test suite in PostToolUse hook" no_posttooluse "No \"PostToolUse\" hook definition"
fails posttooluse_mypy_fails_on_empty_match "mypy in PostToolUse hook" no_posttooluse "No \"PostToolUse\" hook definition"

# ── check_step0_before_install ───────────────────────────────────────────────
fails step0_order_fails_when_install_comes_first "Scaffold runs kit Step 0 before the first install" install_before_step0 "install runs before kit Step 0"
fails step0_order_fails_when_step0_line_deleted "Scaffold runs kit Step 0 before the first install" no_step0_line "no kit Step 0 instruction"

fails step0_order_fails_when_install_comes_first_nestjs "Scaffold runs kit Step 0 before the first install" install_before_step0_nestjs "install runs before kit Step 0"
fails step0_order_fails_when_install_comes_first_vite "Scaffold runs kit Step 0 before the first install" install_before_step0_vite "install runs before kit Step 0"
fails step0_order_fails_when_step0_line_deleted_fastapi "Scaffold runs kit Step 0 before the first install" no_step0_line_fastapi "no kit Step 0 instruction"
fails stack_value_fails_when_wrong_nestjs "Scaffold runs kit Step 0 before the first install" wrong_stack_value "must name STACK=nestjs"
fails stack_value_fails_when_wrong_fastapi "Scaffold runs kit Step 0 before the first install" wrong_stack_value_fastapi "must name STACK=fastapi"
fails stack_value_fails_when_missing_vite "Scaffold runs kit Step 0 before the first install" no_stack_value_vite "must name STACK=vite-react"
fails template_trees_fail_when_script_not_755 "Template trees are complete" sh_not_755 "must be mode 755"

# anchors the migrate docs must carry for the template trees (the manifest and both overlays)
for doc in phase-4-upgrade phase-5-health-check; do
  for anchor in 'scaffold/shared/template.manifest' 'template-ts/' 'template-py/'; do
    fn="strip_${doc//-/_}_$(echo "$anchor" | tr -c 'a-z0-9\n' '_')"
    eval "$fn() { strip_token '$anchor' 'zz-gone/' \"\$S/migrate/general/$doc.md\"; }"
    fails "migrate_inventory_fails_when_${doc}_anchor_deleted[$anchor]" "migrate hook inventory matches" "$fn" "$doc.md — missing template anchor $anchor"
  done
done
step0_stack_on_other_line() { python3 - "$S/scaffold/nextjs/source-files.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert " with `STACK=nextjs` in its fence" in t
open(p, "w", encoding="utf-8").write(t.replace(" with `STACK=nextjs` in its fence", "", 1) + "\nSTACK=nextjs\n")
PY
}
fails step0_stack_must_be_on_the_step0_line "Scaffold runs kit Step 0 before the first install" step0_stack_on_other_line "must name STACK=nextjs on the Step 0 line"

# the B3 copy fence and the seed-neither fence are scaffold-only; the migrate docs and Step B3 say so
for entry in "migrate/general/phase-4-upgrade.md|copy fence and the seed-neither fence are scaffold-only" "migrate/general/phase-5-health-check.md|copy fence and seed-neither fence are scaffold-only" "scaffold/shared/harness-kit-enforcement.md|and the seed-neither fence below are scaffold-only"; do
  doc=${entry%%|*}; phrase=${entry#*|}
  fn="no_scaffold_only_$(echo "$doc" | tr -c 'a-z0-9\n' '_')"
  eval "$fn() { strip_token '$phrase' 'zz-gone' \"\$S/$doc\"; }"
  fails "migrate_inventory_fails_when_scaffold_only_note_deleted[$doc]" "migrate hook inventory matches" "$fn" "$doc — missing the scaffold-only note"
done
# deleting only the note in phase-4 fails even though its Step B3 bullet still says "scaffold-only"
grep -q 'per the scaffold-only note above' skills/migrate/general/phase-4-upgrade.md || { FAIL=$((FAIL + 1)); echo "FAIL: phase-4 no longer repeats the scaffold-only token, so the test below proves nothing"; }
fails migrate_inventory_fails_when_only_the_phase4_note_is_deleted "migrate hook inventory matches" no_scaffold_only_migrate_general_phase_4_upgrade_md "phase-4-upgrade.md — missing the scaffold-only note"
fastapi_step0_outside_6b() { python3 - "$S/scaffold/fastapi/source-files.md" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
i = next(n for n, l in enumerate(lines) if "Step **0**" in l)
moved = lines.pop(i)
lines += ["", moved, ""]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
fails fastapi_step0_must_sit_in_step_6b "Scaffold runs kit Step 0 before the first install" fastapi_step0_outside_6b "Step 0 line must be in the step 6b section"

# ── scan() rules cover template files ────────────────────────────────────────
fails scan_bcrypt_includes_templates "bcrypt references" bcrypt_in_template "bcrypt"
fails scan_version_pins_includes_templates "Version pins in skills" pin_in_template "left-pad@1.3.0"
fails scan_hardcoded_secrets_includes_templates "Hardcoded secrets" secret_in_template "hunter2hunter2"


# ── nextjs stack trees ───────────────────────────────────────────────────────
fails nextjs_template_trees_fail_on_empty_match "Template trees are complete" no_nx_templates "nextjs/template: tree is missing or empty"
fails nextjs_template_trees_fail_when_main_tree_deleted "Template trees are complete" no_nx_main_tree "nextjs/template: tree is missing or empty"
fails nextjs_template_trees_fail_when_agents_tree_deleted "Template trees are complete" no_nx_agents_tree "nextjs/template-agents: tree is missing or empty"
fails nextjs_template_trees_fail_when_manifest_deleted "Template trees are complete" no_nx_manifest "nextjs/template.manifest: file not found"
fails nextjs_template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" nx_manifest_lists_missing "which is not in the tree"
fails nextjs_template_trees_fail_when_file_unlisted "Template trees are complete" nx_unlisted_file "is in the tree but not listed"
fails nextjs_template_trees_fail_when_script_loses_exec_bit "Template trees are complete" nx_exec_bit_lost "is mode 644 but listed as 755"
fails nextjs_template_trees_fail_on_empty_directory "Template trees are complete" nx_empty_dir "empty directory in a template tree"
fails nextjs_comment_narration_scans_template_sh "Change-narration comments" nx_narration_in_sh "Added a retry loop"
fails nextjs_comment_narration_scans_template_yaml "Change-narration comments" nx_narration_in_yaml "Removed the old setting"
fails nextjs_scaffold_seeds_fails_on_empty_match "Scaffold/migrate templates seed the complete harness" no_templates "template file not found"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  fails nextjs_yaml_parse_fails_when_template_yaml_broken "template yaml files parse" nx_broken_yaml "pnpm-workspace.yaml:"
fi
fails nextjs_skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" nx_no_stack_copy "scaffold/nextjs/source-files.md: copy instruction PART=stack missing"
fails nextjs_skilldir_refs_fails_when_base_copy_deleted "<skill-dir> references resolve" nx_no_base_copy "scaffold/nextjs/source-files.md: copy instruction PART=base missing"
fails nextjs_skilldir_refs_fails_when_agents_copy_deleted "<skill-dir> references resolve" nx_no_agents_copy "scaffold/nextjs/source-files.md: copy instruction PART=agents missing"
fails nextjs_skilldir_refs_fails_when_manifest_ref_deleted "<skill-dir> references resolve" nx_no_manifest_ref "scaffold/nextjs/source-files.md: copy instruction <skill-dir>/nextjs/template.manifest missing"
fails nextjs_stack_value_fails_when_wrong "Scaffold runs kit Step 0 before the first install" nx_wrong_stack "must name STACK=nextjs"
fails nextjs_stack_value_fails_when_missing "Scaffold runs kit Step 0 before the first install" nx_no_stack_value "must name STACK=nextjs"

# ── check_ref_file_headers skips shipped template files and still catches reference files ──
fails ref_headers_fail_on_empty_match "Ref file <!-- ref: --> headers" no_ref_md "scanned nothing"
fails ref_headers_fail_when_anchor_deleted "Ref file <!-- ref: --> headers" nx_ref_header_deleted "nextjs/config-files.md"
fails ref_headers_still_check_a_file_beside_the_trees "Ref file <!-- ref: --> headers" headerless_md_beside_template "nextjs/zz-note.md"
fails ref_headers_still_check_a_file_named_template "Ref file <!-- ref: --> headers" headerless_md_named_template "nextjs/template-notes.md"
fails ref_headers_still_check_a_file_in_shared "Ref file <!-- ref: --> headers" headerless_md_in_shared_next_to_trees "shared/zz-note.md"

# ── check_no_middleware_ts: the exclusion names one template file ────────────
fails middleware_fails_in_another_nextjs_template_file "middleware.ts references" middleware_in_nx_template "next.config.ts"
fails middleware_fails_in_a_second_template_markdown_file "middleware.ts references" middleware_in_other_template_md "zz-other.md"
fails middleware_fails_in_nextjs_source_files "middleware.ts references" middleware_in_nx_source_files "source-files.md"

# ── scan() rules and the marker check cover the nextjs template files ────────
fails scan_version_pins_includes_nextjs_template "Version pins in skills" pin_in_nx_template "left-pad@1.3.0"
fails scan_hardcoded_secrets_includes_nextjs_template "Hardcoded secrets" secret_in_nx_template "hunter2hunter2"
fails scan_bare_route_handler_includes_nextjs_template "Bare Next.js route handler exports" bare_handler_in_nx_template "route.ts"
fails scan_agents_marker_includes_nextjs_template "AGENTS.md schema marker not drifted" marker_drift_in_nx_template "template-agents/AGENTS.md"

collect
echo "lint-skills.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
