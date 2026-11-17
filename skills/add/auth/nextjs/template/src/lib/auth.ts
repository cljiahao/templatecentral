import { randomBytes } from 'node:crypto';

import { betterAuth } from 'better-auth';
import { nextCookies } from 'better-auth/next-js';
import { PHASE_PRODUCTION_BUILD } from 'next/constants';

// next build loads this module without runtime secrets, so enforce secrets at runtime only.
const isBuild = process.env.NEXT_PHASE === PHASE_PRODUCTION_BUILD;
if (!process.env.BETTER_AUTH_SECRET && !isBuild) {
  throw new Error(
    'BETTER_AUTH_SECRET environment variable is required — generate with: openssl rand -base64 32'
  );
}

export const auth = betterAuth({
  appName: process.env.NEXT_PUBLIC_APP_NAME ?? 'My App',
  baseURL: process.env.BETTER_AUTH_URL,
  // Throwaway secret for next build only; runtime requires the real one.
  secret:
    process.env.BETTER_AUTH_SECRET ?? (isBuild ? randomBytes(32).toString('base64') : undefined),

  emailAndPassword: {
    enabled: true,
    // SSO only in prod; dev can sign up
    disableSignUp: process.env.NODE_ENV === 'production',
    // OWASP: without MFA, treat passwords under 15 characters as weak.
    minPasswordLength: 15,
    autoSignIn: true,
  },

  // SSO providers go here — see Step 15 for the per-provider config blocks.
  socialProviders: {},

  user: {
    additionalFields: {
      // input: false keeps role out of sign-up and update bodies; change only from server code.
      role: { type: 'string', defaultValue: 'user', input: false },
    },
  },

  session: {
    // Standard tier; see the note below for elevated and high-assurance tiers.
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
