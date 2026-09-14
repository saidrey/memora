import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { CollaboratorsService } from './collaborators.service';

@Controller('albums/:albumId/collaborators')
@UseGuards(SessionAuthGuard)
export class CollaboratorsController {
  constructor(private readonly collaboratorsService: CollaboratorsService) {}

  @Get()
  list(@CurrentUser() user: { id: string }, @Param('albumId') albumId: string) {
    return this.collaboratorsService.list(user.id, albumId);
  }

  // Must be declared BEFORE the ':userId' route below — Nest/Express match
  // routes in declaration order, and 'me' would otherwise never be reached
  // (it would always match ':userId' first).
  @Delete('me')
  @HttpCode(HttpStatus.NO_CONTENT)
  async leave(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
  ): Promise<void> {
    await this.collaboratorsService.leave(user.id, albumId);
  }

  @Delete(':userId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
    @Param('userId') userId: string,
  ): Promise<void> {
    await this.collaboratorsService.remove(user.id, albumId, userId);
  }
}
