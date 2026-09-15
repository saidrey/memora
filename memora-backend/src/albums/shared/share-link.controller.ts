import {
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { ShareLinksService } from './share-links.service';

/** Owner-only management of an album's share link (spec09). This is NOT the
 *  public resolution endpoint — see `shared.controller.ts` for that one. */
@Controller('albums/:albumId/share-link')
@UseGuards(SessionAuthGuard)
export class ShareLinkController {
  constructor(private readonly shareLinksService: ShareLinksService) {}

  /** Creates the album's share link, or returns the existing active one
   *  unchanged (P5: one per album, idempotent). */
  @Post()
  create(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
  ) {
    return this.shareLinksService.createOrGetExisting(user.id, albumId);
  }

  /** Revokes the album's share link. Idempotent if there was none, or it
   *  was already revoked. */
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  async revoke(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
  ): Promise<void> {
    await this.shareLinksService.revoke(user.id, albumId);
  }
}
