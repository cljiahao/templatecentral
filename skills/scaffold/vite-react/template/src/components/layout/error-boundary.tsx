import { ENV } from '@/lib/constants/env';
import { logError } from '@/lib/errors';
import { Component, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error) {
    logError('react.error-boundary', error);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <main className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-2xl font-bold">This page couldn&apos;t load</h1>
          <p className="text-muted-foreground max-w-md text-sm">
            {ENV.IS_DEV && this.state.error
              ? this.state.error.message
              : 'Try again, or reload the page if it keeps happening.'}
          </p>
          <button
            type="button"
            onClick={this.handleRetry}
            className="bg-primary text-primary-foreground hover:bg-primary/90 focus-visible:ring-ring/50 rounded-md px-4 py-2 text-sm font-medium transition-colors outline-none focus-visible:ring-[3px]"
          >
            Try again
          </button>
        </main>
      );
    }

    return this.props.children;
  }
}
