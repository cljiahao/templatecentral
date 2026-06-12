#!/usr/bin/env bash
# scripts/lint-skills.sh — mechanical pattern checks for templateCentral skills
#
# Run locally:  bash scripts/lint-skills.sh
# Run in CI:    bash scripts/lint-skills.sh
#
# HOW TO ADD A NEW CHECK
# 1. Write a check_* function following the pattern below.
# 2. Add a comment explaining WHY the pattern is banned and when to revisit it.
# 3. Call the function in the "Run all checks" section at the bottom.
# 4. If it's ecosystem-era (tied to a specific stack version), mark it ECOSYSTEM-ERA
#    so future maintainers know to revisit it when the stack upgrades.
#
# TIMELESS checks: always wrong regardless of stack version.
# ECOSYSTEM-ERA checks: correct for the current stack; review on major upgrades.

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
HARNESS_SCHEMA_VERSION="4.0.0"

fail() { echo "FAIL: $*"; FAILED=1; }
pass() { echo "OK:   $*"; }
header() { echo ""; echo "── $* ──"; }

# ── TIMELESS ──────────────────────────────────────────────────────────────────

check_no_cve_identifiers() {
  # CVE IDs drift — advisories get patched, re-scored, or superseded.
  # Skills must not reference CVE-XXXX-NNNNN. Use "security advisory" language instead.
  header "CVE identifiers"
  local matches
  matches=$(grep -rn 'CVE-[0-9]\{4\}-[0-9]\+' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "CVE identifiers found — replace with 'security advisory' language"
  else
    pass "No CVE identifiers"
  fi
}

check_no_jurisdiction_specific() {
  # templateCentral is industry- and country-neutral.
  # Known jurisdiction-specific framework names must not appear in skills.
  # ADD TO THIS LIST when a new jurisdiction-specific term is discovered.
  # Remove from this list only if the project explicitly targets that jurisdiction.
  # audit/implementation.md is excluded — it names these patterns in its C6 check and changelog.
  header "Jurisdiction-specific content"
  local pattern='IM8|MAS TRM|GCC2\.0|NRIC|SingPass|MyInfo|PDPA|HIPAA|PCI.DSS|SOC 2|FedRAMP|DISA STIG|NIST SP 800-63'
  local matches
  matches=$(grep -rEn "$pattern" "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Jurisdiction-specific content found — skills must be country/industry neutral"
  else
    pass "No jurisdiction-specific content"
  fi
}

check_no_hardcoded_secrets() {
  # Real secret values must never appear in skill code examples.
  # Safe: placeholders (<your-secret>), change-me strings, env refs (${VAR}), comments (#).
  header "Hardcoded secrets"
  local pattern='(?i)(secret|api_key|password|database_url)\s*=\s*(?![<$"\x27\s#])(?!.*change.me)(?!.*your[-_])(?!.*example).{8,}'
  local matches
  matches=$(grep -rPn "$pattern" "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Potential hardcoded secrets — use placeholder syntax (e.g. <your-secret>)"
  else
    pass "No hardcoded secrets"
  fi
}

check_no_ghost_agent_names() {
  # templateCentral v4.0 renamed agent dispatch references to registered skill names.
  # The old shared-*-agent names no longer exist and must not appear in skill files.
  # Correct names: templatecentral:build, templatecentral:review, templatecentral:test,
  # templatecentral:cleanup. Stack-specific scaffold names (fastapi-scaffold etc.) were
  # unified as templatecentral:scaffold.
  # Also banned: templatecentral:shared-migrate (→ templatecentral:migrate),
  # shared-migrate-database (→ templatecentral:migrate),
  # templatecentral:shared-audit (→ templatecentral:audit),
  # shared-code-standards (→ templatecentral:standards),
  # stack-specific code-standards skill names (→ templatecentral:standards),
  # nextjs-add-auth (→ templatecentral:add (auth)).
  header "Ghost agent / skill names"
  local matches
  matches=$(grep -rEn '`shared-(build|review|test|update|cleanup)-agent`|templatecentral:(fastapi|nestjs|nextjs|vite-react)-scaffold|templatecentral:shared-migrate|`shared-migrate-database`|templatecentral:shared-audit|`shared-code-standards`|`(fastapi|nestjs|nextjs|vite-react)-code-standards`|`nextjs-add-auth`' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Ghost agent/skill name — use templatecentral:build, :review, :test, :cleanup, :scaffold, :migrate, :audit, or :standards"
  else
    pass "No ghost agent/skill names"
  fi
}

# ── ECOSYSTEM-ERA ──────────────────────────────────────────────────────────────

check_no_version_pins() {
  # SSOT policy: version pins belong only in .claude/rules/*.md, not in SKILL.md files.
  # EXCEPTION: shadcn@latest is the official shadcn CLI invocation, not a version pin.
  # REVISIT: if the SSOT policy changes, remove this check.
  header "Version pins in skills (SSOT)"
  local found=0
  while IFS= read -r match; do
    # Skip shadcn@latest — this is a CLI tool invocation, not a dependency pin
    [[ "$match" =~ shadcn@latest ]] && continue
    echo "$match"
    found=1
  done < <(grep -rn '@[a-zA-Z][a-zA-Z0-9_/@-]*@[0-9^~><]' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ $found -eq 1 ]]; then
    fail "Version pins found — move floors/pins to .claude/rules/*.md"
    FAILED=1
  else
    pass "No version pins in skills"
  fi
}

check_no_bcrypt() {
  # Project standard is argon2id (OWASP/NIST SP 800-63B recommendation).
  # REVISIT: if the project standard changes, update this check.
  # audit/implementation.md is excluded — it references bcrypt in its own checklist items.
  header "bcrypt references"
  local matches
  matches=$(grep -rn '\bbcrypt\b' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "bcrypt found — project standard is argon2id"
  else
    pass "No bcrypt references"
  fi
}

check_no_deprecated_zod_flatten() {
  # Zod v4 deprecated error.flatten() — use z.flattenError(error) instead.
  # REVISIT: if the project ever drops to Zod v3, remove this check.
  # audit/implementation.md is excluded — it references .flatten() in its own checklist items.
  header "Deprecated Zod .flatten()"
  local matches
  matches=$(grep -rn '\.flatten()' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail ".flatten() is deprecated in Zod v4 — use z.flattenError()"
  else
    pass "No deprecated .flatten() calls"
  fi
}

check_no_middleware_ts() {
  # Next.js 16 replaced middleware.ts with proxy.ts for auth/proxy patterns.
  # REVISIT: if Next.js reintroduces middleware.ts, remove or adjust this check.
  # Excluded files are meta-documents (audit checklist, migration guides, scaffold templates)
  # that legitimately reference middleware.ts to explain the deprecation.
  header "middleware.ts references"
  local matches
  matches=$(grep -rn 'middleware\.ts' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    | grep -v 'migrate/general/implementation' \
    | grep -v 'scaffold/nextjs/source-files' \
    || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "middleware.ts found — Next.js 16 uses proxy.ts"
  else
    pass "No middleware.ts references"
  fi
}

check_no_pragma_or_expires_headers() {
  # Pragma: no-cache and Expires: 0 are HTTP/1.0 relics — deprecated in HTTP/1.1+.
  # Cache-Control is sufficient. These headers add noise without benefit.
  # REVISIT: if a target environment requires HTTP/1.0 compat, reconsider.
  header "Deprecated HTTP/1.0 cache headers"
  local matches
  matches=$(grep -rEn "Pragma: no-cache|Expires: 0" "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Deprecated HTTP/1.0 headers found — Cache-Control is sufficient"
  else
    pass "No deprecated HTTP/1.0 cache headers"
  fi
}

check_no_zod_string_format_methods() {
  # Zod v4 deprecated chained string-format methods: .string().url(), .string().datetime(),
  # .string().email(), .string().uuid(). Use top-level z.url(), z.iso.datetime(), z.email(), z.uuid() instead.
  # ECOSYSTEM-ERA: correct for Zod v4+. Revisit if the project downgrades to Zod v3.
  # audit/implementation.md is excluded — it may reference these in checklist items.
  header "Deprecated Zod v4 string format methods"
  local matches
  matches=$(grep -rEn 'z\.string\(\)\.(url|datetime|email|uuid)\(' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Deprecated Zod string-chained format method — use top-level z.url(), z.iso.datetime(), z.email(), z.uuid()"
  else
    pass "No deprecated Zod string format methods"
  fi
}

check_no_jest_apis_in_skills() {
  # All Node scaffold stacks (NestJS, Next.js, Vite+React) use Vitest — not Jest.
  # jest.fn(), jest.spyOn(), and jest-e2e.json must not appear in skill code examples.
  # ECOSYSTEM-ERA: correct for NestJS 11+ (Vitest default). Revisit if the project adopts Jest.
  # audit/implementation.md is excluded — it may reference these patterns in checklist items.
  header "Jest APIs in skill code examples"
  local matches
  matches=$(grep -rEn 'jest\.(fn|spyOn|mock|clearAllMocks|resetAllMocks|restoreAllMocks)\(|jest-e2e\.json' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Jest API found in skill code example — all Node stacks use Vitest (vi.fn(), vi.spyOn())"
  else
    pass "No Jest APIs in skill code examples"
  fi
}

check_no_globals_jest_in_vitest_projects() {
  # All Node scaffold stacks use Vitest with globals: false — eslint-globals-jest is not needed.
  # Adding ...globals.jest to an ESLint config in a Vitest project is misleading and unused.
  # ECOSYSTEM-ERA: correct for NestJS 11+ / Vite+React (Vitest default). Revisit if Jest is re-adopted.
  # audit/implementation.md is excluded — it may reference this in checklist items.
  header "globals.jest in ESLint config templates"
  local matches
  matches=$(grep -rn 'globals\.jest' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "globals.jest found in ESLint template — Node stacks use Vitest with globals: false; remove globals.jest"
  else
    pass "No globals.jest in ESLint config templates"
  fi
}

check_no_zod_deprecated_message_key() {
  # Zod v4 custom error params use { error: '...' }, not { message: '...' }.
  # { message: '...' } is the Zod v3 form — still accepted but deprecated in v4 and will be removed.
  # ECOSYSTEM-ERA: correct for Zod v4. Revisit if Zod changes error params API.
  # audit/implementation.md is excluded — it may reference this pattern in checklist items.
  header "Deprecated Zod v3 message key in validators"
  local matches
  matches=$(grep -rEn "z\.(email|url|uuid|iso\.datetime)\(\{ message:" "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Zod validator uses deprecated { message: '...' } — use { error: '...' } for custom error messages in Zod v4"
  else
    pass "No deprecated Zod v3 message key in validators"
  fi
}

check_no_sync_secret_comparison() {
  # Comparing stored secrets (hashes, tokens) with == or === is not timing-safe.
  # Use a constant-time function (e.g. crypto.timingSafeEqual, argon2.verify).
  # NOTE: password === confirmPassword in Zod refine() is safe — both are user inputs,
  #       there is no stored value and no timing oracle. This check targets stored values.
  # REVISIT: if a safe wrapper is introduced, refine the pattern.
  header "Unsafe stored-secret comparison"
  local matches
  matches=$(grep -rEn '\b(storedHash|passwordHash|hashedPassword|sessionToken|accessToken|refreshToken)\s*(===|==)\s*' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Timing-unsafe comparison of stored secret — use a constant-time compare function"
  else
    pass "No unsafe stored-secret comparisons"
  fi
}

check_no_mypy_in_postToolUse() {
  # pyright is 2-5x faster than mypy with near-complete spec conformance.
  # mypy in PostToolUse adds 45+ seconds per edit on real projects.
  # REVISIT: if mypy regains a speed advantage or pyright has correctness regressions, update.
  header "mypy in PostToolUse hook"
  local postToolUse_files
  postToolUse_files=$(grep -rln '"PostToolUse"' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  local mypy_in_postToolUse=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if grep -A15 '"PostToolUse"' "$file" 2>/dev/null | grep -q 'mypy'; then
      mypy_in_postToolUse="$mypy_in_postToolUse\n$file"
    fi
  done <<< "$postToolUse_files"
  if [[ -n "$mypy_in_postToolUse" ]]; then
    printf '%b\n' "$mypy_in_postToolUse"
    fail "mypy in PostToolUse — use pyright instead (2-5x faster, community standard as of May 2026)"
  else
    pass "No mypy in PostToolUse hook"
  fi
}

check_no_tanstack_isLoading() {
  # TanStack Query v5 renamed isLoading to isPending on useQuery()/useMutation() destructuring.
  # isLoading still exists as a derived bool on the query object but has different semantics
  # (true when fetching WITH existing data; isPending is true when there is no data yet).
  # Using isLoading instead of isPending causes the loading state to not show on first render.
  # ECOSYSTEM-ERA: correct for TanStack Query v5+. Revisit if the project pins to TQ v4.
  header "TanStack Query v5 isLoading usage"
  local hits
  hits=$(grep -rn '{ .*isLoading.*} = use\(Query\|Mutation\)\|isPending\s*:\s*isLoading\b' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "TanStack Query v5: use isPending (not isLoading) from useQuery/useMutation destructuring"
  else
    pass "No TanStack Query isLoading usage"
  fi
}

check_no_tanstack_isInitialLoading() {
  # TanStack Query v5 deprecated isInitialLoading (alias for isLoading && isLoading) and removed
  # it in v6. Using it causes a runtime error once projects upgrade to v6.
  # ECOSYSTEM-ERA: correct for TanStack Query v5+. Retire when v6 is the project baseline.
  header "TanStack Query v5 isInitialLoading usage"
  local hits
  hits=$(grep -rn '\bisInitialLoading\b' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "TanStack Query v5: isInitialLoading is deprecated (removed in v6); use isPending instead"
  else
    pass "No TanStack Query isInitialLoading usage"
  fi
}

check_no_starlette_startup_events() {
  # Starlette 1.0.0 removed on_startup/on_shutdown event handlers and add_event_handler().
  # FastAPI 0.136.x requires lifespan= context manager exclusively.
  # ECOSYSTEM-ERA: correct for Starlette ≥1.0.0 / FastAPI ≥0.128.0.
  header "Starlette 1.0 deprecated startup events"
  local hits
  hits=$(grep -rn '@app\.on_event\|add_event_handler\|on_startup=\|on_shutdown=' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    | grep -v 'standards/code-standards' \
    || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "Starlette 1.0: use lifespan= context manager — on_startup/on_shutdown/add_event_handler removed"
  else
    pass "No Starlette deprecated startup events"
  fi
}

check_no_fastapi_orjson_response() {
  # ORJSONResponse and UJSONResponse deprecated in FastAPI 0.130+.
  # Native JSON serialization now uses Pydantic's Rust-based serializer.
  # ECOSYSTEM-ERA: correct for FastAPI ≥0.130.0.
  header "Deprecated FastAPI ORJSONResponse/UJSONResponse"
  local hits
  hits=$(grep -rn 'ORJSONResponse\|UJSONResponse' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "FastAPI 0.130+: ORJSONResponse/UJSONResponse deprecated — use standard JSONResponse"
  else
    pass "No deprecated FastAPI ORJSONResponse/UJSONResponse"
  fi
}

check_no_env_api_base_url_fallback() {
  # Vite+React code-standards rule: NEVER use `ENV.API_BASE_URL ?? ''` — use `getApiBaseUrl()`.
  # The fallback '' silently returns empty string when the env var is missing, hiding config errors.
  # getApiBaseUrl() throws at startup so misconfiguration is caught immediately.
  # ECOSYSTEM-ERA: Vite 8 / React 19 stack. Revisit if ENV helper API changes.
  header "ENV.API_BASE_URL ?? '' anti-pattern in Vite skills"
  local matches
  matches=$(grep -rn "API_BASE_URL ?? ''" "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    | grep -v 'code-standards' \
    || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Use getApiBaseUrl() not ENV.API_BASE_URL ?? '' — see code-standards/vite-react.md"
  else
    pass "No ENV.API_BASE_URL ?? '' anti-pattern"
  fi
}

check_no_postToolUse_full_test_suite() {
  # PostToolUse hooks are feedback-only and cannot block execution.
  # Full test suites (pnpm test, pytest, etc.) belong in Stop hooks, not PostToolUse.
  # Running tests on every file edit is slow and masks real TypeScript feedback.
  # TIMELESS: PostToolUse semantic is feedback-only by design in Claude Code.
  header "Full test suite in PostToolUse hook"
  local matches
  matches=$(grep -rn '"PostToolUse"' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'audit/implementation' \
    || true)
  # Check if any PostToolUse block is followed by a test command within 15 lines
  local postToolUse_files
  postToolUse_files=$(grep -rln '"PostToolUse"' "$SKILLS_DIR/" 2>/dev/null | grep -v 'audit/implementation' || true)
  local test_in_postToolUse=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    # Find lines with pnpm test or pytest inside a PostToolUse context
    if grep -A15 '"PostToolUse"' "$file" 2>/dev/null | grep -qE '"(pnpm test|pytest|npm test|yarn test)'; then
      test_in_postToolUse="$test_in_postToolUse\n$file"
    fi
  done <<< "$postToolUse_files"
  if [[ -n "$test_in_postToolUse" ]]; then
    printf '%b\n' "$test_in_postToolUse"
    fail "Full test suite in PostToolUse — use Stop hook for tests; PostToolUse should run tsc --noEmit only"
  else
    pass "No full test suite in PostToolUse hook"
  fi
}

check_harness_version_matches_plugin() {
  # Scaffold source-files.md embed "templatecentral_version" in the harness.json template they write.
  # If this version drifts from plugin.json on a version bump, scaffolded projects report the wrong generator version.
  # TIMELESS: templatecentral_version must always match the plugin's declared version.
  header "harness.json templatecentral_version matches plugin.json"
  local plugin_json=".claude-plugin/plugin.json"
  if [[ ! -f "$plugin_json" ]]; then
    pass "No plugin.json found — skipping harness version check"
    return
  fi
  local plugin_version
  plugin_version=$(grep '"version"' "$plugin_json" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | head -1)
  local mismatches
  mismatches=$(grep -rn '"templatecentral_version"' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v "\"$plugin_version\"" \
    || true)
  if [[ -n "$mismatches" ]]; then
    echo "$mismatches"
    fail "templatecentral_version in harness.json template does not match plugin.json ($plugin_version) — update scaffold and migrate source-files.md"
  else
    pass "templatecentral_version matches plugin.json ($plugin_version)"
  fi
}

check_agents_marker_not_drifted_to_semver() {
  # The AGENTS.md line-1 marker (`<!-- templateCentral: <stack>@X.Y.Z -->`) is a migration schema
  # floor, NOT plugin semver. Legitimate values: @1.0.0 (migrate light-adoption / legacy examples)
  # and @HARNESS_SCHEMA_VERSION (full current harness). The failure mode this guards against is a
  # well-meaning "version bump" pushing a marker UP to the plugin semver (e.g. 4.5.0), which would
  # break migrate Phase 0's floor logic. Rule: every marker version must be <= HARNESS_SCHEMA_VERSION.
  # TIMELESS: bump HARNESS_SCHEMA_VERSION only on a deliberate harness-structure change (then floor markers move with it).
  header "AGENTS.md schema marker not drifted above HARNESS_SCHEMA_VERSION ($HARNESS_SCHEMA_VERSION)"
  local drifted=""
  local line ver
  # Match only the marker comment; ignore prose mentions of "@4.0.0 or later".
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ver=$(echo "$line" | grep -oE '@[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d '@')
    [[ -z "$ver" ]] && continue
    # If sorting {ver, floor} by version puts ver last AND they differ, ver > floor → drift.
    if [[ "$(printf '%s\n%s\n' "$ver" "$HARNESS_SCHEMA_VERSION" | sort -V | tail -1)" == "$ver" \
       && "$ver" != "$HARNESS_SCHEMA_VERSION" ]]; then
      drifted+="$line"$'\n'
    fi
  done < <(grep -rnoE '<!-- templateCentral: [a-z<>-]+@[0-9]+\.[0-9]+\.[0-9]+' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$drifted" ]]; then
    echo "$drifted"
    fail "AGENTS.md schema marker exceeds HARNESS_SCHEMA_VERSION ($HARNESS_SCHEMA_VERSION) — the marker is a migration floor, not plugin semver; revert it, or bump HARNESS_SCHEMA_VERSION deliberately if the harness structure changed"
  else
    pass "All AGENTS.md schema markers <= @$HARNESS_SCHEMA_VERSION"
  fi
}

check_seeded_skills_scope_tools() {
  # Seeded project skills (*-verify, *-migrate) embedded in scaffold templates are written into
  # every scaffolded project. They must declare a tightly-scoped allowed-tools: line — a skill with
  # no allowed-tools inherits unrestricted tool access. templateCentral must model the scoping it
  # preaches in the Skills Security section.
  # TIMELESS: least-agency (OWASP Agentic ASI02) — seeded skills scope their tools.
  header "Seeded project skills declare scoped allowed-tools"
  local files bad
  files=$(grep -rlE '^name: [a-z][a-z-]*-(verify|migrate)$' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -z "$files" ]]; then
    pass "No seeded *-verify/*-migrate skills found"
    return
  fi
  # shellcheck disable=SC2086  # word-splitting is intentional: $files is newline-separated paths
  bad=$(awk '
    /^name: [a-z][a-z-]*-(verify|migrate)$/ { inblock=1; nm=$2; tools=0; ln=FNR; next }
    inblock && /^allowed-tools:[[:space:]]*Bash\(/ { tools=1 }
    inblock && /^---[[:space:]]*$/ { if(!tools) print FILENAME":"ln": "nm" — missing scoped allowed-tools"; inblock=0 }
  ' $files 2>/dev/null || true)
  if [[ -n "$bad" ]]; then
    echo "$bad"
    fail "Seeded skill missing scoped allowed-tools — add e.g. 'allowed-tools: Bash(pnpm *)' to its frontmatter"
  else
    pass "All seeded project skills declare scoped allowed-tools"
  fi
}

check_no_unscoped_bash_grant() {
  # An allowed-tools: line that grants bare 'Bash' (not 'Bash(...)') hands the skill unrestricted
  # shell access — the opposite of least-agency. Every Bash grant must be scoped to a command prefix.
  # TIMELESS: OWASP Agentic ASI02 (Tool Misuse) — never grant unscoped Bash.
  header "No unscoped Bash in allowed-tools grants"
  local hits
  # Match allowed-tools lines mentioning Bash where Bash is NOT immediately followed by '('.
  hits=$(grep -rnE '^allowed-tools:.*\bBash\b' "$SKILLS_DIR/" 2>/dev/null | grep -vE 'Bash\(' || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "Unscoped 'Bash' in allowed-tools — scope it (e.g. Bash(pnpm *), Bash(git *))"
  else
    pass "No unscoped Bash grants"
  fi
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
  local hits
  hits=$(grep -rnE '\.claude/skills/[a-zA-Z<][a-zA-Z<>-]*-(verify|migrate)\.md' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "$hits"
    fail "Flat .claude/skills/<name>.md seeding path found — skills are directories; use .claude/skills/<name>/SKILL.md (flat files only work under .claude/commands/)"
  else
    pass "No flat .claude/skills/<name>.md seeding paths"
  fi
}

check_scaffold_seeds_complete_harness() {
  # Every scaffold + migrate settings.json template must seed the COMPLETE harness: all 7 hook
  # events, the permissions.deny secret-Read block, skillListingBudgetFraction, a reference to
  # each of the 8 .claude/hooks/ scripts, and the seeded *-verify project skill in directory form
  # (.claude/skills/<name>-verify/SKILL.md). Scaffolds additionally INLINE the script bodies (migrate
  # references the same scripts to stay DRY), so scaffolds must also contain the guard-body markers.
  # If an edit silently drops the Stop gate, a guard, or an event, a project ships a harness with a
  # hole and nothing else catches it (Step 3H is a manual checklist). This makes it enforceable.
  # TIMELESS: these are the load-bearing enforcement hooks; their presence is non-negotiable.
  header "Scaffold/migrate templates seed the complete harness"
  local scaffolds=(
    "$SKILLS_DIR/scaffold/fastapi/source-files.md"
    "$SKILLS_DIR/scaffold/nestjs/source-files.md"
    "$SKILLS_DIR/scaffold/nextjs/source-files.md"
    "$SKILLS_DIR/scaffold/vite-react/source-files.md"
  )
  local migrate="$SKILLS_DIR/migrate/general/implementation.md"
  # Present in BOTH scaffold (inline) and migrate (referenced) forms:
  local universal=(
    '"PreToolUse"' '"UserPromptSubmit"' '"PostToolUse"' '"PostToolUseFailure"'
    '"Stop"' '"SubagentStop"' '"SessionStart"'
    'skillListingBudgetFraction' '"Read(.env)"'
    'protect-files.sh' 'block-no-verify.sh' 'user-prompt-guard'
    'post-edit-typecheck.sh' 'post-tool-failure.sh' 'stop-checks.sh'
    'subagent-stop.sh' 'session-context.sh'
    '-verify/SKILL.md'
  )
  # Guard BODIES — scaffolds inline the scripts, so these strings must appear in scaffolds
  # (stop_hook_active = the seeded Stop hook's loop guard — exit 0 before tests when re-entered):
  local bodies=('--no-verify' 'AKIA' 'stop_hook_active')
  local missing="" f tok
  for f in "${scaffolds[@]}" "$migrate"; do
    [[ -f "$f" ]] || { missing+="$f — file not found"$'\n'; continue; }
    for tok in "${universal[@]}"; do
      grep -qF -- "$tok" "$f" || missing+="$f — missing harness element: $tok"$'\n'
    done
  done
  for f in "${scaffolds[@]}"; do
    [[ -f "$f" ]] || continue
    for tok in "${bodies[@]}"; do
      grep -qF -- "$tok" "$f" || missing+="$f — missing inlined guard body: $tok"$'\n'
    done
  done
  if [[ -n "$missing" ]]; then
    echo "$missing"
    fail "A scaffold/migrate template is missing a required harness element — restore it; full set = 7 events + permissions.deny + skillListingBudgetFraction + the 8 .claude/hooks/ scripts (scaffolds inline the bodies, migrate references them)"
  else
    pass "All scaffold/migrate templates seed the complete harness (7 events + permissions.deny + 8 hook scripts)"
  fi
}

check_no_toplevel_command_in_hooks() {
  # Hook commands that read the bash command from top-level `d.command` (or Python d.get('command'))
  # instead of `d.tool_input.command` will silently get an empty string — the check never fires.
  # For Bash tool events, the command lives at tool_input.command, not at the top level.
  # TIMELESS: Claude Code hook stdin schema places tool input under tool_input; this is by design.
  header "Top-level d.command access in hook commands (should be d.tool_input.command)"
  local matches
  matches=$(grep -rn 'd\.command\|d\[.command.\]\|d\.get(.command.' "$SKILLS_DIR/" 2>/dev/null \
    | grep -v 'tool_input' \
    | grep -v 'audit/implementation' \
    || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Hook reads bash command from top-level d.command — use d.tool_input.command (or d.get('tool_input',{}).get('command','') in Python)"
  else
    pass "No top-level d.command access in hook commands"
  fi
}

check_owasp_llm_sections_complete() {
  # add/ai-security/implementation.md must cover all 10 OWASP LLM Top 10 v2.0 sections.
  # A missing section leaves a gap in AI security guidance — agents won't know to guard against it.
  # TIMELESS: LLM01-LLM10 are stable section names; the guidance may evolve but the structure is fixed.
  header "OWASP LLM Top 10 v2.0 completeness in ai-security skill"
  local ai_sec="$SKILLS_DIR/add/ai-security/implementation.md"
  local missing=""
  if [[ ! -f "$ai_sec" ]]; then
    fail "add/ai-security/implementation.md not found"
    return
  fi
  for n in 01 02 03 04 05 06 07 08 09 10; do
    if ! grep -q "### LLM${n}" "$ai_sec" 2>/dev/null; then
      missing="$missing LLM${n}"
    fi
  done
  if [[ -n "$missing" ]]; then
    fail "add/ai-security/implementation.md is missing OWASP LLM Top 10 sections:$missing"
  else
    pass "All LLM01-LLM10 sections present"
  fi
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
check_owasp_llm_sections_complete
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
check_no_postToolUse_full_test_suite
check_no_env_api_base_url_fallback
check_no_tanstack_isLoading
check_no_tanstack_isInitialLoading
check_no_starlette_startup_events
check_no_fastapi_orjson_response
check_no_toplevel_command_in_hooks
check_harness_version_matches_plugin
check_agents_marker_not_drifted_to_semver
check_seeded_skills_scope_tools
check_no_unscoped_bash_grant
check_seeded_skill_paths_are_directories
check_scaffold_seeds_complete_harness
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== LINT FAILED — fix the above before pushing ==="
  exit 1
fi

echo "=== All checks passed ==="
