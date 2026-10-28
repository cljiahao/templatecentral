'use client';

import { useEffect } from 'react';

import { Button } from '@/components/ui/button';
import { logError } from '@/lib/errors/error-log-handler';

export default function RootError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    logError('app.error-boundary', error);
  }, [error]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="text-2xl font-semibold">This page couldn&apos;t load</h1>
      <p className="text-muted-foreground max-w-md">
        Something went wrong on our side. Try again, or reload the page if it keeps happening.
      </p>
      {error.digest && (
        <p className="text-muted-foreground text-sm">Error reference: {error.digest}</p>
      )}
      <Button onClick={reset}>Try again</Button>
    </main>
  );
}
