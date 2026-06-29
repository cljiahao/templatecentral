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

**Step 1** — Identify the stack: `fastapi`, `nestjs`, `nextjs`, or `vite-react`.

**Step 2** — Load in order. Replace `<skill-dir>` with this skill's own directory — Claude Code prints it as **"Base directory for this skill"** when the skill loads; substitute that absolute path (it is **not** a shell variable). Other Agent-Skills tools provide the skill's directory the same way.

```bash
cat "<skill-dir>/<stack>/config-files.md"
cat "<skill-dir>/<stack>/source-files.md"
```

**Step 3** — Follow each loaded guide fully before proceeding to the next.
