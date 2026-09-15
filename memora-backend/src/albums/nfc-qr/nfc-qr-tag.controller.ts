import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { NfcQrTagsService } from './nfc-qr-tags.service';

/**
 * Deliberately its own controller outside `/albums` (same reasoning as
 * `AcceptInvitationController`, spec05): these routes address a tag
 * directly by ITS OWN `id` — Memora's internal id, seen by the owner after
 * creating the tag — and don't carry an albumId in the URL. This is a
 * DIFFERENT id/route than the public `GET /api/v1/n/:token`
 * (`nfc-qr-resolve.controller.ts`), which looks up by the tag's opaque
 * TOKEN (what's physically recorded on the NFC/QR) — see
 * memora-backend/README.md "NFC/QR (spec10-nfc-qr)" for why the spec's own
 * text collides both routes and how that was resolved.
 */
@Controller('nfc-qr-tags')
@UseGuards(SessionAuthGuard)
export class NfcQrTagController {
  constructor(private readonly nfcQrTagsService: NfcQrTagsService) {}

  /** Owner-only: query the tag's current status/data by its internal id. */
  @Get(':id')
  get(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.nfcQrTagsService.get(user.id, id);
  }

  /** Owner-only soft-delete (P2): marks `disabled`, stamps `disabledAt`.
   *  Idempotent if already disabled. Not reactivable in the MVP. */
  @Patch(':id/disable')
  @HttpCode(HttpStatus.NO_CONTENT)
  async disable(
    @CurrentUser() user: { id: string },
    @Param('id') id: string,
  ): Promise<void> {
    await this.nfcQrTagsService.disable(user.id, id);
  }
}
