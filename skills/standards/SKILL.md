---
name: templatecentral:standards
description: Use when reviewing code quality, naming conventions, validation patterns, drift, or full-stack type contracts in a templateCentral project.
---

**Step 1** — Identify the operation and stack from `AGENTS.md` and the user's request.

| Operation | Description | Path |
|---|---|---|
| `code-standards` | Naming, exports, component patterns | `code-standards/<stack>.md` |
| `validation-patterns` | Zod/Pydantic schemas | `validation-patterns/<stack>.md` (load `validation-patterns/patterns.md` first) |
| `drift-check` | Detect implementation drift | `drift-check/implementation.md` |
| `full-stack-pairing` | Sync frontend/backend contracts | `full-stack-pairing/implementation.md` |

Stacks: `fastapi`, `nestjs`, `nextjs`, `vite-react`

**Step 2** — Cat the reference file:
`cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/standards/<path>"`

**Step 3** — Follow the loaded guide exactly.
