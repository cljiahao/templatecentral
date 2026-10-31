import { randomBytes } from 'node:crypto';

import { betterAuth } from 'better-auth';
import { nextCookies } from 'better-auth/next-js';
import { PHASE_PRODUCTION_BUILD } from 'next/constants';

// `next build` evaluates this module while collecting page data, and build environments
// (CI, the Docker builder stage) carry no runtime secrets — so enforce it at runtime only.
const isBuild = process.env.NEXT_PHASE === PHASE_PRODUCTION_BUILD;
if (!process.env.BETTER_AUTH_SECRET && !isBuild) {
  throw new Error(
    'BETTER_AUTH_SECRET environment variable is required — generate with: openssl rand -base64 32'
  );
}

export const auth = betterAuth({
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? 'My App',
  baseURL: process.env.BETTER_AUTH_URL,
  // Throwaway random secret for `next build` only (silences better-auth's warnings); runtime requires the real one.
  secret:
    process.env.BETTER_AUTH_SECRET ?? (isBuild ? randomBytes(32).toString('base64') : undefined),

  emailAndPassword: {
    enabled: true,
    // SSO only in prod; dev can sign up
    disableSignUp: process.env.NODE_ENV === 'production',
    // OWASP: without MFA, treat <15 chars as weak — this config has no MFA enabled
    minPasswordLength: 15,
    autoSignIn: true,
  },

  // SSO providers go here — see Step 15 for the per-provider config blocks.
  socialProviders: {},

  user: {
    additionalFields: {
      // input: false keeps `role` out of sign-up and update-user bodies, so no user can grant
      // themselves a role. Change it only from trusted server code.
      role: { type: 'string', defaultValue: 'user', input: false },
    },
  },

  session: {
    // Standard tier. Elevated: 12h + 30-min inactivity; high-assurance: 8h + 15-min inactivity (add `freshAge`, see note below).
    expiresIn: 30 * 24 * 60 * 60,
    updateAge: 24 * 60 * 60,
    cookieCache: {
      enabled: true,
      maxAge: 5 * 60,
    },
  },

  advanced: {
    defaultCookieAttributes: {
      sameSite: 'lax',
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
    },
  },

  // nextCookies() must stay the last plugin so Server Actions can set cookies.
  plugins: [nextCookies()],
});

export type Session = typeof auth.$Infer.Session;
