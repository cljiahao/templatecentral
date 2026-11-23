<!-- ref: migrate/general/UPGRADE-NOTES.md
     loaded-by: migrate/SKILL.md
     prereq: A project seeded by an older plugin version, and the defect report has run or the user asked what changed in the template source. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Upgrade notes: older template patterns

The harness refresh updates harness files only. Source files that the plugin generated earlier (`src/**`) keep the code of the version that wrote them. This list names the older patterns that later templates replaced. `defect-report.sh` checks the ones that have an id, read-only. The two items without an id are for review by hand.

Each entry: what the older template did, how to recognise it, the fix, the id. Change source only after the user confirms each fix. Current templates are under `skills/add/`.

## mongoose-client-promise-retry (Next.js)

- Older: `connectDB()` awaited the cached connect promise and never reset it, so one failed connect failed every later request until restart.
- Recognise: `mongoose-client.ts` awaits `X.promise` and has no reset of `X.promise` (to `null` or `undefined`, `delete X.promise`, or `X = { promise: null }`) in the catch block of a try that holds the await, or inside a `.catch(...)` call. Comments are ignored. A reset only in `finally` still matches: that is a different pattern.
- Limits: only the shape `await X.promise` is read, not `const p = X.promise; await p`, `Promise.all([...])` or a dotted receiver. A reset made by a helper function is not seen, so verify by hand.
- Fix: wrap the await in try/catch, set `cached.promise = null` in the catch, rethrow.
- Current: `skills/add/database/typescript/nextjs-mongoose/template/src/integrations/database/mongoose-client.ts`.

## mongoose-init-nextjs and mongoose-init-nestjs (check, verify)

- Older: unique indexes were built in the background, so a write right after boot could run before the index existed.
- Recognise: Next.js `mongoose-client.ts` with `connectDB` and no `.init()`; NestJS `database.module.ts` with `MongooseModule.forRoot` and no `.init()`.
- Fix: await `init()` of each registered model after the connect (NestJS: in `onModuleInit`; Next.js: import the model modules before the first `connectDB()` call).
- Verify first: the match shows a missing wait, not that a duplicate was written. A project with no unique indexes is unaffected.
- Current: `skills/add/database/typescript/nestjs-mongoose/template/src/database/database.module.ts` and the Next.js file above.

## redaction-tool-output

- Older: the redaction hook read `tool_output` from the hook input. The field is `tool_response`, so nothing was masked.
- Recognise: `.claude/hooks/redact-sensitive-output.cjs` or `redact_sensitive_output.py` names `tool_output` and never `tool_response`.
- Fix: read `tool_response`. Re-run the hook's own check from `skills/add/redaction/implementation.md` afterwards.
- Current: `skills/add/redaction/hook-node/template/.claude/hooks/redact-sensitive-output.cjs`.

## vite-auth-csrf

- Older: the Vite auth service sent login and logout without a CSRF token, and logout ignored a failed response.
- Recognise: `src/features/auth/api/auth-service.ts` has `loginWithCredentials`, a `/logout` call and `credentials: 'include'`, and has no `csrfHeader`, `X-CSRF-Token`, `Authorization` or `Bearer`. Comments are ignored.
- Applies when the backend uses cookie-mode auth (HttpOnly session cookie plus an `XSRF-TOKEN` cookie). A client that sends a bearer token is not reported. A CSRF header set in a shared fetch wrapper in another file is still reported: verify by hand.
- Fix: add `src/lib/clients/csrf.ts` and send `csrfHeader()` on the login and logout POSTs.
- Current: `skills/add/auth/vite-react/template/src/features/auth/api/auth-service.ts`.

## argon2-dummy-hash-literal (check)

- Older: the login path verified a fixed literal Argon2 hash when the email was unknown. The current templates build the dummy hash at startup with the project's own hasher.
- Recognise: `auth.service.ts` (NestJS) or `auth_service.py` (FastAPI) contains the literal whose salt part is `c29tZXNhbHRzb21lc2E`.
- Fix: build the dummy hash with the project's hasher at startup and verify it on the unknown-email path.
- Current: `skills/add/database/typescript/nestjs-drizzle.md` (section "Completing Auth Integration") and `skills/add/database/python/sqlalchemy.md` (Step C under "Completing Auth Integration (SQLAlchemy)").

## sqlalchemy-tls-verify (check)

- Older: the engine was built from the database URL alone. The default libpq mode does not verify the server certificate.
- Recognise: `src/database/session.py` calls `create_engine(` and never names `sslmode`.
- Not a match in fact when TLS is set in the URL, or when the database is not PostgreSQL. Check the URL before changing.
- Fix: for PostgreSQL outside dev, pass `connect_args` with `sslmode` set to `verify-full` and a `sslrootcert`.
- Current: `skills/add/database/python/sqlalchemy/template/src/database/session.py`.

## Review by hand: NestJS roles guard

- Older: the roles guard read `user.roles` and called `some` on it directly, so a user object with no roles list threw (a 500) instead of denying, and a list holding non-strings was matched loosely.
- Recognise: `src/modules/auth/roles.guard.ts` calls `user?.roles.some(` with no `Array.isArray` check.
- Fix: deny with a 403 unless `roles` is an array of strings. The current guard is `skills/add/auth/nestjs/template/src/modules/auth/roles.guard.ts`.

## Review by hand: malformed JSON handling

- Older: a malformed JSON body or a validation error could return a 500.
- Recognise: send a request with an invalid JSON body to any endpoint and read the status code. Anything in the 500 range is the defect.
- Fix: return a client error, and use the status code the stack's current template uses. Status `400` for both a malformed body and a validation failure in the NestJS and Next.js templates (Next.js: `request.json().catch(() => null)`, then a Zod check). Status `422` for both in the FastAPI template, because its `RequestValidationError` handler returns `422` by default; domain validation failures raised by a service use `400`. Keep `422` unless the project's clients already expect `400`. See the endpoint and error-handling leaves under `skills/add/` for the current mapping.
