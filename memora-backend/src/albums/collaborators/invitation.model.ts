/**
 * spec05-colaboradores.md — D12/D13: invitación por enlace, de un solo uso
 * (P6), expirable y revocable.
 *
 * `status` is written eagerly on `accept`/`revoke`, but `'expired'` is
 * detected lazily: the in-memory repository has no clock/cron of its own,
 * so `InvitationsService` checks `expiresAt` against `Date.now()` on every
 * read (list/accept/revoke) and persists the `'expired'` transition the
 * first time it notices — see `InvitationsService.resolveEffectiveStatus`.
 */
export type InvitationStatus = 'pending' | 'accepted' | 'revoked' | 'expired';

export interface Invitation {
  id: string;
  albumId: string;
  /** Opaque, random, unguessable (spec05: "no un id secuencial"). Never logged. */
  token: string;
  createdBy: string;
  status: InvitationStatus;
  expiresAt: Date;
  acceptedByUserId?: string;
  createdAt: Date;
}
