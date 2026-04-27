import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function mergeHandlers<Args extends readonly unknown[]>(
  ...handlers: (((...args: Args) => void) | undefined)[]
): (...args: Args) => void {
  return (...args: Args) => {
    handlers.forEach((fn) => fn?.(...args));
  };
}

export { withLogging } from './with-logging';
