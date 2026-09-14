/**
 * spec05-colaboradores.md: pertenencia de un usuario a un álbum con rol.
 *
 * Implementation decision (left open by the spec, "sin cambiar contrato"):
 * the OWNER row is never persisted here — it's derived on the fly from
 * `Album.ownerId` (see `AlbumAccessService`). `MembershipRepository` only
 * ever stores `role: 'collaborator'` rows. Reasons:
 *   - There's no ownership transfer in the MVP, so a persisted owner row
 *     would never change after creation — pure duplicate state to keep in
 *     sync with `Album.ownerId` for zero behavioral benefit.
 *   - Every "is this a member?" check already has the `Album` in hand (it
 *     needs it anyway to 404 on a nonexistent album), so deriving the
 *     owner role costs nothing extra.
 * The `role` field stays on the model (matching the spec's literal shape)
 * even though the in-memory repository only ever creates `'collaborator'`
 * values — kept for interface fidelity / a future real repository that
 * might choose to persist owner rows too.
 */
export type AlbumRole = 'owner' | 'collaborator';

export interface AlbumMembership {
  albumId: string;
  userId: string;
  role: AlbumRole;
  joinedAt: Date;
}
