'use client';

import { authClient } from '@/lib/auth-client';
import { useRouter } from 'next/navigation';
import type { ComponentProps } from 'react';

import { Button } from '@/components/ui/button';

interface SignOutButtonProps extends ComponentProps<typeof Button> {
  redirectTo?: string;
}

export function SignOutButton({
  redirectTo = '/',
  children = 'Sign out',
  ...buttonProps
}: SignOutButtonProps) {
  const router = useRouter();

  async function handleSignOut() {
    await authClient.signOut();
    router.push(redirectTo);
  }

  return (
    <Button onClick={handleSignOut} {...buttonProps}>
      {children}
    </Button>
  );
}
