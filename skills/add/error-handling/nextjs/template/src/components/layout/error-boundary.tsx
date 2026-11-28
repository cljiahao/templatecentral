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

  // Report here: getDerivedStateFromError cannot, so render errors would never reach the logger.
  override componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    logError('ErrorBoundary caught an error', error);
    if (process.env.NODE_ENV === 'development') {
      console.error('Component stack:', errorInfo.componentStack);
    }
  }

  override render() {
    if (this.state.error) {
      if (this.props.fallback) return this.props.fallback;

      return (
        <ErrorFallback error={this.state.error} onReset={() => window.location.reload()} />
      );
    }

    return this.props.children;
  }
}
