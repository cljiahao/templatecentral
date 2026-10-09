## What does this PR do?

<!-- One sentence summary -->

## Type of change

- [ ] Bug fix — a skill produced incorrect, broken, or insecure output
- [ ] Accuracy fix — a skill referenced a deprecated API, wrong version, or outdated pattern
- [ ] New capability — adds a reference file under an existing registered skill (e.g. `skills/add/<capability>/<stack>.md`); never a new `skills/<stack>-<name>/` skill (`skills/CONVENTIONS.md` §6)
- [ ] New stack — adds scaffold + rules + AGENTS.md routing
- [ ] Infrastructure — CI, lint script, audit tooling, templates

## Checklist

- [ ] Read `skills/CONVENTIONS.md`; any touched `SKILL.md` keeps valid `name`/`description` frontmatter and every reference file keeps its `<!-- ref: … -->` header
- [ ] Any version floor/pin in a skill body matches `.claude/rules/<stack>.md` (the stack-version source of truth)
- [ ] `bash scripts/lint-skills.sh skills/` passes locally
- [ ] CI passes (frontmatter validation + lint-patterns)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] README updated if skill count changed

## Testing

<!-- How did you verify the skill produces correct output? Include the prompt you used and what Claude generated. -->

## Related issues

<!-- Closes #... -->
