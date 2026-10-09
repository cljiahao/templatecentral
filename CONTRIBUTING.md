# Contributing to templatecentral

Thanks for helping improve templatecentral. Contributions of all kinds are welcome — new skills, bug fixes, documentation improvements, and new stacks.

## What to Work On

Check [Issues](https://github.com/cljiahao/templatecentral/issues) for open tasks. Good first contributions:

- **Skill improvements** — accuracy fixes, version bumps, missing edge cases
- **New capability reference files** — coverage gaps within an existing stack (added under `templatecentral:add`, not as standalone skills)
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

Skills are auto-discovered. `plugin.json` already points to `"skills": "./skills/"`, so any directory under `skills/` whose `SKILL.md` carries `name:` frontmatter is registered automatically — no `plugin.json` edits needed. A `SKILL.md` that has a `<!-- ref: -->` header instead of `name:` frontmatter is an **agent utility** (e.g. `build`, `test`, `review`, `cleanup`): it is catted on demand, not registered. See `skills/CONVENTIONS.md`.

### Adding a new stack

1. Add reference files under `skills/scaffold/<stack>/` (e.g., `source-files.md`, `config-files.md`) and route to them from `skills/scaffold/SKILL.md`
2. Add `skills/add/<capability>/<stack>.md` for each supported capability and its detection row in `skills/add/SKILL.md` (procedure: `skills/CONVENTIONS.md` §6)
3. Add `.claude/rules/<stack>.md` with stack-specific agent rules
4. Add the detection signal to the Stack Detection table in `AGENTS.md`
5. Add the stack to `README.md` → **What You Get**

## Pull Request Checklist

- [ ] `SKILL.md` has valid `name` and `description` frontmatter
- [ ] Version floors in skill files agree with `.claude/rules/*.md` (the floor of record)
- [ ] `bash scripts/lint-skills.sh skills/` passes locally
- [ ] `bash scripts/validate-manifest.sh` passes locally (validates `plugin.json` and `marketplace.json`)
- [ ] `bash scripts/validate-scaffold-configs.sh` passes locally if a `skills/scaffold/*/config-files.md` was touched (validates fenced JSON/JS config blocks)
- [ ] `bash scripts/test-harness-kit.sh` passes locally if `skills/scaffold/shared/harness-kit.md` was touched
- [ ] `bash scripts/pre-guard.test.sh` passes locally if a repo guard script was touched
- [ ] README updated if the skill count, capability list, or stack list changed
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] CI passes (frontmatter validation + `lint-patterns` job run automatically)

## Commit Style

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(add): add websocket capability reference for nextjs
fix(fastapi): correct pytest async config in scaffold
docs(readme): update skills table
```

## Scheduled loops

Two monthly GitHub Actions workflows run automatically on the 1st of each month. Both require Anthropic credentials: either the `ANTHROPIC_API_KEY` repository secret (API) or `CLAUDE_CODE_OAUTH_TOKEN` (Claude subscription — generate with `claude setup-token`). If neither secret is configured, scheduled runs **skip gracefully** with a notice instead of failing. Either workflow can also be triggered manually via **Actions → Run workflow**.

| Workflow | Schedule | What it does |
|---|---|---|
| `ecosystem-refresh.yml` | 02:00 UTC on the 1st | Runs a full web scan (Step 0b of `.claude/skills/tc-audit/implementation.md`), overwrites `.claude/audit-ecosystem-research.md`, and opens a PR summarising new versions, advisories, harness-consensus findings, and any result that invalidates a current skill. |
| `scaffold-verify.yml` | 03:00 UTC on the 1st | Scaffolds each stack (`fastapi`, `nestjs`, `nextjs`, `vite-react`) into a clean directory, runs all quality gates exactly as documented, and fails if any template file is missing or any gate does not pass. |

**Handling scaffold-verify failures:** when any matrix leg fails the workflow automatically opens a GitHub issue titled `scaffold-verify: <stack> failed <date>`. Triage: find the broken template section named in the agent output, then open a fix PR.

## Questions

Open a [Discussion](https://github.com/cljiahao/templatecentral/discussions) for anything that doesn't fit an issue.
