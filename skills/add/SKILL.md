---
name: templatecentral:add
description: Use when adding any capability to a FastAPI, NestJS, Next.js, or Vite+React project — auth, database, tests, components, logging, and more.
---

**Step 1** — From `AGENTS.md` and the user's request, identify the **capability** and **stack**.

**Capability → path** (base: `$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/`):

| Capability | Stacks | Path |
|---|---|---|
| `auth` | fastapi, nestjs, nextjs, vite-react | `auth/<stack>.md` |
| `database` | fastapi→python, nestjs/nextjs→typescript | `database/<python\|typescript>.md` |
| `test` | fastapi, nestjs, nextjs, vite-react | `test/<stack>.md` |
| `integration` | fastapi, nestjs, nextjs, vite-react | `integration/<stack>.md` |
| `logging` | fastapi, nestjs, nextjs | `logging/<stack>.md` |
| `error-handling` | fastapi, nestjs, nextjs, vite-react | `error-handling/<stack>.md` |
| `pagination` | fastapi, nestjs, nextjs, vite-react | `pagination/<stack>.md` |
| `component`, `page`, `feature`, `form` | nextjs, vite-react | `<capability>/<stack>.md` |
| `ai-security` | all stacks | `ai-security/implementation.md` |
| `mutation` | fastapi→python, nestjs/nextjs/vite-react→typescript | `mutation/<python\|typescript>.md` |
| `endpoint` | fastapi only | `endpoint/implementation.md` |
| `module` | nestjs only | `module/implementation.md` |
| `api-route` | nextjs only | `api-route/implementation.md` |

**Step 2** — Run:
`cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/<path>"`

**Step 3** — Follow the loaded guide exactly. For `database`, the loaded file will instruct the next `cat`.
