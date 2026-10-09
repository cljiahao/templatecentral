<!-- ref: cleanup/SKILL.md
     loaded-by: agent — not a registered skill; cat directly when a cleanup step is needed
     prereq: Project identified. Do not invoke this file directly — it is catted directly by agents as a de-registered utility. -->

**Identify the operation:**
- **Remove example code**: `remove-example/implementation.md`
- **Task management**: `task-management/implementation.md`

**Cat the reference file:**
> `<skill-dir>` = the directory you just catted this file from (this utility is not a registered skill, so no "Base directory" line is printed) — substitute that absolute path; it is **not** a shell variable.

`cat "<skill-dir>/<path>"`

Follow the loaded guide exactly.
