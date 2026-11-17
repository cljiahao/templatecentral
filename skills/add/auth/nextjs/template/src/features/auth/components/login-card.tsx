'use client';

import { authClient } from '@/lib/auth-client';
import { isDev } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useRouter } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { CustomCard } from '@/components/widgets/custom-card';

// better-auth rejects single-label domains such as dev@local; use a dotted domain.
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
      // First run: create the account; autoSignIn signs in immediately.
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
        {/* One LoginButton per SSO provider goes here. */}
        {isDev && (
          <Button onClick={handleDevLogin} variant="outline">
            Dev login (bypass auth)
          </Button>
        )}
      </div>
    </CustomCard>
  );
}
