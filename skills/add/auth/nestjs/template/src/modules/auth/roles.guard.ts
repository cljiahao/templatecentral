import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { FastifyRequest } from 'fastify';

import type { AuthUser } from './jwt.strategy';
import { Roles } from './roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride(Roles, [
      context.getHandler(),
      context.getClass(),
    ]);
    // A route behind this guard without @Roles is a mistake, so it is denied rather than opened.
    if (!required?.length) {
      throw new ForbiddenException('Insufficient permissions.');
    }
    // Partial: a customised validate() may omit roles, which must deny (403), not throw (500).
    const { user } = context
      .switchToHttp()
      .getRequest<FastifyRequest & { user?: Partial<AuthUser> }>();
    const roles = user?.roles;
    // A malformed roles list (any non-string entry) denies outright instead of being matched loosely.
    if (
      !Array.isArray(roles) ||
      !roles.every((role) => typeof role === 'string') ||
      !roles.some((role) => required.includes(role))
    ) {
      throw new ForbiddenException('Insufficient permissions.');
    }
    return true;
  }
}
