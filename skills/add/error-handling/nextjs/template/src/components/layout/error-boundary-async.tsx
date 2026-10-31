// src/components/layout/error-boundary-async.tsx
'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { ErrorFallback } from './error-fallback';

interface AsyncErrorBoundaryProps {
  children: ReactNode;
}

export function AsyncErrorBoundary({ children }: AsyncErrorBoundaryProps) {
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      const reason: unknown = event.reason;
      setError(reason instanceof Error ? reason : new Error('An error occurred'));
    };

    window.addEventListener('unhandledrejection', handleUnhandledRejection);
    return () => window.removeEventListener('unhandledrejection', handleUnhandledRejection);
  }, []);

  if (error) {
    return <ErrorFallback error={error} onReset={() => window.location.reload()} />;
  }

  return <>{children}</>;
}
