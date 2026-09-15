/**
 * spec09-compartir-visor.md — a read-only, no-login share link for an
 * album's viewer (D2). NOT the same thing as an M4 `Invitation`
 * (spec05-colaboradores.md): an invitation is single-use and turns the
 * acceptor into an authenticated collaborator; a `ShareLink` is reusable by
 * anyone who has it and never grants any role — it only unlocks the public
 * read-only view (`GET /api/v1/shared/:token`).
 *
 * P5 — one link per album: the repository keeps at most one `ShareLink` row
 * per `albumId`. Revoking and then creating again produces a brand-new
 * `token` (a new row entirely) — it never reactivates the revoked one.
 */
export type ShareLinkStatus = 'active' | 'revoked';

export interface ShareLink {
  id: string;
  albumId: string;
  /** Opaque, random, unguessable (same shape/entropy as Invitation.token —
   *  spec05). Never derivable from albumId, never logged. */
  token: string;
  status: ShareLinkStatus;
  createdAt: Date;
}
