## What does this PR do?

<!-- One sentence summary -->

## Type of change

- [ ] Bug fix — a skill produced incorrect, broken, or insecure output
- [ ] Accuracy fix — a skill referenced a deprecated API, wrong version, or outdated pattern
- [ ] New skill — adds a `skills/<stack>-<name>/SKILL.md`
- [ ] New stack — adds scaffold + rules + AGENTS.md routing
- [ ] Infrastructure — CI, lint script, audit tooling, templates

## Checklist

- [ ] `SKILL.md` has valid `name` and `description` frontmatter
- [ ] No version pins in skill bodies — floors/pins belong in `.claude/rules/*.md` only
- [ ] `bash scripts/lint-skills.sh skills/` passes locally
- [ ] CI passes (frontmatter validation + lint-patterns)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] README updated if skill count changed

## Testing

<!-- How did you verify the skill produces correct output? Include the prompt you used and what Claude generated. -->

## Related issues

<!-- Closes #... -->
