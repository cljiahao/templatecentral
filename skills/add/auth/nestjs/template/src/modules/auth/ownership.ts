import { NotFoundException } from '@nestjs/common';

/** Throws unless `userId` owns the record; pass `undefined` when the record does not exist. */
export function assertOwner(ownerId: string | undefined, userId: string): void {
  // 404 rather than 403, so a caller cannot probe which ids belong to other users.
  if (ownerId === undefined || ownerId !== userId) {
    throw new NotFoundException('Not found.');
  }
}
