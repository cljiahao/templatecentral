<!-- ref: review/SKILL.md
     loaded-by: agent — not a registered skill; cat directly when a review or update step is needed
     prereq: Project identified. Do not invoke this file directly — it is catted directly by agents as a de-registered utility. -->

**Identify the operation:**
- **Review**: analyse code quality, flag issues → `review/implementation.md`
- **Update**: apply review feedback, fix flagged issues → `update/implementation.md`

**Cat the reference file:**
> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

`cat "<skill-dir>/<review|update>/implementation.md"`

Follow the loaded guide exactly.
