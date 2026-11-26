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
- **Reference paths use the `<skill-dir>` placeholder** — this skill's own directory, which the tool provides at invocation (Claude Code prints it as **"Base directory for this skill"**). The agent substitutes the literal path. Within-skill: `cat "<skill-dir>/<path>"`. Sibling skill: `cat "<skill-dir>/../<other-skill>/<path>"`. Plugin root: `<skill-dir>/../../`. Do not hardcode `$HOME/.claude/plugins/...` (install-location-specific; breaks outside Claude Code) and do not use `${CLAUDE_SKILL_DIR}` (empty in agent-run bash — it only populates for CC `!`-injection, not the agent-run `cat` blocks here). Lint-enforced.
- **Location:** Live inside skill directories, alongside or beneath the SKILL.md that loads them.

**Rule:** If a file has implementation steps in it, it is a reference file. If a file detects context and issues `cat` commands, it is a registered skill. These two roles must never be combined in a single file.

### Template trees

A leaf that tells the agent to write a file verbatim keeps that file as a real file, not as a code fence to re-type. The files live in a **template tree**, and a manifest lists them. The same layout serves every skill (scaffold, add, migrate); the lint finds a tree by its directory name, so adding one needs no lint edit. Any directory named `template` or `template-*` anywhere under `skills/` is a template tree: it must sit beside a `template.manifest` that lists its files, and a manifest with no tree beside it fails.

- **Tree directory:** a directory named `template` or `template-<suffix>`, holding the files exactly as they land in the project, at their project-relative paths. Scaffold trees sit under `skills/scaffold/<stack>/` and `skills/scaffold/shared/`. For add and migrate, the tree sits in a directory named after the leaf's file stem, next to the leaf: the leaf `skills/add/auth/nestjs.md` owns `skills/add/auth/nestjs/template/`, and `skills/add/database/typescript/nestjs-kysely-iam.md` owns `skills/add/database/typescript/nestjs-kysely-iam/template/`. Use a `template-<suffix>` sibling when one leaf copies different file sets at different steps.
- **Manifest:** one `template.manifest` in the directory that holds the trees (the leaf's stem directory, or the scaffold stack directory). It lists every file of every `template*` tree there in the scaffold format: one line `path mode placeholders seams`. `path` is relative to the manifest's directory and starts with the tree name; `mode` is the octal git mode (`644` or `755`, and every `.sh` is `755`); `placeholders` is a comma-separated list of `__TC_<NAME>__` tokens or `-`; `seams` is a comma-separated list of `[[post-harness]]` markers or `-`. Lines starting with `#` are comments. The lint fails on a file missing from the manifest, a manifest line with no file, a mode mismatch, an empty directory, a symlink, or a manifest with no tree.
- **Skill files:** a template skill ships as `SKILL.md.tmpl`, never `SKILL.md`. A loader that scans for `SKILL.md` would register it as a skill of this plugin. The copy drops the `.tmpl` suffix; a manifest must not list both `X` and `X.tmpl`.
- **Not reference files:** files inside a tree are shipped content, so they carry no `<!-- ref: -->` header and are exempt from the nesting-depth limit (§2). Every content scan (version pins, secrets, change narration, bare route handlers) still reads them. A file merely *named* `template-*.md` outside a tree directory is an ordinary reference file and needs its header.
- **A file standing in for a fence:** when a template file replaces a code fence of a leaf, its content is the fence body byte for byte (dedented when the fence was indented) and it ends in a newline. A body with no final newline does not match. `tests/golden/fences/moved.d/*.tsv` records which fence each file replaces.
- **Leaf prose stays:** the leaf keeps the steps, the decisions and the pointer to the tree. Only the copy-verbatim content moves.
- **Copying an add or migrate tree:** after the router's context check, the leaf runs `TC_PART=leaf TC_LEAF=<add|migrate>/<leaf stem> bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` (add `TC_TREE=template-<suffix>` to copy one tree at the step that needs it). Each moved fence becomes one line, `Copied verbatim from \`<skill-dir>/<path to the file>\` by the copy step; do not re-type it.` The script refuses, writes nothing and prints a `STOP:` line when a target path already exists.
- **What stays inline:** only a fence that creates a new file with fixed content moves. A fence that edits or replaces an existing project file, an example the agent adapts or renames (`my_thing`, `projects`), a value the agent fills in from the user, and the canonical side of a drift-checked pair stay in the markdown.
- **Snapshot rule:** a slice that moves fences adds rows to its own `tests/golden/fences/moved.d/<slice>.tsv` and never edits `tests/golden/fences/<skill>.tsv`. `python3 scripts/check-fences.py --root .` must pass.
- **Deleted fences:** a slice that deletes copy-verbatim fences adds one row per fence to its own `tests/golden/fences/deleted.d/<slice>.tsv` (file, heading, index, sha256 of the snapshot row), needs the `fence-snapshot-change` label, and never edits `<skill>.tsv`.

### Version floors

Version floors and the reasons for them live only in `.claude/rules/<stack>.md`. Skill prose points there instead of restating a floor. Install commands and requirement lines keep their floors, in a fence or in inline code. Lint-enforced: a `≥X.Y` in skill prose outside fences and inline code fails.

---

## Section 2: Nesting Depth Rules

### 2-Level (default)

Use when a stack has **≤ 2 variants**. `add/SKILL.md` routes straight to `add/<capability>/<stack>.md` (`add/auth/fastapi.md`): 1 `cat`, no sub-SKILL.md; a capability directory never holds a SKILL.md of its own.

### 3-Level

Use when a stack has **> 2 variants** (several ORMs or drivers). `add/SKILL.md` → stack router `add/database/python.md` (detects the variant) → leaf `add/database/python/sqlalchemy.md`: 2 `cat` calls. A subdirectory shared by two stacks prefixes the stack (`nestjs-drizzle.md`, §7); an add-on leaf sits beside its base leaf.

### Hard Rules

- **Never use 4+ levels.** Maximum nesting depth is 3 levels (2 `cat` calls per chain).
- **Threshold:** If the per-stack variant count exceeds 2 for any stack, promote the **entire skill** to 3-level, not just that stack.
- Stack routers at the 3-level middle tier are reference files themselves (never registered skills).
- Files inside a template tree (Section 1) mirror a project's own layout, so the depth limit does not apply below the tree directory.

---

## Section 3: SKILL.md Constraints

A registered `SKILL.md` has `name` and `description` frontmatter, a description of at most 150 characters and a body of at most 30 lines. Optional fields: `when_to_use`, `disable-model-invocation`, `allowed-tools` (scope tightly: `Bash(git add *)`, not `Bash`), `paths`, `argument-hint`; description plus `when_to_use` stay under 1,536 characters.

The body holds only stack detection, a routing table or decision tree, `cat` commands to reference files and a one-line prerequisite. No implementation steps, file templates, numbered how-to lists or prose copied from another skill. A utility `SKILL.md` (test, review, cleanup) has no frontmatter and stays a router of at most 12 lines.

Set `disable-model-invocation: true` on a destructive or scaffold-scope skill, so only an explicit user call runs it.

Enforced by `check_skillmd_description_length`, `check_skillmd_body_length` and `check_file_line_budget`.

---

## Section 4: Reference File Header Format

Line 1 of every reference file is this block, with no blank line inside it:

```
<!-- ref: <path relative to skills/>
     loaded-by: <SKILL.md, or router → SKILL.md for a 3-level file>
     prereq: <what must be known first>. Do not invoke this file directly — it is loaded at runtime by the templatecentral:<skill> skill. -->
```

- Utility reference files (test, review, cleanup) end `— it is catted by agents via skills/<name>/SKILL.md (de-registered agent utility).` instead.
- Files inside a template tree take no header (Section 1).
- Enforced by `check_ref_file_headers` and `check_ref_header_prereq_suffix`.

---

## Section 5: Description Writing Guide

Form: `Use when <trigger verb phrase> — <stack list>.` Stack order: FastAPI, NestJS, Next.js, Vite + React; list only stacks the skill supports. Front-load the trigger, use active verbs (`adding`, `scaffolding`, `migrating`), name what the user gets when it fits, drop articles when space is tight.

Never use `covers`, `provides`, `ensures`, `delivers` or `helps with` (checked by `/tc-audit`, not by the lint). The 150-character cap counts Unicode characters (lint-enforced).

---

## Section 6: Adding a New Framework

Never create `<framework>-add-auth` or similar registered skills. Add reference files inside the existing registered skills:

1. Create `skills/<capability>/<name>/<framework>.md` for each capability the framework supports (3-level, Section 2, when a stack has more than 2 variants).
2. Start each with its ref header (Section 4).
3. Add the detection signal and `cat` row to the skill's `SKILL.md` routing table.
4. Run `bash scripts/lint-skills.sh skills/`, then `/tc-audit`.
5. Add the signal to the table below.

| Framework | Detection signal |
|---|---|
| FastAPI | `requirements.txt` contains `fastapi` |
| NestJS | `nest-cli.json` exists, or `@nestjs/core` in `package.json` |
| Next.js | `next.config.ts`, `.js` or `.mjs` exists |
| Vite + React | `vite.config.ts` or `.js` exists and no `next.config.*` |

### Line budget

`check_file_line_budget` (`scripts/lint-skills.sh`) scans every markdown file under `skills/` except the template roots (§1) and caps it by class: utility router 12, stack router 40, `patterns.md` and `comments.md` 60, scaffold `source-files.md` and kit, `code-standards`, `validation-patterns`, `drift-check`, `full-stack-pairing` 120, every other `add/` or `migrate/` file 150 plus 50 prose lines outside fences, every other file 150 (this file too).
Only an exact-path row in `tests/golden/line-budget.txt` lets a file exceed its cap; rows only shrink, and `scripts/check-line-budget-frozen.sh BASE_REF` fails CI when one grows or a new one appears. Cut the file, never raise its row; a new file fits its class cap and takes no row. Any symlink outside a template root, a hidden directory, a name not in lowercase `*.md` or not `SKILL.md`, a CR byte, or an unclosed or over-7-line frontmatter fails; a `SKILL.md` that is not registered (depth 1, `name:` in the frontmatter) is capped at 12.

---

## Section 7: Naming Conventions

- Registered skill: `skills/<capability>/`. Reference file: `<stack>.md` in the capability directory (`add/auth/fastapi.md`); a 3-level stack router is `<stack>.md` and its leaves sit in `<stack>/`.
- Stack names: `fastapi`, `nestjs`, `nextjs`, `vite-react`. Variants: lowercase with hyphens (`sqlalchemy`, `drizzle`).
- A subdirectory shared by two stacks prefixes the stack: `nestjs-drizzle.md`, `nextjs-drizzle.md`.
- No `index.md` (checked by `/tc-audit`, not by the lint).
- Scaffold files (`source-files.md`, the shared kits) keep their own layout.

---

## Section 8: Audit Checklist

`scripts/lint-skills.sh` enforces headers, description and body length, nesting depth, template trees and manifests, fence snapshot, version floors, `<skill-dir>` references and the line budget. `/tc-audit` adds what the lint cannot see:

- No reference file is also a registered skill.
- No registered `SKILL.md` repeats prose from another one.
- Registered skills = 4 (`add`, `migrate`, `scaffold`, `standards`); `test`, `review` and `cleanup` are utilities with ref headers, not `name:` frontmatter.
- Every stack in a routing table has its reference file, and every `cat` target exists (`check_skilldir_refs_resolve`).

---

*Change history for these conventions lives in `CHANGELOG.md`.*
