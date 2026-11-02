---
name: templatecentral:scaffold
description: Use when creating a new FastAPI, NestJS, Next.js, or Vite+React project from scratch.
---

**Step 0 — If the user did not name a stack:** ask before assuming. Pose at most two questions ("Frontend, backend, or full-stack? Any language preference?"), then recommend from this table, state the one-line reason, and confirm before Step 1:

| Use case | Recommend |
|---|---|
| Interactive product UI, SSR, or full-stack web | `nextjs` |
| Client-only SPA or internal dashboard | `vite-react` |
| Python REST / async API | `fastapi` |
| Enterprise TypeScript API (DI, Swagger) | `nestjs` |

Full-stack → scaffold frontend and backend as two separate runs.

**Step 1** — Identify the stack: `fastapi`, `nestjs`, `nextjs`, or `vite-react`. Then settle the inputs every guide uses, asking only for what the user has not given:
- `<target>` — the project directory. If it exists and is not empty, confirm with the user before writing anything into it.
- project name — lowercase, matching `^[a-z0-9][a-z0-9-]*$` (used for `package.json` / settings).
- project title — one line, for headings and `__TC_PROJECT_TITLE__` (defaults to the name).
- one-sentence description.
- CI host — GitHub Actions or Azure DevOps.

Then settle the user's choices the later steps act on: `cat "<skill-dir>/shared/user-choices.md"` (`<skill-dir>` as in Step 2) lists them with their defaults.

**Step 2** — Load the guide. Replace `<skill-dir>` with this skill's own directory — Claude Code prints it as **"Base directory for this skill"** when the skill loads; substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill's directory the same way.

```bash
cat "<skill-dir>/<stack>/source-files.md"
```

**Step 3** — Follow the loaded guide fully.
