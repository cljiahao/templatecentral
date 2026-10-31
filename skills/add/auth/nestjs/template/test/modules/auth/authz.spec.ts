import { describe, expect, it } from 'vitest';
import { ForbiddenException, NotFoundException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { assertOwner } from '../../../src/modules/auth/ownership';
import { Roles } from '../../../src/modules/auth/roles.decorator';
import { RolesGuard } from '../../../src/modules/auth/roles.guard';

// `this: void` lets each handler be passed around unbound, as Nest's ExecutionContext does.
class OpenController {
  list(this: void) {
    return [];
  }
}

class AdminController {
  @Roles(['admin'])
  remove(this: void) {
    return true;
  }
}

@Roles(['admin'])
class MixedController {
  @Roles(['user'])
  read(this: void) {
    return true;
  }
}

/** The two things RolesGuard reads: route metadata, and whatever user is on the request. */
function contextWithUser(
  controller: abstract new () => object,
  handler: () => unknown,
  user: object | undefined
): ExecutionContext {
  return {
    getHandler: () => handler,
    getClass: () => controller,
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as unknown as ExecutionContext;
}

/** A request carrying the user JwtStrategy.validate() returns. */
function contextFor(
  controller: abstract new () => object,
  handler: () => unknown,
  roles: string[]
): ExecutionContext {
  return contextWithUser(controller, handler, { id: 'u1', email: 'a@example.com', roles });
}

const guard = new RolesGuard(new Reflector());

describe('RolesGuard', () => {
  it('denies when the handler has no @Roles metadata', () => {
    const context = contextFor(OpenController, OpenController.prototype.list, ['admin']);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a user without any required role', () => {
    const context = contextFor(AdminController, AdminController.prototype.remove, ['user']);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('allows a user holding one required role', () => {
    const context = contextFor(AdminController, AdminController.prototype.remove, ['admin']);
    expect(guard.canActivate(context)).toBe(true);
  });

  it('lets handler @Roles override class @Roles', () => {
    const context = contextFor(MixedController, MixedController.prototype.read, ['user']);
    expect(guard.canActivate(context)).toBe(true);
  });

  it('denies a request with no user', () => {
    const context = contextWithUser(AdminController, AdminController.prototype.remove, undefined);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a roles list containing a non-string entry', () => {
    const user = { id: 'u1', email: 'a@example.com', roles: ['admin', 42] };
    const context = contextWithUser(AdminController, AdminController.prototype.remove, user);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('denies a user without a roles list', () => {
    const user = { id: 'u1', email: 'a@example.com' };
    const context = contextWithUser(AdminController, AdminController.prototype.remove, user);
    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });
});

describe('assertOwner', () => {
  it('assertOwner throws NotFoundException for another owner', () => {
    expect(() => assertOwner('u2', 'u1')).toThrow(NotFoundException);
  });

  it('assertOwner throws NotFoundException for a missing record', () => {
    expect(() => assertOwner(undefined, 'u1')).toThrow(NotFoundException);
  });

  it('assertOwner allows the owner', () => {
    expect(() => assertOwner('u1', 'u1')).not.toThrow();
  });
});
