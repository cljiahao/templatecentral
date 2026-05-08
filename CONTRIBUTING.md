# Contributing to templatecentral

Thanks for helping improve templatecentral. Contributions of all kinds are welcome — new skills, bug fixes, documentation improvements, and new stacks.

## What to Work On

Check [Issues](https://github.com/cljiahao/templatecentral/issues) for open tasks. Good first contributions:

- **Skill improvements** — accuracy fixes, version bumps, missing edge cases
- **New add-* skills** — coverage gaps within an existing stack
- **New stacks** — if you know a stack well and can write a complete scaffold skill

## Adding or Modifying a Skill

### Skill file structure

Every skill lives at `skills/<stack>-<skill>/SKILL.md` with required YAML frontmatter:

```markdown
---
name: <stack>-<skill>
description: Use when... (one sentence, shown in skill picker)
---

# Skill Title
...
```

Both `name` and `description` are required — CI will reject a skill missing either field.

### Registering a skill

Add the skill name to `.claude-plugin/plugin.json` under `"skills"`:

```json
{
  "skills": "./skills/",
  "...": "..."
}
```

### Adding a new stack

1. Create `skills/<stack>-scaffold/SKILL.md` as the entry point
2. Add `.claude/rules/<stack>.md` with stack-specific agent rules
3. Update `AGENTS.md` to include the new stack in the routing table
4. Update `README.md` to add the stack to the skills table

## Pull Request Checklist

- [ ] `SKILL.md` has valid `name` and `description` frontmatter
- [ ] No version pins in skill body — floors/pins belong in `.claude/rules/*.md` only
- [ ] `bash scripts/lint-skills.sh skills/` passes locally
- [ ] README updated if skill count changed
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] CI passes (frontmatter validation + `lint-patterns` job run automatically)

## Commit Style

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(nextjs): add nextjs-add-websocket skill
fix(fastapi): correct pytest async config in scaffold
docs(readme): update skills table
```

## Questions

Open a [Discussion](https://github.com/cljiahao/templatecentral/discussions) for anything that doesn't fit an issue.
