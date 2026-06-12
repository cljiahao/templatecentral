<!-- ref: cleanup/task-management/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Task management workflow. Do not invoke this file directly — it is catted by agents via skills/cleanup/SKILL.md (de-registered agent utility). -->

# Task Management Protocol

A structured workflow for complex, multi-step tasks. This protocol ensures the agent plans before acting, validates at each step, and leaves a trail for future agents.

Task management is "enabled" when the project's `AGENTS.md` contains a `## Task Management` section referencing this protocol — added at scaffold time if the user opts in (see repository root `AGENTS.md`, **Scaffold: optional Task Management**).

> **If `superpowers` is installed:** prefer its brainstorm → plan → execute workflow, which includes task tracking. Use this protocol only if superpowers is not available or the user explicitly requests it.

Activate this protocol when:
- The project's `AGENTS.md` has a `## Task Management` section **and** the task touches 3+ files or involves architectural decisions
- The user explicitly requests structured task management (overrides the AGENTS.md check)

Skip this protocol when:
- Scaffolding a new project (scaffold skills have their own flow)
- Single-file changes (rename, add a constant, fix a typo)
- The user asks for something quick and specific

For **test coverage workflow** (separate AI sessions for writing vs reviewing tests), see repository root `AGENTS.md` → **Independent test workflow** — complementary to this protocol, not a replacement.

## The 6 Steps

### Step 1: Plan

Before writing any code, produce a plan:

```
## Task: <one-sentence summary>

### Files to create or modify
- `src/features/auth/types.ts` — define User and Session interfaces
- `src/features/auth/api/auth-service.ts` — login/logout API calls
- `src/features/auth/hooks/use-auth.query.ts` — React Query hook
- `src/features/auth/components/login-form.tsx` — login UI
- `src/features/auth/index.ts` — barrel export

### Approach
<2-3 sentences explaining the architectural approach and why>

### Risks
- <anything that could break: existing imports, route conflicts, type mismatches>

### Open questions
- <anything unclear that needs user input before proceeding>
```

Present the plan to the user. Do not start coding until the plan is confirmed.

### Step 2: Verify Plan

Before executing, check these conditions:
- [ ] All file paths follow the project's naming conventions
- [ ] No circular dependencies will be introduced
- [ ] The approach aligns with the project's architecture (check `AGENTS.md`)
- [ ] All open questions are resolved

If any open questions remain, ask the user. Do not assume.

### Step 3: Track Progress

As you work, maintain a checklist. Mark each item as you complete it:

```
- [x] Created `types.ts` with User and Session interfaces
- [x] Created `auth-service.ts` with login/logout functions
- [ ] Creating `use-auth.query.ts`...
- [ ] `login-form.tsx`
- [ ] Barrel export
- [ ] Validation
```

If a step produces an unexpected result (import error, type mismatch, test failure), stop and report the issue before continuing.

### Step 4: Explain Changes

After each file creation or modification, briefly state:
- **What** changed
- **Why** it was done this way (not just "because the plan said so")

Example: "Created `auth-service.ts` with a `login` function that returns a typed `Session` object. Used the project's `APIError` class for error handling to keep error responses consistent with existing endpoints."

### Step 5: Document Results

After all changes are complete:

1. **Run validation** — build, lint, and test as appropriate for the stack
2. **Summarize** what was built in 3-5 bullet points
3. **Update project memory** — append significant decisions to the `## Project-Specific Notes` section of the project's `AGENTS.md`

Example entry for project memory:
```markdown
### Auth Feature (2026-03-12)
- Added JWT-based auth with login/logout under `src/features/auth/`
- Session stored in React Query cache, cleared on logout
- Protected routes check session via `useAuth()` hook
```

### Step 6: Capture Lessons

If anything unexpected happened during the task, note it for future agents:

- Patterns that worked well and should be reused
- Gotchas or constraints discovered during implementation
- Deviations from the original plan and why

Append these to `## Project-Specific Notes` in the project's `AGENTS.md` under a "Lessons" subsection.

## Rules

- NEVER start coding before the plan is confirmed by the user — if the user has already approved proceeding (e.g., "go ahead", "just do it", "use your judgment"), treat that as implicit confirmation
- NEVER skip the validation step — always build/lint/test after changes
- NEVER leave open questions unresolved — ask before assuming
- Keep plans concise — the plan is a communication tool, not documentation
- Track progress visibly — the user should always know where you are
- Update project memory only with decisions that future agents need — not implementation details