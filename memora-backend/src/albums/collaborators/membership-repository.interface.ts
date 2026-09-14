import { AlbumMembership } from './album-membership.model';

export const MEMBERSHIP_REPOSITORY = Symbol('MEMBERSHIP_REPOSITORY');

/**
 * Persists COLLABORATOR memberships only — the owner role is derived from
 * `Album.ownerId` (see album-membership.model.ts for why). Same
 * repository-pattern shape as `AlbumRepository`/`PhotoRepository`: interface
 * + `Symbol` DI token + in-memory mock.
 */
export interface MembershipRepository {
  /** Idempotent: adding the same collaborator twice keeps the original joinedAt. */
  addCollaborator(albumId: string, userId: string): Promise<AlbumMembership>;
  findCollaborator(
    albumId: string,
    userId: string,
  ): Promise<AlbumMembership | null>;
  listCollaborators(albumId: string): Promise<AlbumMembership[]>;
  removeCollaborator(albumId: string, userId: string): Promise<void>;
  /** Albums where this user collaborates — backs the combined GET /albums list (P3). */
  listAlbumIdsForCollaborator(userId: string): Promise<string[]>;
  /** Cascade cleanup when an album is deleted (D16). Never touches other albums. */
  deleteAllForAlbum(albumId: string): Promise<void>;
}
