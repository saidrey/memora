import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { parseNfcQrTagType } from './parse-create-nfc-qr-tag-input';
import { NfcQrTagsService } from './nfc-qr-tags.service';

/** Owner-only: associate a new NFC/QR tag to an album (spec10-nfc-qr.md).
 *  See `nfc-qr-tag.controller.ts` for the by-id owner-only routes
 *  (GET/disable) and `nfc-qr-resolve.controller.ts` for the public one. */
@Controller('albums/:albumId/nfc-qr-tags')
@UseGuards(SessionAuthGuard)
export class NfcQrTagsController {
  constructor(private readonly nfcQrTagsService: NfcQrTagsService) {}

  /** Always creates a brand-new tag (no dedup by type/album) with a random
   *  token and `enabled` status. Responds `{ id, type, token, url, ... }`. */
  @Post()
  create(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
    @Body() body: unknown,
  ) {
    const type = parseNfcQrTagType(body);
    return this.nfcQrTagsService.create(user.id, albumId, type);
  }
}
