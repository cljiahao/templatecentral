#!/usr/bin/env bash
# scripts/lint-skills.sh — mechanical pattern checks for templateCentral skills
#
# Usage:  bash scripts/lint-skills.sh [SKILLS_DIR]   (run from the repo root; default: skills)
#
# HOW TO ADD A NEW CHECK
# 1. Write a check_* function: header, collect offending lines (usually via scan), then report.
# 2. Comment WHY the pattern is banned and when to revisit it.
# 3. Call the function in the "Run all checks" section at the bottom.
# 4. Mark ecosystem-era checks (tied to a specific stack version) ECOSYSTEM-ERA so future
#    maintainers revisit them when the stack upgrades.
#
# TIMELESS checks: always wrong regardless of stack version.
# ECOSYSTEM-ERA checks: correct for the current stack; review on major upgrades.
#
# This runs after every Edit/Write in this repo, so keep checks to one process per file set:
# no per-file or per-line subshells.

set -euo pipefail

SKILLS_DIR="${1:-skills}"
# One spelling of the root: every path below is built as "$SKILLS_DIR/...", so a trailing slash
# (CI passes "skills/") would give "skills//..." and break string comparisons between paths.
while [[ ${#SKILLS_DIR} -gt 1 && "$SKILLS_DIR" == */ ]]; do SKILLS_DIR=${SKILLS_DIR%/}; done
FAILED=0

# HARNESS_SCHEMA_VERSION — the AGENTS.md line-1 marker (`<!-- templateCentral: <stack>@X.Y.Z -->`)
# is a MIGRATION SCHEMA FLOOR, not the plugin's semver. migrate Phase 0 reads it as
# "@<this> or later → no migration needed". It must stay PINNED at the version where the
# current harness structure was established, and only bump when the harness structure changes
# in a breaking way (a major release). Do NOT bump it every plugin release — that would make
# every existing project falsely report "needs migration". Contrast with `templatecentral_version`
# in harness.json, which tracks plugin semver and is checked against plugin.json separately.
#
# v5.0.0 — seeded project skills use directory form `.claude/skills/<name>/SKILL.md`. Flat skill
# files are silently ignored by Claude Code (flat files only work under `.claude/commands/`).
# Projects seeded below v5.0.0 must run `templatecentral:migrate` to convert them.
#
# v6.0.0 — settings.json hooks use the exec form `"command": "<bin>", "args": [...]` with
# `${CLAUDE_PROJECT_DIR}`-anchored script paths; an array-valued `"command": [...]` is silently
# ignored by Claude Code. Projects marked below v6.0.0 carry inert hooks and must re-sync
# settings.json + hooks from the harness kit via `templatecentral:migrate`.
HARNESS_SCHEMA_VERSION="6.0.0"

fail() { echo "FAIL: $*"; FAILED=1; }
pass() { echo "OK:   $*"; }
header() { echo ""; echo "── $* ──"; }

# report <offending-lines> <fail-msg> <pass-msg>
report() {
  if [[ -n "$1" ]]; then
    echo "$1"
    fail "$2"
  else
    pass "$3"
  fi
}

# scan <grep-flags> <pattern> [exclude...] — `grep -rn` hits under SKILLS_DIR, minus lines
# matching any exclude (basic regex). Pass "" for no extra flags.
# The scaffold template trees (skills/scaffold/shared/template*/) are shipped files that land in every
# scaffolded project, so every rule scans them like any other skill file. A rule that must skip them
# passes the exclude 'scaffold/shared/template'; each such exclusion states its reason where it is used.
scan() {
  local flags=$1 pattern=$2 hits ex
  shift 2
  hits=$(grep -rn ${flags:+"$flags"} -- "$pattern" "$SKILLS_DIR/" 2>/dev/null || true)
  for ex in "$@"; do
    [[ -n "$hits" ]] || break
    hits=$(grep -v -- "$ex" <<<"$hits" || true)
  done
  printf '%s' "$hits"
}

have_python() { command -v python3 >/dev/null 2>&1; }

# TEMPLATED_STACKS — the stacks whose verbatim files live in skills/scaffold/<stack>/template and
# template-agents (listed in <stack>/template.manifest). Add a stack here once its files live in `template/`.
TEMPLATED_STACKS=(nextjs fastapi)
# The trees the manifests list. template-tail files are appended to AGENTS.md, never copied as files.
SHARED_TREES="template template-ts template-py template-ci template-settings-ts template-settings-py template-late template-tail"
STACK_TREES="template template-agents template-tail"

# template_files — every file in the scaffold template trees, one path per line. The trees are
# named explicitly (not matched by a path glob), so a checkout directory whose name contains
# "template" cannot widen the set, and a missing shared/ or stack directory yields no paths.
template_files() {
  local d st
  {
    for d in $SHARED_TREES; do
      find "$SKILLS_DIR/scaffold/shared/$d" -type f 2>/dev/null
    done
    for st in ${TEMPLATED_STACKS[@]+"${TEMPLATED_STACKS[@]}"}; do
      for d in $STACK_TREES; do
        find "$SKILLS_DIR/scaffold/$st/$d" -type f 2>/dev/null
      done
    done
  } | LC_ALL=C sort
}

# ── TIMELESS ──────────────────────────────────────────────────────────────────

check_no_cve_identifiers() {
  # CVE IDs drift — advisories get patched, re-scored, or superseded.
  # Skills must not reference CVE-XXXX-NNNNN. Use "security advisory" language instead.
  header "CVE identifiers"
  report "$(scan "" 'CVE-[0-9]\{4\}-[0-9]\+')" \
    "CVE identifiers found — replace with 'security advisory' language" \
    "No CVE identifiers"
}

check_no_jurisdiction_specific() {
  # templateCentral is industry- and country-neutral, so known jurisdiction-specific framework
  # names must not appear in skills. Extend the list when a new term is discovered; remove one
  # only if the project explicitly targets that jurisdiction.
  # audit/implementation.md is excluded — it names these patterns in its C6 check. TIMELESS.
  header "Jurisdiction-specific content"
  local pattern='GDPR|CCPA|FISMA|IM8|MAS TRM|GCC2\.0|NRIC|SingPass|MyInfo|PDPA|HIPAA|PCI.DSS|SOC 2|FedRAMP|DISA STIG|NIST SP 800-63'
  report "$(scan -E "$pattern" 'audit/implementation' 'CONVENTIONS.md')" \
    "Jurisdiction-specific content found — skills must be country/industry neutral" \
    "No jurisdiction-specific content"
}

check_no_hardcoded_secrets() {
  # Real secret values must never appear in skill code examples.
  # Safe: placeholders (<your-secret>), change-me strings, env refs (${VAR}), comments (#).
  # POSIX ERE (not grep -P, which silently no-ops on stock macOS BSD grep); the negative
  # lookaheads a PCRE pattern would use are emulated by the grep -v chain. TIMELESS.
  header "Hardcoded secrets"
  local matches
  matches=$(grep -rniE '(secret|api_key|password|database_url|better_auth_secret|private_key|access_token)[[:space:]]*=[[:space:]]*.{8,}' "$SKILLS_DIR/" 2>/dev/null \
    | grep -vE '=[[:space:]]*[<$'"'"'\\]' \
    | grep -vi 'change.me\|change-me\|your[-_]\|example\|placeholder\|changeme' \
    | grep -vE '=[[:space:]]*[a-zA-Z_]+[[(.]' \
    | grep -vE '=[[:space:]]*await ' \
    | grep -vE '=[[:space:]]*[A-Z_]{4,}' \
    | grep -v 'postgresql://\|mysql://\|mongodb://\|https://\|http://' \
    || true)
  report "$matches" \
    "Potential hardcoded secrets — use placeholder syntax (e.g. <your-secret>)" \
    "No hardcoded secrets"
}

check_no_comment_narration() {
  # Change-narration comments rot once the change is no longer recent — same doctrine as
  # comments.md, applied here to scripts/*.sh, bash fences in skill markdown and the comments of the
  # seeded template files (# comments in shell, yaml, toml and python; // comments in .cjs).
  header "Change-narration comments"
  local patterns="$SKILLS_DIR/scaffold/shared/template/.claude/comment-hygiene-patterns.txt"
  if [[ ! -f "$patterns" ]]; then
    fail "Missing $patterns"
    return
  fi
  local tmp matches
  tmp=$(mktemp -d)
  # This check blocks CI (lint-patterns has no bypass label), so — like the CI gate seeded into
  # scaffolded projects — it reads only the first 10 (anchored keyword) lines, never the last 3
  # (date/ticket/issue-ref), which false-positive on legitimate terms like UTF-8/SHA-256/RFC-7231.
  head -n 10 "$patterns" > "$tmp/patterns"
  # Comment bodies go to stdout and their source file to the line-aligned "src" file, so the
  # patterns (anchored with ^) only ever see the comment text, never the path prefix.
  # shellcheck disable=SC2016  # awk program: $0 is awk's, not the shell's.
  local extract='
    FNR == 1 { in_bash = 0 }
    FILENAME ~ /\.md$/ {
      if ($0 == "```bash") { in_bash = 1; next }
      if ($0 == "```") { in_bash = 0; next }
      if (!in_bash) next
    }
    FILENAME ~ /\.cjs$/ {
      if ($0 ~ /^[[:space:]]*\/\//) {
        body = $0
        sub(/^[[:space:]]*\/\/[[:space:]]?/, "", body)
        if (body != "") { print body; print FILENAME >> src }
      }
      next
    }
    /^[[:space:]]*#/ {
      body = $0
      sub(/^[[:space:]]*#[[:space:]]?/, "", body)
      if (body != "") { print body; print FILENAME >> src }
    }'
  : > "$tmp/src"
  awk -v src="$tmp/src" "$extract" scripts/*.sh > "$tmp/text" 2>/dev/null || true
  find "$SKILLS_DIR" -name '*.md' -exec awk -v src="$tmp/src" "$extract" {} + >> "$tmp/text"
  # The seeded shell scripts are real files under the template trees; they must be scanned too.
  local tpl_files
  tpl_files=$(template_files | grep -E '\.(sh|yml|yaml|toml|py|cjs)$' || true)
  if [[ -z "$tpl_files" ]]; then
    rm -rf "$tmp"
    fail "No template files under $SKILLS_DIR/scaffold/shared/template*/ — nothing to scan for change-narration comments"
    return
  fi
  # shellcheck disable=SC2086  # newline-separated paths without spaces
  awk -v src="$tmp/src" "$extract" $tpl_files >> "$tmp/text"
  matches=$(grep -nEf "$tmp/patterns" "$tmp/text" \
    | awk 'NR == FNR { file[NR] = $0; next }
           { n = $0; sub(/:.*/, "", n); sub(/^[0-9]+:/, ""); print file[n] ": " $0 }' "$tmp/src" - \
    || true)
  rm -rf "$tmp"
  report "$matches" \
    "Change-narration comments found — state WHAT the code does now, not what changed" \
    "No change-narration comments"
}

check_no_ghost_agent_names() {
  # Ghost agent / skill names that must never appear as invocations in skill files:
  #   shared-(build|review|test|update|cleanup)-agent → de-registered; use the cat-path contract
  #   <stack>-scaffold → templatecentral:scaffold
  #   templatecentral:shared-migrate, shared-migrate-database → templatecentral:migrate
  #   templatecentral:shared-audit → /tc-audit
  #   shared-code-standards / <stack>-code-standards → templatecentral:standards
  #   nextjs-add-auth → templatecentral:add (auth)
  #   templatecentral:(build|test|review|cleanup) — utilities with no `name:` frontmatter, so they
  #     cannot be invoked as skills; reference them as
  #     `<name> utility (cat skills/<name>/SKILL.md via plugin root)`
  #   templatecentral:(audit|write-skill) — repo-internal project skills (.claude/skills/), not
  #     shipped; use /tc-audit and /tc-write-skill
  # Legitimate shipped registered skills: templatecentral:scaffold, :add, :migrate, :standards.
  # audit/implementation.md and CONVENTIONS.md are excluded — they document the banned names.
  header "Ghost agent / skill names"
  # shellcheck disable=SC2016  # literal backticks/colons are regex content, not shell expansions
  report "$(scan -E \
    '`shared-(build|review|test|update|cleanup)-agent`|templatecentral:(fastapi|nestjs|nextjs|vite-react)-scaffold|templatecentral:shared-migrate|`shared-migrate-database`|templatecentral:shared-audit|`shared-code-standards`|`(fastapi|nestjs|nextjs|vite-react)-code-standards`|`nextjs-add-auth`|templatecentral:(build|test|review|cleanup|audit|write-skill)' \
    'audit/implementation' 'CONVENTIONS\.md')" \
    "Ghost agent/skill name — templatecentral:(build|test|review|cleanup) are de-registered utilities (load via cat-path). templatecentral:audit / :write-skill moved to repo-internal project skills /tc-audit / /tc-write-skill (.claude/skills/) and must not be referenced from shipped skills/. Registered shipped skills (invoke normally): templatecentral:scaffold, :add, :migrate, :standards" \
    "No ghost agent/skill names"
}

check_skillmd_description_length() {
  # SKILL.md description: lines longer than 150 chars are truncated in the Claude Code skill picker,
  # causing the skill's purpose to be invisible to the user. Registered SKILL.md (has name:) only —
  # utility SKILL.md files without name: are loading stubs, not displayed. TIMELESS.
  header "SKILL.md description length (<=150 chars)"
  # Measured in bash, not awk: ${#desc} counts characters, while BSD awk length() counts bytes.
  local bad="" f desc
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    grep -q '^name:' "$f" || continue
    desc=$(grep -m1 '^description:' "$f" | sed 's/^description:[[:space:]]*//')
    [[ ${#desc} -gt 150 ]] && bad+="$f (${#desc} chars)"$'\n'
  done
  report "${bad%$'\n'}" \
    "SKILL.md description exceeds 150 chars — shorten it so it displays fully in the skill picker" \
    "All registered SKILL.md descriptions <=150 chars"
}

check_ref_file_headers() {
  # Every reference .md file under skills/ (except SKILL.md and CONVENTIONS.md) must begin with
  # a <!-- ref: --> comment so agents know the file's load path and purpose without reading the body.
  # Missing headers cause agents to silently skip context about how to load the file. TIMELESS.
  # The files under scaffold/*/template*/ are shipped verbatim into every scaffolded project (the
  # AGENTS.md seed starts with its own schema marker on line 1), so they are not reference files and
  # are skipped. A skills tree with no reference file at all fails, so the check cannot pass on nothing.
  header "Ref file <!-- ref: --> headers"
  local bad="" f firstline n=0
  while IFS= read -r f; do
    n=$((n + 1))
    firstline=""
    IFS= read -r firstline < "$f" || true
    [[ "$firstline" == "<!-- ref:"* ]] || bad+="$f"$'\n'
  done < <(find "$SKILLS_DIR" -name '*.md' ! -name 'SKILL.md' ! -name 'CONVENTIONS.md' ! -path '*/scaffold/*/template*/*' 2>/dev/null)
  [[ "$n" -gt 0 ]] || bad+="$SKILLS_DIR: no reference .md file found — the header check scanned nothing"$'\n'
  report "${bad%$'\n'}" \
    "Ref file missing <!-- ref: --> on line 1 — add a ref header following CONVENTIONS.md §2" \
    "All ref files have <!-- ref: --> headers"
}

check_skillmd_body_length() {
  # Registered SKILL.md bodies must be <=30 lines (CONVENTIONS §3). TIMELESS.
  # A long body bloats the skill picker tooltip and forces agents to read unnecessary prose
  # before they can delegate to the appropriate ref file.
  header "SKILL.md body length (<=30 lines)"
  local bad
  bad=$(awk '
    function flush() { if (f != "" && registered && NR_f - fm_end > 30) print f " (" NR_f - fm_end " lines)" }
    FNR == 1 { flush(); f = FILENAME; registered = 0; dashes = 0; fm_end = 0 }
    { NR_f = FNR }
    /^name:/ { registered = 1 }
    /^---$/ && ++dashes == 2 { fm_end = FNR }
    END { flush() }' "$SKILLS_DIR"/*/SKILL.md)
  report "$bad" \
    "SKILL.md body exceeds 30 lines — move prose into an implementation.md ref file" \
    "All registered SKILL.md bodies <=30 lines"
}

check_nesting_depth() {
  # Skills nested more than 3 directory levels under skills/ are unreachable by templateCentral's
  # ref-file loader and indicate a structure drift from CONVENTIONS.md §1. TIMELESS.
  # The depth is counted from the normalised directory name, so "skills" and "skills/"
  # agree: NF>5 catches skills/a/b/c/d/file.md (4+ dirs deep). The files under scaffold/*/template*/
  # are shipped into projects (they mirror a project's own layout), so they are not skill reference
  # files and are skipped.
  header "Nesting depth (<=3 levels under skills/)"
  local base dir=$SKILLS_DIR
  base=$(awk -F'/' '{print NF}' <<<"$dir")
  report "$(find "$dir" -name '*.md' ! -name 'SKILL.md' ! -name 'CONVENTIONS.md' ! -path '*/scaffold/*/template*/*' \
    | awk -F'/' -v base="$base" 'NF > base + 4')" \
    "File nested >3 levels under skills/ — restructure to match CONVENTIONS.md §1" \
    "No files nested >3 levels under skills/"
}

check_seeded_skills_scope_tools() {
  # Seeded project skills (*-verify, *-migrate) embedded in scaffold templates are written into
  # every scaffolded project. They must declare allowed-tools: with no bare Bash token — bare Bash
  # grants unrestricted shell access (opposite of least-agency). Mixed tool lists like
  # "Read, Edit, Write, Bash(pnpm *), Grep, Glob" are accepted; bare "Bash" (not followed by '(')
  # is rejected. TIMELESS: least-agency (OWASP Agentic ASI02) — seeded skills scope their tools.
  header "Seeded project skills declare scoped allowed-tools"
  local files
  files=$(grep -rlE '^name: [a-z][a-z-]*-(verify|migrate)$' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -z "$files" ]]; then
    pass "No seeded *-verify/*-migrate skills found"
    return
  fi
  # shellcheck disable=SC2086  # word-splitting is intentional: $files is newline-separated paths
  report "$(awk '
    /^name: [a-z][a-z-]*-(verify|migrate)$/ { inblock=1; nm=$2; has_tools=0; bare_bash=0; ln=FNR; next }
    inblock && /^allowed-tools:/ {
      has_tools=1
      if ($0 ~ /Bash[^(]/ || $0 ~ /Bash$/) { bare_bash=1 }
      next
    }
    inblock && /^---[[:space:]]*$/ {
      if (!has_tools) print FILENAME":"ln": "nm" - missing allowed-tools"
      else if (bare_bash) print FILENAME":"ln": "nm" - bare Bash in allowed-tools (must be scoped, e.g. Bash(pnpm *))"
      inblock=0
    }
  ' $files 2>/dev/null || true)" \
    "Seeded skill missing scoped allowed-tools — add e.g. 'allowed-tools: Bash(pnpm *)' to its frontmatter" \
    "All seeded project skills declare scoped allowed-tools"
}

check_no_unscoped_bash_grant() {
  # An allowed-tools: line that grants bare 'Bash' (not 'Bash(...)') hands the skill unrestricted
  # shell access — the opposite of least-agency. Every Bash grant must be scoped to a command prefix.
  # TIMELESS: OWASP Agentic ASI02 (Tool Misuse) — never grant unscoped Bash.
  header "No unscoped Bash in allowed-tools grants"
  report "$(scan -E '^allowed-tools:.*\bBash\b' 'Bash(')" \
    "Unscoped 'Bash' in allowed-tools — scope it (e.g. Bash(pnpm *), Bash(git *))" \
    "No unscoped Bash grants"
}

check_seeded_skill_paths_are_directories() {
  # A Claude Code skill is a DIRECTORY with SKILL.md as the entrypoint — flat
  # .claude/skills/<name>.md files are silently ignored (flat files are only valid under
  # .claude/commands/). A seeding instruction that writes the flat form ships a skill that never
  # loads, and nothing at scaffold time catches it. Concrete flat paths (next-verify.md,
  # <stack>-verify.md, next-migrate.md, ...) are banned; the generic '<name>.md' placeholder in
  # explanatory prose is allowed — it documents the anti-pattern.
  # ECOSYSTEM-ERA: skill-discovery rule per current Claude Code docs (directory + SKILL.md entrypoint).
  header "Seeded project skills use directory form (.claude/skills/<name>/SKILL.md)"
  # shellcheck disable=SC2016  # the pattern is a regex, not a shell expansion
  if [[ -z "$(scan -E '\.claude/skills/[a-zA-Z<][a-zA-Z<>-]*-verify/SKILL\.md')" ]]; then
    fail "No .claude/skills/<name>-verify/SKILL.md seeding path found anywhere — the check below would scan nothing"
    return
  fi
  report "$(scan -E '\.claude/skills/[a-zA-Z<][a-zA-Z<>-]*-(verify|migrate)\.md')" \
    "Flat .claude/skills/<name>.md seeding path found — skills are directories; use .claude/skills/<name>/SKILL.md (flat files only work under .claude/commands/)" \
    "No flat .claude/skills/<name>.md seeding paths"
}

check_no_toplevel_command_in_hooks() {
  # Hook commands that read the bash command from top-level `d.command` (or Python d.get('command'))
  # instead of `d.tool_input.command` will silently get an empty string — the check never fires.
  # For Bash tool events, the command lives at tool_input.command, not at the top level.
  # TIMELESS: Claude Code hook stdin schema places tool input under tool_input; this is by design.
  header "Top-level d.command access in hook commands (should be d.tool_input.command)"
  local hook_files
  hook_files=$( { template_files | grep '/\.claude/hooks/' | while IFS= read -r f; do grep -l 'tool_input' "$f" || true; done; } || true)
  if [[ -z "$hook_files" ]]; then
    fail "No template hook reads tool_input — the check below would scan no hook"
    return
  fi
  report "$(scan "" 'd\.command\|d\[.command.\]\|d\.get(.command.' 'tool_input' 'audit/implementation')" \
    "Hook reads bash command from top-level d.command — use d.tool_input.command (or d.get('tool_input',{}).get('command','') in Python)" \
    "No top-level d.command access in hook commands"
}

check_hook_command_uses_args_array() {
  # Hook definitions must use Claude Code's exec form: a STRING "command" naming the binary plus
  # an "args" array — "command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh"].
  # Three failure modes, each silent at runtime:
  #   (1) "command": [ ... ] — an array-valued command is not a valid hook; Claude Code skips the
  #       hook without any error, so the guard simply never runs.
  #   (2) A .claude/hooks/ path without the ${CLAUDE_PROJECT_DIR} prefix — hooks execute in
  #       Claude's current working directory, so a relative path breaks as soon as Claude cd's
  #       into a subdirectory. Claude Code substitutes ${CLAUDE_PROJECT_DIR} in command and args.
  #   (3) A shell-string command ("command": "bash .claude/hooks/x.sh") — runs through a shell,
  #       so the path is subject to word-splitting/interpolation; the exec form passes argv
  #       directly with no shell in between.
  # Every "command"/"args" key in skills/ that mentions .claude/hooks/ is a hook definition.
  # TIMELESS: string command + args[] is the documented exec form.
  header "Hook commands use exec form (string command + args[]) with \${CLAUDE_PROJECT_DIR} paths"
  local bad="" m v n f
  # The settings.json bodies are the files in template-settings-ts/ and template-settings-py/; a
  # settings file with no hook definition left would let every pattern below pass on nothing.
  for v in ts py; do
    f="$SKILLS_DIR/scaffold/shared/template-settings-$v/.claude/settings.json"
    n=$(grep -cE '"args"[[:space:]]*:.*\.claude/hooks/' "$f" 2>/dev/null || true)
    [[ "${n:-0}" -ge 1 ]] || bad+="$f: no hook definition found to check"$'\n'
  done
  m=$(scan -E '"command"[[:space:]]*:[[:space:]]*\[')
  [[ -n "$m" ]] && bad+="$m"$'\n'"  ^ array-valued \"command\" is silently ignored by Claude Code — use \"command\": \"bash\", \"args\": [...]"$'\n'
  # shellcheck disable=SC2016  # ${CLAUDE_PROJECT_DIR} is a literal pattern, not an expansion.
  m=$(scan -E '"(command|args)"[[:space:]]*:.*\.claude/hooks/' \
      | sed 's#\${CLAUDE_PROJECT_DIR}/\.claude/hooks/#__OK__#g' | grep -F '.claude/hooks/' || true)
  [[ -n "$m" ]] && bad+="$m"$'\n'"  ^ hook script path must be \${CLAUDE_PROJECT_DIR}/.claude/hooks/... (hooks run in Claude's current dir)"$'\n'
  m=$(scan -E '"command"[[:space:]]*:[[:space:]]*"[^"]*[[:space:]][^"]*\.claude/hooks/')
  [[ -n "$m" ]] && bad+="$m"$'\n'"  ^ shell-string hook command — use exec form: \"command\": \"bash\", \"args\": [\"\${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh\"]"$'\n'
  # shellcheck disable=SC2016  # ${CLAUDE_PROJECT_DIR} is literal message text
  report "$bad" \
    'Hook command form invalid — use "command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]' \
    "All hook commands use exec form with \${CLAUDE_PROJECT_DIR}-anchored script paths"
}

check_scaffold_seeds_complete_harness() {
  # The shared harness kit (skills/scaffold/shared/harness-kit*.md — an index plus ts/fastapi
  # variant files and the shared enforcement/finalize files) is the single source of truth for the
  # complete harness: all 6 hook events, the permissions.deny secret-Read block,
  # skillListingBudgetFraction, the .claude/hooks/ script bodies, stop_hook_active guard,
  # CONSTITUTION.md, FUTURE.md, harness.json step, .agents symlink, and the shared AGENTS.md tail.
  # Each of the 4 scaffold source-files.md and migrate/general/implementation.md must load the
  # index, the two shared files, and exactly the right variant, and each variant must carry the
  # full per-stack hook set — this keeps the harness enforceable from one kit rather than 5 copies,
  # while a run loads only its own stack's bodies.
  # The hook, lefthook, gitleaks and CI bodies are real files under shared/template*/ (copied by
  # harness-kit.md Step 0 and the Step B3 CI copy), so the body tokens are read from those files and
  # the check fails when an expected file, or the copy instruction itself, is missing.
  # TIMELESS: these are the load-bearing enforcement hooks; their presence is non-negotiable.
  header "Scaffold/migrate templates seed the complete harness"

  local kit_dir="$SKILLS_DIR/scaffold/shared"
  local kit_files=(
    "$kit_dir/harness-kit.md" "$kit_dir/harness-kit-ts.md" "$kit_dir/harness-kit-fastapi.md"
    "$kit_dir/harness-kit-enforcement.md" "$kit_dir/harness-kit-finalize.md"
  )
  # migrate loads the kit from its router (keeps chains at 2 cat hops); Phase 4 seeds the skill.
  local migrate="$SKILLS_DIR/migrate/general/implementation.md"
  local migrate_phase4="$SKILLS_DIR/migrate/general/phase-4-upgrade.md"
  local scaffolds=(
    "$SKILLS_DIR/scaffold/fastapi/source-files.md"
    "$SKILLS_DIR/scaffold/nestjs/source-files.md"
    "$SKILLS_DIR/scaffold/nextjs/source-files.md"
    "$SKILLS_DIR/scaffold/vite-react/source-files.md"
  )
  local kit_tokens=(
    '"PreToolUse"' '"UserPromptSubmit"' '"PostToolUse"'
    '"Stop"' '"SubagentStop"' '"SessionStart"'
    'skillListingBudgetFraction' '"Read(.env)"' '"Read(**/.env)"'
    'protect-files.sh' 'block-no-verify.sh' 'user-prompt-guard'
    'post-edit-typecheck.sh' 'stop-checks.sh'
    'subagent-stop.sh' 'session-context.sh'
    # Content-authoring token, not just a path reference: every consumer (settings.json,
    # harness.json, protect-files.sh) can point at comment-hygiene-patterns.txt while the kit never
    # authors it, and verify-harness.sh then hard-fails on MISSING for every fresh scaffold.
    '[Ww][Aa][Ss][[:space:]]'
  )
  # Every per-stack variant file must author the full stack-specific set on its own — a run
  # loads exactly one variant, so a token present only in the other variant never reaches it.
  local variant_tokens=(
    '"PreToolUse"' '"UserPromptSubmit"' '"PostToolUse"'
    '"Stop"' '"SubagentStop"' '"SessionStart"'
    'skillListingBudgetFraction' '"Read(.env)"'
    '.claude/hooks/protect-files.sh' '.claude/hooks/block-no-verify.sh' '.claude/hooks/user-prompt-guard.'
    '.claude/hooks/post-edit-typecheck.sh' '.claude/hooks/post-edit-comment-check.sh'
    '.claude/hooks/stop-checks.sh' '.claude/hooks/subagent-stop.sh'
    'lefthook.yml'
  )
  # Body tokens are read from the one file that must carry them, not from a haystack of every file:
  # a token that survives in some other file must not hide its removal from the file that needs it.
  local file_tokens=(
    "template-ts/.claude/hooks/user-prompt-guard.cjs|AKIA" "template-py/.claude/hooks/user-prompt-guard.py|AKIA"
    "template-ts/.claude/hooks/stop-checks.sh|stop_hook_active" "template-py/.claude/hooks/stop-checks.sh|stop_hook_active"
    "template-ts/.claude/hooks/subagent-stop.sh|stop_hook_active" "template-py/.claude/hooks/subagent-stop.sh|stop_hook_active"
    "template-ts/.claude/hooks/block-no-verify.sh|--no-verify" "template-py/.claude/hooks/block-no-verify.sh|--no-verify"
    "template-ts/.claude/hooks/protect-files.sh|node -e" "template-py/.claude/hooks/protect-files.sh|python3 -c"
    "template/.claude/hooks/session-context.sh|CONSTITUTION"
  )
  local missing="" tok f kf all_kit="" v other tdir hay p
  for kf in "${kit_files[@]}"; do
    [[ -f "$kf" ]] || missing+="$kf — file not found"$'\n'
  done
  # Template files every scaffold copies, per tree; the variant trees must each hold the full hook set.
  local shared_files=(
    .claude/hooks/session-context.sh .claude/hooks/skill-usage-log.sh .claude/ci-gates.sh
    .claude/verify-harness.sh .claude/regen-harness.sh .claude/comment-hygiene-patterns.txt
    .lefthook/commit-msg.sh .gitleaks.toml
  )
  local variant_files=(
    .claude/hooks/protect-files.sh .claude/hooks/block-no-verify.sh .claude/hooks/post-edit-typecheck.sh
    .claude/hooks/post-edit-comment-check.sh .claude/hooks/stop-checks.sh .claude/hooks/subagent-stop.sh lefthook.yml
  )
  for p in "${shared_files[@]}"; do
    [[ -f "$kit_dir/template/$p" ]] || missing+="$kit_dir/template/$p — template file not found"$'\n'
  done
  for tdir in ts py; do
    for p in "${variant_files[@]}"; do
      [[ -f "$kit_dir/template-$tdir/$p" ]] || missing+="$kit_dir/template-$tdir/$p — template file not found"$'\n'
    done
  done
  [[ -f "$kit_dir/template-ts/.claude/hooks/user-prompt-guard.cjs" ]] || missing+="$kit_dir/template-ts/.claude/hooks/user-prompt-guard.cjs — template file not found"$'\n'
  [[ -f "$kit_dir/template-py/.claude/hooks/user-prompt-guard.py" ]] || missing+="$kit_dir/template-py/.claude/hooks/user-prompt-guard.py — template file not found"$'\n'
  for p in github-ts/.github/workflows/ci.yml github-py/.github/workflows/ci.yml azure/azure-pipelines/templatecentral-gates.yml; do
    [[ -f "$kit_dir/template-ci/$p" ]] || missing+="$kit_dir/template-ci/$p — template file not found"$'\n'
  done
  for p in template-settings-ts/.claude/settings.json template-settings-py/.claude/settings.json \
    template-late/FUTURE.md template-late/docs/CONSTITUTION.md template-late/.claude/skills/skill-audit/SKILL.md.tmpl \
    template-tail/AGENTS-tail.md; do
    [[ -f "$kit_dir/$p" ]] || missing+="$kit_dir/$p — template file not found"$'\n'
  done
  # The copy instruction is anchored on its own lines (the SEL line and the cp loop), so prose that
  # merely names the trees cannot satisfy it.
  # shellcheck disable=SC2016  # the anchor is literal text, not an expansion
  local cp_line='cp -- "$SK/$t/$p" "$TGT/$dest"'
  # shellcheck disable=SC2016  # the anchors are literal text, not expansions
  if [[ -f "$kit_dir/harness-kit.md" ]]; then
    for tok in "$cp_line" 'PART=base' 'PART=settings' 'PART=late' 'SEL="template template-$V"' 'SEL="template-settings-$V"' 'SEL="template-late"' 'template-py' '<skill-dir>/shared'; do
      grep -qF -- "$tok" "$kit_dir/harness-kit.md" || missing+="$kit_dir/harness-kit.md — Step 0 copy instruction missing: $tok"$'\n'
    done
  fi
  # shellcheck disable=SC2016  # the anchors are literal text, not expansions
  if [[ -f "$kit_dir/harness-kit-enforcement.md" ]]; then
    for tok in 'PART=ci' 'CI=none' 'PART=settings' 'PART=late'; do
      grep -qF -- "$tok" "$kit_dir/harness-kit-enforcement.md" || missing+="$kit_dir/harness-kit-enforcement.md — Step B3 CI copy instruction missing: $tok"$'\n'
    done
  fi
  for tok in "${file_tokens[@]}"; do
    f="$kit_dir/${tok%%|*}"
    [[ -f "$f" ]] && { grep -qF -- "${tok#*|}" "$f" || missing+="$f — missing token: ${tok#*|}"$'\n'; }
  done
  if [[ -z "$missing" ]]; then
    all_kit=$(cat "${kit_files[@]}"; { template_files | while IFS= read -r f; do cat "$f"; done; } || true)
    for tok in "${kit_tokens[@]}"; do
      grep -qF -- "$tok" <<<"$all_kit" || missing+="$kit_dir/harness-kit*.md + template*/ — missing harness element: $tok"$'\n'
    done
    for v in ts fastapi; do
      tdir=ts; [[ $v == fastapi ]] && tdir=py
      hay=$(cat "$kit_dir/harness-kit-$v.md"; { template_files | grep -E "$kit_dir/template(-settings)?-$tdir/" | while IFS= read -r f; do cat "$f"; done; } || true)
      for tok in "${variant_tokens[@]}"; do
        grep -qF -- "$tok" <<<"$hay" || \
          missing+="$kit_dir/harness-kit-$v.md + template-$tdir/ — variant missing harness element: $tok"$'\n'
      done
    done
  fi

  for f in "${scaffolds[@]}" "$migrate"; do
    [[ -f "$f" ]] || { missing+="$f — file not found"$'\n'; continue; }
    # Form-agnostic: matches the absolute path and the <skill-dir>-relative form.
    for kf in harness-kit.md harness-kit-enforcement.md harness-kit-finalize.md; do
      grep -qF "shared/$kf" "$f" || missing+="$f — does not load shared/$kf"$'\n'
    done
    case "$f" in
      */scaffold/fastapi/*) v=fastapi; other=ts ;;
      */scaffold/*) v=ts; other=fastapi ;;
      *) v='' ; other='' ;;
    esac
    if [[ -n "$v" ]]; then
      grep -qF "shared/harness-kit-$v.md" "$f" || missing+="$f — does not load its variant shared/harness-kit-$v.md"$'\n'
      grep -qF "shared/harness-kit-$other.md" "$f" && \
        missing+="$f — loads the other stack's variant shared/harness-kit-$other.md"$'\n'
    else
      # migrate detects the stack at runtime: one <variant-file> cat, with both names spelled out.
      for kf in 'shared/<variant-file>' harness-kit-ts.md harness-kit-fastapi.md; do
        grep -qF -- "$kf" "$f" || missing+="$f — variant loading must name $kf"$'\n'
      done
    fi
    local seeder="$f"
    [[ "$f" == "$migrate" ]] && seeder="$migrate_phase4"
    grep -qF -- '-verify/SKILL.md' "$seeder" || \
      missing+="$seeder — missing stack verify-skill seeding (-verify/SKILL.md)"$'\n'
  done

  report "$missing" \
    "Harness check failed — kit (scaffold/shared/harness-kit*.md + template*/ trees) must contain all universal tokens and each variant the full per-stack set; all 4 scaffolds + the migrate router must load the index, both shared files, and their own variant; each must seed a *-verify/SKILL.md" \
    "Shared harness kit contains all universal tokens; every scaffold/migrate loader loads its own variant"
}

check_migrate_hook_inventory_matches_kit() {
  # migrate/general/phase-4-upgrade.md enumerates the kit's hooks by name in prose (Step 4d),
  # separate from the kit's own authoring blocks — a hook added to the kit without updating
  # that list leaves every migrated project short a hook.
  header "migrate hook inventory matches the harness kit"
  local kit_dir="$SKILLS_DIR/scaffold/shared"
  local migrate="$SKILLS_DIR/migrate/general/phase-4-upgrade.md"
  if [[ ! -d "$kit_dir" || ! -f "$migrate" ]]; then
    fail "Missing $kit_dir or $migrate"
    return
  fi
  local hooks missing="" h
  # The hooks the kit seeds are the files in the template trees' .claude/hooks/ directories.
  hooks=$(template_files | grep '/\.claude/hooks/' | sed -E 's#.*/##; s#\.[a-z]+$##' | sort -u || true)
  if [[ -z "$hooks" ]]; then
    fail "No hook files under the template trees' .claude/hooks/ — nothing to compare against migrate's inventory"
    return
  fi
  for h in $hooks; do
    grep -qF -- "$h" "$migrate" || missing+="migrate is missing hook: $h"$'\n'
  done
  grep -qF -- '.claude/comment-hygiene-patterns.txt' "$migrate" || \
    missing+="migrate does not mention .claude/comment-hygiene-patterns.txt"$'\n'
  # Both migrate docs name the template trees and the manifest as the canonical source of a re-sync.
  local doc tok
  for doc in "$migrate" "$SKILLS_DIR/migrate/general/phase-5-health-check.md"; do
    for tok in 'scaffold/shared/template.manifest' 'template-ts/' 'template-py/'; do
      grep -qF -- "$tok" "$doc" 2>/dev/null || missing+="$doc — missing template anchor $tok"$'\n'
    done
  done
  # Phase 4 runs the kit's Step G from the migrate directory, where <skill-dir>/shared does not exist:
  # its Step 4f-3 paragraph must name the tail file through ../scaffold (another paragraph naming it does not count).
  # shellcheck disable=SC2016  # the anchor is literal text with backticks, not an expansion
  grep -qF -- 'a source named `<name>.tmpl` is copied to `<name>`' "$migrate" 2>/dev/null || \
    missing+="$migrate — the Template files paragraph must say a source named <name>.tmpl is copied to <name>"$'\n'
  local step_4f3
  step_4f3=$(awk '/^\*\*Step 4f-3[: ]/ { on = 1; next } /^\*\*Step / { on = 0 } on' "$migrate" 2>/dev/null || true)
  grep -qF -- '<skill-dir>/../scaffold/shared/template-tail/AGENTS-tail.md' <<<"$step_4f3" || \
    missing+="$migrate — Step 4f-3 must name <skill-dir>/../scaffold/shared/template-tail/AGENTS-tail.md"$'\n'
  for tok in 'scaffold/shared/template-settings-ts/' 'scaffold/shared/template-late/'; do
    grep -qF -- "$tok" "$migrate" 2>/dev/null || missing+="$migrate — missing template anchor $tok"$'\n'
  done
  # The Step B3 runs of the copy script (PART=ci, CI=github, azure or none) assume Step 0 ran, so each doc that describes
  # them states that they are scaffold-only and that a migration copies the CI file by hand.
  # Each anchor is a phrase that appears once in its file, so a later mention of the same word cannot
  # stand in for the note.
  local note_docs=(
    "$migrate|runs of the copy script are scaffold-only"
    "$SKILLS_DIR/migrate/general/phase-5-health-check.md|runs of the copy script are scaffold-only"
    "$kit_dir/harness-kit-enforcement.md|runs of the copy script are scaffold-only"
  )
  local entry
  for entry in "${note_docs[@]}"; do
    grep -qF -- "${entry#*|}" "${entry%%|*}" 2>/dev/null || missing+="${entry%%|*} — missing the scaffold-only note"$'\n'
  done
  report "$missing" \
    "migrate's hook/file inventory has drifted from the template trees — update skills/migrate/general/phase-4-upgrade.md Step 4d" \
    "migrate's phase-4 names every hook file in the template trees' .claude/hooks/ and the .claude/comment-hygiene-patterns.txt path"
}

check_duplicated_iam_blocks_match() {
  # The AWS IAM session/config modules exist in two independently-loaded flows: the add-database
  # leaf that installs them and the migrate-database leaf that retrofits them.
  # Deduplicating by cross-catting is the wrong trade here — the add leaves are long
  # from-scratch install guides, so a migrate flow would pay their full token cost to reuse ~70
  # lines, and risks re-running the install steps. Duplicating the block costs nothing at runtime
  # (each flow loads exactly one copy) and only risks silent drift — which this check removes.
  # The add leaf is canonical; the migrate copy must match it byte for byte. Security-critical:
  # these blocks carry sslmode=verify-full / rejectUnauthorized + CA-bundle settings, where a
  # one-sided edit silently downgrades TLS on the migrate path only.
  # TIMELESS: enforces the invariant, not any particular stack version.
  header "Duplicated IAM session/config blocks match their canonical source"
  if ! have_python; then
    pass "skipped (python3 not available)"
    return
  fi
  local out
  out=$(python3 - "$SKILLS_DIR" <<'PY'
import sys
root = sys.argv[1]

# (label, canonical file, canonical anchor, copy file, copy anchor, fence language)
PAIRS = [
    ("FastAPI IAM session.py",
     "add/database/python/sqlalchemy-iam.md", "### A4. Create `src/database/session.py`",
     "migrate/database/fastapi.md", "### Step 2 — Replace `src/database/session.py`", "python"),
    ("FastAPI IAM alembic/env.py",
     "add/database/python/sqlalchemy-iam.md", "### A6. Update `alembic/env.py`",
     "migrate/database/fastapi.md", "### Step 4 — Update `alembic/env.py`", "python"),
    ("NestJS IAM KyselyService",
     "add/database/typescript/nestjs-kysely-iam.md", "Replace the entire contents of `kysely.service.ts` with:",
     "migrate/database/nestjs.md", "### Step 4 — Create `src/database/kysely.service.ts` (IAM variant)", "typescript"),
    ("NestJS IAM envSchema fields",
     "add/database/typescript/nestjs-kysely-iam.md", "Add IAM fields to `envSchema`",
     "migrate/database/nestjs.md", "### Step 10 — Update `src/config/env.config.ts`", "typescript"),
    ("NestJS IAM serviceConfig mapping",
     "add/database/typescript/nestjs-kysely-iam.md", "Then map the validated fields into `serviceConfig`",
     "migrate/database/nestjs.md", "Then map the validated fields into `serviceConfig`", "typescript"),
]

def fence_after(path, anchor, lang):
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except OSError:
        return None
    start = next((i for i, l in enumerate(lines) if anchor in l), None)
    if start is None:
        return None
    for i in range(start + 1, len(lines)):
        if lines[i].strip() == '```' + lang:
            j = i + 1
            while j < len(lines) and not lines[j].startswith('```'):
                j += 1
            return "\n".join(lines[i + 1:j])
    return None

for label, ca_f, ca_a, cp_f, cp_a, lang in PAIRS:
    a = fence_after(root + "/" + ca_f, ca_a, lang)
    b = fence_after(root + "/" + cp_f, cp_a, lang)
    if a is None:
        print("%s: canonical anchor/fence not found in %s (%r)" % (label, ca_f, ca_a))
    elif b is None:
        print("%s: copy anchor/fence not found in %s (%r)" % (label, cp_f, cp_a))
    elif a != b:
        print("%s: %s has drifted from canonical %s" % (label, cp_f, ca_f))
PY
)
  report "$out" \
    "Duplicated IAM block drifted — the add/ leaf is canonical; re-copy it into the migrate/ leaf" \
    "All duplicated IAM blocks match their canonical source"
}

check_yaml_fences_parse() {
  # A seeded lefthook.yml/ci.yml is authored as a ```yaml fence in prose docs — nothing else
  # ever parses it before it reaches a real project. A shell variable assignment that spans
  # physical lines inside a `run: |` block scalar silently breaks YAML indentation rules
  # without any syntax error in the shell itself, so this must parse the fence content, not
  # just lint the shell inside it. The lefthook and CI files are real files in the
  # template trees and are parsed as files; a tree with no yaml file at all fails rather than passing on nothing.
  # TIMELESS: catches this bug class regardless of cause.
  header "Seeded \`\`\`yaml fences and template yaml files parse as valid YAML"
  if ! have_python || ! python3 -c 'import yaml' >/dev/null 2>&1; then
    if [[ "${CI:-}" == true ]]; then
      fail "python3/PyYAML not available in CI — the yaml fences and template yaml files went unparsed"
    else
      pass "skipped (python3/PyYAML not available)"
    fi
    return
  fi
  local out
  out=$(template_files | grep -E '\.(yml|yaml)$' | python3 -c '
import sys, yaml
tpl = 0
for p in sys.stdin.read().split("\n"):
    if not p:
        continue
    tpl += 1
    try:
        list(yaml.safe_load_all(open(p, encoding="utf-8").read()))
    except Exception as e:
        print(f"{p}: {str(e).splitlines()[0]}")
if tpl == 0:
    print("no yaml files under any template tree — nothing was parsed")
' || true
  python3 - "$SKILLS_DIR" <<'PY'
import os, sys, yaml
root = sys.argv[1]
for dp, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.md'): continue
        p = os.path.join(dp, f)
        lines = open(p, encoding='utf-8').read().split('\n')
        i = 0
        while i < len(lines):
            if lines[i].strip() != '```yaml':
                i += 1
                continue
            start = j = i + 1
            while j < len(lines) and lines[j].strip() != '```':
                j += 1
            try:
                list(yaml.safe_load_all('\n'.join(lines[start:j])))
            except Exception as e:
                print(f"{p}:{start+1}-{j}: {str(e).splitlines()[0]}")
            i = j + 1
PY
)
  report "$out" \
    "Seeded yaml fence(s) or template yaml file(s) fail to parse — check block-scalar (run: |) indentation" \
    "All seeded yaml fences and template yaml files parse"
}

check_no_absolute_plugin_path() {
  # References load via the <skill-dir> placeholder (the tool-provided skill directory at invocation),
  # never an absolute install path, and never ${CLAUDE_SKILL_DIR} (empty in agent-run bash — only
  # populated for CC !-injection, not the agent-run cat blocks used here). See CONVENTIONS.md §1.
  # TIMELESS: skills must be portable across Agent-Skills tools; the install path is never hardcoded.
  header "No absolute plugin-path or \${CLAUDE_SKILL_DIR} references"
  report "$(scan -E 'plugins/marketplaces/templatecentral|CLAUDE_SKILL_DIR' 'CONVENTIONS.md')" \
    "Use the <skill-dir> placeholder (CONVENTIONS.md §1), not an absolute plugin path or \${CLAUDE_SKILL_DIR}." \
    "No absolute plugin-path / \${CLAUDE_SKILL_DIR} references (all use <skill-dir>)"
}

check_skilldir_refs_resolve() {
  # Every concrete <skill-dir>/<path> reference must resolve to a real file, so the cat-routing
  # contract (CONVENTIONS §1/§8 "every reference file referenced in a cat command actually exists")
  # cannot silently break when a ref file is moved or renamed. Placeholder refs (containing <, >, or |
  # — e.g. <skill-dir>/<stack>/config-files.md) are skipped. TIMELESS: this is the core load mechanism.
  header "<skill-dir> references resolve to real files"
  if ! have_python; then
    pass "skipped (python3 not available)"
    return
  fi
  local out
  out=$(python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys
root = sys.argv[1]
def owning(p):
    d = os.path.dirname(p)
    while d.startswith(root):
        if os.path.exists(os.path.join(d, "SKILL.md")): return d
        nd = os.path.dirname(d)
        if nd == d: break
        d = nd
    return None
# Tight char class: matches a concrete path and stops cleanly at backtick/quote/paren/space and
# at placeholder markers (<stack>, <path>, |), so doc placeholders are skipped without a filter.
tok = re.compile(r'<skill-dir>(/[A-Za-z0-9._/*{}-]+)')
for dp, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.md'): continue
        p = os.path.join(dp, f)
        try: t = open(p, encoding='utf-8').read()
        except Exception: continue
        base = owning(p)
        if not base: continue
        for m in tok.finditer(t):
            rel = m.group(1).lstrip('/')
            if not os.path.exists(os.path.join(base, rel)):
                print(p + ': <skill-dir>/' + rel)
# The copy instructions must exist and name every template tree, so a deleted instruction is not
# mistaken for "no broken references".
need = {
    "scaffold/shared/harness-kit.md": ['cp -- "$SK/$t/$p" "$TGT/$dest"', "PART=base", 'SEL="template template-$V"', 'SEL="template"', 'SEL="template-agents"', 'SEL="template-late"', 'SEL="template-settings-$V"', 'SEL="template-ci/github-$V"', 'SEL="template-ci/azure"', "settings | late)", "stack | agents)", "none) SEL= ;;", 'rm -f -- "$TGT/$gate"', "<skill-dir>/shared"],
    "scaffold/shared/harness-kit-enforcement.md": ["PART=ci", "CI=none", "PART=settings", "PART=late"],
    "scaffold/nextjs/source-files.md": ["PART=stack", "PART=base", "PART=agents", "STACK=nextjs", "<skill-dir>/nextjs/template.manifest", "<skill-dir>/nextjs/template-agents/"],
    "scaffold/fastapi/source-files.md": ["PART=stack", "PART=base", "PART=agents", "STACK=fastapi", "<skill-dir>/fastapi/template.manifest", "<skill-dir>/fastapi/template-agents/"],
}
for rel, toks in need.items():
    try: t = open(os.path.join(root, rel), encoding='utf-8').read()
    except OSError:
        print(rel + ': file not found'); continue
    for tok in toks:
        if tok not in t: print(rel + ': copy instruction ' + tok + ' missing')
PY
)
  report "$out" \
    "Broken <skill-dir> reference(s) — target file does not exist (CONVENTIONS §8)" \
    "All concrete <skill-dir> references resolve"
}

check_ref_header_prereq_suffix() {
  # CONVENTIONS §4: a ref file's prereq must state how it is loaded — ending with
  # "— it is loaded at runtime by the templatecentral:<skill> skill" (or noting it is a
  # de-registered agent utility). The bare "Do not invoke this file directly." form tends to
  # drift back in; this locks the full form so routing intent stays self-documenting. TIMELESS.
  header "Ref-header prereq carries the §4 'loaded at runtime by' clause"
  local bad
  # shellcheck disable=SC2016  # awk program passed through find -exec.
  bad=$(find "$SKILLS_DIR" -name '*.md' -exec awk '
    function flush() { if (f != "" && ref && prereq && !ok) print f }
    FNR == 1 { flush(); f = FILENAME; ref = prereq = ok = 0 }
    FNR <= 6 {
      if (index($0, "<!-- ref:")) ref = 1
      if (index($0, "prereq:")) prereq = 1
      if (index($0, "loaded at runtime by the templatecentral:") \
          || tolower($0) ~ /de-registered|agent utilit|catted directly/) ok = 1
    }
    END { flush() }' {} + 2>/dev/null)
  report "$bad" \
    "Ref-header prereq missing the §4 'loaded at runtime by the templatecentral:<skill> skill' clause" \
    "All ref-header prereqs carry the §4 'loaded at runtime by' clause"
}

check_owasp_llm_sections_complete() {
  # add/ai-security/implementation.md must cover all 10 OWASP LLM Top 10 v2.0 sections.
  # A missing section leaves a gap in AI security guidance — agents won't know to guard against it.
  # TIMELESS: LLM01-LLM10 are stable section names; the guidance may evolve but the structure is fixed.
  header "OWASP LLM Top 10 v2.0 completeness in ai-security skill"
  local ai_sec="$SKILLS_DIR/add/ai-security/implementation.md"
  if [[ ! -f "$ai_sec" ]]; then
    fail "add/ai-security/implementation.md not found"
    return
  fi
  local present missing="" n
  present=$(grep -o '### LLM[0-9][0-9]' "$ai_sec" || true)
  for n in 01 02 03 04 05 06 07 08 09 10; do
    [[ "$present" == *"### LLM${n}"* ]] || missing+=" LLM${n}"
  done
  if [[ -n "$missing" ]]; then
    fail "add/ai-security/implementation.md is missing OWASP LLM Top 10 sections:$missing"
  else
    pass "All LLM01-LLM10 sections present"
  fi
}

check_no_bare_nextjs_route_handlers() {
  # Next.js scaffold wires check-route-logging.mjs into `pnpm check`, which fails the build
  # on any bare `export async function GET/POST/...` App Router handler — every skill example
  # must wrap handlers in withLogging() (the pattern add/endpoint/nextjs.md documents).
  # TIMELESS: tied to the scaffold's own enforced convention (scripts/check-route-logging.mjs).
  header "Bare Next.js route handler exports (must be wrapped in withLogging)"
  report "$(scan -E 'export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)[[:space:]]*\(' \
    'check-route-logging' 'audit/implementation' 'nextjs-backend-extraction')" \
    "Bare Next.js route handler export — wrap it in withLogging() (see add/endpoint/nextjs.md); pnpm check's check-route-logging.mjs fails the build on this pattern" \
    "No bare Next.js route handler exports"
}

check_no_husky() {
  # The git-hook layer is lefthook (harness-kit Step B2) — the single source for ALL stacks,
  # since it installs from Node OR Python (Husky is Node-only and cannot run in a FastAPI scaffold).
  # A stray husky reference means a scaffold drifted back to a contradictory dual-hook setup.
  # TIMELESS: lefthook is the harness design SSOT.
  header "No husky references (lefthook is the git-hook SSOT)"
  local lf
  for lf in template-ts template-py; do
    [[ -f "$SKILLS_DIR/scaffold/shared/$lf/lefthook.yml" ]] || { fail "Missing $SKILLS_DIR/scaffold/shared/$lf/lefthook.yml — the lefthook layer this check protects is gone"; return; }
  done
  report "$(scan "" 'husky')" \
    "husky reference found — the git-hook layer is lefthook (harness-kit Step B2). Remove husky." \
    "No husky references (lefthook only)"
}

check_lefthook_prepare_has_fallback() {
  # lefthook's "install" CLI command has no graceful skip when .git is absent (verified against
  # lefthook's own Go source — unlike husky, which checks existsSync('.git') and no-ops). Every
  # TS scaffold's Dockerfile `deps` stage runs `pnpm i`/`npm ci` before `.git` exists in the build
  # context (dockerignored), which fires the "prepare" script and hard-fails the install unless it
  # tolerates a non-zero exit. A bare "lefthook install" prepare script (missing `|| true`) breaks
  # every Docker build derived from it.
  # TIMELESS: lefthook's install-command behavior is a fixed property of the tool, not ecosystem drift.
  header "lefthook prepare script has Docker-safe fallback"
  if [[ -z "$(scan "" '"prepare":')" ]]; then
    fail "No \"prepare\" script found in any skill file — the check below would scan nothing"
    return
  fi
  report "$(scan "" '"prepare":[[:space:]]*"lefthook install"')" \
    "prepare script runs bare 'lefthook install' with no fallback — breaks Docker builds (.git absent in build context). Use \"lefthook install || true\"." \
    "All lefthook prepare scripts tolerate a missing .git"
}

# posttooluse_files_running <ERE> — files whose "PostToolUse" block (next 15 lines) matches ERE.
posttooluse_files_running() {
  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    grep -A15 '"PostToolUse"' "$file" 2>/dev/null | grep -qE -- "$1" && echo "$file"
  done < <(grep -rl '"PostToolUse"' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  return 0
}

# have_posttooluse — succeed when any skill file defines a "PostToolUse" hook, so the two checks
# that read those definitions cannot pass on nothing.
have_posttooluse() { [[ -n "$(grep -rl '"PostToolUse"' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)" ]]; }

check_no_postToolUse_full_test_suite() {
  # PostToolUse hooks are feedback-only and cannot block execution.
  # Full test suites (pnpm test, pytest, etc.) belong in Stop hooks, not PostToolUse.
  # Running tests on every file edit is slow and masks real TypeScript feedback.
  # TIMELESS: PostToolUse semantic is feedback-only by design in Claude Code.
  header "Full test suite in PostToolUse hook"
  have_posttooluse || { fail "No \"PostToolUse\" hook definition found in any skill file — nothing to check"; return; }
  report "$(posttooluse_files_running '"(pnpm test|pytest|npm test|yarn test)')" \
    "Full test suite in PostToolUse — use Stop hook for tests; PostToolUse should run tsc --noEmit only" \
    "No full test suite in PostToolUse hook"
}

check_no_bare_pytest_invocation() {
  # A bare `pytest ...` invocation resolves via PATH — if the caller's shell doesn't have the
  # project .venv activated, it silently runs a different/system pytest or fails with
  # "command not found." `python -m pytest` always resolves via the active Python, matching
  # the `python -m pyright` convention used everywhere else in the FastAPI skills.
  # TIMELESS: tied to the venv-based invocation convention (skills/test/implementation.md).
  header "Bare pytest invocation (must use python -m pytest)"
  report "$(scan -E '(^|[^-.a-zA-Z])pytest[[:space:]]+(test/|-[a-zA-Z])' 'python -m pytest' 'audit/implementation')" \
    "Bare 'pytest ...' invocation — use 'python -m pytest' so it resolves via the active venv (see skills/test/implementation.md)" \
    "No bare pytest invocation"
}

# ── ECOSYSTEM-ERA ──────────────────────────────────────────────────────────────

check_no_version_pins() {
  # SSOT policy: version pins belong only in .claude/rules/*.md, not in SKILL.md files.
  # Catches: scoped npm pins (@org/pkg@version), unscoped npm pins (pkg@X.Y.Z),
  # and Python exact pins (pkg==X.Y). Exclusions:
  #   shadcn@latest: the official shadcn CLI invocation, not a dependency pin
  #   templateCentral: schema markers (<!-- templateCentral: stack@X.Y.Z -->)
  #   "packageManager" field: corepack requires an exact version in this field by design
  #   ":<space>stack@version" prose (drift-check example output, schema version references)
  # REVISIT: if the SSOT policy changes, remove this check.
  header "Version pins in skills (SSOT)"
  report "$( {
      scan "" '@[a-zA-Z][a-zA-Z0-9_/@-]*@[0-9^~><]'
      echo
      scan -E '[a-zA-Z0-9_-]+@[0-9]+\.[0-9]+\.[0-9]+' 'templateCentral:' '"packageManager"' \
        | grep -vE ':[[:space:]]+[a-zA-Z][a-zA-Z0-9_-]*@[0-9]' || true
      echo
      scan -E '[a-zA-Z0-9_-]+[=]{2}[0-9]+\.[0-9]+'
    } | grep -v '^$' | sort -u | grep -v 'shadcn@latest' || true)" \
    "Version pins found — move floors/pins to .claude/rules/*.md" \
    "No version pins in skills"

  # The template package.json files carry caret floors, so a dependency written as an exact
  # "name": "X.Y.Z" is an unreviewed pin. eslint-plugin-sonarjs is the one exact pin by design
  # (its enabled-rule set changes across minor versions; see the scaffold notes).
  header "Template package.json dependencies use floors, not exact pins"
  local pj pins="" n=0
  while IFS= read -r pj; do
    n=$((n + 1))
    pins+=$(grep -nE '^[[:space:]]+"[^"]+":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$pj" \
      | grep -vE '"(version|packageManager|eslint-plugin-sonarjs)"' | sed "s#^#$pj:#" || true)
  done < <(template_files | grep '/package\.json$' || true)
  [[ "$n" -gt 0 ]] || pins="no template package.json found — nothing to check"
  report "$pins" \
    "Exact dependency pin in a template package.json — use a caret floor aligned with .claude/rules/*.md (eslint-plugin-sonarjs is the only exact pin)" \
    "Template package.json dependencies use floors (eslint-plugin-sonarjs exact by design)"
}

check_no_bcrypt() {
  # Project standard is argon2id (OWASP/NIST SP 800-63B recommendation).
  # REVISIT: if the project standard changes, update this check.
  # audit/implementation.md is excluded — it references bcrypt in its own checklist items.
  header "bcrypt references"
  report "$(scan "" '\bbcrypt\b' 'audit/implementation')" \
    "bcrypt found — project standard is argon2id" \
    "No bcrypt references"
}

check_no_deprecated_zod_flatten() {
  # Zod v4 deprecated error.flatten() — use z.flattenError(error) instead.
  # REVISIT: if the project ever drops to Zod v3, remove this check.
  # audit/implementation.md is excluded — it references .flatten() in its own checklist items.
  header "Deprecated Zod .flatten()"
  report "$(scan "" '\.flatten()' 'audit/implementation')" \
    ".flatten() is deprecated in Zod v4 — use z.flattenError()" \
    "No deprecated .flatten() calls"
}

check_no_middleware_ts() {
  # Next.js 16 replaced middleware.ts with proxy.ts for auth/proxy patterns.
  # REVISIT: if Next.js reintroduces middleware.ts, remove or adjust this check.
  # Excluded files are meta-documents (audit checklist, migration guide) and the Next.js AGENTS.md
  # seed, which legitimately reference middleware.ts to explain the deprecation. The exclusion
  # names that one template file, so every other template file is still scanned.
  header "middleware.ts references"
  report "$(scan "" 'middleware\.ts' 'audit/implementation' 'migrate/general/phase-4-upgrade' 'scaffold/nextjs/template-agents/AGENTS\.md')" \
    "middleware.ts found — Next.js 16 uses proxy.ts" \
    "No middleware.ts references"
}

check_no_pragma_or_expires_headers() {
  # Pragma: no-cache and Expires: 0 are HTTP/1.0 relics — deprecated in HTTP/1.1+.
  # Cache-Control is sufficient. These headers add noise without benefit.
  # REVISIT: if a target environment requires HTTP/1.0 compat, reconsider.
  header "Deprecated HTTP/1.0 cache headers"
  report "$(scan -E 'Pragma: no-cache|Expires: 0')" \
    "Deprecated HTTP/1.0 headers found — Cache-Control is sufficient" \
    "No deprecated HTTP/1.0 cache headers"
}

check_no_jest_apis_in_skills() {
  # All Node scaffold stacks (NestJS, Next.js, Vite+React) use Vitest — not Jest.
  # jest.fn(), jest.spyOn(), and jest-e2e.json must not appear in skill code examples.
  # ECOSYSTEM-ERA: correct for NestJS 11+ (Vitest default). Revisit if the project adopts Jest.
  # audit/implementation.md is excluded — it may reference these patterns in checklist items.
  header "Jest APIs in skill code examples"
  report "$(scan -E 'jest\.(fn|spyOn|mock|clearAllMocks|resetAllMocks|restoreAllMocks)\(|jest-e2e\.json' 'audit/implementation')" \
    "Jest API found in skill code example — all Node stacks use Vitest (vi.fn(), vi.spyOn())" \
    "No Jest APIs in skill code examples"
}

check_no_globals_jest_in_vitest_projects() {
  # All Node scaffold stacks use Vitest with globals: false — eslint-globals-jest is not needed.
  # Adding ...globals.jest to an ESLint config in a Vitest project is misleading and unused.
  # ECOSYSTEM-ERA: correct for NestJS 11+ / Vite+React (Vitest default). Revisit if Jest is re-adopted.
  # audit/implementation.md is excluded — it may reference this in checklist items.
  header "globals.jest in ESLint config templates"
  report "$(scan "" 'globals\.jest' 'audit/implementation')" \
    "globals.jest found in ESLint template — Node stacks use Vitest with globals: false; remove globals.jest" \
    "No globals.jest in ESLint config templates"
}

check_no_sync_secret_comparison() {
  # Comparing stored secrets (hashes, tokens) with == or === is not timing-safe.
  # Use a constant-time function (e.g. crypto.timingSafeEqual, argon2.verify).
  # NOTE: password === confirmPassword in Zod refine() is safe — both are user inputs,
  #       there is no stored value and no timing oracle. This check targets stored values.
  # REVISIT: if a safe wrapper is introduced, refine the pattern.
  header "Unsafe stored-secret comparison"
  report "$(scan -E '\b(storedHash|passwordHash|hashedPassword|sessionToken|accessToken|refreshToken)\s*(===|==)\s*')" \
    "Timing-unsafe comparison of stored secret — use a constant-time compare function" \
    "No unsafe stored-secret comparisons"
}

check_no_zod_string_format_methods() {
  # Zod v4 deprecated chained string-format methods: .string().url(), .string().datetime(),
  # .string().email(), .string().uuid(). Use top-level z.url(), z.iso.datetime(), z.email(), z.uuid() instead.
  # ECOSYSTEM-ERA: correct for Zod v4+. Revisit if the project downgrades to Zod v3.
  # audit/implementation.md is excluded — it may reference these in checklist items.
  header "Deprecated Zod v4 string format methods"
  report "$(scan -E 'z\.string\(\)\.(url|datetime|email|uuid)\(' 'audit/implementation')" \
    "Deprecated Zod string-chained format method — use top-level z.url(), z.iso.datetime(), z.email(), z.uuid()" \
    "No deprecated Zod string format methods"
}

check_no_zod_deprecated_message_key() {
  # Zod v4 custom error params use { error: '...' }, not { message: '...' }.
  # { message: '...' } is the Zod v3 form — still accepted but deprecated in v4 and will be removed.
  # Matches any z.<method>({ message: so z.string(), z.number(), z.object(), ... are all covered.
  # ECOSYSTEM-ERA: correct for Zod v4.
  # audit/implementation.md is excluded — it may reference this pattern in checklist items.
  header "Deprecated Zod v3 message key in validators"
  report "$(scan -E 'z\.[a-z]+\([[:space:]]*\{[[:space:]]*message:' 'audit/implementation')" \
    "Zod validator uses deprecated { message: '...' } — use { error: '...' } for custom error messages in Zod v4" \
    "No deprecated Zod v3 message key in validators"
}

check_no_mypy_in_postToolUse() {
  # pyright is 2-5x faster than mypy with near-complete spec conformance.
  # mypy in PostToolUse adds 45+ seconds per edit on real projects.
  # REVISIT: if mypy regains a speed advantage or pyright has correctness regressions, update.
  header "mypy in PostToolUse hook"
  have_posttooluse || { fail "No \"PostToolUse\" hook definition found in any skill file — nothing to check"; return; }
  report "$(posttooluse_files_running 'mypy')" \
    "mypy in PostToolUse — use pyright instead (2-5x faster, community standard as of May 2026)" \
    "No mypy in PostToolUse hook"
}

check_no_env_api_base_url_fallback() {
  # Vite+React code-standards rule: NEVER use `ENV.API_BASE_URL ?? ''` — use `getApiBaseUrl()`.
  # The fallback '' silently returns empty string when the env var is missing, hiding config errors.
  # getApiBaseUrl() throws at startup so misconfiguration is caught immediately.
  # ECOSYSTEM-ERA: Vite 8 / React 19 stack. Revisit if ENV helper API changes.
  header "ENV.API_BASE_URL ?? '' anti-pattern in Vite skills"
  report "$(scan "" "API_BASE_URL ?? ''" 'audit/implementation' 'code-standards')" \
    "Use getApiBaseUrl() not ENV.API_BASE_URL ?? '' — see code-standards/vite-react.md" \
    "No ENV.API_BASE_URL ?? '' anti-pattern"
}

check_no_tanstack_isLoading() {
  # TanStack Query v5 renamed isLoading to isPending on useQuery()/useMutation() destructuring.
  # isLoading still exists as a derived bool on the query object but has different semantics
  # (true when fetching WITH existing data; isPending is true when there is no data yet).
  # Using isLoading instead of isPending causes the loading state to not show on first render.
  # ECOSYSTEM-ERA: correct for TanStack Query v5+. Revisit if the project pins to TQ v4.
  header "TanStack Query v5 isLoading usage"
  report "$(scan "" '{ .*isLoading.*} = use\(Query\|Mutation\)\|isPending\s*:\s*isLoading\b' 'audit/implementation')" \
    "TanStack Query v5: use isPending (not isLoading) from useQuery/useMutation destructuring" \
    "No TanStack Query isLoading usage"
}

check_no_tanstack_isInitialLoading() {
  # TanStack Query v5 deprecated isInitialLoading (alias for isLoading && isLoading) and removed
  # it in v6. Using it causes a runtime error once projects upgrade to v6.
  # ECOSYSTEM-ERA: correct for TanStack Query v5+. Retire when v6 is the project baseline.
  header "TanStack Query v5 isInitialLoading usage"
  report "$(scan "" '\bisInitialLoading\b' 'audit/implementation')" \
    "TanStack Query v5: isInitialLoading is deprecated (removed in v6); use isPending instead" \
    "No TanStack Query isInitialLoading usage"
}

check_no_starlette_startup_events() {
  # Starlette 1.0.0 removed on_startup/on_shutdown event handlers and add_event_handler().
  # FastAPI 0.136.x requires lifespan= context manager exclusively.
  # ECOSYSTEM-ERA: correct for Starlette ≥1.0.0 / FastAPI ≥0.128.0.
  header "Starlette 1.0 deprecated startup events"
  report "$(scan "" '@app\.on_event\|add_event_handler\|on_startup=\|on_shutdown=' 'audit/implementation' 'standards/code-standards')" \
    "Starlette 1.0: use lifespan= context manager — on_startup/on_shutdown/add_event_handler removed" \
    "No Starlette deprecated startup events"
}

check_no_fastapi_orjson_response() {
  # ORJSONResponse and UJSONResponse deprecated in FastAPI 0.130+.
  # Native JSON serialization now uses Pydantic's Rust-based serializer.
  # ECOSYSTEM-ERA: correct for FastAPI ≥0.130.0.
  header "Deprecated FastAPI ORJSONResponse/UJSONResponse"
  report "$(scan "" 'ORJSONResponse\|UJSONResponse' 'audit/implementation')" \
    "FastAPI 0.130+: ORJSONResponse/UJSONResponse deprecated — use standard JSONResponse" \
    "No deprecated FastAPI ORJSONResponse/UJSONResponse"
}

check_security_seeds_present() {
  # The deps gate and the deny-by-default authz helpers are shipped security seeds: dropping one
  # from a skill file silently removes the protection from every project scaffolded afterwards.
  # Matches anchor on the pipeline step lines and the code definitions, not on prose mentions.
  # The gate script and CI files are real files under shared/template*/; a missing file fails.
  header "Deps gate and deny-by-default authz seeds present"
  local missing="" spec file pattern
  local shared="$SKILLS_DIR/scaffold/shared" gates f
  gates="$shared/template/.claude/ci-gates.sh"
  if [[ -f "$gates" ]]; then
    grep -qE '^  deps\)$' "$gates" || missing+=$'\n'"$gates: ci-gates.sh has no deps case"
  else
    missing+=$'\n'"$gates: file not found"
  fi
  for f in "$shared/template-ci/github-ts/.github/workflows/ci.yml" "$shared/template-ci/github-py/.github/workflows/ci.yml"; do
    if [[ -f "$f" ]]; then
      grep -qE '^[[:space:]]+run: bash \.claude/ci-gates\.sh deps$' "$f" || missing+=$'\n'"$f: GitHub pipeline step 'run: bash .claude/ci-gates.sh deps' missing"
    else
      missing+=$'\n'"$f: file not found"
    fi
  done
  f="$shared/template-ci/azure/azure-pipelines/templatecentral-gates.yml"
  if [[ -f "$f" ]]; then
    grep -qE '^[[:space:]]+- bash: bash \.claude/ci-gates\.sh deps$' "$f" || missing+=$'\n'"$f: Azure pipeline step '- bash: bash .claude/ci-gates.sh deps' missing"
  else
    missing+=$'\n'"$f: file not found"
  fi
  for spec in \
    "fastapi|^def require_roles\(" "fastapi|^def get_current_roles\(" "fastapi|^def ensure_owner\(" \
    "nestjs|^export class RolesGuard " "nestjs|^export function assertOwner\(" \
    "nextjs|^export function hasRole\(" "nextjs|^export function isOwner\("; do
    file="$SKILLS_DIR/add/auth/${spec%%|*}.md"
    pattern="${spec#*|}"
    [[ -f "$file" ]] || continue
    grep -qE "$pattern" "$file" || missing+=$'\n'"$file: authz definition /$pattern/ missing"
  done
  report "${missing#$'\n'}" \
    "Deps gate or authz seed missing — restore it (see the harness engineering checks in .claude/skills/tc-audit/implementation.md)" \
    "Deps gate and authz seeds present"
}

# tree_problems <root> <tree>... — one line per disagreement between <root>/template.manifest and
# the files in the named trees under <root> (path and mode), plus a line for each empty or missing tree.
tree_problems() {
  python3 - "$@" <<'PY'
import os, sys
shared = sys.argv[1]
want_trees = sys.argv[2:]
actual = {}
import subprocess
# Inside a git work tree the index mode is what a checkout (and the plugin cache) reproduces; a
# working-tree mode can differ (umask, a copy). Outside git, or for an untracked file, use the file mode.
indexed = {}
try:
    r = subprocess.run(["git", "-C", shared, "ls-files", "-s", "--", "."], capture_output=True, text=True)
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            meta, path = line.split("\t", 1)
            indexed[path] = meta.split()[0][-3:]
except OSError:
    pass
for tree in want_trees:
    root = os.path.join(shared, tree)
    n = 0
    for dp, ds, fs in os.walk(root):
        if not ds and not fs and dp != root:
            print(f"{dp}: empty directory in a template tree")
        for f in fs:
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, shared)
            actual[rel] = indexed.get(rel, "%o" % (os.stat(full).st_mode & 0o777))
            n += 1
    if n == 0:
        print(f"{root}: tree is missing or empty")
manifest = os.path.join(shared, "template.manifest")
listed = {}
try:
    for line in open(manifest, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            cols = line.split()
            if len(cols) != 4:
                print(f"{manifest}: malformed line: {line}")
                continue
            listed[cols[0]] = cols[1]
except OSError:
    print(f"{manifest}: file not found")
for p in sorted(actual):
    if p not in listed:
        print(f"{manifest}: {p} is in the tree but not listed")
    elif listed[p] != actual[p]:
        print(f"{manifest}: {p} is mode {actual[p]} but listed as {listed[p]}")
    elif p.endswith(".sh") and listed[p] != "755":
        print(f"{manifest}: {p} is a script and must be mode 755, not {listed[p]}")
for p in sorted(listed):
    if p not in actual:
        print(f"{manifest}: lists {p}, which is not in the tree")
# a <name>.tmpl source is copied to <name>, so two paths that agree once the suffix is dropped would write one project file twice
by_target = {}
for p in sorted(set(actual) | set(listed)):
    by_target.setdefault(p[:-5] if p.endswith(".tmpl") else p, []).append(p)
for target, srcs in sorted(by_target.items()):
    if len(srcs) > 1:
        print(f"{manifest}: {' and '.join(srcs)} both copy to {target}")
PY
}

check_template_trees_complete() {
  # The scaffold copies skills/scaffold/shared/template*/ verbatim, so the file set is the contract:
  # template.manifest lists every file with its mode, and the tree holds exactly those files. A
  # file added without a manifest line, a manifest line without a file, or a mode that differs from
  # the manifest (a hook that lost its exec bit) fails here. An empty or missing tree fails too,
  # so the checks that scan these trees cannot pass on nothing. TIMELESS.
  header "Template trees are complete and listed in the manifest"
  if ! have_python; then
    pass "skipped (python3 not available)"
    return
  fi
  local out="" st
  out=$(
    # shellcheck disable=SC2086  # the tree lists are space-separated names
    tree_problems "$SKILLS_DIR/scaffold/shared" $SHARED_TREES
    for st in ${TEMPLATED_STACKS[@]+"${TEMPLATED_STACKS[@]}"}; do
      # shellcheck disable=SC2086
      tree_problems "$SKILLS_DIR/scaffold/$st" $STACK_TREES
    done
  )
  report "$out" \
    "Template tree and template.manifest disagree — list every file (path mode placeholders seams) and keep each .sh mode 755" \
    "Template trees match template.manifest"
}

check_no_template_skill_md() {
  # A skill loader that scans a skills path recursively for SKILL.md registers any such file it
  # finds, so a template skill that ships under that name would load as a skill of this plugin.
  # Template skills ship as SKILL.md.tmpl; the copy step drops the suffix in the project. TIMELESS.
  header "Template trees hold no file named SKILL.md"
  local scaf="$SKILLS_DIR/scaffold" bad tmpl
  tmpl=
  if [[ -d "$scaf" ]]; then
    tmpl=$(cd "$scaf" && find . -name 'SKILL.md.tmpl' -path './*/template*/*' | LC_ALL=C sort)
  fi
  if [[ -z "$tmpl" ]]; then
    fail "No SKILL.md.tmpl found under $scaf/*/template*/ — the check below would scan nothing"
    return
  fi
  bad=$(cd "$scaf" && find . -name 'SKILL.md' -path './*/template*/*' | LC_ALL=C sort)
  report "$bad" \
    "A file named SKILL.md sits in a template tree — rename it to SKILL.md.tmpl so no skill loader registers it" \
    "No template tree holds a file named SKILL.md"
}

check_copy_script_single() {
  # Every copy in a scaffold (base, settings, ci, late and the stack parts) is one script: the fence
  # in harness-kit.md Step 0, run with another PART. A second guard body would drift from the first
  # and halve the tokens the template trees save, so no other skills file may carry one under any
  # heredoc name or spelling, and Step B3 must say it runs that script with PART=ci. The one other
  # script fence is the AGENTS.md tail command in harness-kit-finalize.md, named TC_TAIL. TIMELESS.
  header "The copy script has exactly one copy"
  local kit="$SKILLS_DIR/scaffold/shared/harness-kit.md" enf="$SKILLS_DIR/scaffold/shared/harness-kit-enforcement.md"
  local bad="" tok b3 hits line file delim guard_body guard_n=0 tail_n=0 fin="$SKILLS_DIR/scaffold/shared/harness-kit-finalize.md"
  # Any heredoc that feeds a shell, in any spelling: a shell named bare, by path or through env, with
  # options; a heredoc delimiter that is quoted, double-quoted, backslashed or bare; and a heredoc
  # piped into a shell. The bodies of the two allowed fences are skipped, so the heredocs inside the
  # copy script do not count. Only skills/**/*.md is scanned: template files are not instructions.
  # shellcheck disable=SC2016  # the awk program is single-quoted on purpose
  hits=$(find "$SKILLS_DIR" -name '*.md' -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 awk '
    function delim(s,   t) {
      if (match(s, /<<-?[ \t]*["\047\\]*[A-Za-z0-9_]+/)) { t = substr(s, RSTART, RLENGTH); sub(/^<<-?[ \t]*["\047\\]*/, "", t); return t }
      return ""
    }
    FNR == 1 { skip = "" }
    skip != "" { if ($0 == skip) skip = ""; next }
    {
      hit = 0
      if ($0 ~ /(^|[^A-Za-z0-9_\/])(\/bin\/|\/usr\/bin\/env )?(ba|z)?sh([^A-Za-z0-9_]|$)[^<]*<</) hit = 1
      if ($0 ~ /<<-?[ \t]*["\047\\]*TC_/) hit = 1
      if ($0 ~ /<<[^|]*\|[ \t]*(\/bin\/|\/usr\/bin\/env )?(ba|z)?sh([^A-Za-z0-9_]|$)/) hit = 1
      if (hit) { print FILENAME ":" FNR ":" $0; d = delim($0); if (d == "TC_GUARD" || d == "TC_TAIL") skip = d }
    }' 2>/dev/null || true)
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    file=${line%%:*}
    delim=$(sed -nE "s/.*<<-?[[:space:]]*[\"'\\\\]*([A-Za-z0-9_]+).*/\\1/p" <<<"$line")
    if [[ "$delim" == TC_GUARD ]]; then
      guard_n=$((guard_n + 1))
      [[ "$file" == "$kit" ]] || bad+="the copy script must live only in $kit; also found in $file"$'\n'
    elif [[ "$delim" == TC_TAIL ]]; then
      tail_n=$((tail_n + 1))
      [[ "$file" == "$fin" ]] || bad+="the AGENTS.md tail command must live only in $fin; also found in $file"$'\n'
    else
      bad+="a second script fence (${delim:-no delimiter}) in $line — the only fences allowed are TC_GUARD in $kit and TC_TAIL in $fin"$'\n'
    fi
  done <<<"$hits"
  [[ "$guard_n" == 1 ]] || bad+="skills/ holds $guard_n copy-script fences (want exactly 1 TC_GUARD, in $kit)"$'\n'
  [[ "$tail_n" == 1 ]] || bad+="skills/ holds $tail_n AGENTS.md tail fences (want exactly 1 TC_TAIL, in $fin)"$'\n'
  # The copy script copies files; the tail is appended to AGENTS.md by its own command, so the
  # script must not mention it anywhere.
  # The body is captured first: under pipefail, `awk | grep -q` fails when grep exits before awk has
  # written everything (SIGPIPE), which would let a mention pass unseen.
  guard_body=$(awk '$0 == "bash <<\047TC_GUARD\047" { on = 1; next } $0 == "TC_GUARD" { on = 0 } on' "$kit" 2>/dev/null || true)
  if [[ -z "$guard_body" ]]; then
    bad+="$kit — could not read the copy script body"$'\n'
  elif [[ "$guard_body" == *template-tail* ]]; then
    bad+="$kit — the copy script mentions template-tail, which is appended to AGENTS.md and never copied"$'\n'
  fi
  # Only the Step B3 section counts: the same words elsewhere in the file would satisfy a whole-file grep.
  b3=$(awk '/^## Step B3[. ]/ { on = 1; next } /^## / { on = 0 } on' "$enf" 2>/dev/null || true)
  if [[ -z "$b3" ]]; then bad+="$enf — no Step B3 section found"$'\n'; fi
  for tok in 'harness-kit.md' 'PART=ci' 'CI=none'; do
    grep -qF -- "$tok" <<<"$b3" || bad+="$enf — Step B3 must name $tok"$'\n'
  done
  report "${bad%$'\n'}" \
    "The copy script is not a single copy in harness-kit.md Step 0 — keep one script and run it with PART=ci from Step B3" \
    "One copy script (harness-kit.md Step 0), run with PART=ci from Step B3"

  # The template-tail trees are appended to AGENTS.md, never copied as files: no selector may name them.
  header "No copy selector names template-tail"
  bad=""
  n=$(grep -cE '^[[:space:]]*(.*;[[:space:]]*)?(then[[:space:]]+|else[[:space:]]+)?SEL=' "$kit" 2>/dev/null || true)
  [[ "${n:-0}" -ge 1 ]] || bad+="$kit — no SEL assignment found, so the selector check would scan nothing"$'\n'
  b3=$(grep -rn 'SEL=.*template-tail' "$SKILLS_DIR/" 2>/dev/null || true)
  [[ -z "$b3" ]] || bad+="$b3"$'\n'"  ^ a copy selector names template-tail; those files are appended to AGENTS.md, not copied"$'\n'
  report "${bad%$'\n'}" \
    "A copy selector reaches template-tail, which must never be copied as a file" \
    "No copy selector names template-tail"
}

check_step0_before_install() {
  # Step 0 copies lefthook.yml. A `pnpm install` (whose prepare script runs `lefthook install`) or a
  # `lefthook install` that runs first writes a stub lefthook.yml, and Step 0's guard then refuses the
  # scaffold. So in the TS stack files the first install must come after the Step 0 line. FastAPI has
  # no install that writes a lefthook config (its `lefthook install` is a later Step B2 note), so its
  # Step 0 line is anchored to the step 6b section instead, and still ordered before any install it
  # mentions. Every stack file must name its own STACK value on that line, because the Step 0 and
  # Step B3 fences derive the template trees from it. TIMELESS: the order is a property of the guard.
  header "Scaffold runs kit Step 0 before the first install"
  local f bad="" s0 step0 inst st vals step0_line h6b hnext templated base_line agents_line fmt_line inst_pat step_ad agents_step
  for st in nestjs nextjs vite-react fastapi; do
    f="$SKILLS_DIR/scaffold/$st/source-files.md"
    if [[ ! -f "$f" ]]; then bad+="$f — file not found"$'\n'; continue; fi
    vals=$(grep -oE 'STACK=[a-z-]+' "$f" | sort -u || true)
    [[ "$vals" == "STACK=$st" ]] || bad+="$f — must name STACK=$st and no other STACK value (found: ${vals:-none})"$'\n'
    step0_line=$(grep -m1 -E 'Step \*\*0\*\*' "$f" || true)
    [[ "$step0_line" == *"STACK=$st"* ]] || bad+="$f — must name STACK=$st on the Step 0 line"$'\n'
    step0=$(grep -nE 'Step \*\*0\*\*' "$f" | head -n 1 | cut -d: -f1 || true)
    templated=0
    for h6b in ${TEMPLATED_STACKS[@]+"${TEMPLATED_STACKS[@]}"}; do
      if [[ "$h6b" == "$st" ]]; then templated=1; fi
    done
    # A templated stack runs kit Step 0 for PART=base, PART=stack and PART=agents; its install commands are
    # the ones on a line of their own (prose notes mention `pnpm install` too).
    inst_pat='pnpm install|lefthook install'
    if [[ "$templated" == 1 ]]; then inst_pat='^(pnpm install|lefthook install)'; fi
    inst=$(grep -nE "$inst_pat" "$f" | head -n 1 | cut -d: -f1 || true)
    if [[ "$templated" == 1 ]]; then
      base_line=$(grep -nE 'STACK=.*PART=base|PART=base.*STACK=' "$f" | head -n 1 | cut -d: -f1 || true)
      agents_line=$(grep -nE 'STACK=.*PART=agents|PART=agents.*STACK=' "$f" | head -n 1 | cut -d: -f1 || true)
      fmt_line=$(grep -nE '^pnpm format' "$f" | head -n 1 | cut -d: -f1 || true)
      # FastAPI has no pnpm: its AGENTS.md copy must follow the verification-gate step instead.
      if [[ "$st" == fastapi ]]; then fmt_line=$(grep -nE '^### [0-9]+[a-z]?\. Verification gate' "$f" | head -n 1 | cut -d: -f1 || true); fi
      if [[ -z "$base_line" ]]; then
        bad+="$f — no kit Step 0 instruction with STACK=$st and PART=base"$'\n'
      elif [[ -n "$inst" && "$base_line" -ge "$inst" ]]; then
        bad+="$f:$base_line — the PART=base copy comes after the first install (line $inst)"$'\n'
      fi
      if [[ -z "$agents_line" || -z "$fmt_line" ]]; then
        bad+="$f — needs a PART=agents instruction and a pnpm format line (the AGENTS.md copy must follow the format step)"$'\n'
      elif [[ "$agents_line" -le "$fmt_line" ]]; then
        bad+="$f:$agents_line — the PART=agents copy comes before the pnpm format line ($fmt_line); prettier would reformat AGENTS.md"$'\n'
      fi
    fi
    if [[ "$st" == fastapi && -n "$step0" ]]; then
      h6b=$(grep -nE '^### 6b\.' "$f" | head -n 1 | cut -d: -f1 || true)
      hnext=$(awk -v h="${h6b:-0}" 'NR > h && /^### / { print NR; exit }' "$f")
      s0=${base_line:-$step0}
      if [[ -z "$h6b" || "$s0" -le "$h6b" || ( -n "$hnext" && "$s0" -ge "$hnext" ) ]]; then
        bad+="$f:$s0 — the Step 0 line must be in the step 6b section"$'\n'
      fi
    fi
    # PART=settings and PART=late refuse until AGENTS.md exists, so the "Steps A through D" instruction
    # must come after the step that writes AGENTS.md (which follows the verification gate).
    step_ad=$(grep -nE 'A through D' "$f" | head -n 1 | cut -d: -f1 || true)
    agents_step=$(grep -nE '^### [0-9]+[a-z]?\. .*AGENTS\.md' "$f" | head -n 1 | cut -d: -f1 || true)
    if [[ -z "$step_ad" || -z "$agents_step" ]]; then
      bad+="$f — needs a \"Steps A through D\" instruction and an AGENTS.md step heading"$'\n'
    elif [[ "$step_ad" -le "$agents_step" ]]; then
      bad+="$f:$step_ad — \"Steps A through D\" comes before the AGENTS.md step (line $agents_step)"$'\n'
    fi
    if [[ -z "$step0" ]]; then
      bad+="$f — no kit Step 0 instruction"$'\n'
    elif [[ -n "$inst" && "$inst" -lt "$step0" ]]; then
      bad+="$f:$inst — install runs before kit Step 0 (line $step0)"$'\n'
    fi
  done
  report "${bad%$'\n'}" \
    "A stack runs its first install before kit Step 0 — move the Step 0 instruction ahead of it" \
    "Every scaffold stack runs kit Step 0 before its first install"
}

check_harness_version_matches_plugin() {
  # Scaffold source-files.md embed "templatecentral_version" in the harness.json template they write.
  # If this version drifts from plugin.json on a version bump, scaffolded projects report the wrong generator version.
  # ECOSYSTEM-ERA: tied to the current plugin semver scheme; revisit if versioning strategy changes.
  header "harness.json templatecentral_version matches plugin.json"
  local plugin_json=".claude-plugin/plugin.json"
  if [[ ! -f "$plugin_json" ]]; then
    pass "No plugin.json found — skipping harness version check"
    return
  fi
  local plugin_version
  plugin_version=$(grep '"version"' "$plugin_json" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -1)
  report "$(scan "" '"templatecentral_version"' "\"$plugin_version\"")" \
    "templatecentral_version in harness.json template does not match plugin.json ($plugin_version) — update scaffold and migrate source-files.md" \
    "templatecentral_version matches plugin.json ($plugin_version)"
}

check_agents_marker_not_drifted_to_semver() {
  # The AGENTS.md line-1 marker (`<!-- templateCentral: <stack>@X.Y.Z -->`) is a migration schema
  # floor, NOT plugin semver. Legitimate values: @1.0.0 (migrate light-adoption / legacy examples)
  # and @HARNESS_SCHEMA_VERSION (full current harness). The failure mode this guards against is a
  # well-meaning "version bump" pushing a marker UP to the plugin semver (e.g. 4.5.0), which would
  # break migrate Phase 0's floor logic. Rule: every marker version must be <= HARNESS_SCHEMA_VERSION.
  # ECOSYSTEM-ERA: tied to the current plugin semver scheme; the floor marker and schema version concept may evolve.
  header "AGENTS.md schema marker not drifted above HARNESS_SCHEMA_VERSION ($HARNESS_SCHEMA_VERSION)"
  # Only the marker comment counts; prose mentions like "@4.0.0 through @4.x" are ignored.
  # Numeric per-component compare in awk instead of a sort -V subshell per marker.
  report "$(grep -rnoE '<!-- templateCentral: [a-z<>-]+@[0-9]+\.[0-9]+\.[0-9]+' "$SKILLS_DIR/" 2>/dev/null \
    | awk -v floor="$HARNESS_SCHEMA_VERSION" '
        BEGIN { split(floor, f, ".") }
        {
          v = $0; sub(/.*@/, "", v); split(v, p, ".")
          for (i = 1; i <= 3; i++) {
            if (p[i] + 0 > f[i] + 0) { print; next }
            if (p[i] + 0 < f[i] + 0) next
          }
        }' || true)" \
    "AGENTS.md schema marker exceeds HARNESS_SCHEMA_VERSION ($HARNESS_SCHEMA_VERSION) — the marker is a migration floor, not plugin semver; revert it, or bump HARNESS_SCHEMA_VERSION deliberately if the harness structure changed" \
    "All AGENTS.md schema markers <= @$HARNESS_SCHEMA_VERSION"
}

# ── RUN ALL CHECKS ─────────────────────────────────────────────────────────────

echo "=== templateCentral skill lint ==="
echo "Checking: $SKILLS_DIR/"
echo ""
echo "TIMELESS"
check_no_cve_identifiers
check_no_jurisdiction_specific
check_no_hardcoded_secrets
check_no_ghost_agent_names
check_no_comment_narration
check_owasp_llm_sections_complete
check_skillmd_description_length
check_ref_file_headers
check_skillmd_body_length
check_nesting_depth
check_seeded_skills_scope_tools
check_no_unscoped_bash_grant
check_seeded_skill_paths_are_directories
check_no_toplevel_command_in_hooks
check_hook_command_uses_args_array
check_scaffold_seeds_complete_harness
check_template_trees_complete
check_no_template_skill_md
check_copy_script_single
check_step0_before_install
check_migrate_hook_inventory_matches_kit
check_duplicated_iam_blocks_match
check_yaml_fences_parse
check_no_absolute_plugin_path
check_skilldir_refs_resolve
check_ref_header_prereq_suffix
check_no_husky
check_lefthook_prepare_has_fallback
check_no_bare_nextjs_route_handlers
check_no_postToolUse_full_test_suite
check_no_bare_pytest_invocation
echo ""
echo "ECOSYSTEM-ERA"
check_no_version_pins
check_no_bcrypt
check_no_deprecated_zod_flatten
check_no_middleware_ts
check_no_pragma_or_expires_headers
check_no_jest_apis_in_skills
check_no_globals_jest_in_vitest_projects
check_no_sync_secret_comparison
check_no_zod_string_format_methods
check_no_zod_deprecated_message_key
check_no_mypy_in_postToolUse
check_no_env_api_base_url_fallback
check_no_tanstack_isLoading
check_no_tanstack_isInitialLoading
check_no_starlette_startup_events
check_no_fastapi_orjson_response
check_security_seeds_present
check_harness_version_matches_plugin
check_agents_marker_not_drifted_to_semver
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== LINT FAILED — fix the above before pushing ==="
  exit 1
fi

echo "=== All checks passed ==="
