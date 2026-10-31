'use client';

import { authClient } from '@/lib/auth-client';
import { isDev } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useRouter } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { CustomCard } from '@/components/widgets/custom-card';

// better-auth's email validator rejects single-label domains — 'dev@local' fails with
// INVALID_EMAIL on both sign-in and sign-up. Use a dotted domain.
const DEV_EMAIL = 'dev@dev.local';
const DEV_PASSWORD = 'dev-password-local';

export function LoginCard() {
  const router = useRouter();

  async function handleDevLogin() {
    const { error } = await authClient.signIn.email({
      email: DEV_EMAIL,
      password: DEV_PASSWORD,
    });

    if (error) {
      // First run: account does not exist yet — create it (autoSignIn: true signs in immediately)
      const { error: signUpError } = await authClient.signUp.email({
        email: DEV_EMAIL,
        password: DEV_PASSWORD,
        name: 'Dev User',
      });
      if (signUpError) {
        console.error('Dev login failed:', signUpError.message);
        return;
      }
    }

    router.push(PAGE_ROUTES.DASHBOARD);
  }

  return (
    <CustomCard header="Sign in" className="w-full max-w-sm">
      <div className="flex flex-col gap-3">
        {/* Add SSO provider buttons here — import LoginButton and render one per provider */}
        {isDev && (
          <Button onClick={handleDevLogin} variant="outline">
            Dev login (bypass auth)
          </Button>
        )}
      </div>
    </CustomCard>
  );
}
