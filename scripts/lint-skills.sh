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
  # comments.md, applied here to scripts/*.sh and bash fences in skill markdown.
  header "Change-narration comments"
  local patterns="$SKILLS_DIR/scaffold/shared/comment-hygiene-patterns.txt"
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
    FILENAME !~ /\.sh$/ {
      if ($0 == "```bash") { in_bash = 1; next }
      if ($0 == "```") { in_bash = 0; next }
      if (!in_bash) next
    }
    /^[[:space:]]*#/ {
      body = $0
      sub(/^[[:space:]]*#[[:space:]]?/, "", body)
      if (body != "") { print body; print FILENAME >> src }
    }'
  : > "$tmp/src"
  awk -v src="$tmp/src" "$extract" scripts/*.sh > "$tmp/text" 2>/dev/null || true
  find "$SKILLS_DIR" -name '*.md' -exec awk -v src="$tmp/src" "$extract" {} + >> "$tmp/text"
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
  header "Ref file <!-- ref: --> headers"
  local bad="" f firstline
  while IFS= read -r f; do
    firstline=""
    IFS= read -r firstline < "$f" || true
    [[ "$firstline" == "<!-- ref:"* ]] || bad+="$f"$'\n'
  done < <(find "$SKILLS_DIR" -name '*.md' ! -name 'SKILL.md' ! -name 'CONVENTIONS.md' 2>/dev/null)
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
  # With default SKILLS_DIR="skills": NF>5 catches skills/a/b/c/d/file.md (4+ dirs deep).
  header "Nesting depth (<=3 levels under skills/)"
  local base
  base=$(awk -F'/' '{print NF}' <<<"$SKILLS_DIR")
  report "$(find "$SKILLS_DIR" -name '*.md' ! -name 'SKILL.md' ! -name 'CONVENTIONS.md' \
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
  local bad="" m
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
    'stop_hook_active' '--no-verify' 'AKIA'
    'node' 'python3'
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
    'stop_hook_active' '--no-verify' 'AKIA' 'lefthook.yml'
  )
  local missing="" tok f kf all_kit="" v other
  for kf in "${kit_files[@]}"; do
    [[ -f "$kf" ]] || missing+="$kf — file not found"$'\n'
  done
  if [[ -z "$missing" ]]; then
    all_kit=$(cat "${kit_files[@]}")
    for tok in "${kit_tokens[@]}"; do
      grep -qF -- "$tok" <<<"$all_kit" || missing+="$kit_dir/harness-kit*.md — missing harness element: $tok"$'\n'
    done
    for v in ts fastapi; do
      for tok in "${variant_tokens[@]}"; do
        grep -qF -- "$tok" "$kit_dir/harness-kit-$v.md" || \
          missing+="$kit_dir/harness-kit-$v.md — variant missing harness element: $tok"$'\n'
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
    "Harness check failed — kit (scaffold/shared/harness-kit*.md) must contain all universal tokens and each variant the full per-stack set; all 4 scaffolds + the migrate router must load the index, both shared files, and their own variant; each must seed a *-verify/SKILL.md" \
    "Shared harness kit contains all universal tokens; every scaffold/migrate loader loads its own variant"
}

check_migrate_hook_inventory_matches_kit() {
  # migrate/general/phase-4-upgrade.md enumerates the kit's hooks by name in prose (Step 4d),
  # separate from the kit's own authoring blocks — a hook added to the kit without updating
  # that list leaves every migrated project short a hook.
  header "migrate hook inventory matches the harness kit"
  local kit_dir="$SKILLS_DIR/scaffold/shared"
  local migrate="$SKILLS_DIR/migrate/general/phase-4-upgrade.md"
  local kit_files=("$kit_dir"/harness-kit*.md)
  if [[ ! -f "${kit_files[0]}" || ! -f "$migrate" ]]; then
    fail "Missing $kit_dir/harness-kit*.md or $migrate"
    return
  fi
  local hooks missing="" h
  hooks=$(cat "${kit_files[@]}" | grep -oE '^\*\*`\.claude/hooks/[a-zA-Z0-9_-]+' | sed -E 's#.*/##' | sort -u)
  for h in $hooks; do
    grep -qF -- "$h" "$migrate" || missing+="migrate is missing hook: $h"$'\n'
  done
  grep -qF -- '.claude/comment-hygiene-patterns.txt' "$migrate" || \
    missing+="migrate does not mention .claude/comment-hygiene-patterns.txt"$'\n'
  report "$missing" \
    "migrate's hook/file inventory has drifted from the harness kit — update skills/migrate/general/phase-4-upgrade.md Step 4d" \
    "migrate's hook inventory covers every hook + file authored in the harness kit"
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
  # just lint the shell inside it. TIMELESS: catches this bug class regardless of cause.
  header "Seeded \`\`\`yaml fences parse as valid YAML"
  if ! have_python || ! python3 -c 'import yaml' >/dev/null 2>&1; then
    pass "skipped (python3/PyYAML not available)"
    return
  fi
  local out
  out=$(python3 - "$SKILLS_DIR" <<'PY'
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
    "Seeded yaml fence(s) fail to parse — check block-scalar (run: |) indentation" \
    "All seeded yaml fences parse"
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

check_no_postToolUse_full_test_suite() {
  # PostToolUse hooks are feedback-only and cannot block execution.
  # Full test suites (pnpm test, pytest, etc.) belong in Stop hooks, not PostToolUse.
  # Running tests on every file edit is slow and masks real TypeScript feedback.
  # TIMELESS: PostToolUse semantic is feedback-only by design in Claude Code.
  header "Full test suite in PostToolUse hook"
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
  # Excluded files are meta-documents (audit checklist, migration guides, scaffold templates)
  # that legitimately reference middleware.ts to explain the deprecation.
  header "middleware.ts references"
  report "$(scan "" 'middleware\.ts' 'audit/implementation' 'migrate/general/phase-4-upgrade' 'scaffold/nextjs/source-files')" \
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
check_harness_version_matches_plugin
check_agents_marker_not_drifted_to_semver
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== LINT FAILED — fix the above before pushing ==="
  exit 1
fi

echo "=== All checks passed ==="
