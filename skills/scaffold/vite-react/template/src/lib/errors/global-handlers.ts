import { logError } from './error-log-handler';

// ErrorBoundary only catches render errors; these listeners log everything else.
export function registerGlobalErrorHandlers(): void {
  window.addEventListener('error', (event) => {
    logError('window.onerror', event.error ?? event.message);
  });

  window.addEventListener('unhandledrejection', (event) => {
    logError('unhandledrejection', event.reason);
  });
}
