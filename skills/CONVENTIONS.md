# Skill Authoring Conventions

This file is the single source of truth for all skill authoring rules in templateCentral.
All other tasks and skill authors must follow these conventions exactly.

---

## Section 1: Registered Skills vs Reference Files

### Registered Skills

- **Definition:** Any skill directory under `skills/<name>/` whose `SKILL.md` appears in Claude's skill listing.
- **Sole job:** Detect the project context (stack, variant, etc.) and `cat` the appropriate reference file. Nothing else.
- **No inline implementation:** A registered skill's `SKILL.md` must not contain implementation steps, code samples, file lists, or instructional prose. Those belong in reference files.
- **Structure:** Every registered skill lives at `skills/<name>/SKILL.md`.

### Reference Files

- **Definition:** Markdown files that carry the actual implementation instructions.
- **Never registered:** Reference files are never listed as skills. Claude only reads them when a registered SKILL.md explicitly `cat`s them.
- **Loaded at runtime:** A registered SKILL.md detects context and issues a `cat` command pointing to the correct reference file.
- **Location:** Live inside skill directories, alongside or beneath the SKILL.md that loads them.

**Rule:** If a file has implementation steps in it, it is a reference file. If a file detects context and issues `cat` commands, it is a registered skill. These two roles must never be combined in a single file.

---

## Section 2: Nesting Depth Rules

### 2-Level (Default)

Use when a skill has **≤ 2 variants per stack**.

```
skills/
  add/
    auth/
      SKILL.md              ← registered skill (detection + cat)
      fastapi.md            ← reference file (implementation)
      nestjs.md             ← reference file (implementation)
      nextjs.md             ← reference file (implementation)
      vite-react.md         ← reference file (implementation)
```

The chain is: `SKILL.md` → implementation file (1 `cat` call).

### 3-Level

Use when a skill has **> 2 variants per stack** (e.g., multiple ORMs or drivers).

```
skills/
  add/
    database/
      SKILL.md              ← registered skill (detection + cat to stack router)
      python.md             ← stack router (detects DB variant + cat to leaf)
      python/
        sqlalchemy.md       ← leaf reference file
        beanie.md           ← leaf reference file
      typescript.md         ← stack router (detects DB variant + cat to leaf)
      typescript/
        drizzle.md          ← leaf reference file
        kysely.md           ← leaf reference file
        mongoose.md         ← leaf reference file
```

The chain is: `SKILL.md` → stack router → leaf file (2 `cat` calls).

### Hard Rules

- **Never use 4+ levels.** Maximum nesting depth is 3 levels (2 `cat` calls per chain).
- **Threshold:** If the per-stack variant count exceeds 2 for any stack, promote the **entire skill** to 3-level, not just that stack.
- Stack routers at the 3-level middle tier are reference files themselves (never registered skills).

---

## Section 3: SKILL.md Constraints

Every registered `SKILL.md` must obey these constraints:

| Constraint | Limit |
|---|---|
| Description length | ≤ 150 characters |
| Body length (excluding frontmatter) | ≤ 30 lines |
| Inline implementation | Not allowed |
| Inline code blocks | Only `cat` commands and detection logic |

### Frontmatter Fields

```yaml
---
name: skill-name
description: "Use when <trigger phrase> — <stack list>."
# optionally:
disable-model-invocation: true
---
```

Required fields: `name`, `description`.
Optional fields: `disable-model-invocation` (set to `true` for pure-routing skills that should never trigger model generation).

### Body Content

The body must contain only:
1. Stack/variant detection logic (file existence checks, config sniffs)
2. A routing table or decision tree
3. `cat` commands pointing to reference files
4. A brief "Prerequisites" note if needed (e.g., "Requires a project scaffolded with templatecentral:fastapi-scaffold. See Step 0.")

It must NOT contain: code blocks with implementation steps, file content templates, numbered how-to instructions, or prose duplicated from another skill.

---

## Section 4: Reference File Header Format

Every reference file must begin with this comment block as its **first line**:

```
<!-- ref: <path relative to skills/>
     loaded-by: <SKILL.md that triggers this>
     prereq: <what must be known before this file is useful. End with: Do not invoke this file directly.> -->
```

### 2-Level Example

```
<!-- ref: add/auth/fastapi.md
     loaded-by: add/auth/SKILL.md
     prereq: Stack identified as FastAPI. Do not invoke this file directly. -->
```

### 3-Level Stack Router Example

```
<!-- ref: add/database/python.md
     loaded-by: add/database/SKILL.md
     prereq: Stack identified as FastAPI. Do not invoke this file directly. -->
```

### 3-Level Leaf Example

```
<!-- ref: add/database/python/sqlalchemy.md
     loaded-by: add/database/python.md → add/database/SKILL.md
     prereq: Stack = FastAPI, DB = SQL, compliance = standard. Do not invoke this file directly. -->
```

### Rules

- The `ref:` path is always relative to the `skills/` directory.
- The `loaded-by:` field lists the full chain from nearest parent to root SKILL.md (arrow-separated) for 3-level files.
- The `prereq:` sentence must always end with: `Do not invoke this file directly.`
- No blank lines between the opening `<!--` and closing `-->`.

### Exception

Scaffold reference files (`source-files.md`, `config-files.md`) that predate this convention may be retrofitted gradually. They are not required to have the header immediately, but new scaffold reference files must include it.

---

## Section 5: Description Writing Guide

### Format

```
Use when <trigger verb phrase> — <stack list>.
```

- **Max 150 characters** (hard limit enforced by shared-audit).
- **Front-load the trigger action.** The reader needs to know the "when" immediately.
- **Stack list after the em-dash** (—). Only include stacks that are actually supported.
- **Stack order:** FastAPI, NestJS, Next.js, Vite + React.

### Forbidden Words

Never use these words in a description: `covers`, `provides`, `ensures`, `delivers`, `helps with`.

### Bad vs Good Examples

| Bad | Good |
|---|---|
| "Provides authentication for backend projects" | "Use when adding JWT auth or user login — FastAPI, NestJS." |
| "Covers database setup and migration" | "Use when adding a database with migrations — FastAPI, NestJS, Next.js." |
| "Helps with adding tests to your project" | "Use when adding unit or integration tests — FastAPI, NestJS, Next.js, Vite + React." |
| "Ensures consistent code standards are followed" | "Use when writing or reviewing code — NestJS." |
| "Delivers scaffold for a new API project" | "Use when scaffolding a new backend project — FastAPI." |

### Tips

- Use active verbs: `adding`, `scaffolding`, `connecting`, `validating`, `migrating`.
- Be concrete: name what the user gets (JWT, Drizzle, Pydantic, etc.) if it fits within the character limit.
- Omit articles ("a", "the") to save characters when space is tight.

---

## Section 6: Adding a New Framework

This section describes the canonical process for adding a new framework (e.g., Django) to the templateCentral skill system.

> **Critical rule:** Do NOT create `django-add-auth`, `django-add-database`, or similar registered skills. New frameworks are added as reference files inside existing registered skills under the new nested structure.

### Step-by-Step: Adding Django

**1. Create reference files inside existing skill directories.**

For each skill that Django should support, create a new reference file:

```
skills/add/auth/django.md
skills/add/test/django.md
skills/add/database/django.md       ← if ≤ 2 DB variants
skills/add/database/django/         ← if > 2 DB variants (3-level)
  django-orm.md
  sqlalchemy.md
```

**2. Add the ref header to each new file.**

Every new file must start with the correct `<!-- ref: ... -->` header per Section 4.

Example for `skills/add/auth/django.md`:
```
<!-- ref: add/auth/django.md
     loaded-by: add/auth/SKILL.md
     prereq: Stack identified as Django. Do not invoke this file directly. -->
```

**3. Add stack detection signal and `cat` command to each relevant SKILL.md.**

In `skills/add/auth/SKILL.md`, add Django to the routing table:

```
| Django | `manage.py` exists AND `requirements.txt` contains `django` | `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/auth/django.md"` |
```

**4. Check variant count. If > 2 ORM/driver variants → promote to 3-level.**

If Django will have more than 2 database variants, convert the skill to 3-level structure per Section 2.

**5. Run `templatecentral:audit` to verify all constraints pass.**

The audit will check headers, line counts, description length, and nesting depth.

**6. Update CONVENTIONS.md Section 6 with the new framework's detection signal.**

Add to the stack detection signals table below.

### Stack Detection Signals

| Framework | Detection Signal |
|---|---|
| FastAPI | `requirements.txt` contains `fastapi` |
| NestJS | `nest-cli.json` exists |
| Next.js | `next.config.ts` or `next.config.js` or `next.config.mjs` exists |
| Vite + React | `vite.config.ts` or `vite.config.js` exists AND no `next.config.*` |

When adding a new framework, define its detection signal clearly and add it to this table.

---

## Section 7: Naming Conventions

| Item | Naming Pattern | Example |
|---|---|---|
| Registered skill (top-level) | `skills/<capability>/` | `skills/add/`, `skills/scaffold/` |
| Sub-skill within a capability | `skills/<capability>/<noun>/SKILL.md` | `skills/add/auth/SKILL.md` |
| 2-level reference file | `<stack>.md` inside sub-skill dir | `add/auth/fastapi.md` |
| 3-level stack router | `<stack>.md` inside sub-skill dir | `add/database/python.md` |
| 3-level leaf file | `<variant>.md` (plain) or `<stack>-<variant>.md` (when multiple stacks share the subdirectory) inside subdir | `add/database/python/sqlalchemy.md` |
| Scaffold reference files (existing pattern) | `source-files.md`, `config-files.md` | `scaffold/nestjs/source-files.md` |

### Notes

- Stack names in file paths use lowercase with hyphens: `fastapi`, `nestjs`, `nextjs`, `vite-react`.
- Variant names in leaf file paths use lowercase with hyphens: `sqlalchemy`, `drizzle`, `mongoose`.
- When a single subdir is shared by multiple stacks (e.g., `typescript/` serves both NestJS and Next.js), prefix with the stack name to disambiguate: `nestjs-drizzle.md`, `nextjs-drizzle.md`.
- Do not use `index.md` as a filename — every file should have a descriptive name.
- Scaffold skills (`<stack>-scaffold/`) are stack-specific and follow their own internal structure; they are not subject to the shared-skill naming rule.

---

## Section 8: Audit Checklist (Manual Reference)

This checklist matches what `templatecentral:audit` enforces automatically. Use it for manual spot-checks before committing.

### Registered SKILL.md Files

- [ ] All registered `SKILL.md` files: `description` ≤ 150 characters
- [ ] All registered `SKILL.md` files: body ≤ 30 lines (excluding frontmatter)
- [ ] All registered `SKILL.md` files: no inline implementation steps (no numbered how-to lists, no code templates, no file content)
- [ ] All registered `SKILL.md` files: no prose duplicated from another registered skill

### Reference Files

- [ ] All reference files: `<!-- ref: ... loaded-by: ... prereq: ... -->` is the first line of the file
- [ ] All reference files: `prereq:` ends with `Do not invoke this file directly.`
- [ ] All reference files: `loaded-by:` lists the full chain (arrow-separated) for 3-level files

### Structural Rules

- [ ] No reference file is also a registered skill (dual-role files are forbidden)
- [ ] Maximum nesting depth: 3 levels (max 2 `cat` calls per chain)
- [ ] No 4-level or deeper nesting exists anywhere under `skills/`

### Count Limit

- [ ] Total registered skill count = 10: verify with `ls -d skills/*/ | wc -l`

### Stack Detection

- [ ] Every stack/variant referenced in a SKILL.md routing table has a corresponding reference file
- [ ] Every reference file referenced in a `cat` command actually exists at that path

---

*Last updated: 2026-05-09. Maintained by the templateCentral skill architecture.*
