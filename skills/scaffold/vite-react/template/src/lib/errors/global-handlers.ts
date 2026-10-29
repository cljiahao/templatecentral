import { logError } from './error-log-handler';

// React's ErrorBoundary only catches errors thrown during render. Everything else —
// errors in event handlers, timers, and async code, plus promise rejections with no
// .catch() (e.g. a failed fetch) — escapes it. These two global listeners close that gap
// so no uncaught error goes unlogged. Register once at bootstrap (see main.tsx).
export function registerGlobalErrorHandlers(): void {
  window.addEventListener('error', (event) => {
    logError('window.onerror', event.error ?? event.message);
  });

  window.addEventListener('unhandledrejection', (event) => {
    logError('unhandledrejection', event.reason);
  });
}
