import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { requireStringField } from '../common/validation/require-string-field';
import { CurrentUser } from '../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../auth/session/session-auth.guard';
import { AlbumsService } from './albums.service';
import { PhotosService } from './photos/photos.service';

const MAX_ALBUM_NAME_LENGTH = 100;

@Controller('albums')
@UseGuards(SessionAuthGuard)
export class AlbumsController {
  constructor(
    private readonly albumsService: AlbumsService,
    private readonly photosService: PhotosService,
  ) {}

  @Post()
  create(@CurrentUser() user: { id: string }, @Body() body: unknown) {
    const name = readAlbumName(body);
    return this.albumsService.create(user.id, name);
  }

  @Get()
  list(@CurrentUser() user: { id: string }) {
    return this.albumsService.listForUser(user.id);
  }

  @Get(':id')
  get(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.albumsService.getForUser(user.id, id);
  }

  @Patch(':id')
  rename(
    @CurrentUser() user: { id: string },
    @Param('id') id: string,
    @Body() body: unknown,
  ) {
    const name = readAlbumName(body);
    return this.albumsService.rename(user.id, id, name);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: { id: string },
    @Param('id') id: string,
  ): Promise<void> {
    await this.albumsService.delete(user.id, id);
  }

  /** Associates an existing photo of the caller's to this album (N:M). */
  @Post(':albumId/photos')
  @HttpCode(HttpStatus.NO_CONTENT)
  async associatePhoto(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
    @Body() body: unknown,
  ): Promise<void> {
    const photoId = requireStringField(body, 'photoId');
    await this.photosService.associate(user.id, albumId, photoId);
  }

  /** Removes the relation only — never the photo or its storage file (D3/D4). */
  @Delete(':albumId/photos/:photoId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async disassociatePhoto(
    @CurrentUser() user: { id: string },
    @Param('albumId') albumId: string,
    @Param('photoId') photoId: string,
  ): Promise<void> {
    await this.photosService.disassociate(user.id, albumId, photoId);
  }
}

function readAlbumName(body: unknown): string {
  return requireStringField(body, 'name', { maxLength: MAX_ALBUM_NAME_LENGTH });
}
