<!-- ref: cleanup/remove-example/implementation.md
     loaded-by: cleanup/SKILL.md
     prereq: Removing example code. Do not invoke this file directly — it is catted by agents via skills/cleanup/SKILL.md (de-registered agent utility). -->

# Remove Example Code

Remove the example/demo code from a templateCentral-scaffolded project.

Needs the `<!-- templateCentral:` marker in `AGENTS.md` (it names the stack); without it, run `templatecentral:migrate` first and stop if still absent. When the script prints "No example code found — nothing to remove", stop and tell the user.

| Stack | Example code |
|---|---|
| `nextjs`, `vite-react` | `src/features/example/` |
| `fastapi` | `src/api/routers/example.py` |
| `nestjs` | `src/modules/example/` |

## Remove

1. Dry run: `bash "<skill-dir>/remove-example/remove-example.sh" "<project-dir>"`. It reads the stack from the `AGENTS.md` marker and prints every file it would delete and every line it would edit; it writes nothing.
2. Show the dry run to the user and ask before going on: this deletes project files.
3. After the user confirms: run it again with `--apply`.

A `BLOCK` line means the script refused the whole run and changed nothing: an example file differs from the scaffold's, or an expected line is missing. Show the user the line. Delete a modified example file only when the user names it, with `--force <path>`; fix a missing line by hand, then run the dry run again. A repeat run after a removal does nothing.

What the script removes per stack is listed in `<skill-dir>/remove-example/<stack>.manifest`. The `/dashboard` route stays, with a heading only. What stays manual: any import of the example outside those files, found by the build below.

> `src/features/auth/` is intentional scaffold code (auth context, `AuthProvider`, `ProtectedRoute`, `LoginCard`) — do **not** delete it. `templatecentral:add (auth)` replaces the dev stub with a real implementation.

## Verify

Run that stack's **tests and production build** (`pnpm test` + `pnpm build`; FastAPI: `python -m pytest` + a container build); the typecheck catches stale imports. Then run `bash scripts/check-docs.sh`: it reports each link or path in the README, AGENTS.md or `docs/` that still points at the example, with file and line. Fix each one.
