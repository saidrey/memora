import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { InvitationsService } from './invitations.service';

/** Owner-only management of an album's invitations (D12/D13). */
@Controller('albums/:albumId/invitations')
@UseGuards(SessionAuthGuard)
export class InvitationsController {
  constructor(private readonly invitationsService: InvitationsService) {}

  @Post()
  create(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
  ) {
    return this.invitationsService.create(user.id, albumId);
  }

  @Get()
  list(@CurrentUser() user: { id: string }, @Param('albumId') albumId: string) {
    return this.invitationsService.list(user.id, albumId);
  }

  @Delete(':invitationId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async revoke(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
    @Param('invitationId') invitationId: string,
  ): Promise<void> {
    await this.invitationsService.revoke(user.id, albumId, invitationId);
  }
}
