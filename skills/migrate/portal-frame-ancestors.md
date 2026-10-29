<!-- ref: migrate/portal-frame-ancestors.md
     loaded-by: migrate/SKILL.md
     prereq: Project scaffolded by templateCentral before 6.2.0 that must be framed by its appCentral portal. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Portal framing (`APPCENTRAL_PORTAL_ORIGIN`)

Since 6.2.0 a scaffolded app may be framed by its appCentral portal, and only by it. The platform
injects `APPCENTRAL_PORTAL_ORIGIN` (e.g. `https://appcentral-uat.cpfnet.gov.sg`) at runtime.

| `APPCENTRAL_PORTAL_ORIGIN` | `Content-Security-Policy` | `X-Frame-Options` |
|---|---|---|
| unset, or fails the origin check | `frame-ancestors 'none'` + the existing directives | `DENY` |
| one valid origin | `frame-ancestors <origin>` + the existing directives | not sent |

The origin check is exactly `^https://[a-z0-9-]+(\.[a-z0-9-]+)+$`: one https origin, lowercase, no
path, port, wildcard, quotes, whitespace, semicolons or newlines. It is what stops the variable from
injecting CSP directives or headers — never loosen it, never accept `*` or a list.

Dev behaviour does not change: the stacks that skip anti-clickjacking in dev still skip it.

## Step 1 — Detect the stack and check the current headers

Detect the stack (AGENTS.md "Stack Detection"). Confirm the project still sends the 6.1 defaults:
`X-Frame-Options: DENY` and `frame-ancestors 'none'` in the file listed for its stack below. If
the project has customised either, stop and show the user the current lines before changing them.

## Step 2 — Apply the stack's change

Load the current scaffold source for the stack and copy the named sections from it **verbatim**:

```bash
cat "<skill-dir>/../scaffold/<stack>/source-files.md"   # fastapi, nestjs
cat "<skill-dir>/../scaffold/<stack>/config-files.md"   # nestjs
```

For Next.js and Vite + React the scaffold files are real files; read the ones the steps below name:

```bash
cat "<skill-dir>/../scaffold/nextjs/template/src/lib/security/frame-protection.ts"
cat "<skill-dir>/../scaffold/nextjs/template/test/lib/frame-protection.test.ts"
cat "<skill-dir>/../scaffold/nextjs/template/src/proxy.ts"
cat "<skill-dir>/../scaffold/nextjs/template/next.config.ts"
```

```bash
cat "<skill-dir>/../scaffold/vite-react/template/docker/15-frame-protection.envsh"
cat "<skill-dir>/../scaffold/vite-react/template/Dockerfile"
cat "<skill-dir>/../scaffold/vite-react/template/nginx.conf.template"
```

**Next.js** — `next.config.ts` `headers()` is resolved at build time, so the CSP and frame headers
move to the runtime proxy, which becomes the only place the CSP is set.
1. Add `src/lib/security/frame-protection.ts` and `test/lib/frame-protection.test.ts` (the first two files above).
   If the project's `next.config.ts` CSP has directives beyond the 6.1 baseline
   (`frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self'`), move them into
   `CSP_BASE` in that file — never leave them in `headers()`, where the proxy's header replaces them.
   If the backend rewrite path is not `/api/external`, set `BACKEND_PROXY_PATH` to it.
2. In `next.config.ts` `headers()` (the scaffold's `next.config.ts` above): remove the `X-Frame-Options` and
   `Content-Security-Policy` entries. Leave every other header unchanged.
3. Find the proxy: `src/proxy.ts`, or `proxy.ts` at the project root. Next.js runs it only from
   the same level as the `app/` directory: `src/proxy.ts` for `src/app/`, root `proxy.ts` for a
   root `app/`. A root `proxy.ts` next to `src/app/` never runs — report it to the user instead of
   relying on it. Edit the file Next.js runs, in place. Put `frame-protection.ts` (and its test
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

**Vite + React** — nginx `envsubst` leaves an undefined `${VAR}` in place, and nginx then refuses
to start, so a sourced entrypoint script always exports both values.
1. Add `docker/15-frame-protection.envsh` (the first Vite file above).
2. In `Dockerfile` prod stage (the second Vite file above), add the `COPY --chmod=755 ./docker/15-frame-protection.envsh …` line
   after the `nginx.conf.template` copy.
3. In `nginx.conf.template` (the third Vite file above), replace the `X-Frame-Options` and `Content-Security-Policy` lines with
   the `${TC_X_FRAME_OPTIONS}` / `${TC_FRAME_ANCESTORS}` versions.

**FastAPI**
1. Add `APPCENTRAL_PORTAL_ORIGIN: str = Field(default="")` to `CommonSettings` in `src/core/config.py`.
2. Replace `src/core/security_headers.py` with the scaffold version, and add
   `test/test_utils/test_security_headers.py`. `error_handler.py` reuses `SECURITY_HEADERS` — no change.

**NestJS**
1. Add `APPCENTRAL_PORTAL_ORIGIN: z.string().optional()` to `envSchema` and to `appConfig` in
   `src/config/env.config.ts`. Do not validate it there: an invalid value must deny framing, not fail boot.
2. In `src/config/setups/security.setup.ts`, add `PORTAL_ORIGIN_RE` and `portalFrameAncestor()`, set
   `'frame-ancestors': isDev ? null : [portal ?? "'none'"]` and
   `frameguard: isDev || portal ? false : { action: 'deny' }`. Add `test/config/security.setup.spec.ts`.

Next.js, NestJS and FastAPI: add the commented `APPCENTRAL_PORTAL_ORIGIN` line to `.env.example` (FastAPI: `src/.env.default`). Vite + React reads it only in the nginx container, so its `.env.example` (build-time `VITE_*`) does not change.

## Step 3 — Verify

Run the project's verify gate (`.claude/skills/*-verify`, or `templatecentral` build + test). Then
check both cases against a production-mode run (`curl -sI`):

- variable unset → `X-Frame-Options: DENY` and `frame-ancestors 'none'`
- `APPCENTRAL_PORTAL_ORIGIN=https://appcentral-uat.cpfnet.gov.sg` → no `X-Frame-Options`, and
  `frame-ancestors https://appcentral-uat.cpfnet.gov.sg` with the other CSP directives intact
- `APPCENTRAL_PORTAL_ORIGIN='https://a.example.gov.sg; script-src *'` → same as unset
