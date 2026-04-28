# Shared Skills Bug Fixes — Design Spec

**Date:** 2026-04-28
**Scope:** Fix 4 confirmed bug classes across 7 shared skills — accuracy, security, and stale references.

---

## Background

Audit of all 12 shared skills identified 4 bug classes. No architectural changes — all fixes are targeted text edits to SKILL.md files.

---

## Bug 1 — Stack Detection Missing `next.config.mjs`

**Affected skills:** `shared-build-agent`, `shared-test-agent`, `shared-update-agent`, `shared-review-agent`

**Problem:** All 4 skills detect Next.js by checking for `next.config.ts` or `next.config.js`. They do not check for `next.config.mjs`, which is valid ESM config supported by Next.js since v13.1 and commonly used. Projects using `next.config.mjs` would fall through to "unknown stack."

**Fix:** Add `next.config.mjs` to each skill's stack detection check.

### shared-build-agent (line 16)
```
Before: | `next.config.ts` or `next.config.js` | Next.js |
After:  | `next.config.ts`, `next.config.js`, or `next.config.mjs` | Next.js |
```

Also update the error message on line 68:
```
Before: No next.config.ts, vite.config.ts, nest-cli.json, or fastapi in requirements.txt found at project root.
After:  No next.config.ts/.js/.mjs, vite.config.ts/.js, nest-cli.json, or fastapi in requirements.txt found at project root.
```

### shared-test-agent (line 12)
```
Before: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.
After:  check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

### shared-update-agent (line 12)
```
Before: Same as `build-agent`: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.
After:  Same as `build-agent`: check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

### shared-review-agent (line 12)
```
Before: Check for `next.config.ts` → Next.js, `vite.config.ts` → Vite-React, `nest-cli.json` → NestJS, `requirements.txt` containing `fastapi` → FastAPI.
After:  Check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

---

## Bug 2 — Slash-Format Skill Name References

**Affected skills:** `shared-build-agent`, `shared-test-agent`, `shared-update-agent`, `shared-add-error-handling`, `shared-add-logging`, `shared-add-pagination`, `shared-validation-patterns`

**Problem:** Cross-skill references in "Callers" and "Related Skills" sections use `stack/skill-name` slash format (e.g., `nextjs/scaffold`, `shared/add-logging`) instead of the correct dash format (`nextjs-scaffold`, `shared-add-logging`). These sections are read by agents to understand dispatch relationships; wrong names cause lookup failures.

**Fix:** Replace all slash-format references with dash format.

### shared-build-agent — Callers section
```
Before: `nextjs/scaffold`, `vite-react/scaffold`, `fastapi/scaffold`, `nestjs/scaffold`, `shared/update-agent`, `nextjs/add-feature`, `nextjs/add-component`, `nextjs/add-api-route`, `vite-react/add-feature`, `vite-react/add-component`, `fastapi/add-endpoint`, `nestjs/add-module`
After:  `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-update-agent`, `nextjs-add-feature`, `nextjs-add-component`, `nextjs-add-api-route`, `vite-react-add-feature`, `vite-react-add-component`, `fastapi-add-endpoint`, `nestjs-add-module`
```

### shared-update-agent — Callers section
```
Before: `nextjs/scaffold`, `vite-react/scaffold`, `fastapi/scaffold`, `nestjs/scaffold`, `shared/drift-check`
After:  `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-drift-check`
```

### shared-test-agent — "what to dispatch" list (lines 18–21) + Callers section (line 64)
```
Lines 18-21 before: `nextjs/add-test`, `vite-react/add-test`, `fastapi/add-test`, `nestjs/add-test`
Lines 18-21 after:  `nextjs-add-test`, `vite-react-add-test`, `fastapi-add-test`, `nestjs-add-test`

Line 64 before: `nextjs/add-feature`, `nextjs/add-api-route`, `vite-react/add-feature`, `fastapi/add-endpoint`, `nestjs/add-module`
Line 64 after:  `nextjs-add-feature`, `nextjs-add-api-route`, `vite-react-add-feature`, `fastapi-add-endpoint`, `nestjs-add-module`
```

### shared-add-error-handling — Related Skills section
```
Before: `shared/add-logging`, `shared/validation-patterns`
After:  `shared-add-logging`, `shared-validation-patterns`
```

### shared-add-logging — Related Skills section
```
Before: `shared/add-error-handling`, `shared/validation-patterns`
After:  `shared-add-error-handling`, `shared-validation-patterns`
```

### shared-add-pagination — all slash references (body + Related Skills)
```
Before: `shared/add-error-handling` (×2 in body, ×1 in related), `shared/validation-patterns` (×2)
After:  `shared-add-error-handling`, `shared-validation-patterns`
```

### shared-validation-patterns — Related Skills section
```
Before: `shared/add-error-handling`, `shared/add-logging`
After:  `shared-add-error-handling`, `shared-add-logging`
```

---

## Bug 3 — File Upload Security Gaps (`shared-validation-patterns`)

**Problem:** The `fileUploadSchema` extension blocklist and path traversal check have two gaps:

1. **Incomplete extension blocklist.** Current: `['exe', 'sh', 'bat', 'cmd', 'dll']`. Missing dangerous extensions that can execute on Windows or be interpreted server-side: `.com`, `.scr`, `.msi`, `.vbs`, `.ps1`, `.php`, `.jsp`, `.jar`, `.pif`, `.hta`.

2. **Path traversal check does not URL-decode.** The check `!name.includes('..')` catches literal `..` but not URL-encoded variants (`%2e%2e`, `%2e.`, `.%2e`) which can bypass the check if the filename is not decoded before validation.

**Fix:**

```ts
// Before — fileUploadSchema filename refinements:
.refine(
  (name) => !name.includes('..') && !name.startsWith('/'),
  'Invalid filename'
)
.refine(
  (name) => {
    const ext = name.split('.').pop()?.toLowerCase();
    const blocked = ['exe', 'sh', 'bat', 'cmd', 'dll'];
    return !blocked.includes(ext || '');
  },
  'File type not allowed'
),

// After:
.refine(
  (name) => {
    const decoded = decodeURIComponent(name);
    return !decoded.includes('..') && !decoded.startsWith('/') && !decoded.startsWith('./');
  },
  'Invalid filename'
)
.refine(
  (name) => {
    const ext = name.split('.').pop()?.toLowerCase();
    const blocked = [
      'exe', 'com', 'scr', 'pif', 'msi', 'msp',  // Windows executables
      'bat', 'cmd', 'vbs', 'ps1', 'hta',           // Windows scripts
      'sh', 'bash', 'zsh', 'csh',                  // Unix shells
      'php', 'php3', 'php4', 'php5', 'phtml',      // PHP variants
      'jsp', 'jspx', 'jnlp', 'jar',                // Java
      'dll', 'so', 'dylib',                         // Libraries
    ];
    return !blocked.includes(ext || '');
  },
  'File type not allowed'
),
```

The `decodeURIComponent` call must be wrapped in try/catch for malformed URIs — refinement returns `false` on decode error:

```ts
.refine(
  (name) => {
    try {
      const decoded = decodeURIComponent(name);
      return !decoded.includes('..') && !decoded.startsWith('/') && !decoded.startsWith('./');
    } catch {
      return false;
    }
  },
  'Invalid filename'
)
```

---

## Bug 4 — Missing Security Audit in `shared-update-agent`

**Problem:** After applying dependency updates and running the build, `shared-update-agent` does not check for known CVEs in the updated packages. A package bump could introduce a vulnerability that passes the build check silently.

**Fix:** Add a security audit step after a successful build:

### Node stacks — after step 6 (dispatch build-agent):
```
6. Dispatch `build-agent`
7. If build fails → rollback (see Rollback below)
7a. Run `pnpm audit --audit-level=high` (or `npm audit --audit-level=high`)
    - If high/critical CVEs found: report them in the summary under "Security advisories"
    - Do NOT auto-rollback on audit findings — report only; let the user decide
8. Report results (see Reporting below)
```

### FastAPI — after step 6:
```
6. Dispatch `build-agent`
7. If build fails → rollback
7a. Run `pip-audit` (if installed) or skip with note "pip-audit not installed — skipping CVE check"
    - If vulnerabilities found: report them under "Security advisories"
    - Do NOT auto-rollback — report only
8. Report results
```

### Reporting section — add advisory block:
```
Security advisories (from audit):
- some-package 2.3.0: CVE-2026-XXXX (high) — see advisory URL
```

If no advisories: omit the block entirely (do not show "Security advisories: none").

---

## Non-goals

- No changes to stack-specific scaffold skills (nextjs-scaffold, fastapi-scaffold, etc.)
- No changes to skills not listed above
- No refactoring of validation logic beyond the two targeted fixes
- No auto-rollback on CVE findings (report only — user decides)

---

## Acceptance Criteria

- [ ] `shared-build-agent`, `shared-test-agent`, `shared-update-agent`, `shared-review-agent`: stack detection includes `next.config.mjs`
- [ ] `shared-build-agent` error message updated to include `.mjs`
- [ ] All 7 skills: no remaining `stack/skill-name` slash-format cross-skill references
- [ ] `shared-validation-patterns` `fileUploadSchema`: extension blocklist expanded to include Windows executables/scripts, Unix shells, PHP/Java/library types; path traversal check calls `decodeURIComponent` with try/catch
- [ ] `shared-update-agent`: `pnpm audit --audit-level=high` step present for Node stacks
- [ ] `shared-update-agent`: `pip-audit` step present for FastAPI with graceful skip
- [ ] `shared-update-agent`: Reporting section includes "Security advisories" block description
- [ ] No other skills modified
