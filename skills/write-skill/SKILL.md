---
name: templatecentral:write-skill
description: Use when writing or modifying files under skills/ — walks through CONVENTIONS.md authoring checklist.
---

1. **Read CONVENTIONS.md** (full runtime path):
   ```
   cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/CONVENTIONS.md"
   ```

2. **Determine file type:**
   - Registered skill (`SKILL.md` at skill root)? → Enforce constraints (Section 3)
   - Reference file? → Enforce header format (Section 4)

3. **If SKILL.md (registered skill):**
   - Description ≤ 150 characters (count carefully)
   - Body ≤ 30 lines (excluding frontmatter)
   - No inline implementation content
   - Only: detection logic, routing table, `cat` commands

4. **If reference file:**
   - First line: `<!-- ref: ... loaded-by: ... prereq: ... -->`
   - End `prereq:` with: "Do not invoke this file directly."
   - Check nesting level (Section 2): 2-level or 3-level?

5. **Check for duplicates:**
   - Does this skill/content already exist elsewhere?
   - Can it be merged into an existing registered skill?

6. **After writing:**
   - Run `templatecentral:audit` to verify compliance
