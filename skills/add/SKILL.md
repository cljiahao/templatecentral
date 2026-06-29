---
name: templatecentral:add
description: Use when adding any capability to a FastAPI, NestJS, Next.js, or Vite+React project — auth, database, tests, components, logging, and more.
---

**Step 1** — From `AGENTS.md` and the user's request, identify the **capability** and **stack**.

**Capability → path** (base: `<skill-dir>/`):

| Capability | Stacks | Path |
|---|---|---|
| `auth` | fastapi, nestjs, nextjs, vite-react | `auth/<stack>.md` |
| `database` | fastapi→python, nestjs/nextjs→typescript | `database/<python\|typescript>.md` |
| `test` | fastapi, nestjs, nextjs, vite-react | `test/<stack>.md` |
| `integration` | fastapi, nestjs, nextjs, vite-react | `integration/<stack>.md` |
| `logging` | fastapi, nestjs, nextjs, vite-react | `logging/<stack>.md` |
| `error-handling` | fastapi, nestjs, nextjs, vite-react | `error-handling/<stack>.md` |
| `pagination` | fastapi, nestjs, nextjs, vite-react | `pagination/<stack>.md` |
| `page`, `feature`, `form` | nextjs, vite-react | `<capability>/<stack>.md` |
| `ai-security` | all stacks | `ai-security/implementation.md` |
| `mutation-testing` / `mutation` (alias) | fastapi→python, nestjs/nextjs/vite-react→typescript | `mutation-testing/<python\|typescript>.md` |
| `endpoint` / `api-route` (alias) / `module` (alias) | fastapi→`endpoint/fastapi.md`, nestjs→`endpoint/nestjs.md`, nextjs→`endpoint/nextjs.md` | see path |
| `component` (alias) | nextjs, vite-react | `feature/<stack>.md` |

**Step 2** — Run:
> `<skill-dir>` = this skill directory; Claude Code shows it as "Base directory for this skill" when the skill loads — substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill directory the same way.

`cat "<skill-dir>/<path>"`

**Step 3** — Follow the loaded guide exactly. For `database`, the loaded file will instruct the next `cat`.
