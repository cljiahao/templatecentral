---
name: shared-add-pagination
description: Add offset-based pagination to list endpoints with resource exhaustion (CWE-400) prevention across stacks
---

## Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to context check.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for the marker.
- Marker now present → proceed to context check.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm the project contains at least one route handler file (e.g. any `.ts` file under `src/app/api/` for Next.js, any `.py` file under `src/api/routers/` for FastAPI, any controller file under `src/modules/` for NestJS, or any `.ts` file under `src/features/*/api/` for Vite + React).

If none found → STOP. Tell the user: "No API routes or endpoints found. Add some first, then return here to add pagination."

If found → proceed to Step 1.

## Step 1 — Load stack guide

Read `AGENTS.md` to identify the stack, then run the corresponding command:

- **FastAPI:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/fastapi.md"`
- **NestJS:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/nestjs.md"`
- **Next.js:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/nextjs.md"`
- **Vite + React:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-pagination/vite-react.md"`

After running the cat command, follow the loaded guide exactly.
