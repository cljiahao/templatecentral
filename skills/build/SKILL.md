<!-- ref: build/SKILL.md
     loaded-by: agent — not a registered skill; cat directly when a build step is needed
     prereq: Project identified. Do not invoke this file directly — it is catted directly by agents as a de-registered utility. -->

> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

`cat "<skill-dir>/implementation.md"`

Follow the loaded guide exactly.
