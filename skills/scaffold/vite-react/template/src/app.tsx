import { ErrorBoundary, Providers } from '@/components/layout';
import { AppRouter } from '@/router';

export function App() {
  return (
    <ErrorBoundary>
      <Providers>
        <AppRouter />
      </Providers>
    </ErrorBoundary>
  );
}
