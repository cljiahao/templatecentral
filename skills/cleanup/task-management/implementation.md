<!-- ref: cleanup/task-management/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Task management workflow. Do not invoke this file directly — it is catted by agents via skills/cleanup/SKILL.md (de-registered agent utility). -->

# Task Management Protocol

Enabled when the project's `AGENTS.md` has a `## Task Management` section and the task touches 3+ files or involves architectural decisions, or when the user asks for it. Skip it for scaffolding and single-file changes. If `superpowers` is installed, use its brainstorm → plan → execute workflow instead.

1. **Plan first.** List the files to create or change, the approach, the risks and open questions. Start coding once the user confirms the plan; "go ahead" counts.
2. **Stop on surprises.** An import error, type mismatch or test failure is reported before you continue.
3. **Validate at the end.** Build, lint and test as the stack needs.
4. **Record only what a future agent needs.** Append significant decisions, gotchas and plan deviations to `## Project-Specific Notes` in `AGENTS.md`, never implementation details.
5. **Test work:** follow the test-value rule in `docs/CONSTITUTION.md` §4. A fresh session may review tests for duplicated or no-value cases to merge or delete. Wait for the user's confirmation before deleting any test; merging into a parametrized test needs none.
