import { App } from '@/app';
import { registerGlobalErrorHandlers } from '@/lib/errors';
import '@/styles/globals.css';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

// Capture async/event/promise errors that ErrorBoundary (render-phase only) cannot see.
registerGlobalErrorHandlers();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
