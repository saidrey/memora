import { NfcQrTag, NfcQrTagType } from './nfc-qr-tag.model';

export const NFC_QR_TAG_REPOSITORY = Symbol('NFC_QR_TAG_REPOSITORY');

/**
 * Same repository-pattern shape as `ShareLinkRepository`/`InvitationRepository`:
 * interface + `Symbol` DI token + in-memory mock. UNLIKE `ShareLinkRepository`
 * (at most one row per albumId), this one is keyed by `id` — there is no
 * uniqueness constraint here, several tags can share the same `albumId`
 * and/or `type` (see nfc-qr-tag.model.ts for why).
 */
export interface NfcQrTagRepository {
  /** Always creates a brand-new row — no dedup/replace by albumId or type. */
  create(input: {
    albumId: string;
    type: NfcQrTagType;
    token: string;
  }): Promise<NfcQrTag>;
  findById(id: string): Promise<NfcQrTag | null>;
  findByToken(token: string): Promise<NfcQrTag | null>;
  /** Marks the tag `disabled` and stamps `disabledAt`. Idempotent/no-op if
   *  already disabled (mirrors ShareLinkRepository.revoke). */
  disable(id: string): Promise<NfcQrTag>;
  /** Cascade cleanup when an album is deleted (D16) — hard-delete, unlike
   *  the tag's own soft-delete (`disable`). Idempotent. */
  deleteAllForAlbum(albumId: string): Promise<void>;
}
