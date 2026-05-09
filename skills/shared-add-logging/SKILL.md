---
name: shared-add-logging
description: Add structured JSON logging to any templateCentral project with sensitive data protection
---

## Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Step 1 — Load stack guide

Read `AGENTS.md` to identify the stack, then run the corresponding command:

- **FastAPI:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/fastapi.md"`
- **NestJS:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/nestjs.md"`
- **Next.js:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-logging/nextjs.md"`

Note: Logging is backend-only — no Vite + React section.

After running the cat command, follow the loaded guide exactly.
