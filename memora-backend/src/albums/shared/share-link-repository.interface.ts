import { ShareLink } from './share-link.model';

export const SHARE_LINK_REPOSITORY = Symbol('SHARE_LINK_REPOSITORY');

/**
 * Same repository-pattern shape as `InvitationRepository`: interface +
 * `Symbol` DI token + in-memory mock. One row per `albumId` (P5) — see
 * `share-link.model.ts` for what "one per album" means for create/revoke.
 */
export interface ShareLinkRepository {
  /** Always creates a brand-new row (new id/token), REPLACING whatever row
   *  (active or revoked) previously existed for this album — this is what
   *  makes "revoke, then create" produce a fresh token instead of
   *  reactivating the old one (P5). */
  create(input: { albumId: string; token: string }): Promise<ShareLink>;
  findByAlbumId(albumId: string): Promise<ShareLink | null>;
  findByToken(token: string): Promise<ShareLink | null>;
  /** Marks the album's current row `revoked`. Idempotent/no-op if there is
   *  no row (nothing to revoke) or it's already revoked. */
  revoke(albumId: string): Promise<void>;
  /** Cascade cleanup when an album is deleted (D16-style hygiene). Idempotent. */
  deleteByAlbumId(albumId: string): Promise<void>;
}
