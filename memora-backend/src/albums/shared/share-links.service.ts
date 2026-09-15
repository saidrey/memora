import { randomBytes } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AlbumAccessService } from '../collaborators/album-access.service';
import {
  SHARE_LINK_REPOSITORY,
  ShareLinkRepository,
} from './share-link-repository.interface';

const DEFAULT_BASE_URL = 'https://memora.app/s/{token}';

export interface ShareLinkView {
  token: string;
  url: string;
}

/**
 * Owner-only management of an album's share link (spec09-compartir-visor.md,
 * D2/P5). Reads `APP_SHARE_BASE_URL` via `ConfigService` — same pattern as
 * `InvitationsService`/`APP_INVITE_BASE_URL` — never `process.env` directly.
 *
 * "Estado del enlace consultable" (checklist item) is satisfied by
 * `createOrGetExisting` itself: since it's idempotent (P5, "crea o devuelve
 * el existente"), calling it again is how an owner checks the current
 * token/url without creating a duplicate. A dedicated `GET` was considered
 * and deliberately skipped — it would just re-expose the same
 * `ShareLinkView` shape with no extra information (there's no separate
 * "status" to report beyond "the token you'd get right now"), so it would
 * be a second route for the same read with no behavioral difference.
 */
@Injectable()
export class ShareLinksService {
  constructor(
    @Inject(SHARE_LINK_REPOSITORY)
    private readonly shareLinks: ShareLinkRepository,
    private readonly albumAccess: AlbumAccessService,
    private readonly configService: ConfigService,
  ) {}

  /** P5: one link per album. Returns the existing ACTIVE link untouched, or
   *  creates a fresh one (new token) if there is none yet or the previous
   *  one was revoked — revoking never gets reactivated by this call. */
  async createOrGetExisting(
    ownerId: string,
    albumId: string,
  ): Promise<ShareLinkView> {
    await this.albumAccess.requireOwner(albumId, ownerId);

    const existing = await this.shareLinks.findByAlbumId(albumId);
    if (existing && existing.status === 'active') {
      return { token: existing.token, url: this.buildUrl(existing.token) };
    }

    const created = await this.shareLinks.create({
      albumId,
      token: generateShareToken(),
    });
    return { token: created.token, url: this.buildUrl(created.token) };
  }

  /** Idempotent: revoking when there's no link yet, or it's already
   *  revoked, is a no-op — both cases already mean "not resolvable", so
   *  there's no distinguishable error to raise (same idempotence criterion
   *  already used by InvitationsService.revoke). */
  async revoke(ownerId: string, albumId: string): Promise<void> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    await this.shareLinks.revoke(albumId);
  }

  private buildUrl(token: string): string {
    return this.baseUrl.replace('{token}', token);
  }

  private get baseUrl(): string {
    return (
      this.configService.get<string>('APP_SHARE_BASE_URL') ?? DEFAULT_BASE_URL
    );
  }
}

function generateShareToken(): string {
  // Opaque, random, unguessable, never derivable from albumId (spec09) —
  // same 256-bit/URL-safe shape as Invitation's token (spec05).
  return randomBytes(32).toString('base64url');
}
