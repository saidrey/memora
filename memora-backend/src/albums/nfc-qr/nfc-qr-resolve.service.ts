import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from '../album-repository.interface';
import {
  SHARE_LINK_REPOSITORY,
  ShareLinkRepository,
} from '../shared/share-link-repository.interface';
import {
  NFC_QR_TAG_REPOSITORY,
  NfcQrTagRepository,
} from './nfc-qr-tag-repository.interface';

/**
 * Backs the ONE public, unauthenticated NFC/QR endpoint
 * (`GET /api/v1/n/:token` — see `nfc-qr-resolve.controller.ts`, which is
 * deliberately NOT decorated with `@UseGuards(SessionAuthGuard)`, same
 * mechanism as `SharedController` from spec09).
 *
 * Resolution is INDIRECT by design (tag -> albumId -> whichever ShareLink
 * is active for that album right now): the tag never stores a ShareLink
 * token directly, so revoking/regenerating the album's ShareLink (spec09)
 * never breaks a physical tag already printed/written (D14, spec10).
 *
 * Redirects to this backend's own `GET /api/v1/shared/:shareToken` (the
 * spec's literal checklist target) rather than to the `APP_SHARE_BASE_URL`
 * placeholder URL — that placeholder point at a frontend domain
 * (`https://memora.app/...`) that doesn't exist yet in this MVP, so
 * redirecting there would 404 in any real/e2e test. Redirecting to our own
 * working endpoint keeps the observable behavior (a 302 to "the ShareLink
 * of the album, if active") while staying test-verifiable end-to-end.
 *
 * All failure cases (tag missing, tag disabled, album deleted, no
 * ShareLink, ShareLink revoked) collapse to the exact same uniform 404 —
 * never distinguished, same P1 criterion as SharedViewService (spec09).
 */
@Injectable()
export class NfcQrResolveService {
  constructor(
    @Inject(NFC_QR_TAG_REPOSITORY)
    private readonly tags: NfcQrTagRepository,
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    @Inject(SHARE_LINK_REPOSITORY)
    private readonly shareLinks: ShareLinkRepository,
  ) {}

  /** Returns the path to redirect to (302), or throws the uniform 404. */
  async resolve(token: string): Promise<string> {
    const tag = await this.tags.findByToken(token);
    if (!tag || tag.status !== 'enabled') {
      throw resolveNotFound();
    }

    const album = await this.albums.findById(tag.albumId);
    if (!album) {
      // Album deleted (D16) — AlbumsService.delete also hard-deletes the
      // tag itself, but this check is defense in depth either way.
      throw resolveNotFound();
    }

    const link = await this.shareLinks.findByAlbumId(album.id);
    if (!link || link.status !== 'active') {
      throw resolveNotFound();
    }

    return `/api/v1/shared/${link.token}`;
  }
}

function resolveNotFound(): NotFoundException {
  // Same message/shape as every other uniform 404 in this backend.
  return new NotFoundException('Recurso no encontrado');
}
