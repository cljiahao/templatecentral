# Contributing to templatecentral

Thanks for helping improve templatecentral. Contributions of all kinds are welcome — new skills, bug fixes, documentation improvements, and new stacks.

## What to Work On

Check [Issues](https://github.com/cljiahao/templatecentral/issues) for open tasks. Good first contributions:

- **Skill improvements** — accuracy fixes, version bumps, missing edge cases
- **New add-* skills** — coverage gaps within an existing stack
- **New stacks** — if you know a stack well and can write a complete scaffold skill

## Adding or Modifying a Skill

### Skill file structure

Registered skills live at `skills/<category>/SKILL.md` (e.g., `skills/scaffold/SKILL.md`, `skills/add/SKILL.md`). Reference files live under the category (e.g., `skills/add/auth/fastapi.md`). Read `skills/CONVENTIONS.md` for the full nesting rules, description limits, and ref-header format before creating any file.

Required YAML frontmatter in every `SKILL.md`:

```markdown
---
name: templatecentral:<category>
description: Use when... (one sentence, ≤150 chars)
---
```

Both `name` and `description` are required — CI will reject a skill missing either field.

### Registering a skill

Skills are auto-discovered. `plugin.json` already points to `"skills": "./skills/"`, so any directory under `skills/` that contains a valid `SKILL.md` is registered automatically. No edits to `plugin.json` needed.

### Adding a new stack

1. Add reference files under `skills/scaffold/<stack>/` (e.g., `source-files.md`, `config-files.md`)
2. Add a routing branch for the new stack in `skills/scaffold/SKILL.md`
3. Add `.claude/rules/<stack>.md` with stack-specific agent rules
4. Update `AGENTS.md` to include the new stack in the routing table
5. Update `README.md` to add the stack to the skills table

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
