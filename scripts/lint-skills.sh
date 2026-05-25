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
  # shared-code-standards (→ cat standards/code-standards/<stack>.md).
  header "Ghost agent / skill names"
  local matches
  matches=$(grep -rEn '`shared-(build|review|test|update|cleanup)-agent`|templatecentral:(fastapi|nestjs|nextjs|vite-react)-scaffold|templatecentral:shared-migrate|`shared-migrate-database`|templatecentral:shared-audit|`shared-code-standards`' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "Ghost agent/skill name — use templatecentral:build, :review, :test, :cleanup, :scaffold, :migrate, or :audit"
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
  for file in $postToolUse_files; do
    if grep -A15 '"PostToolUse"' "$file" 2>/dev/null | grep -q 'mypy'; then
      mypy_in_postToolUse="$mypy_in_postToolUse\n$file"
    fi
  done
  if [[ -n "$mypy_in_postToolUse" ]]; then
    echo -e "$mypy_in_postToolUse"
    fail "mypy in PostToolUse — use pyright instead (2-5x faster, community standard as of May 2026)"
  else
    pass "No mypy in PostToolUse hook"
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
  for file in $postToolUse_files; do
    # Find lines with pnpm test or pytest inside a PostToolUse context
    if grep -A15 '"PostToolUse"' "$file" 2>/dev/null | grep -qE '"(pnpm test|pytest|npm test|yarn test)'; then
      test_in_postToolUse="$test_in_postToolUse\n$file"
    fi
  done
  if [[ -n "$test_in_postToolUse" ]]; then
    echo -e "$test_in_postToolUse"
    fail "Full test suite in PostToolUse — use Stop hook for tests; PostToolUse should run tsc --noEmit only"
  else
    pass "No full test suite in PostToolUse hook"
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
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "=== LINT FAILED — fix the above before pushing ==="
  exit 1
fi

echo "=== All checks passed ==="
