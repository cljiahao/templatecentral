/// <reference types="vite/client" />

// Declared so dot access stays valid under noPropertyAccessFromIndexSignature.
interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string;
}

declare namespace NodeJS {
  interface ProcessEnv {
    CI?: string;
  }
}
