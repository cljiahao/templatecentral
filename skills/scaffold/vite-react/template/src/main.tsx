import { App } from '@/app';
import { registerGlobalErrorHandlers } from '@/lib/errors';
import '@/styles/globals.css';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

registerGlobalErrorHandlers();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
