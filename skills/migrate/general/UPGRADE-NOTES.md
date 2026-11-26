<!-- ref: migrate/general/UPGRADE-NOTES.md
     loaded-by: migrate/SKILL.md
     prereq: A project seeded by an older plugin version, and the defect report has run or the user asked what changed in the template source. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Upgrade notes: older template patterns

The harness refresh updates harness files only; source the plugin generated earlier keeps the code of the version that wrote it. `defect-report.sh` finds each id below, read-only, and prints what the older code did and how it was matched. The two items without an id are for review by hand. Change source only after the user confirms each fix. Current templates are under `skills/add/` and `skills/scaffold/`.

## mongoose-client-promise-retry

- Fix: wrap the await in try/catch, set `cached.promise = null` in the catch, rethrow.
- Current: `skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts`.

## mongoose-init-nextjs and mongoose-init-nestjs

- Fix: await `init()` of each registered model after the connect (NestJS: in `onModuleInit`; Next.js: import the model modules before the first `connectDB()` call). A project with no unique indexes is unaffected.
- Current: `skills/add/database/typescript/nestjs-mongoose/template/src/database/database.module.ts` and the Next.js file above.

## redaction-tool-output

- Fix: read `tool_response`, not `tool_output`. Re-run the hook's own check from `skills/add/redaction/implementation.md` afterwards.
- Current: `skills/add/redaction/hook-node/template/.claude/hooks/redact-sensitive-output.cjs`.

## vite-auth-csrf

- Fix: add `src/lib/clients/csrf.ts` and send `csrfHeader()` on the login and logout POSTs. Applies only to cookie-mode auth.
- Current: `skills/add/auth/vite-react/template/src/features/auth/api/auth-service.ts`.

## argon2-dummy-hash-literal

- Fix: build the dummy hash with the project's hasher at startup and verify it on the unknown-email path.
- Current: `skills/add/database/typescript/nestjs-drizzle.md` (section "Completing Auth Integration") and `skills/add/database/python/sqlalchemy.md` (Step C under "Completing Auth Integration (SQLAlchemy)").

## sqlalchemy-tls-verify

- Fix: for PostgreSQL outside dev, pass `connect_args` with `sslmode` set to `verify-full` and a `sslrootcert`. Check the URL first: TLS may be set there.
- Current: `skills/add/database/python/sqlalchemy/template/src/database/session.py`.

## frame-ancestors

- Fix: the steps in `skills/migrate/frame-ancestors.md`. Skip when the app must never be framed.
- Renamed: an app from 6.2.0 or later that sets the earlier variable (ending `_PORTAL_ORIGIN`) in deploy config or `.env.example` is silently denied framing. Rename it to `EMBED_PARENT_ORIGIN` there and re-copy the code per the same guide.
- Current: the framing files that guide lists, under `skills/scaffold/`.

## Review by hand: NestJS roles guard

- Older: the roles guard read `user.roles` and called `some` on it directly, so a user object with no roles list threw (a 500) instead of denying, and a list holding non-strings was matched loosely.
- Recognise: `src/modules/auth/roles.guard.ts` calls `user?.roles.some(` with no `Array.isArray` check.
- Fix: deny with a 403 unless `roles` is an array of strings. The current guard is `skills/add/auth/nestjs/template/src/modules/auth/roles.guard.ts`.

## Review by hand: malformed JSON handling

- Older: a malformed JSON body or a validation error could return a 500.
- Recognise: send a request with an invalid JSON body to any endpoint and read the status code. Anything in the 500 range is the defect.
- Fix: return a client error, and use the status code the stack's current template uses. Status `400` for both a malformed body and a validation failure in the NestJS and Next.js templates (Next.js: `request.json().catch(() => null)`, then a Zod check). Status `422` for both in the FastAPI template, because its `RequestValidationError` handler returns `422` by default; domain validation failures raised by a service use `400`. Keep `422` unless the project's clients already expect `400`. See the endpoint and error-handling leaves under `skills/add/` for the current mapping.
