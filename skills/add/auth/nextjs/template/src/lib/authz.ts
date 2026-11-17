import type { Session } from '@/lib/auth';

/** True only when a signed-in user holds `role`; check for a null session first. */
export function hasRole(session: Session | null, role: string): session is Session {
  return session?.user.role === role;
}

/** True only when the record exists and belongs to `userId`. */
export function isOwner(ownerId: string | null | undefined, userId: string): boolean {
  return ownerId != null && ownerId === userId;
}
