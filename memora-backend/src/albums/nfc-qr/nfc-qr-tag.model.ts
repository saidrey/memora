/**
 * spec10-nfc-qr.md — a stable, pre-recordable identifier for a physical NFC
 * tag or QR code that a user affixes somewhere (a shop, a wedding
 * invitation, a landmark) pointing at an album's viewer.
 *
 * Why this exists instead of writing the `ShareLink` (spec09) token
 * directly onto the tag: a `ShareLink` can be revoked/regenerated (its
 * token changes), which would permanently break a physical tag. A
 * `NfcQrTag` is associated with the ALBUM, not the `ShareLink` — resolution
 * is indirect (tag -> albumId -> whatever ShareLink is active right now,
 * see `nfc-qr-resolve.service.ts`) so regenerating the ShareLink never
 * breaks a tag already printed/written (D14).
 *
 * No uniqueness constraint by design: unlike `ShareLink` (at most one row
 * per album), a `POST` here ALWAYS creates a brand-new row — an album can
 * have several NFC tags and/or several QR codes at once (spec10, despite
 * the spec's own checklist text momentarily saying "one per type per
 * album" and then immediately contradicting itself by describing multiple
 * rows of the same type; see memora-backend/README.md for the note).
 */
export type NfcQrTagType = 'NFC' | 'QR';
export type NfcQrTagStatus = 'enabled' | 'disabled';

export interface NfcQrTag {
  id: string;
  albumId: string;
  type: NfcQrTagType;
  /** Opaque, random, unguessable, 256-bit (same shape as ShareLink.token /
   *  Invitation.token) — never derivable from albumId or id. This is the
   *  value physically recorded onto the NFC tag / encoded into the QR. */
  token: string;
  status: NfcQrTagStatus;
  createdAt: Date;
  updatedAt: Date;
  /** Set when disabled (P2 soft-delete). Not reactivable in the MVP even
   *  though the shape supports it (spec10, out of scope). */
  disabledAt?: Date;
}
