# Claude Skills

This directory contains SKILL.md files that instruct AI agents on how to scaffold projects and work within them.

Skills are organized by stack. Each stack folder has an `AGENT.md` with a skill routing table listing all available skills.

## Directory Structure

```
claude-skills/
├── nextjs/                      # Next.js skills (11 skills)
│   ├── AGENT.md                 #   Subagent definition + skill routing
│   ├── scaffold/SKILL.md
│   ├── code-standards/SKILL.md
│   ├── add-feature/SKILL.md
│   ├── add-page/SKILL.md
│   ├── add-api-route/SKILL.md
│   ├── add-component/SKILL.md
│   ├── add-integration/SKILL.md
│   ├── add-auth/SKILL.md
│   ├── add-test/SKILL.md
│   ├── add-form/SKILL.md
│   └── add-database/SKILL.md
├── fastapi/                     # FastAPI skills (7 skills)
│   ├── AGENT.md
│   ├── scaffold/SKILL.md
│   ├── code-standards/SKILL.md
│   ├── add-endpoint/SKILL.md
│   ├── add-test/SKILL.md
│   ├── add-auth/SKILL.md
│   ├── add-database/SKILL.md
│   └── add-integration/SKILL.md
├── vite-react/                  # Vite + React skills (9 skills)
│   ├── AGENT.md
│   ├── scaffold/SKILL.md
│   ├── code-standards/SKILL.md
│   ├── add-feature/SKILL.md
│   ├── add-page/SKILL.md
│   ├── add-component/SKILL.md
│   ├── add-integration/SKILL.md
│   ├── add-auth/SKILL.md
│   ├── add-test/SKILL.md
│   └── add-form/SKILL.md
├── nestjs/                      # NestJS skills (7 skills)
│   ├── AGENT.md
│   ├── scaffold/SKILL.md
│   ├── code-standards/SKILL.md
│   ├── add-module/SKILL.md
│   ├── add-test/SKILL.md
│   ├── add-auth/SKILL.md
│   ├── add-database/SKILL.md
│   └── add-integration/SKILL.md
└── shared/                      # Cross-stack skills (6 skills)
    ├── task-management/SKILL.md
    ├── full-stack-pairing/SKILL.md
    ├── remove-example/SKILL.md
    ├── validation-patterns/SKILL.md
    ├── add-error-handling/SKILL.md
    └── add-pagination/SKILL.md
```

## Skill Format

Each `SKILL.md` file follows the [Agent Skills specification](https://agentskills.io/specification). It starts with YAML frontmatter:

```yaml
---
name: skill-name
description: Use when [observable trigger or situation that tells the agent to use this skill].
---
```

- `name` — Must match the parent directory name. Lowercase letters, numbers, and hyphens only. Max 64 characters.
- `description` — What the skill does and when to use it. Max 1024 characters.

Followed by the full skill content with:
- **Inputs** — What the user needs to provide
- **Steps** — Ordered instructions for the agent
- **Rules** — Conventions and constraints to follow

## Creating a New Skill

1. Find or create the stack directory: `claude-skills/<stack>/`
2. Create a subdirectory: `claude-skills/<stack>/<skill-name>/`
3. Add a `SKILL.md` with frontmatter (`name`, `description`) and skill content
4. Add the skill to the stack's `AGENT.md` skill routing table
5. Update the "Available Skills" section in the root `README.md` — add the skill to the relevant stack's bullet and increment the skill count
