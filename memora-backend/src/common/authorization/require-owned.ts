import { NotFoundException } from '@nestjs/common';

/**
 * 404s (not 403) if the entity doesn't exist OR belongs to someone else —
 * callers use this so a request never reveals that another user's resource
 * exists. Shared by albums and photos ownership checks.
 */
export function requireOwned<T extends { ownerId: string }>(
  entity: T | null,
  ownerId: string,
  notFoundMessage: string,
): T {
  if (!entity || entity.ownerId !== ownerId) {
    throw new NotFoundException(notFoundMessage);
  }
  return entity;
}
