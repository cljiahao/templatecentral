---
name: skill-audit
description: Surface repeated workflows worth capturing as committed project skills, from the skill-usage log.
disable-model-invocation: true
allowed-tools: "Bash(awk *), Bash(sort *), Bash(cat .claude/skill-usage.log), Bash(ls .claude/skills/*)"
---

# Skill Audit

Find workflows you repeat often that aren't yet committed project skills — so the repo (and teammates) carry them, not just your session memory.

## 1. Aggregate usage
```bash
[ -f .claude/skill-usage.log ] || { echo "No skill usage logged yet."; exit 0; }
awk -F'\t' '{c[$2]++} END{for (k in c) printf "%4d  %s\n", c[k], k}' .claude/skill-usage.log | sort -rn
```

## 2. Filter to capture candidates
A skill is a **capture candidate** when it is used **≥ 2 times** AND:
- it is NOT a Claude Code built-in (`code-review`, `verify`, `run`, `init`, `review`, `security-review`, `simplify`) — those ship with the CLI, nothing to capture;
- it is NOT already a project skill — `.claude/skills/<name>/SKILL.md` does not exist (`ls .claude/skills/`).

## 3. Capture (with the user, per candidate)
- **Author a project skill** (recommended) — create `.claude/skills/<name>/SKILL.md` encoding the workflow, tuned to this project, and commit it. Do NOT vendor a third-party skill's files — write a project skill that captures the same intent (a plugin skill used often is a *signal* to author your own).
- **Skip** — note it's intentionally not captured.

Keep each new SKILL.md to one workflow, with a clear trigger description and tightly-scoped `allowed-tools`. See the `## Skill capture` norm in AGENTS.md.
