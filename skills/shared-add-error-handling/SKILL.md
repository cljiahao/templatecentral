---
name: shared-add-error-handling
description: Add consistent error handling and response schemas across all stacks with security boundaries
---

## Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Step 1 — Load stack guide

Read `AGENTS.md` to identify the stack, then run the corresponding command:

- **FastAPI:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/fastapi.md"`
- **NestJS:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/nestjs.md"`
- **Next.js:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/nextjs.md"`
- **Vite + React:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-error-handling/vite-react.md"`

After running the cat command, follow the loaded guide exactly.
