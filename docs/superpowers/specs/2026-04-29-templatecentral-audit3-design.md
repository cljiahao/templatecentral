# templateCentral Audit 3 — Design Spec

**Goal:** Verify every verbatim code block in every scaffold skill matches the original deleted `templates/` folder (recovered from git), update all stacks to their April 2026 state, correct all plugin references, and confirm the scaffold flow produces structurally correct projects.

**Architecture:** Two parallel tracks (template fidelity + web research) feed into five parallel fix agents, one per stack plus shared. A micro plugin-audit agent runs alongside both tracks.

**Priority:** Security bugs → structural divergences from deleted templates → API accuracy → token reduction

---

## Phase 1 — Parallel Research (10 agents)

### Track 1: Template Fidelity (4 agents)

Each agent recovers deleted template files from git commit `591ce19` (the commit that deleted `templates/`), then reads the corresponding scaffold skill and compares:

1. **Directory structure** — does the skill's `### Directory Structure` block list the same files as the deleted template?
2. **Config file verbatim blocks** — do `tsconfig.json`, `Dockerfile`, `docker-entrypoint.sh`, `pyproject.toml`, `package.json`, `next.config.ts`, `vite.config.ts`, `.env.example`, etc. match the deleted templates?
3. **Application code** — do key source files (main entry points, base modules, example routes/components) match?

Agents flag: (a) files present in deleted template but missing from skill, (b) files in skill not in deleted template, (c) content divergences in verbatim blocks that look like bugs (not improvements).

| Agent | Deleted template path | Skill |
|-------|----------------------|-------|
| R1 | `templates/nextjs/` | `nextjs-scaffold/SKILL.md` |
| R2 | `templates/fastapi/` | `fastapi-scaffold/SKILL.md` |
| R3 | `templates/nestjs/` | `nestjs-scaffold/SKILL.md` |
| R4 | `templates/vite-react/` | `vite-react-scaffold/SKILL.md` |

### Track 2: April 2026 Accuracy (5 agents)

Web research agents search for breaking changes, deprecated APIs, and security advisories since August 2025:

| Agent | Scope |
|-------|-------|
| W1 | Next.js 16.x changelog, React 19.x, shadcn/ui latest, `@types/react` 19 |
| W2 | FastAPI 0.115+→0.136+, Pydantic v2, PyJWT, Beanie 2.x, pymongo async |
| W3 | NestJS 11 changelog, `@nestjs/platform-fastify` CVEs/versions, `nestjs-zod` v5 |
| W4 | Vite 8 changelog, Tailwind CSS v4 breaking changes, Zod v4 API changes |
| W5 | better-auth v1+ changelog, Drizzle ORM 0.45+, Kysely 0.28+, TanStack Query v5 |

### Track 3: Plugin Reference Audit (1 agent)

Scans all 46 skills + `AGENTS.md` + `.claude/rules/` for:
- References to `docs/superpowers` (should be zero)
- Incorrect superpowers slash command syntax (e.g. `/superpowers:brainstorm` — verify correct syntax for installed `obra/superpowers` vs `superpowers-extended-cc`)
- Skills that recreate caveman/superpowers/claude-mem functionality instead of referencing install
- Plugin install commands pointing to wrong package names or outdated install methods
- Any `shared-task-management` references that should instead defer to installed superpowers

---

## Phase 2 — Parallel Fix (5 agents)

After Phase 1 consolidation, five fix agents apply findings in parallel:

| Agent | Files in scope |
|-------|---------------|
| F1 | `nextjs-scaffold/SKILL.md`, `nextjs-add-auth/SKILL.md`, `nextjs-add-database/SKILL.md`, `nextjs-add-*` |
| F2 | `fastapi-scaffold/SKILL.md`, `fastapi-add-auth/SKILL.md`, `fastapi-add-database/SKILL.md`, `fastapi-add-*` |
| F3 | `nestjs-scaffold/SKILL.md`, `nestjs-add-auth/SKILL.md`, `nestjs-add-database/SKILL.md`, `nestjs-add-*` |
| F4 | `vite-react-scaffold/SKILL.md`, `vite-react-add-auth/SKILL.md`, `vite-react-add-*` |
| F5 | `shared-*/SKILL.md`, `AGENTS.md`, `.claude/rules/*.md` |

Each fix agent:
1. Reads its consolidated findings (from Phase 1)
2. Applies only confirmed bugs/inaccuracies — does NOT reformat, restructure, or improve style
3. Reports what it changed and why

---

## Success Criteria

- Every verbatim block in every scaffold skill traceable to either the deleted template (unchanged) or a documented intentional improvement
- No breaking API calls for any April 2026 package versions
- No CVEs in pinned package versions
- Zero `docs/superpowers` references in skills
- Plugin install commands match current marketplace identifiers
- `AGENTS.md` routing table covers all 46 skills with no gaps
- Scaffold verification gates (build, test, lint) would pass on a freshly generated project

## Out of Scope

- Rewriting skill prose or restructuring sections
- Adding new skills
- Changes to add-* skills not flagged by Track 2 web research
- Style or formatting improvements not affecting accuracy
