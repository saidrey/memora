import { randomBytes } from 'node:crypto';
import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AlbumAccessService } from '../collaborators/album-access.service';
import { NfcQrTag, NfcQrTagType } from './nfc-qr-tag.model';
import {
  NFC_QR_TAG_REPOSITORY,
  NfcQrTagRepository,
} from './nfc-qr-tag-repository.interface';

// Deliberately a DIFFERENT env var than APP_SHARE_BASE_URL (spec09) — see
// memora-backend/README.md "NFC/QR (spec10-nfc-qr)" for why: the spec text
// literally says "placeholder APP_SHARE_BASE_URL" while giving it the
// `/n/{token}` shape, which would silently change spec09's already-fixed
// `/s/{token}` ShareLink URL. Same per-feature-env-var convention as
// APP_INVITE_BASE_URL/APP_SHARE_BASE_URL, just under its own name.
const DEFAULT_BASE_URL = 'https://memora.app/n/{token}';

export interface NfcQrTagView {
  id: string;
  albumId: string;
  type: NfcQrTagType;
  token: string;
  status: NfcQrTag['status'];
  url: string;
  createdAt: Date;
  updatedAt: Date;
  disabledAt?: Date;
}

/**
 * Owner-only management of an album's NFC/QR tags (spec10-nfc-qr.md).
 * UNLIKE `ShareLinksService.createOrGetExisting` (P5, one per album,
 * idempotent), `create` here ALWAYS inserts a new row — there is no
 * dedup/uniqueness by albumId or type (see nfc-qr-tag.model.ts).
 */
@Injectable()
export class NfcQrTagsService {
  constructor(
    @Inject(NFC_QR_TAG_REPOSITORY)
    private readonly tags: NfcQrTagRepository,
    private readonly albumAccess: AlbumAccessService,
    private readonly configService: ConfigService,
  ) {}

  /** Always creates a brand-new tag, token+`enabled`, regardless of how
   *  many tags (of this type or any other) already exist for the album. */
  async create(
    ownerId: string,
    albumId: string,
    type: NfcQrTagType,
  ): Promise<NfcQrTagView> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    const created = await this.tags.create({
      albumId,
      type,
      token: generateTagToken(),
    });
    return this.toView(created);
  }

  /** 404 uniform if the tag doesn't exist or the caller isn't the owner of
   *  the album it belongs to (resolved via AlbumAccessService.requireOwner). */
  async get(ownerId: string, tagId: string): Promise<NfcQrTagView> {
    const tag = await this.requireOwnedTag(ownerId, tagId);
    return this.toView(tag);
  }

  /** Idempotent (same criterion as ShareLinksService.revoke): disabling an
   *  already-disabled tag is a no-op, not an error. */
  async disable(ownerId: string, tagId: string): Promise<void> {
    const tag = await this.requireOwnedTag(ownerId, tagId);
    if (tag.status === 'disabled') {
      return;
    }
    await this.tags.disable(tagId);
  }

  private async requireOwnedTag(
    ownerId: string,
    tagId: string,
  ): Promise<NfcQrTag> {
    const tag = await this.tags.findById(tagId);
    if (!tag) {
      throw tagNotFound();
    }
    // Reuses the same 404-uniform check as every other owner-only route in
    // this backend — a tag whose album isn't the caller's looks identical
    // to a tag that doesn't exist.
    await this.albumAccess.requireOwner(tag.albumId, ownerId);
    return tag;
  }

  private toView(tag: NfcQrTag): NfcQrTagView {
    return {
      id: tag.id,
      albumId: tag.albumId,
      type: tag.type,
      token: tag.token,
      status: tag.status,
      url: this.buildUrl(tag.token),
      createdAt: tag.createdAt,
      updatedAt: tag.updatedAt,
      disabledAt: tag.disabledAt,
    };
  }

  private buildUrl(token: string): string {
    return this.baseUrl.replace('{token}', token);
  }

  private get baseUrl(): string {
    return (
      this.configService.get<string>('APP_NFC_QR_BASE_URL') ??
      DEFAULT_BASE_URL
    );
  }
}

function tagNotFound(): NotFoundException {
  return new NotFoundException('Etiqueta no encontrada');
}

function generateTagToken(): string {
  // Same 256-bit/URL-safe opaque shape as ShareLink.token/Invitation.token.
  return randomBytes(32).toString('base64url');
}
