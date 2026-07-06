<!-- ref: standards/code-standards/comments.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Comment Hygiene (all stacks)

Shared doctrine for `code-standards/<stack>.md`. Language-neutral — applies to `#`, `//`, docstrings, and JSDoc alike.

### The doctrine

1. **Explain WHY, not WHAT.** A comment captures intent, a constraint, or a non-obvious rationale. Never restate what the next line already says (`// increment i`, `# return the result`).
2. **Prefer own-line comments; use trailing comments sparingly.** Put the comment on its own line above the code. A short trailing *why*-note is acceptable; delete any trailing comment that merely restates the line.
3. **No commented-out code.** Delete it — version control has the history. Dead code left "for reference" rots and misleads.
4. **No change-narration.** Never `// was X, now Y`, `added`, `removed`, `updated`, `renamed`, `refactored`, `per review`, dates, or ticket refs in code. A comment describes the code *as it is*; edit history belongs in the commit message / PR description.
5. **Public-API docs document the contract.** Docstrings / JSDoc on exported functions, classes, and endpoints state inputs, outputs, behavior, and why it exists — not a line-by-line walkthrough of the implementation.

**Keep:** purpose comments, non-obvious "why", `TODO`/`FIXME` with context, and tooling directives (`eslint-disable-*`, `# type: ignore`, `# noqa`, `@ts-expect-error`).

### Why (consensus basis)

Tenets 1, 3, 4, 5 are near-universal (PEP 8, Google/Airbnb style guides, Ruff `ERA`, SonarQube, *Clean Code*). Tenet 2 is deliberately "sparingly, not banned" — PEP 8 permits inline comments used sparingly and ESLint's `no-inline-comments` is opt-in, so projects nudge rather than hard-gate it.

### Enforcement (seeded per stack)

- **TypeScript (Next.js, NestJS, Vite+React):** `no-inline-comments: 'warn'` in `eslint.config.*` — a non-blocking nudge for tenet 2.
- **FastAPI (Python):** Ruff `ERA` rule family enabled in `pyproject.toml` — deterministically flags commented-out code (tenet 3), dependency-free.
- **All stacks:** tenets 1, 4, 5 are judgment calls — the `templatecentral:standards (code-standards)` review pass and the seeded `AGENTS.md` rule are the enforcement surface a linter cannot cover.
