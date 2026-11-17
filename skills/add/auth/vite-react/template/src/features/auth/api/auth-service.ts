import { csrfHeader } from '@/lib/clients/csrf';
import { getApiBaseUrl } from '@/lib/constants/env';
import { APIError } from '@/lib/errors';
import { z } from 'zod';
import type { AuthUser } from '../types';

// Resolved per request: a module-scope throw would blank the page before createRoot().
const authBase = () => `${getApiBaseUrl()}/auth`;

const authUserSchema = z
  .object({
    id: z.string(),
    // NestJS /auth/me returns only token claims; fall back to email.
    name: z.string().optional(),
    email: z.email(),
    // Keep this field or parse() silently strips it.
    image: z.string().nullable().optional(),
  })
  .transform((u): AuthUser => ({ ...u, name: u.name ?? u.email }));

// Cookie-mode login: the backend sets the HttpOnly session cookie, so the JWT never reaches JavaScript.
export async function loginWithCredentials(email: string, password: string): Promise<AuthUser> {
  const res = await fetch(`${authBase()}/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    credentials: 'include',
  });

  if (!res.ok) {
    throw new APIError({
      statusCode: res.status,
      data: await res.json().catch(() => ({ message: 'Login failed' })),
    });
  }

  const user = await fetchCurrentUser();
  if (!user) throw new APIError({ statusCode: 401 });
  return user;
}

export async function fetchCurrentUser(): Promise<AuthUser | null> {
  const res = await fetch(`${authBase()}/me`, { credentials: 'include' });
  if (!res.ok) return null;
  return authUserSchema.parse(await res.json());
}

export async function logoutUser(): Promise<void> {
  const res = await fetch(`${authBase()}/logout`, {
    method: 'POST',
    headers: csrfHeader(),
    credentials: 'include',
  });
  if (!res.ok) throw new APIError({ statusCode: res.status });
}
