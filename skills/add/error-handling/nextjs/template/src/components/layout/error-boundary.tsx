// src/components/layout/error-boundary.tsx
'use client';

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { logError } from '@/lib/errors/error-log-handler';
import { ErrorFallback } from './error-fallback';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  // getDerivedStateFromError only updates state — reporting belongs here, or every
  // caught render error is swallowed and never reaches the logger.
  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    logError('ErrorBoundary caught an error', error);
    if (process.env.NODE_ENV === 'development') {
      console.error('Component stack:', errorInfo.componentStack);
    }
  }

  render() {
    if (this.state.error) {
      if (this.props.fallback) return this.props.fallback;

      return (
        <ErrorFallback error={this.state.error} onReset={() => window.location.reload()} />
      );
    }

    return this.props.children;
  }
}
