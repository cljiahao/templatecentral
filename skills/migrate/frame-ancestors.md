<!-- ref: migrate/frame-ancestors.md
     loaded-by: migrate/SKILL.md
     prereq: Project scaffolded by templateCentral that must be framed by its parent portal: one from before 6.2.0, or one from 6.2.0 or later that still sets the earlier variable name. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Portal framing (`EMBED_PARENT_ORIGIN`)

Run `defect-report.sh` first: the `frame-ancestors` entry lists the files that still send fixed framing headers. If the stack's file has customised headers, stop: show the user the current lines and change them only after the user confirms.

The platform injects `EMBED_PARENT_ORIGIN` at runtime. Unset or invalid → `frame-ancestors 'none'` and `X-Frame-Options: DENY`; one valid origin → `frame-ancestors <origin>` and no `X-Frame-Options`. The origin check is exactly `^https://[a-z0-9-]+(\.[a-z0-9-]+)+$`: never loosen it, never accept `*` or a list.

**Renamed variable:** a project from 6.2.0 or later that sets the earlier name (ending `_PORTAL_ORIGIN`) falls back silently to `'none'`. Rename it to `EMBED_PARENT_ORIGIN` in deploy config and `.env.example`, and apply the steps below so the code reads the new name.

Copy the named sections **verbatim** from these template files (under `<skill-dir>/../scaffold/`):

- FastAPI: `fastapi/template/src/core/config.py`, `src/core/security_headers.py`, `test/test_utils/test_security_headers.py`
- Next.js: `nextjs/template/src/lib/security/frame-protection.ts`, `test/lib/frame-protection.test.ts`, `src/proxy.ts`, `next.config.ts`
- NestJS: `nestjs/template/src/config/env.config.ts`, `src/config/setups/security.setup.ts`, `test/config/security.setup.spec.ts`
- Vite + React: `vite-react/template/docker/15-frame-protection.envsh`, `Dockerfile`, `nginx.conf.template`

**Next.js** — the CSP and frame headers move to the runtime proxy, the only place the CSP is set.
1. Add `src/lib/security/frame-protection.ts` and `test/lib/frame-protection.test.ts` (the first two files above).
   Move any `next.config.ts` CSP directive beyond the 6.1 baseline (`frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self'`) into `CSP_BASE` in that file, never `headers()`, where the proxy's header replaces it.
   If the backend rewrite path is not `/api/external`, set `BACKEND_PROXY_PATH` to it.
2. In `next.config.ts` `headers()` (the scaffold's `next.config.ts` above): remove the `X-Frame-Options` and
   `Content-Security-Policy` entries. Leave every other header unchanged.
3. Find the proxy Next.js runs: it sits at the `app/` level (`src/proxy.ts` for `src/app/`, root
   `proxy.ts` for a root `app/`). A root `proxy.ts` next to `src/app/` never runs — report it to the
   user instead of relying on it. Edit the file Next.js runs, in place. Put `frame-protection.ts` (and its test
   import) where that project's `@/*` path alias points — `src/lib/…` for `@/*` → `./src/*`,
   `lib/…` for `@/*` → `./*`.
   - **Neither exists:** add the scaffold's `src/proxy.ts` (above), at the `app/` level.
   - **It exists without auth** (no `better-auth` import): make every response it returns go through
     `applyFrameProtection(req.nextUrl.pathname, res)`, and make sure its `matcher` covers every
     page and route (excluding at most `_next/static`, `_next/image` and `favicon.ico`).
   - **It exists with auth** (`templatecentral:add (auth)`): rename its `proxy` function to
     `async function route(req: NextRequest): Promise<Response>`, import `applyFrameProtection`, and add
     `export async function proxy(req: NextRequest) { return applyFrameProtection(req.nextUrl.pathname, await route(req)); }`
     — the shape in `add/auth/nextjs.md` step 4. Keep its matcher.

**Vite + React** — nginx refuses an undefined `${VAR}`, so the sourced script always exports both values.
1. Add `docker/15-frame-protection.envsh` (the first Vite file above).
2. In `Dockerfile` prod stage (the second Vite file above), add the `COPY --chmod=755 ./docker/15-frame-protection.envsh …` line
   after the `nginx.conf.template` copy.
3. In `nginx.conf.template` (the third Vite file above), replace the `X-Frame-Options` and `Content-Security-Policy` lines with
   the `${TC_X_FRAME_OPTIONS}` / `${TC_FRAME_ANCESTORS}` versions.

**FastAPI**
1. Add `EMBED_PARENT_ORIGIN: str = Field(default="")` to `CommonSettings` in `src/core/config.py` (the scaffold copy is the first file above).
2. Replace `src/core/security_headers.py` with the scaffold version, and add
   `test/test_utils/test_security_headers.py` (the two files above). `error_handler.py` reuses `SECURITY_HEADERS` — no change.

**NestJS**
1. Add `EMBED_PARENT_ORIGIN: z.string().optional()` to `envSchema` and to `appConfig` in `src/config/env.config.ts`. Do not validate it there: an invalid value must deny framing, not fail boot.
2. In `src/config/setups/security.setup.ts`, add `PORTAL_ORIGIN_RE` and `portalFrameAncestor()`, set `'frame-ancestors': isDev ? null : [portal ?? "'none'"]` and `frameguard: isDev || portal ? false : { action: 'deny' }`. Add `test/config/security.setup.spec.ts` (the three files above).

Next.js, NestJS and FastAPI: add the commented `EMBED_PARENT_ORIGIN` line to `.env.example` (FastAPI: `src/.env.default`). Vite + React reads it only in nginx; its `.env.example` does not change.

## Verify

Run the project's verify gate, then check against a production-mode run (`curl -sI`): variable unset → `X-Frame-Options: DENY` and `frame-ancestors 'none'`; `EMBED_PARENT_ORIGIN=https://portal.example.com` → no `X-Frame-Options`, `frame-ancestors https://portal.example.com` with the other CSP directives intact; an origin with `; script-src *` appended → same as unset.
