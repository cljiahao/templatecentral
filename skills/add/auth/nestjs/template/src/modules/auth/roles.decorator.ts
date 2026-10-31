import { Reflector } from '@nestjs/core';

/** Roles allowed to call a handler; holding any one is enough. Handler metadata overrides class metadata. */
export const Roles = Reflector.createDecorator<string[]>();
