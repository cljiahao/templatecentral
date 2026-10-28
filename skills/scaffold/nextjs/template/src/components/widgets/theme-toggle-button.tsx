'use client';

import { Moon, Sun } from 'lucide-react';
import { useTheme } from 'next-themes';

// Icon visibility is driven by the `dark:` variant, not by `resolvedTheme`: the theme is
// unknown during SSR, so state-derived styles would mismatch on hydration.
export function ThemeToggleButton() {
  const { resolvedTheme, setTheme } = useTheme();

  return (
    <button
      type="button"
      onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
      className="bg-muted focus-visible:ring-ring/50 relative overflow-hidden rounded-full p-5 transition-colors outline-none focus-visible:ring-[3px]"
      aria-label="Toggle dark mode"
    >
      <span className="flex-center absolute inset-0 -translate-y-1/2 opacity-0 transition-all duration-200 dark:translate-y-0 dark:opacity-100">
        <Sun className="h-5 w-5" fill="currentColor" />
      </span>
      <span className="flex-center absolute inset-0 transition-all duration-200 dark:translate-y-1/2 dark:opacity-0">
        <Moon className="h-5 w-5" fill="currentColor" />
      </span>
    </button>
  );
}
