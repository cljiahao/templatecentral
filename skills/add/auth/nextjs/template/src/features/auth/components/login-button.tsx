'use client';

import { authClient } from '@/lib/auth-client';
import type { ComponentProps } from 'react';

import { Button } from '@/components/ui/button';

interface LoginButtonProps extends ComponentProps<typeof Button> {
  provider: 'google' | 'github' | 'microsoft';
  callbackURL?: string;
  label?: string;
}

export function LoginButton({
  provider,
  callbackURL = '/dashboard',
  label = 'Sign in',
  ...buttonProps
}: LoginButtonProps) {
  return (
    <Button
      onClick={() => authClient.signIn.social({ provider, callbackURL })}
      {...buttonProps}
    >
      {label}
    </Button>
  );
}
