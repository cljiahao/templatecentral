---
name: templatecentral:standards
description: Use when reviewing code quality, naming conventions, validation patterns, drift, or full-stack type contracts in a templateCentral project.
---

**Step 1** — From `AGENTS.md` and the request, identify the operation and stack.

| Operation | Description | Path |
|---|---|---|
| `code-standards` | Naming, exports, component patterns, comment hygiene | `code-standards/<stack>.md` (load `code-standards/comments.md` first) |
| `validation-patterns` | Zod/Pydantic schemas | `validation-patterns/<stack>.md` (load `validation-patterns/patterns.md` first) |
| `drift-check` | Detect implementation drift | `drift-check/implementation.md` |
| `full-stack-pairing` | Sync frontend/backend contracts | `full-stack-pairing/implementation.md` |

Stacks: `fastapi`, `nestjs`, `nextjs`, `vite-react`

**Step 2** — Run `cat "<skill-dir>/<path>"`. `<skill-dir>` is this skill's directory, shown as "Base directory for this skill" when it loads; substitute the absolute path (it is **not** a shell variable).

**Step 3** — Follow the loaded guide exactly.
