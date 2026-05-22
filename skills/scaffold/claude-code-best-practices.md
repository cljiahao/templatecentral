<!-- ref: scaffold/claude-code-best-practices.md
     loaded-by: scaffold/<stack>/source-files.md → scaffold/SKILL.md
     prereq: A scaffolded project exists, verification gates have passed, and AGENTS.md has been written. The CLAUDE.md generation step (Claude Code users only) is starting. Do not invoke this file directly. -->

## Claude Code best practices for scaffolded projects

Source: Anthropic, *How Claude Code Works in Large Codebases* (2026). Distilled to what applies at scaffold time and what to apply as the project grows.

This file is loaded by every `<stack>/source-files.md` during the **Generate CLAUDE.md** step. It tells the scaffolding agent two things:

1. The short list of artefacts to **emit now** into the scaffolded project.
2. The short list of practices to **mention in the generated CLAUDE.md** so the project owner knows what to apply later.

Do not paste the whole reference into the project. The blog's central rule — *keep CLAUDE.md lean and layered* — applies to this output too.

---

### How Claude Code reads a codebase (1-paragraph context)

Claude Code uses **agentic search**: it traverses the file system live, reads files, greps, and follows references — no embedding index that goes stale. The trade-off is that Claude needs enough *starting context* to know where to look. Every artefact below exists to give that starting context.

---

### Apply now (during the CLAUDE.md generation step)

#### A. Emit `.claude/settings.json` with `permissions.deny` for build artefacts

The blog: *"Committing `permissions.deny` rules in `.claude/settings.json` means the exclusions are version-controlled."* Generated files (`node_modules/`, `dist/`, `.next/`, `__pycache__/`, etc.) are noise — denying them at the harness level prevents Claude from grepping or globbing into them and burning context on machine-generated output.

Stack-specific deny lists (the calling `source-files.md` provides the exact JSON for its stack):

| Stack | Paths to deny |
|---|---|
| Next.js | `node_modules/**`, `.next/**`, `dist/**`, `coverage/**`, `.turbo/**`, `*.tsbuildinfo` |
| Vite + React | `node_modules/**`, `dist/**`, `coverage/**`, `.turbo/**`, `*.tsbuildinfo` |
| FastAPI | `.venv/**`, `__pycache__/**`, `.pytest_cache/**`, `.ruff_cache/**`, `.mypy_cache/**`, `htmlcov/**`, `dist/**` |
| NestJS | `node_modules/**`, `dist/**`, `coverage/**` |

Deny `Read` and `Glob` for each path (both tools could otherwise pull these into context).

#### B. Append a "Working with Claude Code" subsection to the generated `CLAUDE.md`

5 bullets, no more. The full reference lives in templateCentral; the project's CLAUDE.md is a pointer. Use this verbatim block, substituting `<stack-skills>` from the existing CLAUDE.md step:

```markdown
## Working with Claude Code

- **Workflow**: simple / medium → templateCentral skills (`<stack-skills>`); complex (3+ files, architectural decisions) → Superpowers (`/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`).
- **Settings**: `.claude/settings.json` denies build artefacts (`node_modules`, `dist`, etc.) so Claude does not grep into machine-generated files. Edit it if you add new generated directories.
- **LSP** (recommended once the project is non-trivial): install a Claude Code LSP plugin and the language server for this stack so symbol search replaces string grep. Without LSP, "find references to `getUser`" returns every match; with LSP, it returns only the same symbol.
- **As this project grows**: add a `CLAUDE.md` inside any subdirectory that develops its own conventions (test commands, naming, gotchas). Claude loads each one additively as it walks down the tree. Keep this root file pointers-only — `AGENTS.md` holds the detail.
- **Refresh every 3–6 months**: rules written for older models can constrain newer ones. Re-read CLAUDE.md after major Claude releases and prune anything the new model handles natively.
```

The Build & Dev commands and templateCentral skills list (which the existing scaffold step already writes) stay above this section.

---

### Apply as the project grows (mention in CLAUDE.md, do not bake)

These are growth practices the project owner triggers — the scaffold does not pre-create files for them.

| Practice | When to adopt | What it looks like |
|---|---|---|
| **Subdirectory `CLAUDE.md`** | A module gets distinct conventions, test commands, or gotchas | One file per module (`src/features/billing/CLAUDE.md`) with local rules. Claude loads root + every parent as it descends. |
| **Per-subdirectory scoped commands** | Running the full test/lint suite for a one-file change starts to time out or pollute context | Document `pnpm test src/features/billing` (or `pytest test/billing`) in that subdirectory's CLAUDE.md, not the root |
| **LSP server** | Symbol collisions in grep (common function names like `handler`, `validate`, `User`) start eating context | Install a Claude Code code-intelligence plugin + the language server (`ts-server`, `pyright`, `gopls`). Symbol search beats string match. |
| **Stop / start hooks** | A pattern recurs across sessions (style violation, missing test, env mismatch) | A stop hook can propose CLAUDE.md updates while context is fresh. A start hook can load per-module context dynamically. |
| **Skills for reusable workflows** | A specific task type (security review, doc-sync after API changes) repeats often enough that re-explaining it every session wastes tokens | Author a skill; path-scope it so it only auto-loads in relevant directories. templateCentral's `templatecentral:write-skill` walks the authoring checklist. |
| **MCP server** | Claude needs data it cannot reach via the filesystem (internal analytics, ticket system, design tool) | Add a project-scoped MCP via `.mcp.json` or per-user MCP via `claude mcp add`. Avoid putting org-wide MCPs in project config. |
| **Plugin (org rollout)** | Three or more developers in your org are copy-pasting the same Claude setup | Bundle skills + hooks + MCP into a plugin and distribute via a marketplace. templateCentral itself is the canonical example — the same configuration ships to every developer who installs it. |
| **Codebase map** | The repo grows past ~20 top-level folders and `ls` no longer tells the story | A markdown table-of-contents at the root, one line per folder. Better: layered — root names the top level, each subdirectory's CLAUDE.md names its children. |

---

### Periodic review (3–6 months)

The blog: *"Rules written for earlier models can constrain newer ones. Skills and hooks compensating for specific limitations become overhead once resolved."*

Concrete cadence:

1. Open `CLAUDE.md`, `AGENTS.md`, every subdirectory CLAUDE.md, every project-local skill, every project-local hook.
2. For each rule, ask: *"Did Claude need this guidance the last three sessions, or did it handle the case without help?"*
3. Delete rules the current model handles natively. Tighten rules that still bite. Promote any genuine new gotcha you discovered into the right file.
4. Trigger this review on major Claude releases or whenever performance feels like it plateaued.

---

### Org-level practices (not in scope at scaffold time — note for the README/handoff)

The blog dedicates significant space to *who owns* the Claude Code configuration. For a single-project scaffold these are aspirational, but worth flagging on handoff:

- **DRI**: one person with authority over `.claude/`, plugin marketplace inclusion, and CLAUDE.md conventions, and the responsibility to keep them current. Without this role, conventions fragment.
- **Cross-functional working group** in regulated environments: engineering + infosec + governance define which skills/plugins/MCPs are approved, and how AI-generated code goes through the same review gate as human code.
- **Bottoms-up risk**: enthusiasm without ownership generates conflicting CLAUDE.md hierarchies across teams. A DRI prevents tribal knowledge from staying tribal.

This bullet stays in templateCentral. Do not paste it into a project that is just spinning up.

---

### What this reference does NOT do

- It does **not** install LSP servers, hooks, or plugins on the user's machine. Those are project-owner decisions, not scaffold defaults.
- It does **not** write subdirectory CLAUDE.md files at scaffold time. There are no subdirectories yet that have distinct conventions.
- It does **not** add MCP entries to `.mcp.json`. The project does not yet know which external services it needs.
- It does **not** duplicate the project's existing `AGENTS.md` content. CLAUDE.md stays a pointer, per the blog's "lean and layered" rule.

If the project later grows into any of the above, the project owner adds it deliberately.

---

*Source: claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start. Last reviewed against blog: 2026-05-22.*
