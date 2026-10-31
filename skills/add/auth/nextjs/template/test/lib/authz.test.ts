import { describe, expect, it } from 'vitest';

import type { Session } from '@/lib/auth';
import { hasRole, isOwner } from '@/lib/authz';

// Only `user.role` matters to hasRole; the cast skips building a full better-auth session.
function sessionWithRole(role: string): Session {
  return { user: { role } } as unknown as Session;
}

describe('hasRole', () => {
  it('hasRole is false without a session', () => {
    expect(hasRole(null, 'admin')).toBe(false);
  });

  it('hasRole is false for another role', () => {
    expect(hasRole(sessionWithRole('user'), 'admin')).toBe(false);
  });

  it('hasRole is true for the held role', () => {
    expect(hasRole(sessionWithRole('admin'), 'admin')).toBe(true);
  });
});

describe('isOwner', () => {
  it('isOwner is false for a missing owner', () => {
    expect(isOwner(undefined, 'u1')).toBe(false);
  });

  it('isOwner is false for another owner', () => {
    expect(isOwner('u2', 'u1')).toBe(false);
  });

  it('isOwner is true for the owner', () => {
    expect(isOwner('u1', 'u1')).toBe(true);
  });
});
