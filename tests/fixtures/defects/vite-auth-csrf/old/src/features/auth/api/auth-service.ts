import { z } from 'zod';
import { getApiBaseUrl } from '@/lib/constants/env';
import { APIError } from '@/lib/errors';
import type { AuthUser } from '../types';

// Resolved per-request, never at module scope: getApiBaseUrl() throws when
// VITE_API_BASE_URL is unset, and a module-scope throw kills bundle evaluation
// before createRoot() runs — a blank page with no ErrorBoundary to catch it.
const authBase = () => `${getApiBaseUrl()}/auth`;

// Validate API response shapes at the boundary — mirrors the AuthUser type.
const authUserSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.email(),
  // AuthUser has it — without this, parse() silently strips it
  image: z.string().nullable().optional(),
});

export async function loginWithCredentials(
  email: string,
  password: string
): Promise<AuthUser> {
  const res = await fetch(`${authBase()}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    credentials: 'include',
  });

  if (!res.ok) {
    throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Login failed' })) });
  }

  return authUserSchema.parse(await res.json());
}

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const res = await fetch(`${authBase()}/me`, { credentials: 'include' });
  if (!res.ok) return null;
  return authUserSchema.parse(await res.json());
}

export async function logoutUser(): Promise<void> {
  await fetch(`${authBase()}/logout`, {
    method: 'POST',
    credentials: 'include',
  });
}
