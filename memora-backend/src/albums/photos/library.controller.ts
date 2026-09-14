import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import { PhotosService } from './photos.service';

/** Biblioteca personal (D11): fotos del usuario, independiente de álbumes. */
@Controller('library')
@UseGuards(SessionAuthGuard)
export class LibraryController {
  constructor(private readonly photosService: PhotosService) {}

  @Get()
  list(@CurrentUser() user: { id: string }) {
    return this.photosService.listLibrary(user.id);
  }
}
