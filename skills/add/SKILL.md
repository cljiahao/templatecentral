---
name: templatecentral:add
description: Use when adding any capability to a FastAPI, NestJS, Next.js, or Vite+React project — auth, database, tests, components, logging, and more.
---

1. From `AGENTS.md` and the request, pick the **capability** and **stack**, then its path under `<skill-dir>/`:

| Capability (aliases) | Stacks | Path |
|---|---|---|
| `auth`, `test`, `integration`, `logging`, `error-handling`, `pagination` | all four | `<capability>/<stack>.md` |
| `page`, `feature` (`component`), `form` | nextjs, vite-react | `<capability>/<stack>.md` |
| `endpoint` (`api-route`, `module`) | fastapi, nestjs, nextjs | `endpoint/<stack>.md` |
| `database` | fastapi→python, nestjs/nextjs→typescript | `database/<python\|typescript>.md` |
| `mutation-testing` (`mutation`) | fastapi→python, else typescript | `mutation-testing/<python\|typescript>.md` |
| `ai-security`, `documentation` (`docs`, `readme`), `redaction` (`masking`, `dlp`) | all | `<capability>/implementation.md` |

2. Run `cat "<skill-dir>/<path>"` — `<skill-dir>` is this skill's "Base directory for this skill" (an absolute path, **not** a shell variable).
3. Follow the loaded guide exactly; for `database` it names the next `cat`.
