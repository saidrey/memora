import {
  Controller,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { InvitationsService } from './invitations.service';

/**
 * Deliberately its own controller outside `/albums` (spec05: "controller
 * nuevo fuera de /albums") — accepting doesn't need (or have) an albumId in
 * the URL, only the invitation token.
 */
@Controller('invitations')
@UseGuards(SessionAuthGuard)
export class AcceptInvitationController {
  constructor(private readonly invitationsService: InvitationsService) {}

  /** 204 both for a fresh join and for the idempotent already-a-member case
   *  (P5) — the caller can't tell them apart, and doesn't need to. */
  @Post(':token/accept')
  @HttpCode(HttpStatus.NO_CONTENT)
  async accept(
    @CurrentUser() user: { id: string },
    @Param('token') token: string,
  ): Promise<void> {
    await this.invitationsService.accept(user.id, token);
  }
}
