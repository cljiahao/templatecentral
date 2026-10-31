import type { Session } from '@/lib/auth';

/**
 * True only when a signed-in user holds `role`; narrows `session` to `Session` when true.
 * Check for a null session first: the false branch also covers a missing session, so it
 * does not mean "signed in without the role" and must not be narrowed as if it did.
 */
export function hasRole(session: Session | null, role: string): session is Session {
  return session?.user.role === role;
}

/** True only when the record exists and belongs to `userId`. */
export function isOwner(ownerId: string | null | undefined, userId: string): boolean {
  return ownerId != null && ownerId === userId;
}
