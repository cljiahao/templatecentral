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
  OUT=$(bash "$LINT" "$w/skills${SLASH:+/}" 2>&1 || true)
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

# fails_both <same arguments as fails> — the test as written, then again with the skills path given a trailing slash, as CI gives it.
fails_both() {
  fails "$@"
  SLASH=1
  fails "${1}_with_trailing_slash" "${@:2}"
  SLASH=
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
no_templates() { rm -rf "$SH"/template "$SH"/template-* "$SH"/template.manifest; }
no_shared() { rm -rf "$SH"; }
no_hooks() { rm -rf "$SH"/template/.claude/hooks "$SH"/template-ts/.claude/hooks "$SH"/template-py/.claude/hooks; }
# Every templated stack; the empty-match helpers below empty all of them, so a check that scans the
# stacks still sees nothing.
TEMPLATED_TREES=(nextjs vite-react fastapi nestjs)
no_yaml() { local d; find "$SH"/template* \( -name '*.yml' -o -name '*.yaml' \) -delete; for d in "${TEMPLATED_TREES[@]}"; do find "$S/scaffold/$d/template" "$S/scaffold/$d/template-agents" \( -name '*.yml' -o -name '*.yaml' \) -delete; done; }
no_scannable() { local d; find "$SH"/template* -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete; for d in "${TEMPLATED_TREES[@]}"; do find "$S/scaffold/$d/template" "$S/scaffold/$d/template-agents" -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete; done; }
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
array_command_in_settings() { python3 - "$SH/template-settings-ts/.claude/settings.json" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert '"command": "node"' in t
open(p, "w", encoding="utf-8").write(t.replace('"command": "node"', '"command": ["node"]', 1))
PY
}
no_settings_hooks() { python3 - "$SH/template-settings-ts/.claude/settings.json" "$SH/template-settings-py/.claude/settings.json" <<'PY'
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
no_cp_line() { strip_token 'cp -- "$SK/$t/$p" "$TGT/$dest"' 'true' "$SH/tc-copy.sh"; }
# shellcheck disable=SC2016
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
nx_ref_header_deleted() { sed -i.bak '1d' "$(NXD)/source-files.md" && rm -f "$(NXD)/source-files.md.bak"; }
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
nx_base_after_install() { python3 - "$(NXD)/source-files.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert "PART=base" in t
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: STACK=nextjs PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
nx_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(NXD)/source-files.md"; }
nx_agents_before_format() { printf 'Run kit Step 0: STACK=nextjs PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(NXD)/source-files.md" > "$S/x" && mv "$S/x" "$(NXD)/source-files.md"; }
nx_no_agents_line() { strip_token 'PART=agents' 'PART=agent' "$(NXD)/source-files.md"; }
# vite-react stack trees (skills/scaffold/vite-react/template, template-agents, template.manifest)
VRD() { echo "$S/scaffold/vite-react"; }
no_vr_templates() { rm -rf "$(VRD)/template" "$(VRD)/template-agents" "$(VRD)/template.manifest"; }
no_vr_manifest() { rm -f "$(VRD)/template.manifest"; }
no_vr_agents_tree() { rm -rf "$(VRD)/template-agents"; }
no_vr_main_tree() { rm -rf "$(VRD)/template"; }
vr_manifest_lists_missing() { printf 'template/zz-ghost.txt 644 - -\n' >> "$(VRD)/template.manifest"; }
vr_unlisted_file() { printf 'x\n' > "$(VRD)/template/zz-unlisted.txt"; }
vr_exec_bit_lost() { chmod -x "$(VRD)/template/docker-entrypoint.sh"; }
vr_empty_dir() { mkdir -p "$(VRD)/template/zz-empty"; }
vr_narration_in_sh() { printf '\n# Added a retry loop\n' >> "$(VRD)/template/docker-entrypoint.sh"; }
vr_narration_in_yaml() { printf '\n# Removed the old setting\n' >> "$(VRD)/template/pnpm-workspace.yaml"; }
vr_broken_yaml() { printf '  bad:\n- not: [valid\n' >> "$(VRD)/template/pnpm-workspace.yaml"; }
vr_no_stack_copy() { strip_token 'PART=stack' 'PART=stac' "$(VRD)/source-files.md"; }
vr_no_base_copy() { strip_token 'PART=base' 'PART=bas' "$(VRD)/source-files.md"; }
vr_no_agents_copy() { strip_token 'PART=agents' 'PART=agent' "$(VRD)/source-files.md"; }
vr_no_manifest_ref() { strip_token '<skill-dir>/vite-react/template.manifest' '<skill-dir>/vite-react/template.manifes' "$(VRD)/source-files.md"; }
vr_wrong_stack() { strip_token 'STACK=vite-react' 'STACK=nestjs' "$(VRD)/source-files.md"; }
vr_ref_header_deleted() { sed -i.bak '1d' "$(VRD)/source-files.md" && rm -f "$(VRD)/source-files.md.bak"; }
headerless_md_beside_vr_template() { printf 'no header\n' > "$(VRD)/zz-note.md"; }
pin_in_vr_template() { printf 'left-pad@1.3.0\n' >> "$(VRD)/template/.npmrc"; }
secret_in_vr_template() { printf 'password = "hunter2hunter2"\n' >> "$(VRD)/template/.npmrc"; }
marker_drift_in_vr_template() { strip_token 'vite-react@6.0.0' 'vite-react@99.0.0' "$(VRD)/template-agents/AGENTS.md"; }
vr_base_after_install() { python3 - "$(VRD)/source-files.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert "PART=base" in t
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: STACK=vite-react PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
vr_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(VRD)/source-files.md"; }
vr_agents_before_format() { printf 'Run kit Step 0: STACK=vite-react PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(VRD)/source-files.md" > "$S/x" && mv "$S/x" "$(VRD)/source-files.md"; }
vr_no_agents_line() { strip_token 'PART=agents' 'PART=agent' "$(VRD)/source-files.md"; }
exact_pin_in_vr_package() { python3 - "$(VRD)/template/package.json" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace('"dependencies": {', '"dependencies": {\n    "left-pad": "1.3.0",', 1))
PY
}
vite_skill_md_appears() { printf -- '---\nname: zz\n---\n' > "$(VRD)/template/.claude/skills/vite-verify/SKILL.md"; }
vr_tmpl_and_plain_both_listed() { printf 'template/.claude/skills/vite-verify/SKILL.md 644 - -\n' >> "$(VRD)/template.manifest"; }
# shellcheck disable=SC2016
no_kit_stack_case() { strip_token 'stack | agents)' 'stack | agent)' "$SH/tc-copy.sh"; }
no_kit_sel_template() { strip_token 'SEL="template"' 'SEL="templat"' "$SH/tc-copy.sh"; }
exact_pin_in_nx_package() { python3 - "$(NXD)/template/package.json" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace('"dependencies": {', '"dependencies": {\n    "left-pad": "1.3.0",', 1))
PY
}
no_nx_package_json() { local d; for d in "${TEMPLATED_TREES[@]}"; do rm -f "$S/scaffold/$d/template/package.json"; done; }
no_vr_package_json() { rm -f "$(VRD)/template/package.json"; }

# nestjs stack trees (skills/scaffold/nestjs/template, template-agents, template.manifest)
NSD() { echo "$S/scaffold/nestjs"; }
no_ns_templates() { rm -rf "$(NSD)/template" "$(NSD)/template-agents" "$(NSD)/template.manifest"; }
no_ns_manifest() { rm -f "$(NSD)/template.manifest"; }
no_ns_agents_tree() { rm -rf "$(NSD)/template-agents"; }
no_ns_main_tree() { rm -rf "$(NSD)/template"; }
ns_manifest_lists_missing() { printf 'template/zz-ghost.txt 644 - -\n' >> "$(NSD)/template.manifest"; }
ns_unlisted_file() { printf 'x\n' > "$(NSD)/template/zz-unlisted.txt"; }
ns_exec_bit_lost() { chmod -x "$(NSD)/template/docker-entrypoint.sh"; }
ns_empty_dir() { mkdir -p "$(NSD)/template/zz-empty"; }
ns_narration_in_sh() { printf '\n# Added a retry loop\n' >> "$(NSD)/template/docker-entrypoint.sh"; }
ns_narration_in_yaml() { printf '\n# Removed the old setting\n' >> "$(NSD)/template/pnpm-workspace.yaml"; }
ns_broken_yaml() { printf '  bad:\n- not: [valid\n' >> "$(NSD)/template/pnpm-workspace.yaml"; }
ns_no_stack_copy() { strip_token 'PART=stack' 'PART=stac' "$(NSD)/source-files.md"; }
ns_no_base_copy() { strip_token 'PART=base' 'PART=bas' "$(NSD)/source-files.md"; }
ns_no_agents_copy() { strip_token 'PART=agents' 'PART=agent' "$(NSD)/source-files.md"; }
ns_no_manifest_ref() { strip_token '<skill-dir>/nestjs/template.manifest' '<skill-dir>/nestjs/template.manifes' "$(NSD)/source-files.md"; }
ns_wrong_stack() { strip_token 'STACK=nestjs' 'STACK=nextjs' "$(NSD)/source-files.md"; }
ns_no_stack_value() { strip_token 'STACK=nestjs' 'STACK-nestjs' "$(NSD)/source-files.md"; }
ns_ref_header_deleted() { sed -i.bak '1d' "$(NSD)/source-files.md" && rm -f "$(NSD)/source-files.md.bak"; }
ns_headerless_md_beside_template() { printf 'no header\n' > "$(NSD)/zz-note.md"; }
ns_headerless_md_named_template() { printf 'no header\n' > "$(NSD)/template-notes.md"; }
pin_in_ns_template() { printf 'left-pad@1.3.0\n' >> "$(NSD)/template/.npmrc"; }
secret_in_ns_template() { printf 'password = "hunter2hunter2"\n' >> "$(NSD)/template/.npmrc"; }
marker_drift_in_ns_template() { strip_token 'nestjs@6.0.0' 'nestjs@99.0.0' "$(NSD)/template-agents/AGENTS.md"; }
ns_base_after_install() { python3 - "$(NSD)/source-files.md" <<'PY2'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert "PART=base" in t
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: STACK=nestjs PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY2
}
ns_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(NSD)/source-files.md"; }
ns_agents_before_format() { printf 'Run kit Step 0: STACK=nestjs PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(NSD)/source-files.md" > "$S/x" && mv "$S/x" "$(NSD)/source-files.md"; }
ns_no_format_line() { strip_token 'pnpm format' 'pnpm fmt' "$(NSD)/source-files.md"; }
ns_symlinked_dir() { rm -rf "$(NSD)/template/src/config" && ln -s "$(NSD)/template/src/common" "$(NSD)/template/src/config"; }
ns_symlinked_file() { rm "$(NSD)/template/.npmrc" && ln -s "$(NSD)/template/.prettierrc" "$(NSD)/template/.npmrc"; }
ns_no_agents_line() { strip_token 'PART=agents' 'PART=agent' "$(NSD)/source-files.md"; }
no_ad_line_nestjs() { strip_token 'A through D' 'A to D' "$(NSD)/source-files.md"; }
nest_verify_bare_bash() { sed -i.bak 's/^allowed-tools: Bash(pnpm \*)/allowed-tools: Bash/' "$(NSD)/template/.claude/skills/nest-verify/SKILL.md.tmpl" && rm -f "$(NSD)/template/.claude/skills/nest-verify/SKILL.md.tmpl.bak"; }
nestjs_skill_md_appears() { printf -- '---\nname: zz\n---\n' > "$(NSD)/template/.claude/skills/nest-verify/SKILL.md"; }
exact_pin_in_ns_package() { python3 - "$(NSD)/template/package.json" <<'PY2'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace('"dependencies": {', '"dependencies": {\n    "left-pad": "1.3.0",', 1))
PY2
}
second_copy_script() { cp "$SH/tc-copy.sh" "$SH/tc-copy-2.sh"; }
tc_rm_script_returns() { printf "\n\`\`\`bash\nbash <<'TC_RM'\nexit 0\nTC_RM\n\`\`\`\n" >> "$SH/harness-kit-enforcement.md"; }
no_copy_script() { rm -f "$SH/tc-copy.sh"; }
script_not_executable() { chmod a-x "$SH/tc-copy.sh"; }
b3_forgets_part_ci() { strip_token 'PART=ci' 'PART=cx' "$SH/harness-kit-enforcement.md"; }
b3_forgets_ci_none() { strip_token 'CI=none' 'CI=nope' "$SH/harness-kit-enforcement.md"; }
b3_forgets_kit() { strip_token 'harness-kit.md' 'harness-kit-x.md' "$SH/harness-kit-enforcement.md"; }
no_kit_settings_case() { strip_token 'settings | late | tail)' 'settings | late | tai)' "$SH/tc-copy.sh"; }
no_kit_none_case() { strip_token 'none) SEL= ;;' 'nope) SEL= ;;' "$SH/tc-copy.sh"; }
# shellcheck disable=SC2016  # the anchors are literal script text
no_kit_rm_line() { strip_token 'rm -f -- "$TGT/$gate"' 'true' "$SH/tc-copy.sh"; }
no_kit_late_sel() { strip_token 'SEL="template-late"' 'SEL="template-lat"' "$SH/tc-copy.sh"; }
# shellcheck disable=SC2016
no_kit_settings_sel() { strip_token 'SEL="template-settings-$V"' 'SEL="template-settin-$V"' "$SH/tc-copy.sh"; }
no_settings_tree() { rm -rf "$SH/template-settings-ts" "$SH/template-settings-py"; }
no_late_tree() { rm -rf "$SH/template-late"; }
no_tail_tree() { rm -rf "$SH/template-tail"; }
no_settings_ts_file() { rm -f "$SH/template-settings-ts/.claude/settings.json"; }
no_late_constitution() { rm -f "$SH/template-late/docs/CONSTITUTION.md"; }
no_tail_file() { rm -f "$SH/template-tail/AGENTS-tail.md"; }
deep_skill_file() { mkdir -p "$S/add/auth/a/b" && printf '<!-- ref: x -->\n' > "$S/add/auth/a/b/c.md"; }
second_fence_renamed() { printf "\n\`\`\`bash\nbash <<'TC_COPY'\nexit 0\nTC_COPY\n\`\`\`\n" >> "$SH/harness-kit-enforcement.md"; }
b3_tokens_only_elsewhere() { python3 - "$SH/harness-kit-enforcement.md" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
a = t.index("## Step B3"); b = t.index("\n## ", a + 5)
sec = t[a:b].replace("PART=ci", "PART=cx").replace("CI=none", "CI=nope").replace("harness-kit.md", "harness-kit-x.md")
t = t[:a] + sec + t[b:] + "\nPART=ci CI=none harness-kit.md\n"
open(p, "w", encoding="utf-8").write(t)
PY
}
# shellcheck disable=SC2016  # the text is literal script content
sel_names_tail() { printf '\nif [ "$PART" = zz ]; then SEL="template-tail"; fi\n' >> "$SH/tc-copy.sh"; }
no_sel_lines() { strip_token 'SEL=' 'SEX=' "$SH/tc-copy.sh"; }
ad_before_agents_nextjs() { printf 'Execute kit Steps **A through D** now.\n' | cat - "$S/scaffold/nextjs/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/nextjs/source-files.md"; }
ad_before_agents_nestjs() { printf 'Execute kit Steps **A through D** now.\n' | cat - "$S/scaffold/nestjs/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/nestjs/source-files.md"; }
ad_before_agents_vite() { printf 'Execute kit Steps **A through D** now.\n' | cat - "$S/scaffold/vite-react/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/vite-react/source-files.md"; }
ad_before_agents_fastapi() { printf 'Execute kit Steps **A through D** now.\n' | cat - "$S/scaffold/fastapi/source-files.md" > "$S/x" && mv "$S/x" "$S/scaffold/fastapi/source-files.md"; }
no_ad_line_nextjs() { strip_token 'A through D' 'A to D' "$S/scaffold/nextjs/source-files.md"; }
migrate_forgets_tail_path() { strip_token 'scaffold/shared/tc-copy.sh' 'zz-gone/tc-copy.sh' "$S/migrate/general/phase-4-upgrade.md"; }
migrate_forgets_settings_tree() { strip_token 'scaffold/shared/template-settings-ts/' 'zz-gone/' "$S/migrate/general/phase-4-upgrade.md"; }
migrate_forgets_late_tree() { strip_token 'scaffold/shared/template-late/' 'zz-gone/' "$S/migrate/general/phase-4-upgrade.md"; }
migrate_4f3_forgets_tail_path() { python3 - "$S/migrate/general/phase-4-upgrade.md" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
a = t.index("\n**Step 4f-3:")
b = t.index("\n**Step ", a + 5)
seg = t[a:b].replace("<skill-dir>/../scaffold/shared/tc-copy.sh", "<skill-dir>/zz-gone/tc-copy.sh")
open(p, "w", encoding="utf-8").write(t[:a] + seg + t[b:])
PY
}
template_skill_md_appears() { mkdir -p "$SH/template-late/.claude/skills/zz"; printf -- '---\nname: zz\n---\n' > "$SH/template-late/.claude/skills/zz/SKILL.md"; }
nextjs_skill_md_appears() { printf -- '---\nname: zz\n---\n' > "$(NXD)/template/.claude/skills/next-verify/SKILL.md"; }
no_tmpl_skills() { find "$S/scaffold" -name 'SKILL.md.tmpl' -delete; }
fence_indented() { printf "\n  bash <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_dash_s() { printf "\nbash -s <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_dash_heredoc() { printf "\nbash <<-'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_double_quoted() { printf '\nbash <<"TC_X"\nexit 0\nTC_X\n' >> "$SH/harness-kit-enforcement.md"; }
fence_unquoted() { printf '\nbash <<TC_X\nexit 0\nTC_X\n' >> "$SH/harness-kit-enforcement.md"; }
fence_sh() { printf "\nsh <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
guard_fence_returns() { printf "\n\`\`\`bash\nbash <<'TC_GUARD'\nexit 0\nTC_GUARD\n\`\`\`\n" >> "$SH/harness-kit.md"; }
tail_fence_returns() { printf "\n\`\`\`bash\nbash <<'TC_TAIL'\nexit 0\nTC_TAIL\n\`\`\`\n" >> "$SH/harness-kit-finalize.md"; }
kit_forgets_tail_part() { strip_token 'PART=tail' 'PART=tai' "$SH/harness-kit.md"; }
kit_forgets_call_line() { strip_token 'bash "<skill-dir>/shared/tc-copy.sh" "<target>"' 'bash "<skill-dir>/shared/tc-cop.sh" "<target>"' "$SH/harness-kit.md"; }
stack_step0_drops_script() { strip_token 'tc-copy.sh' 'tc-cop.sh' "$S/scaffold/$1/source-files.md"; }
nx_step0_drops_script() { stack_step0_drops_script nextjs; }
vr_step0_drops_script() { stack_step0_drops_script vite-react; }
ns_step0_drops_script() { stack_step0_drops_script nestjs; }
fa_step0_drops_script() { stack_step0_drops_script fastapi; }
# shellcheck disable=SC2016  # the token is literal text with backticks
migrate_forgets_tmpl_rule() { strip_token 'is copied to `<name>`' 'is copied elsewhere' "$S/migrate/general/phase-4-upgrade.md"; }
tmpl_and_plain_both_listed() { printf 'template/.claude/skills/next-verify/SKILL.md 644 - -\n' >> "$(NXD)/template.manifest"; }
tmpl_and_plain_both_in_tree() { printf 'x\n' > "$(NXD)/template/.claude/skills/next-verify/SKILL.md"; }
fence_abs_bash() { printf "\n/bin/bash <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_env_bash() { printf "\n/usr/bin/env bash <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_zsh() { printf "\nzsh <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_bash_option() { printf "\nbash --norc <<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_no_space() { printf "\nbash<<'TC_X'\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_backslash_delim() { printf '\nbash <<\\TC_X\nexit 0\nTC_X\n' >> "$SH/harness-kit-enforcement.md"; }
fence_cat_pipe_tc() { printf "\ncat <<'TC_X' | bash\nexit 0\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
fence_cat_pipe_eof() { printf "\ncat <<'EOF' | bash\nexit 0\nEOF\n" >> "$SH/harness-kit-enforcement.md"; }
fence_plain_eof() { printf "\nbash <<'EOF'\nexit 0\nEOF\n" >> "$SH/harness-kit-enforcement.md"; }
fence_other_delim_not_shell() { printf "\ncat <<'TC_X'\nhello\nTC_X\n" >> "$SH/harness-kit-enforcement.md"; }
none() { :; }

# ── baseline ─────────────────────────────────────────────────────────────────
if [[ -z "${ONLY:-}" ]]; then
  damage_and_lint "$T/base" none
  [[ "$OUT" == *"=== All checks passed ==="* ]]; check 0 $? "baseline_passes: lint passes on the unmodified tree (${OUT##*$'\n'})"
  SLASH=1; damage_and_lint "$T/base-slash" none; SLASH=
  [[ "$OUT" == *"=== All checks passed ==="* ]]; check 0 $? "baseline_passes_with_a_trailing_slash: the command CI runs passes (${OUT##*$'\n'})"
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
assert "STACK=nextjs PART=stack" in t
open(p, "w", encoding="utf-8").write(t.replace("STACK=nextjs PART=stack", "PART=stack", 1) + "\nSTACK=nextjs\n")
PY
}
fails step0_stack_must_be_on_the_step0_line "Scaffold runs kit Step 0 before the first install" step0_stack_on_other_line "must name STACK=nextjs on the Step 0 line"

# fastapi stack trees (skills/scaffold/fastapi/template, template-agents, template-tail, template.manifest)
FAD() { echo "$S/scaffold/fastapi"; }
no_fa_templates() { rm -rf "$(FAD)/template" "$(FAD)/template-agents" "$(FAD)/template.manifest"; }
no_fa_manifest() { rm -f "$(FAD)/template.manifest"; }
no_fa_agents_tree() { rm -rf "$(FAD)/template-agents"; }
no_fa_main_tree() { rm -rf "$(FAD)/template"; }
fa_manifest_lists_missing() { printf 'template/zz-ghost.txt 644 - -\n' >> "$(FAD)/template.manifest"; }
fa_unlisted_file() { printf 'x\n' > "$(FAD)/template/zz-unlisted.txt"; }
fa_exec_bit_lost() { chmod -x "$(FAD)/template/docker-entrypoint.sh"; }
fa_empty_dir() { mkdir -p "$(FAD)/template/zz-empty"; }
fa_narration_in_sh() { printf '\n# Added a retry loop\n' >> "$(FAD)/template/docker-entrypoint.sh"; }
fa_narration_in_py() { printf '\n# Removed the old handler\n' >> "$(FAD)/template/src/main.py"; }
fa_narration_in_toml() { printf '\n# Removed the old rule\n' >> "$(FAD)/template/pyproject.toml"; }
fa_no_stack_copy() { strip_token 'PART=stack' 'PART=stac' "$(FAD)/source-files.md"; }
fa_no_base_copy() { strip_token 'PART=base' 'PART=bas' "$(FAD)/source-files.md"; }
fa_no_agents_copy() { strip_token 'PART=agents' 'PART=agent' "$(FAD)/source-files.md"; }
fa_no_manifest_ref() { strip_token '<skill-dir>/fastapi/template.manifest' '<skill-dir>/fastapi/template.manifes' "$(FAD)/source-files.md"; }
fa_no_agents_ref() { strip_token '<skill-dir>/fastapi/template-agents/' '<skill-dir>/fastapi/template-agent/' "$(FAD)/source-files.md"; }
headerless_md_named_fa_template() { printf 'no header\n' > "$(FAD)/template-notes.md"; }
fa_ref_header_deleted() { sed -i.bak '1d' "$(FAD)/source-files.md" && rm -f "$(FAD)/source-files.md.bak"; }
headerless_md_beside_fa_template() { printf 'no header\n' > "$(FAD)/zz-note.md"; }
pin_in_fa_template() { printf 'left-pad@1.3.0\n' >> "$(FAD)/template/.gitignore"; }
secret_in_fa_template() { printf 'password = "hunter2hunter2"\n' >> "$(FAD)/template/.gitignore"; }
marker_drift_in_fa_template() { strip_token 'fastapi@6.0.0' 'fastapi@99.0.0' "$(FAD)/template-agents/AGENTS.md"; }
fa_skill_md_appears() { printf -- '---\nname: zz\n---\n' > "$(FAD)/template/.claude/skills/api-verify/SKILL.md"; }
fa_bare_bash_in_verify() { strip_token 'allowed-tools: Bash(python *), Bash(ruff *)' 'allowed-tools: Bash' "$(FAD)/template/.claude/skills/api-verify/SKILL.md.tmpl"; }
fa_base_after_6b() { python3 - "$(FAD)/source-files.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
assert "PART=base" in t
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: STACK=fastapi PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
fa_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(FAD)/source-files.md"; }
fa_agents_before_gate() { printf 'Run kit Step 0: STACK=fastapi PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(FAD)/source-files.md" > "$S/x" && mv "$S/x" "$(FAD)/source-files.md"; }
fa_no_agents_line() { strip_token 'PART=agents' 'PART=agent' "$(FAD)/source-files.md"; }
nx_no_format_line() { strip_token 'pnpm format ' 'pnpm fmt ' "$(NXD)/source-files.md"; }
vr_no_format_line() { strip_token 'pnpm format' 'pnpm fmt' "$(VRD)/source-files.md"; }
fa_symlinked_dir() { rm -rf "$(FAD)/template/src/api" && ln -s "$(FAD)/template/src/core" "$(FAD)/template/src/api"; }
fa_symlinked_file() { rm "$(FAD)/template/.gitignore" && ln -s "$(FAD)/template/.dockerignore" "$(FAD)/template/.gitignore"; }
nx_symlinked_file() { rm "$(NXD)/template/.npmrc" && ln -s "$(NXD)/template/.prettierrc" "$(NXD)/template/.npmrc"; }
vr_symlinked_dir() { rm -rf "$(VRD)/template/src/lib" && ln -s "$(VRD)/template/src/components" "$(VRD)/template/src/lib"; }
fa_no_gate_heading() { strip_token '### 5. Verification gate' '### 5. Check' "$(FAD)/source-files.md"; }

# the PART=ci runs of the copy script are scaffold-only; the migrate docs and Step B3 say so
for entry in "migrate/general/phase-4-upgrade.md|runs of the copy script are scaffold-only" "migrate/general/phase-5-health-check.md|runs of the copy script are scaffold-only" "scaffold/shared/harness-kit-enforcement.md|runs of the copy script are scaffold-only"; do
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
i = next(n for n, l in enumerate(lines) if "PART=base" in l and "tc-copy.sh" in l)
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
fails vite_react_scaffold_seeds_fails_on_empty_match "Scaffold/migrate templates seed the complete harness" no_templates "template file not found"
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
fails ref_headers_fail_when_anchor_deleted "Ref file <!-- ref: --> headers" nx_ref_header_deleted "nextjs/source-files.md"
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

# ── check_step0_before_install: the PART=base, PART=agents and install order for a templated stack ──
fails nextjs_step0_fails_when_base_copy_moves_after_install "Scaffold runs kit Step 0 before the first install" nx_base_after_install "comes after the first install"
fails nextjs_step0_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" nx_no_base_line "no kit Step 0 instruction with STACK=nextjs and PART=base"
fails nextjs_step0_fails_when_agents_copy_moves_before_format "Scaffold runs kit Step 0 before the first install" nx_agents_before_format "comes before the pnpm format line"
fails nextjs_step0_fails_when_agents_copy_deleted "Scaffold runs kit Step 0 before the first install" nx_no_agents_line "no PART=agents instruction"

# ── vite-react stack trees ───────────────────────────────────────────────────
fails vite_react_template_trees_fail_on_empty_match "Template trees are complete" no_vr_templates "vite-react/template: tree is missing or empty"
fails vite_react_template_trees_fail_when_main_tree_deleted "Template trees are complete" no_vr_main_tree "vite-react/template: tree is missing or empty"
fails vite_react_template_trees_fail_when_agents_tree_deleted "Template trees are complete" no_vr_agents_tree "vite-react/template-agents: tree is missing or empty"
fails vite_react_template_trees_fail_when_manifest_deleted "Template trees are complete" no_vr_manifest "vite-react/template.manifest: file not found"
fails vite_react_template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" vr_manifest_lists_missing "which is not in the tree"
fails vite_react_template_trees_fail_when_file_unlisted "Template trees are complete" vr_unlisted_file "is in the tree but not listed"
fails vite_react_template_trees_fail_when_script_loses_exec_bit "Template trees are complete" vr_exec_bit_lost "is mode 644 but listed as 755"
fails vite_react_template_trees_fail_on_empty_directory "Template trees are complete" vr_empty_dir "empty directory in a template tree"
fails vite_react_comment_narration_scans_template_sh "Change-narration comments" vr_narration_in_sh "Added a retry loop"
fails vite_react_comment_narration_scans_template_yaml "Change-narration comments" vr_narration_in_yaml "Removed the old setting"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  fails vite_react_yaml_parse_fails_when_template_yaml_broken "template yaml files parse" vr_broken_yaml "pnpm-workspace.yaml:"
fi
fails vite_react_skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" vr_no_stack_copy "scaffold/vite-react/source-files.md: copy instruction PART=stack missing"
fails vite_react_skilldir_refs_fails_when_base_copy_deleted "<skill-dir> references resolve" vr_no_base_copy "scaffold/vite-react/source-files.md: copy instruction PART=base missing"
fails vite_react_skilldir_refs_fails_when_agents_copy_deleted "<skill-dir> references resolve" vr_no_agents_copy "scaffold/vite-react/source-files.md: copy instruction PART=agents missing"
fails vite_react_skilldir_refs_fails_when_manifest_ref_deleted "<skill-dir> references resolve" vr_no_manifest_ref "scaffold/vite-react/source-files.md: copy instruction <skill-dir>/vite-react/template.manifest missing"
fails vite_react_stack_value_fails_when_wrong "Scaffold runs kit Step 0 before the first install" vr_wrong_stack "must name STACK=vite-react"
fails vite_react_ref_headers_fail_when_anchor_deleted "Ref file <!-- ref: --> headers" vr_ref_header_deleted "vite-react/source-files.md"
fails vite_react_ref_headers_still_check_a_file_beside_the_trees "Ref file <!-- ref: --> headers" headerless_md_beside_vr_template "vite-react/zz-note.md"
fails scan_version_pins_includes_vite_react_template "Version pins in skills" pin_in_vr_template "left-pad@1.3.0"
fails scan_hardcoded_secrets_includes_vite_react_template "Hardcoded secrets" secret_in_vr_template "hunter2hunter2"
fails scan_agents_marker_includes_vite_react_template "AGENTS.md schema marker not drifted" marker_drift_in_vr_template "template-agents/AGENTS.md"
fails vite_react_step0_fails_when_base_copy_moves_after_install "Scaffold runs kit Step 0 before the first install" vr_base_after_install "comes after the first install"
fails vite_react_step0_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" vr_no_base_line "no kit Step 0 instruction with STACK=vite-react and PART=base"
fails vite_react_step0_fails_when_agents_copy_moves_before_format "Scaffold runs kit Step 0 before the first install" vr_agents_before_format "comes before the pnpm format line"
fails vite_react_step0_fails_when_agents_copy_deleted "Scaffold runs kit Step 0 before the first install" vr_no_agents_line "no PART=agents instruction"
fails vite_react_template_pins_fail_on_exact_dependency "Template package.json dependencies use floors" exact_pin_in_vr_package "left-pad"
fails vite_react_template_trees_fail_when_package_json_deleted "Template trees are complete" no_vr_package_json "template/package.json"
fails vite_react_skill_md_fails_when_the_template_holds_one "Template trees hold no file named SKILL.md" vite_skill_md_appears "template/.claude/skills/vite-verify/SKILL.md"
fails vite_react_template_trees_fail_when_a_tmpl_and_its_target_are_both_listed "Template trees are complete" vr_tmpl_and_plain_both_listed "both copy to"

# ── the kit fences keep the stack and agents branches ────────────────────────
fails skilldir_refs_fails_when_kit_stack_case_deleted "<skill-dir> references resolve" no_kit_stack_case "scaffold/shared/tc-copy.sh: copy instruction stack | agents) missing"
fails skilldir_refs_fails_when_kit_sel_template_deleted "<skill-dir> references resolve" no_kit_sel_template "scaffold/shared/tc-copy.sh: copy instruction SEL=\"template\" missing"

# ── template package.json pins ───────────────────────────────────────────────
fails template_pins_fail_on_empty_match "Template package.json dependencies use floors" no_nx_package_json "no template package.json found"
fails template_pins_fail_on_exact_dependency "Template package.json dependencies use floors" exact_pin_in_nx_package "left-pad"

# ── one copy script ──────────────────────────────────────────────────────────
fails_both copy_script_fails_on_empty_match "The copy script has exactly one copy" no_copy_script "must hold exactly one copy script"
fails_both copy_script_fails_when_a_second_copy_appears "The copy script has exactly one copy" second_copy_script "must hold exactly one copy script"
fails_both copy_script_fails_when_it_is_not_executable "The copy script has exactly one copy" script_not_executable "not executable"
fails_both copy_script_fails_when_tc_rm_returns "The copy script has exactly one copy" tc_rm_script_returns "a shell heredoc in"
fails_both copy_script_fails_when_b3_forgets_part_ci "The copy script has exactly one copy" b3_forgets_part_ci "Step B3 must name PART=ci"
fails_both copy_script_fails_when_b3_forgets_ci_none "The copy script has exactly one copy" b3_forgets_ci_none "Step B3 must name CI=none"
fails_both copy_script_fails_when_b3_forgets_the_kit "The copy script has exactly one copy" b3_forgets_kit "Step B3 must name harness-kit.md"
fails skilldir_refs_fails_when_settings_late_case_deleted "<skill-dir> references resolve" no_kit_settings_case "scaffold/shared/tc-copy.sh: copy instruction settings | late | tail) missing"
fails skilldir_refs_fails_when_none_case_deleted "<skill-dir> references resolve" no_kit_none_case "scaffold/shared/tc-copy.sh: copy instruction none) SEL= ;; missing"
fails skilldir_refs_fails_when_rm_line_deleted "<skill-dir> references resolve" no_kit_rm_line "scaffold/shared/tc-copy.sh: copy instruction rm -f -- \"\$TGT/\$gate\" missing"
fails skilldir_refs_fails_when_late_sel_deleted "<skill-dir> references resolve" no_kit_late_sel "scaffold/shared/tc-copy.sh: copy instruction SEL=\"template-late\" missing"
fails skilldir_refs_fails_when_settings_sel_deleted "<skill-dir> references resolve" no_kit_settings_sel "scaffold/shared/tc-copy.sh: copy instruction SEL=\"template-settings-\$V\" missing"
fails scaffold_seeds_fails_when_kit_settings_sel_deleted "Scaffold/migrate templates seed the complete harness" no_kit_settings_sel "tc-copy.sh — Step 0 copy instruction missing: SEL=\"template-settings-\$V\""

# ── settings and late trees ──────────────────────────────────────────
fails settings_trees_fail_on_empty_match "Template trees are complete" no_settings_tree "template-settings-ts: tree is missing or empty"
fails late_tree_fails_on_empty_match "Template trees are complete" no_late_tree "template-late: tree is missing or empty"
fails tail_tree_fails_on_empty_match "Template trees are complete" no_tail_tree "template-tail: tree is missing or empty"
fails late_tree_fails_when_file_deleted "Template trees are complete" no_late_constitution "template-late/docs/CONSTITUTION.md, which is not in the tree"
fails tail_tree_fails_when_file_deleted "Template trees are complete" no_tail_file "template-tail/AGENTS-tail.md, which is not in the tree"
fails scaffold_seeds_fails_when_settings_file_deleted "Scaffold/migrate templates seed the complete harness" no_settings_ts_file "template-settings-ts/.claude/settings.json — template file not found"
fails scaffold_seeds_fails_when_late_file_deleted "Scaffold/migrate templates seed the complete harness" no_late_constitution "template-late/docs/CONSTITUTION.md — template file not found"
fails scaffold_seeds_fails_when_tail_file_deleted "Scaffold/migrate templates seed the complete harness" no_tail_file "template-tail/AGENTS-tail.md — template file not found"

# ── nesting depth: the same answer with and without a trailing slash, templates skipped ──
fails nesting_depth_fails_on_a_deep_file "Nesting depth" deep_skill_file "c.md"
depth_slash_forms_agree() {
  [[ -n "${ONLY:-}" && ! "depth_slash_forms_agree" =~ $ONLY ]] && return 0
  local w="$T/wdepth" f a b
  rm -rf "$w"; mkdir -p "$w"; cp -R skills "$w/skills"
  for f in .claude .claude-plugin CHANGELOG.md; do ln -s "$REPO_ROOT/$f" "$w/$f"; done
  mkdir -p "$w/skills/add/auth/a/b"; printf '<!-- ref: x -->\n' > "$w/skills/add/auth/a/b/c.md"
  a=$(section "$(bash "$LINT" "$w/skills" 2>&1 || true)" "Nesting depth")
  b=$(section "$(bash "$LINT" "$w/skills/" 2>&1 || true)" "Nesting depth")
  check "$a" "$b" "nesting_depth_slash_and_no_slash_agree"
  check 1 "$([[ "$a" == *"FAIL"* && "$a" == *"c.md"* ]] && echo 1 || echo 0)" "nesting_depth_slash_form_catches_the_deep_file ($b)"
  rm -f "$w/skills/add/auth/a/b/c.md"
  a=$(section "$(bash "$LINT" "$w/skills" 2>&1 || true)" "Nesting depth")
  b=$(section "$(bash "$LINT" "$w/skills/" 2>&1 || true)" "Nesting depth")
  check 1 "$([[ "$a" == *"OK:"* && "$b" == *"OK:"* ]] && echo 1 || echo 0)" "nesting_depth_passes_with_the_template_trees_in_both_forms"
  rm -rf "$w"
}
depth_slash_forms_agree

# ── the copy script: renamed copies, B3 scope, selectors, and ordering ────────
fails_both copy_script_fails_when_a_renamed_second_fence_appears "The copy script has exactly one copy" second_fence_renamed "a shell heredoc in"
fails_both copy_script_fails_when_b3_tokens_sit_outside_b3 "The copy script has exactly one copy" b3_tokens_only_elsewhere "Step B3 must name PART=ci"
fails_both copy_selector_fails_when_it_names_the_tail_tree "No copy selector names template-tail" sel_names_tail "a copy selector names template-tail"
fails_both copy_selector_fails_on_empty_match "No copy selector names template-tail" no_sel_lines "no SEL assignment found"
fails steps_a_to_d_fails_before_the_agents_step_nextjs "Scaffold runs kit Step 0 before the first install" ad_before_agents_nextjs "comes before the AGENTS.md step"
fails steps_a_to_d_fails_before_the_agents_step_nestjs "Scaffold runs kit Step 0 before the first install" ad_before_agents_nestjs "comes before the AGENTS.md step"
fails steps_a_to_d_fails_before_the_agents_step_vite "Scaffold runs kit Step 0 before the first install" ad_before_agents_vite "comes before the AGENTS.md step"
fails steps_a_to_d_fails_before_the_agents_step_fastapi "Scaffold runs kit Step 0 before the first install" ad_before_agents_fastapi "comes before the AGENTS.md step"
fails steps_a_to_d_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" no_ad_line_nextjs "needs a \"Steps A through D\" instruction"
fails migrate_inventory_fails_when_the_tail_path_is_missing "migrate hook inventory matches" migrate_forgets_tail_path "Step 4f-3 must name <skill-dir>/../scaffold/shared/tc-copy.sh"
fails migrate_inventory_fails_when_only_step_4f3_forgets_the_tail_path "migrate hook inventory matches" migrate_4f3_forgets_tail_path "Step 4f-3 must name <skill-dir>/../scaffold/shared/tc-copy.sh"
# ── template skills ship as SKILL.md.tmpl ──
fails template_skill_md_fails_on_empty_match "Template trees hold no file named SKILL.md" no_tmpl_skills "the check below would scan nothing"
fails template_skill_md_fails_when_a_shared_template_holds_one "Template trees hold no file named SKILL.md" template_skill_md_appears "template-late/.claude/skills/zz/SKILL.md"
fails template_skill_md_fails_when_a_stack_template_holds_one "Template trees hold no file named SKILL.md" nextjs_skill_md_appears "template/.claude/skills/next-verify/SKILL.md"
# ── other spellings of a second script fence ──
fails_both copy_script_fails_on_an_absolute_shell_path "The copy script has exactly one copy" fence_abs_bash "a shell heredoc in"
fails_both copy_script_fails_on_env_bash "The copy script has exactly one copy" fence_env_bash "a shell heredoc in"
fails_both copy_script_fails_on_zsh "The copy script has exactly one copy" fence_zsh "a shell heredoc in"
fails_both copy_script_fails_on_a_shell_option "The copy script has exactly one copy" fence_bash_option "a shell heredoc in"
fails_both copy_script_fails_on_no_space_before_heredoc "The copy script has exactly one copy" fence_no_space "a shell heredoc in"
fails_both copy_script_fails_on_a_backslash_delimiter "The copy script has exactly one copy" fence_backslash_delim "a shell heredoc in"
fails_both copy_script_fails_on_a_tc_heredoc_piped_to_bash "The copy script has exactly one copy" fence_cat_pipe_tc "a shell heredoc in"
fails_both copy_script_fails_on_any_heredoc_piped_to_bash "The copy script has exactly one copy" fence_cat_pipe_eof "a shell heredoc in"
fails_both copy_script_fails_on_a_non_tc_delimiter "The copy script has exactly one copy" fence_plain_eof "a shell heredoc in"
fails_both copy_script_fails_on_a_tc_delimiter_that_feeds_no_shell "The copy script has exactly one copy" fence_other_delim_not_shell "a shell heredoc in"
fails migrate_inventory_fails_when_the_tmpl_rule_is_dropped "migrate hook inventory matches" migrate_forgets_tmpl_rule "a source named <name>.tmpl is copied to <name>"
fails template_trees_fail_when_a_tmpl_and_its_target_are_both_listed "Template trees are complete" tmpl_and_plain_both_listed "both copy to"
fails template_trees_fail_when_a_tmpl_and_its_target_are_both_in_the_tree "Template trees are complete" tmpl_and_plain_both_in_tree "both copy to"
fails_both copy_script_fails_on_an_indented_fence "The copy script has exactly one copy" fence_indented "a shell heredoc in"
fails_both copy_script_fails_on_bash_dash_s "The copy script has exactly one copy" fence_dash_s "a shell heredoc in"
fails_both copy_script_fails_on_a_dash_heredoc "The copy script has exactly one copy" fence_dash_heredoc "a shell heredoc in"
fails_both copy_script_fails_on_a_double_quoted_delimiter "The copy script has exactly one copy" fence_double_quoted "a shell heredoc in"
fails_both copy_script_fails_on_an_unquoted_delimiter "The copy script has exactly one copy" fence_unquoted "a shell heredoc in"
fails_both copy_script_fails_on_a_sh_fence "The copy script has exactly one copy" fence_sh "a shell heredoc in"
fails_both copy_script_fails_when_the_guard_heredoc_returns "The copy script has exactly one copy" guard_fence_returns "a shell heredoc in"
fails_both copy_script_fails_when_the_tail_heredoc_returns "The copy script has exactly one copy" tail_fence_returns "a shell heredoc in"
fails scaffold_seeds_fails_when_the_script_is_gone "Scaffold/migrate templates seed the complete harness" no_copy_script "copy script not found"
fails scaffold_seeds_fails_when_kit_forgets_the_tail_part "Scaffold/migrate templates seed the complete harness" kit_forgets_tail_part "harness-kit.md — Step 0 copy instruction missing: PART=tail"
fails scaffold_seeds_fails_when_kit_forgets_the_call_line "Scaffold/migrate templates seed the complete harness" kit_forgets_call_line "Step 0 copy instruction missing: bash"
fails step0_line_fails_when_nextjs_drops_the_script "Scaffold runs kit Step 0 before the first install" nx_step0_drops_script "the Step 0 line must run tc-copy.sh"
fails step0_line_fails_when_vite_react_drops_the_script "Scaffold runs kit Step 0 before the first install" vr_step0_drops_script "the Step 0 line must run tc-copy.sh"
fails step0_line_fails_when_nestjs_drops_the_script "Scaffold runs kit Step 0 before the first install" ns_step0_drops_script "the Step 0 line must run tc-copy.sh"
fails step0_line_fails_when_fastapi_drops_the_script "Scaffold runs kit Step 0 before the first install" fa_step0_drops_script "the Step 0 line must run tc-copy.sh"
fails step0_line_fails_when_nextjs_drops_the_script_base_anchor "Scaffold runs kit Step 0 before the first install" nx_step0_drops_script "no kit Step 0 instruction with STACK=nextjs and PART=base"
fails migrate_inventory_fails_when_the_settings_tree_is_missing "migrate hook inventory matches" migrate_forgets_settings_tree "missing template anchor scaffold/shared/template-settings-ts/"
fails migrate_inventory_fails_when_the_late_tree_is_missing "migrate hook inventory matches" migrate_forgets_late_tree "missing template anchor scaffold/shared/template-late/"

# ── nestjs stack trees ───────────────────────────────────────────────────────
fails nestjs_template_trees_fail_on_empty_match "Template trees are complete" no_ns_templates "nestjs/template: tree is missing or empty"
fails nestjs_template_trees_fail_when_main_tree_deleted "Template trees are complete" no_ns_main_tree "nestjs/template: tree is missing or empty"
fails nestjs_template_trees_fail_when_agents_tree_deleted "Template trees are complete" no_ns_agents_tree "nestjs/template-agents: tree is missing or empty"
fails nestjs_template_trees_fail_when_manifest_deleted "Template trees are complete" no_ns_manifest "nestjs/template.manifest: file not found"
fails nestjs_template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" ns_manifest_lists_missing "which is not in the tree"
fails nestjs_template_trees_fail_when_file_unlisted "Template trees are complete" ns_unlisted_file "is in the tree but not listed"
fails nestjs_template_trees_fail_when_script_loses_exec_bit "Template trees are complete" ns_exec_bit_lost "is mode 644 but listed as 755"
fails nestjs_template_trees_fail_on_empty_directory "Template trees are complete" ns_empty_dir "empty directory in a template tree"
fails nestjs_comment_narration_scans_template_sh "Change-narration comments" ns_narration_in_sh "Added a retry loop"
fails nestjs_comment_narration_scans_template_yaml "Change-narration comments" ns_narration_in_yaml "Removed the old setting"
if python3 -c 'import yaml' >/dev/null 2>&1; then
  fails nestjs_yaml_parse_fails_when_template_yaml_broken "template yaml files parse" ns_broken_yaml "pnpm-workspace.yaml:"
fi
fails nestjs_skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" ns_no_stack_copy "scaffold/nestjs/source-files.md: copy instruction PART=stack missing"
fails nestjs_skilldir_refs_fails_when_base_copy_deleted "<skill-dir> references resolve" ns_no_base_copy "scaffold/nestjs/source-files.md: copy instruction PART=base missing"
fails nestjs_skilldir_refs_fails_when_agents_copy_deleted "<skill-dir> references resolve" ns_no_agents_copy "scaffold/nestjs/source-files.md: copy instruction PART=agents missing"
fails nestjs_skilldir_refs_fails_when_manifest_ref_deleted "<skill-dir> references resolve" ns_no_manifest_ref "scaffold/nestjs/source-files.md: copy instruction <skill-dir>/nestjs/template.manifest missing"
fails nestjs_stack_value_fails_when_wrong "Scaffold runs kit Step 0 before the first install" ns_wrong_stack "must name STACK=nestjs"
fails nestjs_stack_value_fails_when_missing "Scaffold runs kit Step 0 before the first install" ns_no_stack_value "must name STACK=nestjs"
fails nestjs_ref_headers_fail_when_anchor_deleted "Ref file <!-- ref: --> headers" ns_ref_header_deleted "nestjs/source-files.md"
fails nestjs_ref_headers_still_check_a_file_beside_the_trees "Ref file <!-- ref: --> headers" ns_headerless_md_beside_template "nestjs/zz-note.md"
fails nestjs_ref_headers_still_check_a_file_named_template "Ref file <!-- ref: --> headers" ns_headerless_md_named_template "nestjs/template-notes.md"
fails scan_version_pins_includes_nestjs_template "Version pins in skills" pin_in_ns_template "left-pad@1.3.0"
fails scan_hardcoded_secrets_includes_nestjs_template "Hardcoded secrets" secret_in_ns_template "hunter2hunter2"
fails scan_agents_marker_includes_nestjs_template "AGENTS.md schema marker not drifted" marker_drift_in_ns_template "template-agents/AGENTS.md"
fails nestjs_step0_fails_when_base_copy_moves_after_install "Scaffold runs kit Step 0 before the first install" ns_base_after_install "comes after the first install"
fails nestjs_step0_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" ns_no_base_line "no kit Step 0 instruction with STACK=nestjs and PART=base"
fails nestjs_step0_fails_when_agents_copy_moves_before_format "Scaffold runs kit Step 0 before the first install" ns_agents_before_format "comes before the pnpm format line"
fails nestjs_step0_fails_when_agents_copy_deleted "Scaffold runs kit Step 0 before the first install" ns_no_agents_line "no PART=agents instruction"
fails nestjs_steps_a_to_d_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" no_ad_line_nestjs "needs a \"Steps A through D\" instruction"
fails nestjs_template_trees_fail_on_a_symlinked_directory "Template trees are complete" ns_symlinked_dir "src/config: symlink in a template tree"
fails nestjs_template_trees_fail_on_a_symlinked_file "Template trees are complete" ns_symlinked_file ".npmrc: symlink in a template tree"
fails nestjs_step0_fails_when_format_line_deleted "Scaffold runs kit Step 0 before the first install" ns_no_format_line "no pnpm format line for the PART=agents copy to follow"
fails nestjs_template_skill_md_fails_when_a_stack_template_holds_one "Template trees hold no file named SKILL.md" nestjs_skill_md_appears "nestjs/template/.claude/skills/nest-verify/SKILL.md"
fails nestjs_seeded_skills_fail_on_bare_bash "Seeded project skills declare scoped allowed-tools" nest_verify_bare_bash "nest-verify - bare Bash in allowed-tools"
fails nestjs_template_pins_fail_on_exact_dependency "Template package.json dependencies use floors" exact_pin_in_ns_package "nestjs/template/package.json"
# ── fastapi stack trees ──────────────────────────────────────────────────────
fails fastapi_template_trees_fail_on_empty_match "Template trees are complete" no_fa_templates "fastapi/template: tree is missing or empty"
fails fastapi_template_trees_fail_when_main_tree_deleted "Template trees are complete" no_fa_main_tree "fastapi/template: tree is missing or empty"
fails fastapi_template_trees_fail_when_agents_tree_deleted "Template trees are complete" no_fa_agents_tree "fastapi/template-agents: tree is missing or empty"
fails fastapi_template_trees_fail_when_manifest_deleted "Template trees are complete" no_fa_manifest "fastapi/template.manifest: file not found"
fails fastapi_template_trees_fail_when_manifest_lists_missing_file "Template trees are complete" fa_manifest_lists_missing "which is not in the tree"
fails fastapi_template_trees_fail_when_file_unlisted "Template trees are complete" fa_unlisted_file "is in the tree but not listed"
fails fastapi_template_trees_fail_when_script_loses_exec_bit "Template trees are complete" fa_exec_bit_lost "is mode 644 but listed as 755"
fails fastapi_template_trees_fail_on_empty_directory "Template trees are complete" fa_empty_dir "empty directory in a template tree"
fails fastapi_comment_narration_scans_template_sh "Change-narration comments" fa_narration_in_sh "Added a retry loop"
fails fastapi_comment_narration_scans_template_py "Change-narration comments" fa_narration_in_py "Removed the old handler"
fails fastapi_comment_narration_scans_template_toml "Change-narration comments" fa_narration_in_toml "Removed the old rule"
fails fastapi_skilldir_refs_fails_on_empty_match "<skill-dir> references resolve" fa_no_stack_copy "scaffold/fastapi/source-files.md: copy instruction PART=stack missing"
fails fastapi_skilldir_refs_fails_when_base_copy_deleted "<skill-dir> references resolve" fa_no_base_copy "scaffold/fastapi/source-files.md: copy instruction PART=base missing"
fails fastapi_skilldir_refs_fails_when_agents_copy_deleted "<skill-dir> references resolve" fa_no_agents_copy "scaffold/fastapi/source-files.md: copy instruction PART=agents missing"
fails fastapi_skilldir_refs_fails_when_manifest_ref_deleted "<skill-dir> references resolve" fa_no_manifest_ref "scaffold/fastapi/source-files.md: copy instruction <skill-dir>/fastapi/template.manifest missing"
fails fastapi_skilldir_refs_fails_when_agents_ref_deleted "<skill-dir> references resolve" fa_no_agents_ref "scaffold/fastapi/source-files.md: copy instruction <skill-dir>/fastapi/template-agents/ missing"
fails fastapi_ref_headers_fail_when_anchor_deleted "Ref file <!-- ref: --> headers" fa_ref_header_deleted "fastapi/source-files.md"
fails fastapi_ref_headers_still_check_a_file_beside_the_trees "Ref file <!-- ref: --> headers" headerless_md_beside_fa_template "fastapi/zz-note.md"
fails fastapi_ref_headers_still_check_a_file_named_template "Ref file <!-- ref: --> headers" headerless_md_named_fa_template "fastapi/template-notes.md"
fails fastapi_template_trees_fail_on_a_symlinked_directory "Template trees are complete" fa_symlinked_dir "src/api: symlink in a template tree"
fails fastapi_template_trees_fail_on_a_symlinked_file "Template trees are complete" fa_symlinked_file ".gitignore: symlink in a template tree"
fails nextjs_template_trees_fail_on_a_symlinked_file "Template trees are complete" nx_symlinked_file ".npmrc: symlink in a template tree"
fails vite_react_template_trees_fail_on_a_symlinked_directory "Template trees are complete" vr_symlinked_dir "src/lib: symlink in a template tree"
fails nextjs_step0_fails_when_format_line_deleted "Scaffold runs kit Step 0 before the first install" nx_no_format_line "no pnpm format line for the PART=agents copy to follow"
fails vite_react_step0_fails_when_format_line_deleted "Scaffold runs kit Step 0 before the first install" vr_no_format_line "no pnpm format line for the PART=agents copy to follow"
fails scan_version_pins_includes_fastapi_template "Version pins in skills" pin_in_fa_template "left-pad@1.3.0"
fails scan_hardcoded_secrets_includes_fastapi_template "Hardcoded secrets" secret_in_fa_template "hunter2hunter2"
fails scan_agents_marker_includes_fastapi_template "AGENTS.md schema marker not drifted" marker_drift_in_fa_template "template-agents/AGENTS.md"
fails template_skill_md_fails_when_the_fastapi_template_holds_one "Template trees hold no file named SKILL.md" fa_skill_md_appears "template/.claude/skills/api-verify/SKILL.md"
fails seeded_skills_scope_tools_fails_on_a_fastapi_template_skill_with_bare_bash "Seeded project skills declare scoped allowed-tools" fa_bare_bash_in_verify "bare Bash in allowed-tools"
fails fastapi_step0_fails_when_base_copy_is_after_6b "Scaffold runs kit Step 0 before the first install" fa_base_after_6b "the Step 0 line must be in the step 6b section"
fails fastapi_step0_fails_on_empty_match "Scaffold runs kit Step 0 before the first install" fa_no_base_line "no kit Step 0 instruction with STACK=fastapi and PART=base"
fails fastapi_step0_fails_when_agents_copy_moves_before_the_gate "Scaffold runs kit Step 0 before the first install" fa_agents_before_gate "comes before the format/verification-gate step"
fails fastapi_step0_fails_when_agents_copy_deleted "Scaffold runs kit Step 0 before the first install" fa_no_agents_line "no PART=agents instruction"
fails fastapi_step0_fails_when_gate_heading_deleted "Scaffold runs kit Step 0 before the first install" fa_no_gate_heading "no format/verification-gate step for the PART=agents copy to follow"

collect
echo "lint-skills.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
