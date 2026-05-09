---
name: shared-validation-patterns
description: Add consistent input validation with Zod/Pydantic, OWASP/CWE compliance, and sanitization across stacks
---

## Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

## Step 1 — Load pattern reference

`cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/patterns.md"`

## Step 2 — Load stack guide

Read `AGENTS.md` to identify the stack, then run the corresponding command:

- **FastAPI:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/fastapi.md"`
- **NestJS:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/nestjs.md"`
- **Next.js:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/nextjs.md"`
- **Vite + React:** `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-validation-patterns/vite-react.md"`

After running the cat command, follow the loaded guide exactly.
