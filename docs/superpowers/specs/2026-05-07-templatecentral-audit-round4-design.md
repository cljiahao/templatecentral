# templateCentral Round 4 Audit — Design Spec

**Goal:** Fix drifting version pins, fill missing version constraints in rules files, and add security guidance current for May 2026 — without IM8 attribution, CVE identifiers, or patch-level pins.

**Approach:** Two independent groups targeting disjoint concerns — cleanup first, security additions second.

**Architecture:** Markdown-only changes across existing skill and rules files. No new files. No new abstractions.

---

## Context and Rationale

### Version pin policy (established Round 3)

- Major version pins belong in `.claude/rules/*.md` only — single source of truth
- No patch-level version pins anywhere (they drift stale with no mechanism to update)
- No CVE identifiers or sub-dependency pins in skills prose

### Security attribution policy (established Round 3)

- IM8 codes must not appear in any file — templateCentral is used across public and private sector internationally
- Security guidance is valid industry practice regardless of regulatory framework — keep the guidance, drop the attribution
- OWASP, NIST SP 800-63B, and similar vendor-neutral references are fine

---

## Group 1 — Version Cleanup

**Files:** `AGENTS.md`, `.claude/rules/nextjs.md`, `.claude/rules/fastapi.md`, `skills/fastapi-add-auth/SKILL.md`

### AGENTS.md — remove patch-level Next.js pin

**Current (line 117):**
```
Minimum safe: **16.2.4+** or **15.5.9+** (15.x) (fixes auth-related rendering bugs). Keep Next.js current — run `shared-update-agent` monthly.
```

**Replace with:**
```
Keep Next.js current — run `shared-update-agent` monthly.
```

The patch numbers are policy violations (drifting CVE pins). The major version (16) is already captured in `.claude/rules/nextjs.md`.

### .claude/rules/nextjs.md — add Node.js requirement

Next.js 16 dropped Node 18 support; minimum is Node ≥20.9.0. Add to the Stack line:

**Current:**
```
Stack: Next.js 16, React 19, TypeScript 6, Tailwind CSS 4, pnpm 10, Turbopack, Playwright, Vitest.
```

**Replace with:**
```
Stack: Next.js 16, React 19, TypeScript 6, Tailwind CSS 4, pnpm 10, Node.js ≥20.9.0, Turbopack, Playwright, Vitest.
```

### .claude/rules/fastapi.md — tighten Pydantic, add Starlette

`Pydantic v2` is too loose. `v2.9.0` is when `model_validate_strings` and discriminated unions stabilized. FastAPI 0.136+ depends on Starlette 1.0 (stable since late 2025). Update the Stack line accordingly.

**Current Stack line:**
```
Stack: FastAPI 0.136+, Python 3.13, Pydantic v2, SQLAlchemy 2 / SQLModel, Alembic, pytest, Docker.
```

**Replace with:**
```
Stack: FastAPI 0.136+, Python 3.13, Pydantic ≥2.9.0, Starlette 1.0, SQLAlchemy 2 / SQLModel, Alembic, pytest, Docker.
```

### skills/fastapi-add-auth/SKILL.md — remove slowapi version pin

The `slowapi>=0.1.9` pin is a patch-level CVE pin violating policy. Change to just `slowapi`.

**Current (line ~276):**
```
slowapi>=0.1.9
```

**Replace with:**
```
slowapi
```

---

## Group 2 — Security Additions

**Files:** `AGENTS.md`, `skills/shared-add-error-handling/SKILL.md`, `skills/nextjs-add-auth/SKILL.md`, `skills/shared-add-ai-security/SKILL.md`

### AGENTS.md — OWASP A03:2025 Supply Chain framing

The existing supply chain section already has SBOM and `pnpm audit` / `pip-audit` guidance. Add one sentence to anchor it to the 2025 Top 10 ranking — supply chain rose from unranked to #3.

Locate the supply chain section header and add immediately after:

```
Supply chain attacks are OWASP A03:2025 — the third most critical web application risk category. Maintain an SBOM and run `pnpm audit` / `pip-audit` in CI on every dependency update.
```

### skills/shared-add-error-handling/SKILL.md — OWASP A10:2025 note

OWASP A10:2025 is "Mishandling Exceptional Conditions" — a new category (replaced 2021's SSRF) covering unhandled exceptions that leak stack traces, internal state, or sensitive data. Add a security checklist bullet:

```
- **Unhandled exceptions (OWASP A10:2025)**: Never let exceptions surface raw to clients — stack traces and internal messages are A10:2025 violations. All error handlers must return generic user-facing messages; log the full detail server-side only.
```

### skills/nextjs-add-auth/SKILL.md — better-auth v1.6 freshAge note

better-auth 1.6 changed session freshness from `updatedAt` to `createdAt` — a silent behavioral breaking change. Apps with short `freshAge` windows that relied on activity-based refresh will see users unexpectedly challenged for re-authentication.

Add a callout near the session configuration steps (where `freshAge` is set):

```
> **better-auth ≥1.6**: `freshAge` is measured from session `createdAt`, not last activity. If you set a short `freshAge` (e.g. 43200 for AAL2), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.
```

### skills/shared-add-ai-security/SKILL.md — AWS Responsible AI Lens reference

The skill currently covers OWASP LLM Top 10 v2.0. Add a reference to the AWS Responsible AI Lens (re:Invent 2025) as a complementary framework for production AI system reviews.

Add after the OWASP LLM Top 10 section:

```markdown
## AWS Responsible AI Lens

The AWS Responsible AI Lens (re:Invent 2025) defines 10 dimensions for evaluating production AI systems. Use it alongside OWASP LLM Top 10 for pre-launch reviews:

- **Controllability** — ability to override, retrain, or shut down the model
- **Privacy** — data minimization, consent, and PII handling
- **Security** — prompt injection, adversarial input, model extraction defense
- **Safety** — preventing harmful outputs across user populations
- **Veracity** — factual accuracy, hallucination detection, grounding
- **Robustness** — performance under distribution shift and edge inputs
- **Fairness** — equitable outcomes across demographic groups
- **Explainability** — traceability from input to output decision
- **Transparency** — disclosure of AI involvement to end users
- **Governance** — audit trails, policy enforcement, accountability

No single framework covers everything — OWASP LLM Top 10 focuses on attack vectors; the Responsible AI Lens focuses on systemic trustworthiness. Run both checklists before shipping AI features to production.
```

---

## What Is Not Changing

- Security guidance content — Argon2id, log isolation, rate limiting, malware scanning — remains intact
- No changes to non-affected skills
- No structural refactoring
- No new version pins added (policy: major versions in rules files only)
- `shared-drift-check` Step 6 remains the canonical home for CVE tracking

---

## Acceptance Criteria

- [ ] `AGENTS.md` contains no patch-level version pins (no `16.2.4+` or `15.5.9+`)
- [ ] `.claude/rules/nextjs.md` Stack line includes `Node.js ≥20.9.0`
- [ ] `.claude/rules/fastapi.md` Stack line reads `Pydantic ≥2.9.0, Starlette 1.0`
- [ ] `skills/fastapi-add-auth/SKILL.md` contains no `slowapi>=` version pin
- [ ] `AGENTS.md` supply chain section references OWASP A03:2025
- [ ] `skills/shared-add-error-handling/SKILL.md` has OWASP A10:2025 bullet
- [ ] `skills/nextjs-add-auth/SKILL.md` has better-auth `freshAge` callout
- [ ] `skills/shared-add-ai-security/SKILL.md` has AWS Responsible AI Lens section
- [ ] `grep -rn "IM8" skills/ AGENTS.md .claude/` returns zero output
- [ ] `grep -rn "16\.2\.4\|15\.5\.9\|slowapi>=" skills/ AGENTS.md` returns zero output
