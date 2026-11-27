#!/usr/bin/env bash
# scripts/lint-skills.test.sh — negative tests for the lint checks that read the template trees
# (skills/**/template*/, CONVENTIONS.md §1) and the guards that stop a check passing on nothing.
#
# Usage: bash scripts/lint-skills.test.sh   (run from anywhere; needs python3)
#   ONLY=<regex> runs just the tests whose name matches; LINT_TEST_JOBS=<n> sets how many run at once
#   (a whole number from 1 to 256, default: the CPU count; 1 runs them strictly one after another,
#   the parent-side checks included; anything else, empty included, exits 2 before a temp dir exists);
#   LINT=<path> runs the tests against another copy of the linter.
#
# Each case copies skills/ to a scratch dir, damages it, runs scripts/lint-skills.sh on the copy
# and asserts that one named check section reports the expected FAIL message. A check that scans a
# path glob must fail when the glob matches nothing (<check>_fails_on_empty_match) and when the code
# it anchors on is gone (<check>_fails_when_anchor_deleted); otherwise moving code out of markdown
# would let it pass while verifying nothing.
#
# Will not catch: a machine that runs out of disk or memory under high parallelism (lower LINT_TEST_JOBS);
# a probe process that leaves its process group (the pool stops only the groups it started, and then
# keeps the work dirs and warns when a group cannot be confirmed gone).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
LINT="${LINT:-scripts/lint-skills.sh}"
MAX_JOBS=256
CPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
[[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || CPUS=4
(( CPUS <= MAX_JOBS )) || CPUS=$MAX_JOBS
JOBS="${LINT_TEST_JOBS-$CPUS}"
if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || (( ${#JOBS} > 3 )) || (( JOBS > MAX_JOBS )); then
  echo "lint-skills.test: LINT_TEST_JOBS must be a whole number from 1 to $MAX_JOBS, got [$JOBS]" >&2
  exit 2
fi
set -m
[[ $- == *m* ]] || { echo "lint-skills.test: the shell cannot start each probe in its own process group (set -m failed)" >&2; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/lint-skills-test.XXXXXX") || exit 1

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# ── probe pool ───────────────────────────────────────────────────────────────
# Probes run in a ring of JOBS background jobs, each in its own subshell with its own work dir
# $T/w<n>. A probe reports through emit, which writes $T/r<n> whole and ends it with TRAILER;
# pool_collect reads the files in probe order and counts a probe as passed only when it exited
# 0, left a complete result file and that file says PASS. Everything else is a FAIL.
# LINT_TEST_JOBS=1 runs the probes one after another; pool_serial_point makes the parent-side code
# that follows wait for the last probe, so 1 means strictly serial.
# set -m gives every probe job a process group of its own (group id = the job's pid). The pool tracks
# those pids itself: it stops a probe's group when it reaps the probe and at exit (EXIT, INT, TERM),
# and needs no ps. A group it cannot confirm gone keeps its work dir and a warning is printed.
TRAILER='--probe-end--'
NJOB=0
REAPED=0
PNAME=()
PIDS=()
PSTAT=()

# pool_stop_group <pid> — kill the process group the probe job <pid> leads; true when no member is left.
pool_stop_group() {
  kill -KILL -- "-$1" 2>/dev/null || true
  kill -KILL "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
  ! kill -0 -- "-$1" 2>/dev/null
}

CLEAN_TRIES=50
pool_cleanup() {
  local n tries left=0
  trap '' INT TERM
  for (( n = REAPED + 1; n <= NJOB; n++ )); do
    for (( tries = 0; tries < CLEAN_TRIES; tries++ )); do
      pool_stop_group "${PIDS[$n]}" && break
      sleep 0.1
    done
    if (( tries == CLEAN_TRIES )); then left=$((left + 1)); fi
  done
  if (( left > 0 )); then
    echo "lint-skills.test: WARNING: $left probe process group(s) could not be confirmed stopped; $T is left in place" >&2
    return 0
  fi
  rm -rf "$T"
}
trap pool_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# emit <message> — a probe's one result: PASS or a FAIL: message.
emit() {
  printf '%s\n%s\n' "$1" "$TRAILER" > "$T/r$NJOB.tmp" && mv -f "$T/r$NJOB.tmp" "$T/r$NJOB"
}

# pool_reap_one — wait for the oldest probe that is still running, keep its exit status and stop any process it left
# in its group. REAPED moves only after the wait, so an interrupt during the wait leaves that probe to pool_cleanup.
pool_reap_one() {
  local n=$((REAPED + 1))
  wait "${PIDS[$n]}"
  PSTAT[n]=$?
  kill -KILL -- "-${PIDS[$n]}" 2>/dev/null || true
  REAPED=$n
}

# pool_drain — wait for every probe started so far.
pool_drain() {
  while (( REAPED < NJOB )); do pool_reap_one; done
}

# pool_serial_point — with one job the probes run strictly one after another: finish them before the
# parent-side code that follows. With more jobs the parent-side code overlaps the probes.
pool_serial_point() {
  if (( JOBS == 1 )); then pool_drain; fi
}

# pool_start <test name> <probe function> <args...> — run the probe in the background once a slot is free.
# The probe reads /dev/null as stdin: under set -m a background job keeps the terminal, and a probe that
# read stdin would stop on SIGTTIN and hang wait.
pool_start() {
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  while (( NJOB - REAPED >= JOBS )); do pool_reap_one; done
  NJOB=$((NJOB + 1))
  PNAME[NJOB]=$1
  shift
  ( "$@" ) </dev/null &
  PIDS[NJOB]=$!
}

# status_ok <n> — the probe job exited 0.
status_ok() { [[ "${PSTAT[$1]:-}" == 0 ]]; }

# trailer_ok <n> — the result file is complete: its last line is TRAILER.
trailer_ok() { [[ "$(tail -n 1 "$T/r$1")" == "$TRAILER" ]]; }

# missing_results_fail <missing> <found> — probes without a result file are failures, and the run says how many.
missing_results_fail() {
  if (( $1 > 0 )); then
    FAIL=$(($1 + FAIL))
    echo "FAIL: pool — $NJOB probes started, $2 results found, $1 missing"
  fi
}

# result_state <n> — ok, or why the probe's result cannot be trusted.
result_state() {
  status_ok "$1" || { echo "the probe job exited with status ${PSTAT[$1]:-unknown}"; return 0; }
  trailer_ok "$1" || { echo "the probe result is truncated or empty"; return 0; }
  echo ok
}

# pool_collect — wait for the rest, then print every failure in probe order and count the results.
pool_collect() {
  local n state body found=0 missing=0
  pool_drain
  for (( n = 1; n <= NJOB; n++ )); do
    if [[ ! -e "$T/r$n" ]]; then
      missing=$((missing + 1))
      echo "FAIL: ${PNAME[$n]} — the probe wrote no result (it crashed, was killed or exited early)"
      continue
    fi
    found=$((found + 1))
    state=$(result_state "$n")
    if [[ "$state" != ok ]]; then
      FAIL=$((FAIL + 1)); echo "FAIL: ${PNAME[$n]} — $state"
      continue
    fi
    body=$(sed '$d' "$T/r$n")
    if [[ "$body" == PASS ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "$body"; fi
  done
  missing_results_fail "$missing" "$found"
}
# ── end probe pool ───────────────────────────────────────────────────────────

# section <output> <header substring> — the lines of one check's section.
section() {
  awk -v h="$2" '/^── / { on = (index($0, h) > 0); next } on { print }' <<<"$1"
}

# damage_and_lint <work dir> <mutation function> — run the linter on a damaged copy; sets OUT.
damage_and_lint() {
  local w=$1 f
  rm -rf "$w"; mkdir -p "$w"
  cp -R skills "$w/skills"
  mkdir -p "$w/tests/golden"
  cp -R tests/golden/fences "$w/tests/golden/fences"
  cp tests/golden/line-budget.txt "$w/tests/golden/line-budget.txt"
  # Some skill references climb out of skills/ (<skill-dir>/../../.claude/rules); mirror the repo root.
  for f in .claude .claude-plugin CHANGELOG.md; do ln -s "$REPO_ROOT/$f" "$w/$f"; done
  S="$w/skills"
  SH="$S/scaffold/shared"
  "$2"
  OUT=$(bash "$LINT" "$w/skills${SLASH:+/}" 2>&1 || true)
}

probe_fails() { # probe_fails <test name> <header substring> <mutation function> <expected FAIL text>
  local sec
  damage_and_lint "$T/w$NJOB" "$3"
  sec=$(section "$OUT" "$2")
  if [[ -z "$sec" ]]; then
    emit "FAIL: $1 — no section '$2' in the lint output"
  elif ! grep -q '^FAIL:' <<<"$sec"; then
    emit "FAIL: $1 — '$2' did not fail: $(tail -1 <<<"$sec")"
  elif [[ "$sec" != *"$4"* ]]; then
    emit "FAIL: $1 — '$2' failed without the expected text [$4]: $(grep -v '^FAIL:' <<<"$sec" | head -3)"
  else
    emit PASS
  fi
  rm -rf "$T/w$NJOB"
}

probe_passes() { # probe_passes <test name> <header substring> <mutation function>
  local sec
  damage_and_lint "$T/w$NJOB" "$3"
  sec=$(section "$OUT" "$2")
  if [[ -z "$sec" ]]; then
    emit "FAIL: $1 — no section '$2' in the lint output"
  elif grep -q '^FAIL:' <<<"$sec"; then
    emit "FAIL: $1 — '$2' failed: $(head -3 <<<"$sec")"
  else
    emit PASS
  fi
  rm -rf "$T/w$NJOB"
}

probe_passes_all() { # probe_passes_all <test name> <mutation function>
  damage_and_lint "$T/w$NJOB" "$2"
  if [[ "$OUT" == *"=== All checks passed ==="* ]]; then
    emit PASS
  else
    emit "FAIL: $1 — the lint did not pass: $(grep -m3 '^FAIL:' <<<"$OUT")"
  fi
  rm -rf "$T/w$NJOB"
}

# fails <test name> <header substring> <mutation function> <expected FAIL text> — the section must
# report FAIL and the text must be in it. ONLY=<regex> selects tests by name.
fails() { pool_start "$1" probe_fails "$@"; }

# fails_both <same arguments as fails> — the test as written, then again with the skills path given a trailing slash, as CI gives it.
fails_both() {
  fails "$@"
  SLASH=1
  fails "${1}_with_trailing_slash" "${@:2}"
  SLASH=
}

# passes <test name> <header substring> <mutation function> — the section must exist and report no FAIL.
passes() { pool_start "$1" probe_passes "$@"; }

# passes_all <test name> <mutation function> — the whole lint must pass on the damaged copy.
passes_all() { pool_start "$1" probe_passes_all "$@"; }

collect() { pool_collect; }

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
lb_over_other_full() { mkdir -p "$S/zz"; awk 'BEGIN { for (i = 1; i <= 151; i++) print "line " i }' > "$S/zz/y.md"; }
no_templates() { rm -rf "$SH"/template "$SH"/template-* "$SH"/template.manifest; }
no_shared() { rm -rf "$SH"; }
no_hooks() { rm -rf "$SH"/template/.claude/hooks "$SH"/template-ts/.claude/hooks "$SH"/template-py/.claude/hooks; }
# Every templated stack; the empty-match helpers below empty all of them, so a check that scans the
# stacks still sees nothing.
TEMPLATED_TREES=(nextjs vite-react fastapi nestjs)
no_yaml() { local d; find "$SH"/template* \( -name '*.yml' -o -name '*.yaml' \) -delete; for d in "${TEMPLATED_TREES[@]}"; do find "$S/scaffold/$d/template" "$S/scaffold/$d/template-agents" \( -name '*.yml' -o -name '*.yaml' \) -delete; done; }
no_scannable() { local d; find "$SH"/template* -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete; for d in "${TEMPLATED_TREES[@]}"; do find "$S/scaffold/$d/template" "$S/scaffold/$d/template-agents" -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete; done; find "$S" -path "$S/scaffold" -prune -o -type d -name 'template*' -prune -exec find {} -type f \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name '*.toml' -o -name '*.py' -o -name '*.cjs' \) -delete \; ; }
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
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: TC_STACK=nextjs TC_PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
nx_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(NXD)/source-files.md"; }
nx_agents_before_format() { printf 'Run kit Step 0: TC_STACK=nextjs TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(NXD)/source-files.md" > "$S/x" && mv "$S/x" "$(NXD)/source-files.md"; }
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
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: TC_STACK=vite-react TC_PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
vr_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(VRD)/source-files.md"; }
vr_agents_before_format() { printf 'Run kit Step 0: TC_STACK=vite-react TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(VRD)/source-files.md" > "$S/x" && mv "$S/x" "$(VRD)/source-files.md"; }
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
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: TC_STACK=nestjs TC_PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY2
}
ns_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(NSD)/source-files.md"; }
ns_agents_before_format() { printf 'Run kit Step 0: TC_STACK=nestjs TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(NSD)/source-files.md" > "$S/x" && mv "$S/x" "$(NSD)/source-files.md"; }
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
ev_no_space() { printf '\nbash<<X\nexit 0\nX\n' >> "$SH/harness-kit-enforcement.md"; }
ev_exec_bash() { printf '\nexec bash<<X\nexit 0\nX\n' >> "$SH/harness-kit-enforcement.md"; }
ev_dash() { printf '\ndash <<X\nexit 0\nX\n' >> "$SH/harness-kit-enforcement.md"; }
ev_ksh() { printf '\nksh <<X\nexit 0\nX\n' >> "$SH/harness-kit-enforcement.md"; }
ev_abs_path() { printf '\n/opt/homebrew/bin/bash <<X\nexit 0\nX\n' >> "$SH/harness-kit-enforcement.md"; }
ev_procsub() { printf '\nbash <(cat <<X\nexit 0\nX\n)\n' >> "$SH/harness-kit-enforcement.md"; }
# shellcheck disable=SC2016  # the heredoc text is literal
ev_eval() { printf '\neval "$(cat <<X\nexit 0\nX\n)"\n' >> "$SH/harness-kit-enforcement.md"; }
# shellcheck disable=SC2016  # the copy line is literal text
second_loop_script() { mkdir -p "$S/add/zz"; printf '#!/usr/bin/env bash\ncp -- "$SK/$t/$p" "$TGT/$dest"\n' > "$S/add/zz/other-copy.sh"; }
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

# Template trees outside skills/scaffold (CONVENTIONS.md §1): the leaf skills/add/form/nextjs.md owns
# skills/add/form/nextjs/template*/ and the template.manifest beside them; it ships no tree of its own.
AT=add/form/nextjs
# plant_tree <dir under skills> <path inside it> [mode] [content] — one tree file and its manifest line.
plant_tree() {
  local d="$S/$1" rel=$2 mode=${3:-644}
  mkdir -p "$d/$(dirname "$rel")"
  printf '%s\n' "${4:-x}" > "$d/$rel"
  if [[ "$mode" == 755 ]]; then chmod 755 "$d/$rel"; fi
  printf '%s %s - -\n' "$rel" "$mode" >> "$d/template.manifest"
}
add_tree() { plant_tree "$AT" template/src/a.ts; }
# A complete tree: a header-free .md, a nested path deeper than the nesting limit, a skill template and a script.
add_tree_full() {
  plant_tree "$AT" template/src/a.ts
  plant_tree "$AT" template/docs/notes.md 644 'no header here'
  plant_tree "$AT" template/a/b/c/d/e/deep.md 644 'deep'
  plant_tree "$AT" template/.claude/skills/zz-verify/SKILL.md.tmpl
  plant_tree "$AT" template/run.sh 755 '#!/usr/bin/env bash'
  plant_tree "$AT" template-late/FUTURE.md
}
add_tree_unlisted() { add_tree; printf 'x\n' > "$S/$AT/template/src/zz-unlisted.ts"; }
add_tree_manifest_ghost() { add_tree; printf 'template/src/ghost.ts 644 - -\n' >> "$S/$AT/template.manifest"; }
add_tree_no_manifest() { add_tree; rm -f "$S/$AT/template.manifest"; }
add_tree_manifest_alone() { add_tree; rm -rf "$S/$AT/template"; }
add_tree_skill_md() { plant_tree "$AT" template/.claude/skills/zz/SKILL.md; }
add_tree_other_prefix_skill_md() { plant_tree "$AT" template-late/.claude/skills/zz/SKILL.md; }
add_tree_symlink() { add_tree; ln -s a.ts "$S/$AT/template/src/link.ts"; }
add_tree_symlinked_dir() { add_tree; ln -s src "$S/$AT/template/linked"; }
add_tree_empty_dir() { add_tree; mkdir -p "$S/$AT/template/zz-empty"; }
add_tree_mode_lost() { plant_tree "$AT" template/run.sh 755 '#!/usr/bin/env bash'; chmod 644 "$S/$AT/template/run.sh"; }
add_tree_tmpl_and_plain() { add_tree_full; printf 'template/.claude/skills/zz-verify/SKILL.md 644 - -\n' >> "$S/$AT/template.manifest"; }
add_headerless_md_beside_tree() { add_tree; printf 'no header\n' > "$S/$AT/zz-note.md"; }
add_headerless_md_named_template() { add_tree; printf 'no header\n' > "$S/add/auth/template-notes.md"; }
add_deep_md_outside_tree() { add_tree; mkdir -p "$S/$AT/zz/a/b"; printf '<!-- ref: x -->\n' > "$S/$AT/zz/a/b/c.md"; }
narration_in_add_tree() { plant_tree "$AT" template/run.sh 755 '# Added a retry loop'; }
pin_in_add_tree() { plant_tree "$AT" template/.npmrc 644 'left-pad@1.3.0'; }
secret_in_add_tree() { plant_tree "$AT" template/.npmrc 644 'password = "hunter2hunter2"'; }
exact_pin_in_add_tree() { plant_tree "$AT" template/package.json 644 '{ "dependencies": {
  "left-pad": "1.3.0" } }'; }
bare_handler_in_add_tree() { plant_tree "$AT" template/src/app/api/health/route.ts 644 'export async function GET() {}'; }
add_tree_hook() { plant_tree "$AT" template/.claude/hooks/zz-add-only-hook.sh 755 '#!/usr/bin/env bash'; }

# The IAM pairs compare a fence on each side. A fence that lives in a template file is named in
# tests/golden/fences/moved.d/*.tsv (check-fences.py's row format), and the lint resolves the side
# through that row; these tests never patch the lint.
# iam_move <markdown file under skills> <anchor> <fence language> <new file under skills> [indent] —
# take the first fence of that language after the anchor out of the markdown, write its body (without
# the indent) to the new file and map it in moved.d.
iam_move() {
  python3 - "$REPO_ROOT/scripts/check-fences.py" "$S" "$(dirname "$S")" "$@" <<'PY'
import importlib.util, os, sys
sys.dont_write_bytecode = True
cf_path, skills, root, md, anchor, lang, new = sys.argv[1:8]
indent = int(sys.argv[8]) if len(sys.argv) > 8 else 0
spec = importlib.util.spec_from_file_location("cf", cf_path)
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)
path = os.path.join(skills, md)
lines = open(path, encoding="utf-8").read().split("\n")
heading, at, counts, cur, found = "(top)", None, {}, None, None
for n, line in enumerate(lines):
    if cur is None:
        h = cf.HEADING.match(line)
        if h:
            heading = h.group(1).replace("\t", " ")
        if at is None and anchor in line:
            at = n
        m = cf.OPEN.match(line)
        if m:
            info = m.group(3).split()
            cur = (n, heading, (info[0] if info else "-").lower(), m.group(2)[0], len(m.group(2)))
    else:
        s = line.strip()
        if s and set(s) == {cur[3]} and len(s) >= cur[4]:
            start, hd, flang, _, _ = cur
            if flang not in cf.SHELL_TAGS:
                idx = counts.get(hd, 0)
                counts[hd] = idx + 1
                if found is None and at is not None and start > at and flang == lang:
                    found = (start, n, hd, idx)
            cur = None
start, end, hd, idx = found
body = [l[len(cf.OPEN.match(lines[start]).group(1)):] for l in lines[start + 1:end]]
dest = os.path.join(skills, new)
os.makedirs(os.path.dirname(dest), exist_ok=True)
open(dest, "w", encoding="utf-8").write("".join(l + "\n" for l in body))
open(path, "w", encoding="utf-8").write("\n".join(lines[:start] + lines[end + 1:]))
d = os.path.join(root, "tests", "golden", "fences", "moved.d")
os.makedirs(d, exist_ok=True)
row = "skills/%s\t%s\t%d\tskills/%s" % (md, hd, idx, new) + ("\tindent=%d" % indent if indent else "")
with open(os.path.join(d, "zz-test.tsv"), "a", encoding="utf-8") as fh:
    fh.write(row + "\n")
PY
}
# shellcheck disable=SC2016  # the anchors are literal heading text with backticks
IAM_S2=("migrate/database/fastapi.md" '### Step 2 — Replace `src/database/session.py`' python)
IAM_NEW_S=migrate/database/zz/template/session.py
# shellcheck disable=SC2016  # the anchors are literal heading text with backticks
IAM_A6=("add/database/python/sqlalchemy-iam.md" '### A6. Update `alembic/env.py`' python)
# The canonical A4 fence already lives in this template file, mapped in moved.d, so no fence of it
# is left in the markdown to move or to damage; the canonical-side tests damage this file instead.
IAM_NEW_A=add/database/python/sqlalchemy-iam/template/src/database/session.py
iam_copy_moved() { iam_move "${IAM_S2[@]}" "$IAM_NEW_S"; }
iam_canon_in_template() { [[ -f "$S/$IAM_NEW_A" ]] || { echo "iam_canon_in_template: $IAM_NEW_A is not in the tree" >&2; exit 1; }; }
iam_copy_moved_canon_in_template() { iam_canon_in_template; iam_copy_moved; }
iam_copy_moved_indented() { iam_move "${IAM_S2[@]}" "$IAM_NEW_S" 3; }
# Indent the canonical fence by 3 spaces in the markdown: the opener, the body and the closer.
iam_canon_fence_indented() { iam_canon_fence_indent 3; }
# A fence indented by 4 or more spaces is not a fence to check-fences.py, so it is not one here.
iam_canon_fence_indented_4() { iam_canon_fence_indent 4; }
iam_canon_fence_indent() {
  python3 - "$S/${IAM_A6[0]}" "${IAM_A6[1]}" "$1" <<'PY'
import sys
p, anchor, n = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().split("\n")
a = next(i for i, l in enumerate(lines) if anchor in l)
i = next(i for i in range(a + 1, len(lines)) if lines[i].startswith("```python"))
j = next(j for j in range(i + 1, len(lines)) if lines[j].startswith("```"))
for k in range(i, j + 1):
    if lines[k]:
        lines[k] = " " * int(n) + lines[k]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
iam_moved_file_byte_diff() { iam_copy_moved; printf '# drift\n' >> "$S/$IAM_NEW_S"; }
iam_moved_both_byte_diff() { iam_copy_moved_canon_in_template; printf '# drift\n' >> "$S/$IAM_NEW_A"; }
iam_moved_file_no_trailing_newline() { iam_copy_moved; printf '%s' "$(cat "$S/$IAM_NEW_S")" > "$S/$IAM_NEW_S"; }
iam_moved_file_deleted() { iam_copy_moved; rm -f "$S/$IAM_NEW_S"; }
iam_canon_template_file_deleted() { iam_canon_in_template; rm -f "$S/$IAM_NEW_A"; }
iam_moved_file_emptied() { iam_copy_moved; : > "$S/$IAM_NEW_S"; }
iam_moved_file_symlinked() { iam_copy_moved; mv "$S/$IAM_NEW_S" "$S/$IAM_NEW_S.real"; ln -s session.py.real "$S/$IAM_NEW_S"; }
iam_moved_outside_template() { iam_copy_moved; mkdir -p "$S/migrate/database/zz/plain"; mv "$S/$IAM_NEW_S" "$S/migrate/database/zz/plain/session.py"; iam_remap 4 skills/migrate/database/zz/plain/session.py; }
# iam_remap <column> <value> — rewrite one column of the moved.d row.
iam_remap() {
  local f; f="$(dirname "$S")/tests/golden/fences/moved.d/zz-test.tsv"
  awk -F'\t' -v OFS='\t' -v c="$1" -v v="$2" '{ $c = v; print }' "$f" > "$f.new" && mv "$f.new" "$f"
}
# The fence is gone and no row maps it.
iam_fence_gone_unmapped() { iam_copy_moved; rm -f "$(dirname "$S")/tests/golden/fences/moved.d/zz-test.tsv"; }
# The row names another fence, so this side has no mapping.
iam_row_for_another_index() { iam_copy_moved; iam_remap 3 7; }
# Fences that share a heading are mapped by index: moving one leaves its siblings live, and the
# lint must still pair each side with the fence of its own index.
# shellcheck disable=SC2016  # the anchors are literal text with backticks
KY_ENV=("add/database/typescript/nestjs-kysely-iam.md" 'Add IAM fields to `envSchema`' typescript)
# shellcheck disable=SC2016  # the anchors are literal text with backticks
KY_MAP=("add/database/typescript/nestjs-kysely-iam.md" 'Then map the validated fields into `serviceConfig`' typescript)
# shellcheck disable=SC2016  # the anchors are literal text with backticks
S10_ENV=("migrate/database/nestjs.md" '### Step 10 — Update `src/config/env.config.ts`' typescript)
# shellcheck disable=SC2016  # the anchors are literal text with backticks
S10_MAP=("migrate/database/nestjs.md" 'Then map the validated fields into `serviceConfig`' typescript)
IAM_NEW_KY=add/database/typescript/zz/template/env-schema.ts
IAM_NEW_S10=migrate/database/zz/template/env-config.ts
iam_ky_mid_moved() { iam_move "${KY_ENV[@]}" "$IAM_NEW_KY"; }
iam_s10_first_moved() { iam_move "${S10_ENV[@]}" "$IAM_NEW_S10"; }
# iam_touch <markdown file> <anchor> <fence language> — add a line to the first such fence after the anchor.
iam_touch() {
  python3 - "$S/$1" "$2" "$3" <<'PY'
import sys
p, anchor, lang = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().split("\n")
a = next(i for i, l in enumerate(lines) if anchor in l)
i = next(i for i in range(a + 1, len(lines)) if lines[i].startswith("```" + lang))
lines.insert(i + 1, "// drift")
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
iam_ky_moved_file_byte_diff() { iam_ky_mid_moved; printf '// drift\n' >> "$S/$IAM_NEW_KY"; }
iam_ky_live_sibling_byte_diff() { iam_ky_mid_moved; iam_touch "${KY_MAP[@]}"; }
# shellcheck disable=SC2016  # the anchor is literal text with backticks
iam_ky_first_sibling_byte_diff() { iam_ky_mid_moved; iam_touch "add/database/typescript/nestjs-kysely-iam.md" 'Replace the entire contents of `kysely.service.ts` with:' typescript; }
iam_s10_moved_file_byte_diff() { iam_s10_first_moved; printf '// drift\n' >> "$S/$IAM_NEW_S10"; }
iam_s10_live_sibling_byte_diff() { iam_s10_first_moved; iam_touch "${S10_MAP[@]}"; }
iam_moved_path_with_empty_segment() { iam_copy_moved; iam_remap 4 skills/migrate/database/zz//template/session.py; }
# A fence inside a list item may be indented past 3 spaces: the list item's content column sets the limit.
iam_canon_fence_in_list_item() {
  python3 - "$S/${IAM_A6[0]}" "${IAM_A6[1]}" <<'PY'
import sys
p, anchor = sys.argv[1:3]
lines = open(p, encoding="utf-8").read().split("\n")
a = next(i for i, l in enumerate(lines) if anchor in l)
i = next(i for i in range(a + 1, len(lines)) if lines[i].startswith("```python"))
j = next(j for j in range(i + 1, len(lines)) if lines[j].startswith("```"))
for k in range(i, j + 1):
    if lines[k]:
        lines[k] = "    " + lines[k]
lines[i:i] = ["1. Replace the file:", ""]
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
iam_moved_file_crlf() { iam_copy_moved; sed -i.bak 's/$/\r/' "$S/$IAM_NEW_S"; rm -f "$S/$IAM_NEW_S.bak"; }
iam_moved_file_not_utf8() { iam_copy_moved; printf '\377\376 not utf-8\n' > "$S/$IAM_NEW_S"; }
# The row maps the fence but the fence is still in the markdown.
iam_mapped_fence_still_live() {
  cp "$S/${IAM_S2[0]}" "$S/${IAM_S2[0]}.orig"
  iam_copy_moved
  mv "$S/${IAM_S2[0]}.orig" "$S/${IAM_S2[0]}"
}
# The same fence is mapped by two moved.d files.
iam_row_mapped_twice() { iam_copy_moved; cp "$(dirname "$S")/tests/golden/fences/moved.d/zz-test.tsv" "$(dirname "$S")/tests/golden/fences/moved.d/zz-other.tsv"; }
iam_fence_byte_diff() { strip_token 'create_engine(' 'create_engine (' "$S/migrate/database/fastapi.md"; }
# shellcheck disable=SC2016  # the anchors are literal heading text with backticks
iam_copy_anchor_deleted() { strip_token '### Step 2 — Replace `src/database/session.py`' '### Step 2 — Replace session' "$S/migrate/database/fastapi.md"; }
# shellcheck disable=SC2016  # the anchors are literal heading text with backticks
iam_canon_anchor_deleted() { strip_token '### A4. Create `src/database/session.py`' '### A4. Create session' "$S/add/database/python/sqlalchemy-iam.md"; }
iam_fence_emptied() { python3 - "$S/migrate/database/fastapi.md" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
a = t.index("### Step 2 — Replace")
i = t.index("```python\n", a) + len("```python\n")
j = t.index("\n```", i)
open(p, "w", encoding="utf-8").write(t[:i] + t[j + 1:])
PY
}
iam_both_fences_emptied() { iam_fence_emptied; python3 - "$S/add/database/python/sqlalchemy-iam.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
a = t.index("### A4. Create")
i = t.index("```python\n", a) + len("```python\n")
j = t.index("\n```", i)
open(p, "w", encoding="utf-8").write(t[:i] + t[j + 1:])
PY
}

# check_security_seeds_present: a definition may live in the leaf's template tree.
# seed_to_tree <stack> <definition regex> <file in the tree> — the definition line leaves the leaf and
# lands in a tree file under add/auth/<stack>/.
seed_to_tree() {
  local leaf line src
  leaf="$S/add/auth/$1.md"
  src=$(grep -rlE "$2" "$leaf" "$S/add/auth/$1" 2>/dev/null | head -n 1)
  line=$(grep -m1 -E "$2" "$src")
  python3 - "$src" "$line" <<'PY'
import sys
p, line = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace(line, "// moved: " + line.split("(")[0], 1))
PY
  plant_tree "add/auth/$1" "$3" 644 "$line"
}
seed_moved_roles_guard() { seed_to_tree nestjs '^export class RolesGuard ' template/src/auth/roles.guard.ts; }
seed_moved_require_roles() { seed_to_tree fastapi '^def require_roles\(' template/src/auth/roles.py; }
seed_moved_has_role() { seed_to_tree nextjs '^export function hasRole\(' template/src/lib/roles.ts; }
seed_moved_to_wrong_leaf() { seed_to_tree nestjs '^export class RolesGuard ' template/src/auth/roles.guard.ts; mv "$S/add/auth/nestjs" "$S/add/auth/zz-other"; }
seed_deleted_nest_with_tree() { strip_token 'export class RolesGuard ' 'export class Guard ' "$S/add/auth/nestjs.md" "$S/add/auth/nestjs"; plant_tree add/auth/nestjs template/src/auth/other.ts 644 'export class Other {}'; }
seed_deleted_require_roles() { strip_token 'def require_roles(' 'def require_role_list(' "$S/add/auth/fastapi.md" "$S/add/auth/fastapi"; }

# check_owasp_llm_sections_complete: the sections may be split into a ref file beside implementation.md.
owasp_split_to_ref() {
  python3 - "$S/add/ai-security/implementation.md" "$S/add/ai-security/zz-extra.md" <<'PY'
import sys
src, dst = sys.argv[1:3]
t = open(src, encoding="utf-8").read()
a = t.index("### LLM10")
open(src, "w", encoding="utf-8").write(t[:a].rstrip("\n") + "\n")
open(dst, "w", encoding="utf-8").write("<!-- ref: add/ai-security/zz-extra.md -->\n" + t[a:])
PY
}
owasp_section_only_in_tree() { owasp_split_to_ref; mkdir -p "$S/add/ai-security/zz-extra/template"; mv "$S/add/ai-security/zz-extra.md" "$S/add/ai-security/zz-extra/template/zz.md"; }
owasp_section_deleted() { strip_token '### LLM10' '### LLX10' "$S/add/ai-security/implementation.md"; }

# ── baseline ─────────────────────────────────────────────────────────────────
# probe_baseline <test name> <slash flag> — the lint must pass on the unmodified tree.
probe_baseline() {
  SLASH=$2
  damage_and_lint "$T/w$NJOB" none
  if [[ "$OUT" == *"=== All checks passed ==="* ]]; then
    emit PASS
  else
    emit "FAIL: $1 (${OUT##*$'\n'}) — expected [0], got [1]"
  fi
  rm -rf "$T/w$NJOB"
}
if [[ -z "${ONLY:-}" ]]; then
  pool_start baseline_passes probe_baseline "baseline_passes: lint passes on the unmodified tree" ""
  pool_start baseline_passes_with_a_trailing_slash probe_baseline "baseline_passes_with_a_trailing_slash: the command CI runs passes" 1
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
assert "TC_STACK=nextjs TC_PART=stack" in t
open(p, "w", encoding="utf-8").write(t.replace("TC_STACK=nextjs TC_PART=stack", "TC_PART=stack", 1) + "\nSTACK=nextjs\n")
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
open(p, "w", encoding="utf-8").write(t.replace("PART=base", "PART=bas") + "\nRun kit Step 0: TC_STACK=fastapi TC_PART=base bash \"<skill-dir>/shared/tc-copy.sh\" \"<target>\".\n")
PY
}
fa_no_base_line() { strip_token 'PART=base' 'PART=bas' "$(FAD)/source-files.md"; }
fa_agents_before_gate() { printf 'Run kit Step 0: TC_STACK=fastapi TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>".\n' | cat - "$(FAD)/source-files.md" > "$S/x" && mv "$S/x" "$(FAD)/source-files.md"; }
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
pool_serial_point
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
fails_both copy_script_fails_on_bash_without_a_space "The copy script has exactly one copy" ev_no_space "a shell heredoc in"
fails_both copy_script_fails_on_exec_bash_without_a_space "The copy script has exactly one copy" ev_exec_bash "a shell heredoc in"
fails_both copy_script_fails_on_dash "The copy script has exactly one copy" ev_dash "a shell heredoc in"
fails_both copy_script_fails_on_ksh "The copy script has exactly one copy" ev_ksh "a shell heredoc in"
fails_both copy_script_fails_on_a_homebrew_bash_path "The copy script has exactly one copy" ev_abs_path "a shell heredoc in"
fails_both copy_script_fails_on_process_substitution "The copy script has exactly one copy" ev_procsub "a shell heredoc in"
fails_both copy_script_fails_on_eval_of_a_heredoc "The copy script has exactly one copy" ev_eval "a shell heredoc in"
fails_both copy_script_fails_on_a_second_script_with_the_copy_loop "The copy script has exactly one copy" second_loop_script "another file carries the template copy loop"
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

# ── template trees outside skills/scaffold (CONVENTIONS.md §1) ───────────────────────────────
passes_all add_tree_full_passes_the_whole_lint add_tree_full
passes add_tree_ref_headers_skip_files_in_the_tree "Ref file <!-- ref: --> headers" add_tree_full
passes add_tree_nesting_depth_skips_files_in_the_tree "Nesting depth" add_tree_full
fails_both add_tree_fails_when_file_unlisted "Template trees are complete" add_tree_unlisted "zz-unlisted.ts is in the tree but not listed"
fails add_tree_fails_when_manifest_lists_missing_file "Template trees are complete" add_tree_manifest_ghost "lists template/src/ghost.ts, which is not in the tree"
fails add_tree_fails_without_a_manifest "Template trees are complete" add_tree_no_manifest "template.manifest: file not found"
fails add_tree_fails_when_only_the_manifest_is_left "Template trees are complete" add_tree_manifest_alone "which is not in the tree"
fails add_tree_fails_on_a_symlinked_file "Template trees are complete" add_tree_symlink "link.ts: symlink in a template tree"
fails add_tree_fails_on_a_symlinked_directory "Template trees are complete" add_tree_symlinked_dir "linked: symlink in a template tree"
fails add_tree_fails_on_an_empty_directory "Template trees are complete" add_tree_empty_dir "empty directory in a template tree"
fails add_tree_fails_when_exec_bit_lost "Template trees are complete" add_tree_mode_lost "is mode 644 but listed as 755"
fails add_tree_fails_when_tmpl_and_plain_both_listed "Template trees are complete" add_tree_tmpl_and_plain "both copy to"
fails add_tree_skill_md_fails "Template trees hold no file named SKILL.md" add_tree_skill_md "add/form/nextjs/template/.claude/skills/zz/SKILL.md"
fails add_tree_skill_md_fails_in_a_suffixed_tree "Template trees hold no file named SKILL.md" add_tree_other_prefix_skill_md "template-late/.claude/skills/zz/SKILL.md"
fails add_ref_headers_still_check_a_file_beside_the_tree "Ref file <!-- ref: --> headers" add_headerless_md_beside_tree "add/form/nextjs/zz-note.md"
fails add_ref_headers_still_check_a_file_named_template "Ref file <!-- ref: --> headers" add_headerless_md_named_template "add/auth/template-notes.md"
fails add_nesting_depth_still_checks_a_file_beside_the_tree "Nesting depth" add_deep_md_outside_tree "add/form/nextjs/zz/a/b/c.md"
fails add_tree_comment_narration_is_scanned "Change-narration comments" narration_in_add_tree "Added a retry loop"
fails add_tree_version_pins_are_scanned "Version pins in skills" pin_in_add_tree "left-pad@1.3.0"
fails add_tree_hardcoded_secrets_are_scanned "Hardcoded secrets" secret_in_add_tree "hunter2hunter2"
fails add_tree_exact_dependency_pins_are_scanned "Template package.json dependencies use floors" exact_pin_in_add_tree "add/form/nextjs/template/package.json"
fails add_tree_bare_route_handlers_are_scanned "Bare Next.js route handler exports" bare_handler_in_add_tree "add/form/nextjs/template/src/app/api/health/route.ts"
passes add_tree_hook_does_not_enter_the_migrate_inventory "migrate hook inventory matches" add_tree_hook

# ── check_duplicated_iam_blocks_match: a moved fence resolves through moved.d ────────────────
IAMH="Duplicated IAM session/config blocks match"
passes iam_pairs_pass_fence_vs_fence "$IAMH" none
passes iam_pairs_pass_a_moved_copy_side "$IAMH" iam_copy_moved
passes iam_pairs_pass_a_canonical_side_in_a_template "$IAMH" iam_canon_in_template
passes iam_pairs_pass_when_the_copy_side_moved_too "$IAMH" iam_copy_moved_canon_in_template
passes iam_pairs_pass_a_moved_side_with_an_indent_column "$IAMH" iam_copy_moved_indented
passes iam_pairs_pass_an_indented_fence "$IAMH" iam_canon_fence_indented
passes iam_pairs_pass_a_moved_middle_fence_with_typescript_siblings "$IAMH" iam_ky_mid_moved
passes iam_pairs_pass_a_moved_first_fence_of_a_heading "$IAMH" iam_s10_first_moved
fails iam_pairs_fail_on_a_byte_change_in_a_moved_middle_fence "$IAMH" iam_ky_moved_file_byte_diff "NestJS IAM envSchema fields: migrate/database/nestjs.md has drifted"
fails iam_pairs_fail_on_a_byte_change_in_a_live_sibling_after_the_moved_one "$IAMH" iam_ky_live_sibling_byte_diff "NestJS IAM serviceConfig mapping"
fails iam_pairs_fail_on_a_byte_change_in_a_live_sibling_before_the_moved_one "$IAMH" iam_ky_first_sibling_byte_diff "NestJS IAM KyselyService"
fails iam_pairs_fail_on_a_byte_change_in_a_moved_first_fence "$IAMH" iam_s10_moved_file_byte_diff "NestJS IAM envSchema fields"
fails iam_pairs_fail_on_a_byte_change_in_a_live_sibling_of_a_moved_first_fence "$IAMH" iam_s10_live_sibling_byte_diff "NestJS IAM serviceConfig mapping"
fails iam_pairs_fail_on_a_fence_indented_past_three_spaces "$IAMH" iam_canon_fence_indented_4 "canonical add/database/python/sqlalchemy-iam.md holds 1 fence(s) under 'A6."
fails iam_pairs_fail_on_a_mapping_path_with_an_empty_segment "$IAMH" iam_moved_path_with_empty_segment "outside a template* directory"
passes iam_pairs_pass_an_indented_fence_in_a_list_item "$IAMH" iam_canon_fence_in_list_item
fails iam_pairs_fail_on_a_moved_file_with_crlf_line_endings "$IAMH" iam_moved_file_crlf "has drifted"
fails iam_pairs_fail_on_a_moved_file_that_is_not_utf8 "$IAMH" iam_moved_file_not_utf8 "unreadable or not UTF-8"
fails iam_pairs_fail_when_a_mapped_fence_is_still_in_the_markdown "$IAMH" iam_mapped_fence_still_live "a mapped fence still in the markdown"
fails iam_pairs_fail_when_a_fence_is_mapped_twice "$IAMH" iam_row_mapped_twice "is mapped twice"
fails iam_pairs_fail_on_a_fence_byte_diff "$IAMH" iam_fence_byte_diff "FastAPI IAM session.py: migrate/database/fastapi.md has drifted"
fails iam_pairs_fail_on_a_moved_file_byte_diff "$IAMH" iam_moved_file_byte_diff "FastAPI IAM session.py: migrate/database/fastapi.md has drifted"
fails iam_pairs_fail_on_two_moved_files_byte_diff "$IAMH" iam_moved_both_byte_diff "has drifted"
fails iam_pairs_fail_when_a_moved_file_has_no_trailing_newline "$IAMH" iam_moved_file_no_trailing_newline "must end in a newline"
fails iam_pairs_fail_when_the_mapped_copy_file_is_missing "$IAMH" iam_moved_file_deleted "copy mapped file skills/migrate/database/zz/template/session.py"
fails iam_pairs_fail_when_the_mapped_canonical_file_is_missing "$IAMH" iam_canon_template_file_deleted "canonical mapped file skills/add/database/python/sqlalchemy-iam/template/src/database/session.py"
fails iam_pairs_fail_on_an_empty_mapped_file "$IAMH" iam_moved_file_emptied "is empty"
fails iam_pairs_fail_on_a_symlinked_mapped_file "$IAMH" iam_moved_file_symlinked "through a symlink"
fails iam_pairs_fail_on_a_mapping_outside_a_template_directory "$IAMH" iam_moved_outside_template "outside a template* directory"
fails iam_pairs_fail_when_the_fence_is_gone_and_unmapped "$IAMH" iam_fence_gone_unmapped "copy migrate/database/fastapi.md holds 0 fence(s)"
fails iam_pairs_fail_when_the_row_names_another_fence "$IAMH" iam_row_for_another_index "no moved.d row"
fails iam_pairs_fail_on_two_empty_fences "$IAMH" iam_both_fences_emptied "is empty"
fails iam_pairs_fail_when_the_copy_anchor_is_deleted "$IAMH" iam_copy_anchor_deleted "copy anchor/fence not found in migrate/database/fastapi.md"
fails iam_pairs_fail_when_the_canonical_anchor_is_deleted "$IAMH" iam_canon_anchor_deleted "canonical anchor/fence not found in add/database/python/sqlalchemy-iam.md"

# ── manifest alone, and a symlinked tree root ─────────────────────────────────────────────────
add_manifest_only_empty() { mkdir -p "$S/$AT"; : > "$S/$AT/template.manifest"; }
add_manifest_only_comments() { mkdir -p "$S/$AT"; printf '# nothing yet\n' > "$S/$AT/template.manifest"; }
add_tree_root_symlink() { add_tree; mv "$S/$AT/template" "$S/$AT/real-tree"; ln -s real-tree "$S/$AT/template"; }
fails_both add_empty_manifest_without_a_tree_fails "Template trees are complete" add_manifest_only_empty "no template tree sits beside this manifest"
fails add_comment_only_manifest_without_a_tree_fails "Template trees are complete" add_manifest_only_comments "no template tree sits beside this manifest"
fails add_tree_fails_on_a_symlinked_tree_root "Template trees are complete" add_tree_root_symlink "template: symlink in a template tree"

# ── check_security_seeds_present: the definition may live in the leaf's template tree ────────
passes security_seed_moved_into_the_nestjs_template_passes "Deps gate and deny-by-default authz seeds" seed_moved_roles_guard
passes security_seed_moved_into_the_fastapi_template_passes "Deps gate and deny-by-default authz seeds" seed_moved_require_roles
passes security_seed_moved_into_the_nextjs_template_passes "Deps gate and deny-by-default authz seeds" seed_moved_has_role
fails security_seed_fails_when_a_tree_holds_a_different_file "Deps gate and deny-by-default authz seeds" seed_deleted_nest_with_tree "RolesGuard"
fails security_seed_fails_when_the_tree_belongs_to_another_leaf "Deps gate and deny-by-default authz seeds" seed_moved_to_wrong_leaf "RolesGuard"
fails security_seed_fails_when_the_definition_is_deleted "Deps gate and deny-by-default authz seeds" seed_deleted_require_roles "require_roles"

# ── check_template_security_defaults ─────────────────────────────────────────────────────────
H_SEC="Template security defaults present"
sec_empty() { rm -rf "$S/scaffold/nestjs/template" "$S/scaffold/fastapi/template" "$S/scaffold/nextjs/template" "$S/scaffold/vite-react/template"; }
sec_nest_jwt() { sed -i.bak "s/algorithms: \['HS256'\]/algorithms: ['none']/" "$S/add/auth/nestjs/template/src/modules/auth/jwt.strategy.ts"; }
sec_nest_referrer() { sed -i.bak 's/referrerPolicy: {/referrerPolicyX: {/' "$S/scaffold/nestjs/template/src/config/setups/security.setup.ts"; }
sec_nest_trust() { sed -i.bak 's/\.\.\.(trustProxy ? { trustProxy } : {}),//' "$S/scaffold/nestjs/template/src/app.factory.ts"; }
sec_nest_classvalidator() { sed -i.bak 's/"nestjs-zod"/"class-validator": "1.0.0", "nestjs-zod"/' "$S/scaffold/nestjs/template/package.json"; }
sec_fastapi_mw() { sed -i.bak 's/add_middleware(SecurityHeadersMiddleware)/pass/' "$S/scaffold/fastapi/template/src/app.py"; }
sec_fastapi_trust() { sed -i.bak 's/if not api_settings.TRUST_PROXY:/if False:/' "$S/scaffold/fastapi/template/src/app.py"; }
sec_fastapi_deny() { sed -i.bak 's/b"DENY"/b"SAMEORIGIN"/' "$S/scaffold/fastapi/template/src/core/security_headers.py"; }
sec_next_csp_dup() { sed -i.bak "s|^\( *\)source: '/(.\*)',|\1key: 'Content-Security-Policy',\n&|" "$S/scaffold/nextjs/template/next.config.ts"; }
sec_next_origin() { sed -i.bak 's/process.env.TRUST_PROXY/process.env.OTHER/' "$S/scaffold/nextjs/template/src/lib/utils/request-origin.ts"; }
sec_next_deny() { sed -i.bak "s/'DENY'/'ALLOWALL'/" "$S/scaffold/nextjs/template/src/lib/security/frame-protection.ts"; }
sec_vite_exotic() { sed -i.bak 's/^blockExoticSubdeps: true/blockExoticSubdeps: false/' "$S/scaffold/vite-react/template/pnpm-workspace.yaml"; }
sec_vite_envsh() { sed -i.bak 's/TC_X_FRAME_OPTIONS="DENY"/TC_X_FRAME_OPTIONS=""/' "$S/scaffold/vite-react/template/docker/15-frame-protection.envsh"; }
sec_dockerfile() { sed -i.bak 's/ pnpm-workspace.yaml\* / /' "$S/scaffold/nextjs/template/Dockerfile"; }
fails security_defaults_fails_on_empty_match "$H_SEC" sec_empty "file not found"
fails security_defaults_nest_jwt_alg "$H_SEC" sec_nest_jwt "NestJS JWT algorithm whitelist"
fails security_defaults_nest_referrer "$H_SEC" sec_nest_referrer "referrerPolicy"
fails security_defaults_nest_trust_proxy "$H_SEC" sec_nest_trust "TRUST_PROXY reaches FastifyAdapter"
fails security_defaults_nest_class_validator "$H_SEC" sec_nest_classvalidator "class-validator"
fails security_defaults_fastapi_middleware "$H_SEC" sec_fastapi_mw "SecurityHeadersMiddleware registered"
fails security_defaults_fastapi_trust_gate "$H_SEC" sec_fastapi_trust "gated by TRUST_PROXY"
fails security_defaults_fastapi_deny "$H_SEC" sec_fastapi_deny "X-Frame-Options DENY"
fails security_defaults_next_csp_second_source "$H_SEC" sec_next_csp_dup "must be the only source"
fails security_defaults_next_origin_gate "$H_SEC" sec_next_origin "gated by TRUST_PROXY"
fails security_defaults_next_deny "$H_SEC" sec_next_deny "X-Frame-Options DENY"
fails security_defaults_vite_block_exotic "$H_SEC" sec_vite_exotic "blockExoticSubdeps"
fails security_defaults_vite_envsh_deny "$H_SEC" sec_vite_envsh "X-Frame-Options DENY"
sec_nest_fallback() { sed -i.bak "s/portal ?? \"'none'\"/portal ?? \"'self'\"/" "$S/scaffold/nestjs/template/src/config/setups/security.setup.ts"; }
sec_nest_dockerfile_one() { perl -0pi -e 's/pnpm-workspace\.yaml\* //' "$S/scaffold/nestjs/template/Dockerfile"; }
sec_nest_import() { printf "import { IsString } from 'class-validator';\n" >> "$S/scaffold/nestjs/template/src/main.ts"; }
fails security_defaults_nest_frame_ancestors_fallback_only "$H_SEC" sec_nest_fallback "frame-ancestors 'none' fallback"
fails security_defaults_nest_dockerfile_one_stage "$H_SEC" sec_nest_dockerfile_one "both stages"
fails security_defaults_nest_class_validator_import "$H_SEC" sec_nest_import "imports class-validator"
fails security_defaults_dockerfile_workspace "$H_SEC" sec_dockerfile "Dockerfile copies pnpm-workspace.yaml"

# ── check_owasp_llm_sections_complete ────────────────────────────────────────────────────────
passes owasp_sections_may_be_split_into_a_ref_file "OWASP LLM Top 10 v2.0 completeness" owasp_split_to_ref
fails owasp_sections_in_a_template_tree_do_not_count "OWASP LLM Top 10 v2.0 completeness" owasp_section_only_in_tree "LLM10"
fails owasp_fails_when_a_section_is_deleted "OWASP LLM Top 10 v2.0 completeness" owasp_section_deleted "LLM10"

# ── check_no_version_pins: a ≥ floor in prose fails; one in a fence or inline code does not ────
floor_in_prose() { printf '\nNeeds zz-lib ≥9.9 for this.\n' >> "$S/add/form/nextjs.md"; }
# shellcheck disable=SC2016  # literal backticks are fixture text
floor_in_code() { printf '\nInstall `zz-lib ≥9.9` first.\n\n```text\nzz-lib ≥9.9\n```\n' >> "$S/add/form/nextjs.md"; }
fails prose_floor_fails "Version floors in skill prose" floor_in_prose "zz-lib ≥9.9"
passes prose_floor_in_code_passes "Version floors in skill prose" floor_in_code

# ── check_seeded_pipefail_readers ────────────────────────────────────────────────────────────
H_PF="Seeded pipefail scripts do not pipe into an early-exit reader"
PF_FIXTURE="scaffold/shared/template/scripts/zz-pipefail-fixture.sh"
PF_YAML="scaffold/shared/template-ci/github-ts/.github/workflows/zz-pipefail-fixture.yml"
# pf_script <pipefail line> <command>: writes a seeded fixture script whose command sits on line 3.
pf_script() { printf '#!/usr/bin/env bash\n%s\n%s\n' "$1" "$2" > "$S/$PF_FIXTURE"; }
pf_grep_q() { pf_script 'set -uo pipefail' 'printf x | grep -q x'; }
pf_here_string() { pf_script 'set -uo pipefail' "printf '%s\\n' \"\$v\" | grep x >/dev/null"; }
pf_no_pipefail() { pf_script 'set -u' 'printf x | grep -q x'; }
pf_grep_Eq() { pf_script 'set -uo pipefail' 'printf x | grep -Eq x'; }
pf_grep_iqE() { pf_script 'set -uo pipefail' 'if printf x | grep -iqE x; then :; fi'; }
pf_grep_quiet() { pf_script 'set -uo pipefail' 'printf x | grep --quiet x'; }
pf_grep_m1() { pf_script 'set -uo pipefail' "v=\$(printf x | grep -m1 x)"; }
pf_grep_e_arg() { pf_script 'set -uo pipefail' 'printf x | grep -e q -E x'; }
pf_grep_count() { pf_script 'set -uo pipefail' 'printf x | grep -c x'; }
pf_grep_invert() { pf_script 'set -uo pipefail' 'printf x | grep -v y'; }
pf_head() { pf_script 'set -uo pipefail' "v=\$(printf x | head -n 1)"; }
pf_sed_q() { pf_script 'set -uo pipefail' "v=\$(printf x | sed '1q')"; }
pf_sed_s() { pf_script 'set -uo pipefail' "v=\$(printf x | sed 's/x/q/')"; }
pf_awk_exit() { pf_script 'set -uo pipefail' "printf x | awk '/x/ { exit }'"; }
pf_awk_end_exit() { pf_script 'set -uo pipefail' "printf x | awk '/x/ { hit = 1 } END { exit !hit }'"; }
pf_read() { pf_script 'set -uo pipefail' 'printf x | read -r v'; }
pf_read_loop() { pf_script 'set -uo pipefail' 'printf x | while read -r v; do :; done'; }
pf_multiline() { pf_script 'set -uo pipefail' 'printf x |
  grep -q x'; }
pf_in_subshell() { pf_script 'set -uo pipefail' "v=\$(printf x | grep -q x && echo y)"; }
pf_quoted_pipe() { pf_script 'set -uo pipefail' "echo 'a | grep -q b'"; }
pf_heredoc_body() { printf '#!/usr/bin/env bash\nset -uo pipefail\ncat <<EOF\nprintf x | grep -q x\nEOF\n' > "$S/$PF_FIXTURE"; }
pf_comment() { pf_script 'set -uo pipefail' '# printf x | grep -q x'; }
pf_unclosed_quote() { pf_script 'set -uo pipefail' "echo 'never closed"; }
pf_yaml_run() { printf 'steps:\n  - run: |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_clean() { printf '%s\n' 'steps:' '  - run: |' '      set -o pipefail' $'      printf "%s\\n" "$v" | grep x >/dev/null' > "$S/$PF_YAML"; }
pf_yaml_other_key() { printf 'steps:\n  - name: printf x | grep -q x\n    run: |\n      set -o pipefail\n      echo ok\n' > "$S/$PF_YAML"; }
pf_yaml_plain_cont() { printf 'steps:\n  - run:\n      set -o pipefail; printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_plain_cont_clean() { printf 'steps:\n  - run:\n      set -o pipefail; grep -q x file\n' > "$S/$PF_YAML"; }
pf_yaml_quoted_key() { printf 'steps:\n  - "run": |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_quoted_key_clean() { printf 'steps:\n  - "run": |\n      set -o pipefail\n      grep -q x file\n' > "$S/$PF_YAML"; }
pf_yaml_indent_ind() { printf 'steps:\n  - run: |2\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_tagged() { printf 'steps:\n  - run: !!str |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_anchored() { printf 'steps:\n  - run: &r |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_comment_after_key() { printf 'steps:\n  - run: # note\n      set -o pipefail; printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_header_next_line() { printf 'steps:\n  - run:\n      # note\n      |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_sibling_between() { printf 'steps:\n  - run: |\n      set -o pipefail\n      echo ok\n    env:\n      A: x\n  - run: |\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_sibling_before() { printf 'steps:\n  - name: build\n    env:\n      A: x\n    run: |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_yaml_dq_scalar() { printf 'steps:\n  - run: "set -o pipefail; printf x | grep -q x"\n' > "$S/$PF_YAML"; }
pf_yaml_dq_scalar_clean() { printf 'steps:\n  - run: "set -o pipefail; grep -q x file"\n' > "$S/$PF_YAML"; }
pf_yaml_sq_scalar() { printf "steps:\n  - run: 'set -o pipefail; printf x | grep -q x'\n" > "$S/$PF_YAML"; }
pf_yaml_crlf() { printf 'steps:\r\n  - run: |\r\n      set -o pipefail\r\n      printf x | grep -q x\r\n' > "$S/$PF_YAML"; }
pf_yaml_crlf_clean() { printf 'steps:\r\n  - run: |\r\n      set -o pipefail\r\n      grep -q x file\r\n' > "$S/$PF_YAML"; }
pf_yaml_flow() { printf 'steps:\n  - {name: a, run: "set -o pipefail; printf x | grep -q x"}\n' > "$S/$PF_YAML"; }
pf_yaml_tab() { printf 'steps:\n\t- run: |\n\t\t\tset -o pipefail\n' > "$S/$PF_YAML"; }
pf_yaml_alias() { printf 'steps:\n  - run: *cmd\n  - name: set -o pipefail\n' > "$S/$PF_YAML"; }
pf_yaml_dq_multiline() { printf 'steps:\n  - run: "set -o pipefail;\n      printf x | grep -q x"\n' > "$S/$PF_YAML"; }
pf_yaml_empty_key() { printf 'steps:\n  - run:\n  - name: set -o pipefail\n' > "$S/$PF_YAML"; }
pf_yaml_complex_key() { printf 'steps:\n  - ? run\n    : |\n      set -o pipefail\n      printf x | grep -q x\n' > "$S/$PF_YAML"; }
pf_drop_anchor_pipefail() { sed -i.bak 's/pipefail//' "$SH/template/.lefthook/commit-msg.sh"; }
pf_delete_anchor() { rm -f "$SH/template/.lefthook/commit-msg.sh"; }
fails pipefail_reader_grep_q "$H_PF" pf_grep_q "zz-pipefail-fixture.sh:3: pipe into grep"
fails pipefail_reader_in_yaml_run_block "$H_PF" pf_yaml_run "zz-pipefail-fixture.yml:4: pipe into grep"
fails pipefail_reader_fails_when_anchor_pipefail_dropped "$H_PF" pf_drop_anchor_pipefail "anchor script missing or no longer sets pipefail"
fails pipefail_reader_fails_when_anchor_deleted "$H_PF" pf_delete_anchor "anchor script missing or no longer sets pipefail"
passes pipefail_reader_printf_pipe_reads_to_end "$H_PF" pf_here_string

pf_crash() { pf_script 'set -uo pipefail' "echo $(printf '%.0s\044(' {1..800})"; }
pf_xargs() { pf_script 'set -uo pipefail' 'printf x | xargs grep -q x'; }
pf_xargs_clean() { pf_script 'set -uo pipefail' 'printf x | xargs echo'; }
pf_timeout() { pf_script 'set -uo pipefail' 'printf x | timeout 5 grep -q x'; }
pf_timeout_clean() { pf_script 'set -uo pipefail' 'printf x | timeout 5 cat'; }
pf_stdbuf() { pf_script 'set -uo pipefail' 'printf x | stdbuf -oL grep -q x'; }
pf_sudo() { pf_script 'set -uo pipefail' 'printf x | sudo -n grep -q x'; }
pf_group() { pf_script 'set -uo pipefail' 'printf x | { read -r v; }'; }
pf_group_clean() { pf_script 'set -uo pipefail' 'printf x | { cat; }'; }
pf_group_later() { pf_script 'set -uo pipefail' 'printf x | { cat > /dev/null; grep -q x; }'; }
pf_group_closed() { printf '#!/usr/bin/env bash\nset -uo pipefail\nprintf x | { cat; }\ngrep -q x file\n' > "$S/$PF_FIXTURE"; }
pf_subshell() { pf_script 'set -uo pipefail' 'printf x | (grep -q x)'; }
pf_subshell_clean() { pf_script 'set -uo pipefail' 'printf x | (cat)'; }
pf_loop_break() { pf_script 'set -uo pipefail' 'printf x | while read -r l; do break; done'; }
pf_loop_exit() { pf_script 'set -uo pipefail' 'printf x | while read -r l; do exit 1; done'; }
pf_loop_return() { pf_script 'set -uo pipefail' 'f() { printf x | while read -r l; do return 1; done; }'; }
pf_loop_clean() { pf_script 'set -uo pipefail' "printf x | while read -r l; do echo \"\$l\"; done"; }
pf_loop_inner_break() { pf_script 'set -uo pipefail' 'printf x | while read -r l; do for i in 1; do break; done; done'; }
pf_loop_not_piped() { pf_script 'set -uo pipefail' 'while read -r l; do break; done < file'; }
pf_abbrev() { pf_script 'set -uo pipefail' 'printf x | grep --max=1 x'; }
pf_abbrev_quiet() { pf_script 'set -uo pipefail' 'printf x | grep --qu x'; }
pf_abbrev_clean() { pf_script 'set -uo pipefail' 'printf x | grep --colour x'; }
pf_pipe_amp() { pf_script 'set -uo pipefail' 'printf x |& grep -q x'; }
pf_pipe_amp_clean() { pf_script 'set -uo pipefail' 'printf x |& cat'; }
pf_qF() { pf_script 'set -uo pipefail' 'printf x | grep -qF x'; }
pf_qF_clean() { pf_script 'set -uo pipefail' 'printf x | grep -F x'; }
pf_if_not() { pf_script 'set -uo pipefail' 'if ! printf x | grep -q x; then :; fi'; }
pf_if_not_clean() { pf_script 'set -uo pipefail' "if ! printf '%s\\n' \"\$v\" | grep x >/dev/null; then :; fi"; }
pf_awk_string() { pf_script 'set -uo pipefail' "printf x | awk '\$1 == \"exit\" { print }'"; }
pf_awk_regex() { pf_script 'set -uo pipefail' "printf x | awk '/exit/ { print }'"; }
pf_awk_real_exit() { pf_script 'set -uo pipefail' "printf x | awk '\$1 == \"exit\" { exit }'"; }
pf_arith_shift() { printf '#!/usr/bin/env bash\nset -uo pipefail\n(( x = 1 << 2 ))\nprintf x | grep -q x\n' > "$S/$PF_FIXTURE"; }
pf_arith_clean() { printf '#!/usr/bin/env bash\nset -uo pipefail\n(( x = 1 << 2 ))\ngrep -q x file\n' > "$S/$PF_FIXTURE"; }
fails pipefail_reader_scanner_crash_fails_lint "$H_PF" pf_crash "the scanner stopped early"

# Tokenizer cases run through the extracted scanner directly: one fixture file per case, one Python
# run over all of them, instead of a full skills copy and a full lint per case. pfd <name> <fixture
# function> <"LINE: message" | clean>. The end-to-end cases above cover the wiring (the hit shows up
# in the section, the count guard, the anchors); these cover the tokenizer.
pf_file_opt_clean() { pf_script 'set -uo pipefail' 'printf x | grep --file=pats x'; }
pf_abbrev_m() { pf_script 'set -uo pipefail' 'printf x | grep --m=1 x'; }
pf_abbrev_q() { pf_script 'set -uo pipefail' 'printf x | grep --q x'; }
pf_loop_subshell_exit() { pf_script 'set -uo pipefail' 'printf x | while read -r l; do (exit 1); done'; }
PFD_NAMES=()
PFD_FNS=()
PFD_WANT=()
pfd() {
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  PFD_NAMES+=("$1"); PFD_FNS+=("$2"); PFD_WANT+=("$3")
}
pfd pipefail_reader_grep_Eq pf_grep_Eq "3: pipe into grep"
pfd pipefail_reader_grep_iqE pf_grep_iqE "3: pipe into grep"
pfd pipefail_reader_grep_long_quiet pf_grep_quiet "3: pipe into grep"
pfd pipefail_reader_grep_max_count pf_grep_m1 "3: pipe into grep"
pfd pipefail_reader_head pf_head "3: pipe into head"
pfd pipefail_reader_sed_q pf_sed_q "3: pipe into sed"
pfd pipefail_reader_awk_exit pf_awk_exit "3: pipe into awk"
pfd pipefail_reader_read pf_read "3: pipe into read"
pfd pipefail_reader_multiline_pipe_names_reader_line pf_multiline "4: pipe into grep"
pfd pipefail_reader_inside_command_substitution pf_in_subshell "3: pipe into grep"
pfd pipefail_reader_unclosed_quote_fails pf_unclosed_quote "3: single quote is never closed"
pfd pipefail_reader_no_pipefail_script pf_no_pipefail clean
pfd pipefail_reader_grep_pattern_arg_named_q pf_grep_e_arg clean
pfd pipefail_reader_grep_count pf_grep_count clean
pfd pipefail_reader_grep_invert pf_grep_invert clean
pfd pipefail_reader_sed_substitute pf_sed_s clean
pfd pipefail_reader_awk_exit_in_end_block pf_awk_end_exit clean
pfd pipefail_reader_while_read_loop pf_read_loop clean
pfd pipefail_reader_pipe_inside_quotes pf_quoted_pipe clean
pfd pipefail_reader_pipe_inside_heredoc_body pf_heredoc_body clean
pfd pipefail_reader_pipe_inside_comment pf_comment clean
pfd pipefail_reader_yaml_clean_block pf_yaml_clean clean
pfd pipefail_reader_yaml_non_script_key pf_yaml_other_key clean
pfd pipefail_reader_yaml_plain_continuation pf_yaml_plain_cont "3: pipe into grep"
pfd pipefail_reader_yaml_plain_continuation_clean pf_yaml_plain_cont_clean clean
pfd pipefail_reader_yaml_quoted_key pf_yaml_quoted_key "4: pipe into grep"
pfd pipefail_reader_yaml_quoted_key_clean pf_yaml_quoted_key_clean clean
pfd pipefail_reader_yaml_indent_indicator pf_yaml_indent_ind "4: pipe into grep"
pfd pipefail_reader_yaml_tag_before_header pf_yaml_tagged "4: pipe into grep"
pfd pipefail_reader_yaml_anchor_before_header pf_yaml_anchored "4: pipe into grep"
pfd pipefail_reader_yaml_comment_after_key pf_yaml_comment_after_key "3: pipe into grep"
pfd pipefail_reader_yaml_header_on_next_line pf_yaml_header_next_line "6: pipe into grep"
pfd pipefail_reader_yaml_sibling_between_blocks pf_yaml_sibling_between "8: pipe into grep"
pfd pipefail_reader_yaml_sibling_before_key pf_yaml_sibling_before "7: pipe into grep"
pfd pipefail_reader_yaml_double_quoted_scalar pf_yaml_dq_scalar "2: pipe into grep"
pfd pipefail_reader_yaml_double_quoted_scalar_clean pf_yaml_dq_scalar_clean clean
pfd pipefail_reader_yaml_single_quoted_scalar pf_yaml_sq_scalar "2: pipe into grep"
pfd pipefail_reader_yaml_crlf_block pf_yaml_crlf "4: pipe into grep"
pfd pipefail_reader_yaml_crlf_block_clean pf_yaml_crlf_clean clean
pfd pipefail_reader_yaml_flow_mapping_fails pf_yaml_flow "2: yaml form not understood"
pfd pipefail_reader_yaml_tab_indent_fails pf_yaml_tab "2: yaml form not understood"
pfd pipefail_reader_yaml_alias_fails pf_yaml_alias "2: yaml form not understood"
pfd pipefail_reader_yaml_multiline_quoted_fails pf_yaml_dq_multiline "2: yaml form not understood"
pfd pipefail_reader_yaml_key_without_value_fails pf_yaml_empty_key "2: yaml form not understood"
pfd pipefail_reader_yaml_complex_key_fails pf_yaml_complex_key "2: yaml form not understood"
pfd pipefail_reader_behind_xargs pf_xargs "3: pipe into grep"
pfd pipefail_reader_behind_timeout pf_timeout "3: pipe into grep"
pfd pipefail_reader_behind_stdbuf pf_stdbuf "3: pipe into grep"
pfd pipefail_reader_behind_sudo pf_sudo "3: pipe into grep"
pfd pipefail_reader_in_brace_group pf_group "3: pipe into read"
pfd pipefail_reader_later_in_brace_group pf_group_later "3: pipe into grep"
pfd pipefail_reader_in_subshell_group pf_subshell "3: pipe into grep"
pfd pipefail_reader_piped_loop_break pf_loop_break "3: piped loop body can break"
pfd pipefail_reader_piped_loop_exit pf_loop_exit "3: piped loop body can exit"
pfd pipefail_reader_piped_loop_return pf_loop_return "3: piped loop body can return"
pfd pipefail_reader_abbreviated_max_count pf_abbrev "3: pipe into grep"
pfd pipefail_reader_abbreviated_quiet pf_abbrev_quiet "3: pipe into grep"
pfd pipefail_reader_pipe_ampersand pf_pipe_amp "3: pipe into grep"
pfd pipefail_reader_cluster_qF pf_qF "3: pipe into grep"
pfd pipefail_reader_if_not_pipe pf_if_not "3: pipe into grep"
pfd pipefail_reader_awk_real_exit_after_string pf_awk_real_exit "3: pipe into awk"
pfd pipefail_reader_after_arithmetic_shift pf_arith_shift "4: pipe into grep"
pfd pipefail_reader_xargs_clean pf_xargs_clean clean
pfd pipefail_reader_timeout_clean pf_timeout_clean clean
pfd pipefail_reader_brace_group_clean pf_group_clean clean
pfd pipefail_reader_group_closed_does_not_leak pf_group_closed clean
pfd pipefail_reader_subshell_clean pf_subshell_clean clean
pfd pipefail_reader_piped_loop_clean pf_loop_clean clean
pfd pipefail_reader_piped_loop_inner_break pf_loop_inner_break clean
pfd pipefail_reader_loop_reading_a_file pf_loop_not_piped clean
pfd pipefail_reader_abbreviation_clean pf_abbrev_clean clean
pfd pipefail_reader_pipe_ampersand_clean pf_pipe_amp_clean clean
pfd pipefail_reader_cluster_F_clean pf_qF_clean clean
pfd pipefail_reader_if_not_printf_pipe pf_if_not_clean clean
pfd pipefail_reader_awk_exit_in_string pf_awk_string clean
pfd pipefail_reader_awk_exit_in_regex pf_awk_regex clean
pfd pipefail_reader_arithmetic_shift_is_not_a_heredoc pf_arith_clean clean
pfd pipefail_reader_file_option_clean pf_file_opt_clean clean
pfd pipefail_reader_abbreviated_m_equals pf_abbrev_m "3: pipe into grep"
pfd pipefail_reader_abbreviated_q_long pf_abbrev_q "3: pipe into grep"
pfd pipefail_reader_piped_loop_subshell_exit pf_loop_subshell_exit "3: piped loop body can exit"
# run_pfd — write every registered fixture, run the scanner once, check each case's lines.
run_pfd() {
  local d="$T/pfd" py i f ext out want saveS=${S:-} savePF=$PF_FIXTURE saveY=$PF_YAML
  [[ ${#PFD_NAMES[@]} -gt 0 ]] || return 0
  py=$(awk '/^check_seeded_pipefail_readers\(\)/ { f = 1 } f && /read -r -d .. py <<.PY. \|\| true/ { on = 1; next } on && /^PY$/ { exit } on { print }' "$LINT")
  [[ -n "$py" ]] || { FAIL=$((FAIL + 1)); echo "FAIL: pfd — could not extract the scanner from $LINT"; return 0; }
  rm -rf "$d"; mkdir -p "$d"
  S=$d
  for i in "${!PFD_NAMES[@]}"; do
    ext="sh"
    [[ "${PFD_FNS[$i]}" == pf_yaml* ]] && ext=yml
    PF_FIXTURE="${PFD_NAMES[$i]}.$ext"
    PF_YAML="${PFD_NAMES[$i]}.$ext"
    "${PFD_FNS[$i]}"
  done
  S=$saveS; PF_FIXTURE=$savePF; PF_YAML=$saveY
  f=$(find "$d" -type f | LC_ALL=C sort)
  out=$(xargs python3 -I -c "$py" <<<"$f" 2>&1 || true)
  check "${#PFD_NAMES[@]}" "$(awk '/^DONE / { n += $2 } END { print n + 0 }' <<<"$out")" "pfd: the scanner finished every fixture"
  for i in "${!PFD_NAMES[@]}"; do
    ext="sh"
    [[ "${PFD_FNS[$i]}" == pf_yaml* ]] && ext=yml
    f="$d/${PFD_NAMES[$i]}.$ext"
    want=${PFD_WANT[$i]}
    if [[ "$want" == clean ]]; then
      check "" "$(grep -F "$f:" <<<"$out" | grep -E '^(HIT|PARSE) ' || true)" "${PFD_NAMES[$i]} reports nothing"
    else
      check yes "$(grep -qE "^(HIT|PARSE) $f:$want" <<<"$out" && echo yes || echo no)" "${PFD_NAMES[$i]} reports [$want]"
    fi
  done
}

pool_serial_point

# ── check_seeded_here_strings: the scanner alone on fixture files, plus the wiring ──
# hsd <name> <file body> <"LINE" | clean>: one fixture per case; the scanner runs once over all of them.
H_HS="Seeded pipefail scripts and hooks use no here-string"
HSD_NAMES=()
HSD_FILES=()
HSD_WANT=()
hsd() { HSD_NAMES+=("$1"); HSD_FILES+=("$2"); HSD_WANT+=("$3"); }
HS_PF=$'#!/usr/bin/env bash\nset -uo pipefail\n'
hsd here_string_match_test "${HS_PF}"$'if grep -q x <<< "$v"; then :; fi\n' "3"
hsd here_string_read_array "${HS_PF}"$'read -ra t <<< "$seg"\n' "3"
hsd here_string_loop_feed "${HS_PF}"$'while read -r l; do :; done <<< "$x"\n' "3"
hsd here_string_no_space "${HS_PF}"$'grep -q x <<<"$v"\n' "3"
hsd here_string_inside_command_substitution "${HS_PF}"$'v=$(grep x <<< "$y")\n' "3"
hsd here_string_inside_quoted_substitution "${HS_PF}"$'v="$(grep x <<< "$y")"\n' "3"
hsd here_string_after_quoted_text "${HS_PF}"$'echo "a" \'b\' && grep -q x <<< "$v"\n' "3"
hsd here_string_fed_to_command_stdin "${HS_PF}"$'out=$(bash h.sh <<<"$2")\n' "3"
hsd here_string_in_hook_without_pipefail $'#!/usr/bin/env bash\ngrep -q x <<< "$v"\n' "2"
hsd printf_pipe_is_clean "${HS_PF}"$'printf \'%s\\n\' "$v" | grep x >/dev/null\n' clean
hsd process_substitution_is_clean "${HS_PF}"$'while read -r l; do :; done < <(printf \'%s\\n\' "$x")\n' clean
hsd here_string_in_comment_is_clean "${HS_PF}"$'# grep -q x <<< "$v"\n' clean
hsd here_string_in_single_quotes_is_clean "${HS_PF}"$'awk \'{ gsub(/<<</, ""); print }\' f\n' clean
hsd here_string_in_multiline_awk_is_clean "${HS_PF}"$'x=$(printf a | awk \'\n  { l = $0; gsub(/<<</, "", l) }\n  END { print l }\')\n' clean
hsd here_string_in_double_quotes_is_clean "${HS_PF}"$'echo "use <<< never"\n' clean
hsd here_string_in_heredoc_body_is_clean "${HS_PF}"$'cat <<EOF\ngrep -q x <<< "$v"\nEOF\n' clean
hsd arithmetic_shift_is_clean "${HS_PF}"$'(( x = 1 << 2 ))\n' clean
hsd script_without_pipefail_is_clean $'#!/usr/bin/env bash\nset -u\ngrep -q x <<< "$v"\n' clean
hsd shift_by_variable_keeps_scanning "${HS_PF}"$'x=$((1 << n))\nif grep -q a <<< "$y"; then :; fi\n' "4"
hsd shift_by_digit_keeps_scanning "${HS_PF}"$'x=$((1 << 3))\ngrep -q a <<< "$y"\n' "4"
hsd shift_assignment_keeps_scanning "${HS_PF}"$'(( x <<= n ))\ngrep -q a <<< "$y"\n' "4"
hsd shift_in_double_parens_keeps_scanning "${HS_PF}"$'(( y = 1 << n ))\ngrep -q a <<< "$y"\n' "4"
hsd shift_in_nested_arithmetic_keeps_scanning "${HS_PF}"$'x=$(( (1 << n) + 2 ))\ngrep -q a <<< "$y"\n' "4"
hsd real_heredoc_then_here_string "${HS_PF}"$'cat <<EOF\nbody\nEOF\ngrep -q a <<< "$y"\n' "6"
hsd unterminated_heredoc_fails_closed "${HS_PF}"$'cat <<EOF\nbody\n' "3h"
hsd unterminated_heredoc_without_newline_fails_closed "${HS_PF}"$'cat <<EOF' "3h"
hsd shift_with_no_here_string_is_clean "${HS_PF}"$'x=$((1 << n))\necho "$x"\n' clean
run_hsd() {
  local d="$T/hsd" py i f out want
  py=$(awk '/^check_seeded_here_strings\(\)/ { f = 1 } f && /read -r -d .. py <<.PY. \|\| true/ { on = 1; next } on && /^PY$/ { exit } on { print }' "$LINT")
  [[ -n "$py" ]] || { FAIL=$((FAIL + 1)); echo "FAIL: hsd — could not extract the scanner from $LINT"; return 0; }
  rm -rf "$d"; mkdir -p "$d/hooks"
  for i in "${!HSD_NAMES[@]}"; do
    f="$d/${HSD_NAMES[$i]}.sh"
    [[ "${HSD_NAMES[$i]}" == *_hook_* ]] && f="$d/hooks/${HSD_NAMES[$i]}.sh"
    printf '%s' "${HSD_FILES[$i]}" > "$f"
  done
  out=$(find "$d" -type f | LC_ALL=C sort | xargs python3 -I -c "$py" 2>&1 || true)
  check "${#HSD_NAMES[@]}" "$(awk '/^DONE / { n += $2 } END { print n + 0 }' <<<"$out")" "hsd: the scanner finished every fixture"
  for i in "${!HSD_NAMES[@]}"; do
    f="$d/${HSD_NAMES[$i]}.sh"
    [[ "${HSD_NAMES[$i]}" == *_hook_* ]] && f="$d/hooks/${HSD_NAMES[$i]}.sh"
    want=${HSD_WANT[$i]}
    if [[ "$want" == clean ]]; then
      check "" "$(grep -F "$f:" <<<"$out" || true)" "${HSD_NAMES[$i]} reports nothing"
    elif [[ "$want" == *h ]]; then
      check yes "$(grep -qE "^HIT $f:${want%h}: heredoc " <<<"$out" && echo yes || echo no)" "${HSD_NAMES[$i]} reports line ${want%h}"
    else
      check yes "$(grep -qE "^HIT $f:$want: here-string" <<<"$out" && echo yes || echo no)" "${HSD_NAMES[$i]} reports line $want"
    fi
  done
}
hs_pipefail_fixture() { pf_script 'set -uo pipefail' $'grep -q x <<< "$v"'; }
fails here_string_in_seeded_pipefail_script_fails_the_lint "$H_HS" hs_pipefail_fixture "zz-pipefail-fixture.sh:3: here-string"
hs_mutant_ts() { printf '%s\n' $'grep -q x <<< "$v"' >> "$S/scaffold/shared/template-ts/.claude/hooks/block-no-verify.sh"; }
hs_mutant_py() { printf '%s\n' $'grep -q x <<< "$v"' >> "$S/scaffold/shared/template-py/.claude/hooks/block-no-verify.sh"; }
fails here_string_planted_in_the_ts_block_no_verify_hook_fails_the_lint "$H_HS" hs_mutant_ts "template-ts/.claude/hooks/block-no-verify.sh:"
fails here_string_planted_in_the_py_block_no_verify_hook_fails_the_lint "$H_HS" hs_mutant_py "template-py/.claude/hooks/block-no-verify.sh:"
passes unchanged_block_no_verify_hooks_pass_the_here_string_lint "$H_HS" true
hs_hook_fixture() { printf '%s\n' '#!/usr/bin/env bash' $'grep -q x <<< "$v"' > "$S/scaffold/shared/template-ts/.claude/hooks/zz-fixture.sh"; }
fails here_string_in_a_hook_fails_the_lint "$H_HS" hs_hook_fixture "hooks/zz-fixture.sh:2: here-string"

# ── file line budget: the check alone, on a scratch tree (a full lint per probe is too slow) ──
# lb_probe builds a tree that passes (the clean control), applies one mutation and expects the
# named text. The function under test is cut out of $LINT, so reverting the check fails the probes.
LB_FN=$(awk '/^(skillmd_states|registered_skillmds|line_budget_roots|check_file_line_budget|check_skillmd_description_length)\(\) \{/ { on = 1 } on { print } on && /^}/ { on = 0 }' "$LINT")
LB_HEAD=$(cat <<'EOF'
set -euo pipefail; FAILED=0; header() { :; }; fail() { echo "FAIL: $*"; }; pass() { echo "OK:   $*"; }
report() { if [[ -n "$1" ]]; then echo "$1"; fail "$2"; else pass "$3"; fi; }
SKILLS_DIR=$1; while [[ ${#SKILLS_DIR} -gt 1 && "$SKILLS_DIR" == */ ]]; do SKILLS_DIR=${SKILLS_DIR%/}; done
EOF
)
LB_SH="$LB_HEAD"$'\n'"$LB_FN"$'\n''check_file_line_budget'
LBD="$T/lb"
lb_lines() { awk -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) print "line " i }' > "$LBD/skills/$1"; }
lb_leaf() { # lb_leaf <file> <fenced lines> <prose lines>
  { echo '<!-- ref: x -->'; echo '```bash'; awk -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) print "code " i }'; echo '```'; awk -v n="$3" 'BEGIN { for (i = 1; i < n; i++) print "prose " i }'; } > "$LBD/skills/$1"
}
lb_rows() { printf '# header\n'; printf '%b' "$1"; }
lb_base() {
  rm -rf "$LBD"; mkdir -p "$LBD/tests/golden" "$LBD"/skills/{add/auth,add/database,build,standards/validation-patterns,scaffold/shared/template,scaffold/shared/template-ts,other}
  lb_lines CONVENTIONS.md 150
  { echo '<!-- ref: build/SKILL.md'; awk 'BEGIN { for (i = 2; i <= 12; i++) print "l" i }'; } > "$LBD/skills/build/SKILL.md"
  { echo '---'; echo 'name: add'; echo '---'; awk 'BEGIN { for (i = 1; i <= 90; i++) print "body " i }'; } > "$LBD/skills/add/SKILL.md"
  lb_leaf add/auth/fastapi.md 90 50
  lb_lines add/database/python.md 40
  lb_lines standards/validation-patterns/patterns.md 60
  lb_lines scaffold/shared/kit.md 120
  lb_lines other/x.md 150
  lb_lines scaffold/shared/template/big.md 500
  lb_lines scaffold/shared/template-ts/big.md 500
  : > "$LBD/skills/scaffold/shared/template.manifest"
  lb_leaf add/auth/nestjs.md 250 60
  lb_rows 'add/auth/nestjs.md\t312\t60\n' > "$LBD/tests/golden/line-budget.txt"
}
lb_run() { bash -c "$LB_SH" _ "$LBD/skills$1" 2>&1 || true; }
lb_probe() { # lb_probe <name> <mutation function> <want text>
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  local out
  lb_base
  out=$(lb_run "")
  check 0 "$(grep -c '^FAIL' <<<"$out")" "$1: the clean control fails [$out]"
  check 1 "$(grep -c '^OK' <<<"$out")" "$1: the clean control reports OK [$out]"
  "$2"
  out=$(lb_run "")
  if ! grep -q '^FAIL' <<<"$out" || [[ "$out" != *"$3"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected FAIL with [$3], got [$out]"; else PASS=$((PASS + 1)); fi
}
lb_clean() { # lb_clean <name> <mutation function>: the mutated tree still passes
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  local out
  lb_base
  "$2"
  out=$(lb_run "")
  if grep -q '^FAIL' <<<"$out" || ! grep -q '^OK' <<<"$out"; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected OK, got [$out]"; else PASS=$((PASS + 1)); fi
}
lb_ratchet() { printf '%b' "$1" >> "$LBD/tests/golden/line-budget.txt"; }
lb_over_other() { lb_lines other/y.md 151; }
lb_over_conventions() { lb_lines CONVENTIONS.md 151; }
lb_over_utility() { lb_lines build/SKILL.md 13; }
lb_over_router() { lb_lines add/database/python.md 41; }
lb_over_patterns() { lb_lines standards/validation-patterns/patterns.md 61; }
lb_over_kit() { lb_lines scaffold/shared/kit.md 121; }
lb_over_leaf() { lb_leaf add/auth/fastapi.md 99 50; }
lb_over_entry() { lb_lines add/auth/nestjs.md 314; }
lb_at_entry() { lb_leaf add/auth/nestjs.md 250 60; }
lb_stale_row() { lb_ratchet 'add/auth/gone.md\t200\t60\n'; }
lb_template_row() { lb_ratchet 'scaffold/shared/template/big.md\t500\t-\n'; }
lb_row_trailing_space() { lb_ratchet 'other/y.md\t200\t-  \n'; lb_lines other/y.md 160; }
lb_row_crlf() { lb_ratchet 'other/y.md\t200\t-\r\n'; lb_lines other/y.md 160; }
lb_row_two_columns() { lb_ratchet 'other/y.md\t200\n'; lb_lines other/y.md 160; }
lb_row_non_numeric() { lb_ratchet 'other/y.md\tmany\t-\n'; lb_lines other/y.md 160; }
lb_row_duplicate() { lb_lines other/y.md 160; lb_ratchet 'other/y.md\t200\t-\nother/y.md\t300\t-\n'; }
lb_row_dotdot() { lb_ratchet 'add/../other/x.md\t200\t-\n'; }
lb_row_leaf_dash() { lb_ratchet 'add/auth/fastapi.md\t300\t-\n'; }
lb_row_nonleaf_number() { lb_ratchet 'other/x.md\t200\t60\n'; }
lb_row_registered_skill() { lb_ratchet 'add/SKILL.md\t200\t-\n'; }
lb_row_does_not_hide_growth() { lb_lines other/y.md 160; lb_ratchet 'other/y.md\t200\n'; }
lb_prose_over() { lb_leaf add/auth/fastapi.md 40 51; }
lb_prose_fence_not_counted() { lb_leaf add/auth/fastapi.md 98 50; }
lb_prose_unclosed_fence() { { echo '```bash'; awk 'BEGIN { for (i = 1; i <= 60; i++) print "hidden " i }'; } > "$LBD/skills/add/auth/fastapi.md"; }
lb_prose_closed_long_fence() { { echo '````md'; echo '```'; awk 'BEGIN { for (i = 1; i <= 60; i++) print "inside " i }'; echo '```'; echo '````'; } > "$LBD/skills/add/auth/fastapi.md"; }
lb_ratchet_missing() { rm -f "$LBD/tests/golden/line-budget.txt"; }
lb_ratchet_empty() { : > "$LBD/tests/golden/line-budget.txt"; }
lb_no_files() { rm -rf "$LBD/skills"; mkdir -p "$LBD/skills"; }
lb_big_template_file() { lb_lines scaffold/shared/template/more.md 900; lb_lines scaffold/shared/template-ts/more.md 900; }
lb_probe line_budget_item1_over_cap_without_entry lb_over_other "other/y.md: 151 lines, limit 150"
lb_probe line_budget_conventions_over_150 lb_over_conventions "CONVENTIONS.md: 151 lines, limit 150"
lb_probe line_budget_utility_router_over_12 lb_over_utility "build/SKILL.md: 13 lines, limit 12"
lb_probe line_budget_stack_router_over_40 lb_over_router "add/database/python.md: 41 lines, limit 40"
lb_probe line_budget_patterns_over_60 lb_over_patterns "standards/validation-patterns/patterns.md: 61 lines, limit 60"
lb_probe line_budget_kit_over_120 lb_over_kit "scaffold/shared/kit.md: 121 lines, limit 120"
lb_probe line_budget_leaf_over_150 lb_over_leaf "add/auth/fastapi.md: 151 lines, limit 150"
lb_probe line_budget_item2_over_its_entry lb_over_entry "add/auth/nestjs.md: 314 lines, limit 312"
lb_clean line_budget_at_its_entry_passes lb_at_entry
lb_probe line_budget_item5_stale_row lb_stale_row "add/auth/gone.md, which is no file under skills/"
lb_probe line_budget_item5_row_for_template_file lb_template_row "scaffold/shared/template/big.md, which is no file under skills/"
lb_probe line_budget_item6_trailing_space lb_row_trailing_space "malformed row"
lb_probe line_budget_item6_crlf lb_row_crlf "malformed row"
lb_probe line_budget_item6_missing_column lb_row_two_columns "needs exactly 3 tab-separated columns"
lb_probe line_budget_item6_non_numeric lb_row_non_numeric "max_lines must be a positive integer"
lb_probe line_budget_item6_duplicate lb_row_duplicate "duplicate row for other/y.md"
lb_probe line_budget_item6_dotdot_path lb_row_dotdot "empty, . or .. segment"
lb_probe line_budget_item6_leaf_row_with_dash lb_row_leaf_dash "max_prose must be a number"
lb_probe line_budget_item6_non_leaf_row_with_number lb_row_nonleaf_number "max_prose must be -"
lb_probe line_budget_item6_row_for_registered_skill lb_row_registered_skill "row for registered add/SKILL.md"
lb_probe line_budget_item6_bad_row_does_not_allow_growth lb_row_does_not_hide_growth "other/y.md: 160 lines, limit 150"
lb_probe line_budget_item7_prose_over_50 lb_prose_over "51 prose lines outside fences, limit 50"
lb_clean line_budget_item7_fence_lines_are_not_prose lb_prose_fence_not_counted
lb_probe line_budget_item7_unclosed_fence_does_not_hide_prose lb_prose_unclosed_fence "60 prose lines outside fences"
lb_clean line_budget_item7_long_fence_with_inner_fence_is_one_fence lb_prose_closed_long_fence
lb_probe line_budget_item8_ratchet_missing lb_ratchet_missing "line-budget.txt: missing"
lb_probe line_budget_item8_ratchet_empty lb_ratchet_empty "line-budget.txt: empty"
lb_probe line_budget_scans_something lb_no_files "no .md file found"
lb_clean line_budget_template_trees_are_ignored lb_big_template_file
lb_symlink() { ln -s ../other/x.md "$LBD/skills/other/link.md"; }
lb_nested_skillmd() { mkdir -p "$LBD/skills/add/auth/sub"; { printf -- '---\nname: nested\n---\n'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "b" i }'; } > "$LBD/skills/add/auth/sub/SKILL.md"; }
lb_nameless_skillmd() { { printf -- '---\ndescription: x\n---\n'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "b" i }'; } > "$LBD/skills/other/SKILL.md"; }
lb_crlf_skillmd() { awk 'BEGIN { for (i = 1; i <= 12; i++) printf "l%d\r\n", i }' > "$LBD/skills/build/SKILL.md"; }
lb_bare_cr() { printf 'a\rb\rc\r' > "$LBD/skills/other/y.md"; }
lb_unlisted_leaf() { lb_lines add/auth/vite-react.md 151; }
lb_nameless_short() { { printf -- '---\ndescription: x\n---\n'; awk 'BEGIN { for (i = 1; i <= 8; i++) print "b" i }'; } > "$LBD/skills/other/SKILL.md"; }
lb_body_name_skillmd() { { echo 'intro'; echo 'name: not-frontmatter'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "b" i }'; } > "$LBD/skills/other/SKILL.md"; }
lb_fence_name_skillmd() { { echo '```'; echo 'name: in-a-fence'; echo '```'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "b" i }'; } > "$LBD/skills/other/SKILL.md"; }
lb_short_body_name() { { echo 'intro'; echo 'name: x'; } > "$LBD/skills/other/SKILL.md"; }
lb_probe line_budget_fix5_name_in_body_is_not_registered lb_body_name_skillmd "other/SKILL.md: 22 lines, limit 12"
lb_probe line_budget_fix5_name_in_fence_is_not_registered lb_fence_name_skillmd "other/SKILL.md: 23 lines, limit 12"
lb_clean line_budget_fix5_short_skillmd_with_name_in_body_passes lb_short_body_name
lb_probe line_budget_fix1_symlinked_md lb_symlink "other/link.md: is a symbolic link"
lb_probe line_budget_fix2_nested_skillmd_with_frontmatter lb_nested_skillmd "add/auth/sub/SKILL.md: 23 lines, limit 12"
lb_probe line_budget_fix2_skillmd_frontmatter_without_name lb_nameless_skillmd "other/SKILL.md: 23 lines, limit 12"
lb_clean line_budget_fix2_short_nameless_skillmd_passes lb_nameless_short
lb_probe line_budget_fix4_crlf_skillmd lb_crlf_skillmd "build/SKILL.md: contains a carriage return"
lb_probe line_budget_fix4_bare_cr_file lb_bare_cr "other/y.md: contains a carriage return"
lb_probe line_budget_fix3_unlisted_leaf_over_cap lb_unlisted_leaf "add/auth/vite-react.md: 151 lines, limit 150"
# Round 3: symlinked dirs and any-name links, frontmatter cap, real template roots, markdown variants,
# prose cap for add/ and migrate/ files without a row, unclosed frontmatter, shared registration, last line, CRLF.
lb_symlinked_dir() { mkdir -p "$LBD/real"; awk 'BEGIN { for (i = 1; i <= 9999; i++) print "line " i }' > "$LBD/real/huge.md"; ln -s ../../../real "$LBD/skills/add/auth/bigdir"; }
lb_symlink_not_md() { ln -s x.md "$LBD/skills/other/data.txt"; }
lb_symlink_in_root() { ln -s big.md "$LBD/skills/scaffold/shared/template/link.md"; }
lb_fm_n() { { echo '---'; echo 'name: add'; awk -v n="$1" 'BEGIN { for (i = 1; i < n - 1; i++) print "k" i ": v" }'; echo '---'; awk 'BEGIN { for (i = 1; i <= 90; i++) print "body " i }'; } > "$LBD/skills/add/SKILL.md"; }
lb_fm_500() { lb_fm_n 501; }
lb_fm_9() { lb_fm_n 9; }
lb_fm_8() { lb_fm_n 8; }
lb_template_elsewhere() { mkdir -p "$LBD/skills/add/template"; lb_lines add/template/q.md 900; }
lb_template_real_root() { mkdir -p "$LBD/skills/add/template"; : > "$LBD/skills/add/template.manifest"; lb_lines add/template/q.md 900; }
lb_upper_md() { lb_lines other/x2.MD 10; }
lb_markdown_ext() { lb_lines other/x2.markdown 10; }
lb_lower_md() { lb_lines other/x2.md 10; }
lb_new_add_prose_141() { lb_leaf add/auth/zz.md 5 141; }
lb_new_add_prose_50() { lb_leaf add/auth/zz.md 5 50; }
lb_new_migrate_prose_141() { mkdir -p "$LBD/skills/migrate/general"; lb_leaf migrate/general/zz.md 5 141; }
lb_new_migrate_prose_50() { mkdir -p "$LBD/skills/migrate/general"; lb_leaf migrate/general/zz.md 5 50; }
lb_unclosed_fm() { { echo '---'; echo 'name: x'; awk 'BEGIN { for (i = 1; i <= 5; i++) print "body " i }'; } > "$LBD/skills/add/SKILL.md"; }
lb_unclosed_fm_nameless() { { echo '---'; awk 'BEGIN { for (i = 1; i <= 5; i++) print "body " i }'; } > "$LBD/skills/other/SKILL.md"; }
lb_no_final_newline_150() { lb_lines other/x2.md 149; printf 'last' >> "$LBD/skills/other/x2.md"; }
lb_no_final_newline_151() { lb_lines other/x2.md 150; printf 'last' >> "$LBD/skills/other/x2.md"; }
lb_crlf_fm_name() { { printf -- '---\r\nname: add\r\n---\r\n'; awk 'BEGIN { for (i = 1; i <= 20; i++) printf "b%d\r\n", i }'; } > "$LBD/skills/add/SKILL.md"; }
lb_probe line_budget_r3_symlinked_directory lb_symlinked_dir "add/auth/bigdir: is a symbolic link"
lb_probe line_budget_r3_symlink_not_named_md lb_symlink_not_md "other/data.txt: is a symbolic link"
lb_clean line_budget_r3_symlink_inside_template_root_is_ignored lb_symlink_in_root
lb_probe line_budget_r3_frontmatter_500_lines lb_fm_500 "add/SKILL.md: frontmatter is 500 lines, limit 7"
lb_probe line_budget_r3_frontmatter_8_lines lb_fm_9 "add/SKILL.md: frontmatter is 8 lines, limit 7"
lb_clean line_budget_r3_frontmatter_7_lines_passes lb_fm_8
lb_probe line_budget_r3_template_dir_without_manifest_is_scanned lb_template_elsewhere "add/template/q.md: 900 lines, limit 150"
lb_clean line_budget_r3_template_dir_with_manifest_is_exempt lb_template_real_root
lb_probe line_budget_r3_uppercase_md lb_upper_md "other/x2.MD: markdown files under skills/ must be named *.md in lowercase"
lb_probe line_budget_r3_dot_markdown lb_markdown_ext "other/x2.markdown: markdown files under skills/ must be named *.md in lowercase"
lb_clean line_budget_r3_lowercase_md_passes lb_lower_md
lb_probe line_budget_r3_new_add_file_prose_cap lb_new_add_prose_141 "add/auth/zz.md: 141 prose lines outside fences, limit 50"
lb_clean line_budget_r3_new_add_file_prose_50_passes lb_new_add_prose_50
lb_probe line_budget_r3_new_migrate_file_prose_cap lb_new_migrate_prose_141 "migrate/general/zz.md: 141 prose lines outside fences, limit 50"
lb_clean line_budget_r3_new_migrate_file_prose_50_passes lb_new_migrate_prose_50
lb_probe line_budget_r3_unclosed_frontmatter_registered lb_unclosed_fm "add/SKILL.md: frontmatter has no closing ---"
lb_probe line_budget_r3_unclosed_frontmatter_nameless lb_unclosed_fm_nameless "other/SKILL.md: frontmatter has no closing ---"
lb_clean line_budget_r3_last_line_without_newline_150_passes lb_no_final_newline_150
lb_probe line_budget_r3_last_line_without_newline_151_fails lb_no_final_newline_151 "other/x2.md: 151 lines, limit 150"
lb_probe line_budget_r3_crlf_frontmatter_with_name lb_crlf_fm_name "add/SKILL.md: contains a carriage return"
LB_DESC_SH="$LB_HEAD"$'\n'"$LB_FN"$'\n''check_skillmd_description_length'
lb_desc() { # lb_desc <name> <FAIL|OK> <file prefix lines, \n-escaped> <description length>: the description check alone
  if [[ -n "${ONLY:-}" && ! "$1" =~ $ONLY ]]; then return 0; fi
  local out d
  lb_base
  d=$(awk -v n="$4" 'BEGIN { for (i = 0; i < n; i++) printf "d" }')
  printf '%b' "${3//@D@/$d}" > "$LBD/skills/add/SKILL.md"
  out=$(bash -c "$LB_DESC_SH" _ "$LBD/skills" 2>&1 || true)
  if [[ "$out" != *"$2:"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — expected $2, got [$out]"; else PASS=$((PASS + 1)); fi
}
lb_desc line_budget_r3_desc_registered_151_fails FAIL '---\nname: add\ndescription: @D@\n---\nbody\n' 151
lb_desc line_budget_r3_desc_registered_150_passes OK '---\nname: add\ndescription: @D@\n---\nbody\n' 150
lb_desc line_budget_r3_desc_crlf_registered_151_fails FAIL '---\r\nname: add\r\ndescription: @D@\r\n---\r\nbody\r\n' 151
lb_desc line_budget_r3_desc_name_in_body_only_passes OK '---\ndescription: @D@\n---\nname: add\n' 151
lb_desc line_budget_r3_desc_unclosed_with_name_fails FAIL '---\nname: add\ndescription: @D@\nbody\n' 151
lb_trailing_ws_fm() { { printf -- '---  \nname: add\n---\t\n'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "b" i }'; } > "$LBD/skills/add/SKILL.md"; }
lb_trailing_ws_big_fm() { { printf -- '---  \nname: add\n'; awk 'BEGIN { for (i = 1; i <= 20; i++) print "k" i ": v" }'; printf -- '---\t\n'; } > "$LBD/skills/add/SKILL.md"; }
lb_lower_skillmd() { mkdir -p "$LBD/skills/add/x"; lb_lines add/x/skill.md 10; }
lb_hidden_dir() { mkdir -p "$LBD/skills/add/.hid"; lb_lines add/.hid/a.md 10; }
lb_visible_dir() { mkdir -p "$LBD/skills/add/vis"; lb_lines add/vis/a.md 10; }
lb_mdx_file() { lb_lines other/x2.mdx 10; }
lb_template_symlink() { mkdir -p "$LBD/skills/add/real"; lb_lines add/real/a.md 900; ln -s real "$LBD/skills/add/template"; }
lb_probe line_budget_r4_trailing_whitespace_delimiters_still_register lb_trailing_ws_big_fm "add/SKILL.md: frontmatter is 21 lines, limit 7"
lb_clean line_budget_r4_trailing_whitespace_delimiters_small_frontmatter_passes lb_trailing_ws_fm
lb_probe line_budget_r4_skillmd_in_other_letter_case lb_lower_skillmd "add/x/skill.md: must be named SKILL.md"
lb_probe line_budget_r4_hidden_directory lb_hidden_dir "add/.hid: hidden directory under skills/"
lb_clean line_budget_r4_visible_directory_passes lb_visible_dir
lb_probe line_budget_r4_mdx_file lb_mdx_file "other/x2.mdx: markdown files under skills/ must be named *.md in lowercase"
lb_probe line_budget_r4_symlink_named_template_is_not_a_root lb_template_symlink "add/template: is a symbolic link"
lb_desc line_budget_r4_desc_over_cap_frontmatter_still_checked FAIL '---\nname: add\ndescription: @D@\n'"$(awk 'BEGIN { for (i = 1; i <= 20; i++) printf "k%d: v\\n", i }')"'---\nbody\n' 151
lb_slash_agrees() {
  [[ -n "${ONLY:-}" && ! "line_budget_slash_agrees" =~ $ONLY ]] && return 0
  lb_base; lb_over_other
  check "$(lb_run "")" "$(lb_run "/")" "line_budget_slash_and_no_slash_agree"
}
lb_slash_agrees
fails line_budget_is_wired_into_the_lint "file line budget" lb_over_other_full "zz/y.md: 151 lines, limit 150"

run_pfd
run_hsd
collect
echo "lint-skills.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
