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
import { ApiException } from '../common/exceptions/api.exception';
import { requireStringField } from '../common/validation/require-string-field';
import { CurrentUser } from '../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../auth/session/session-auth.guard';
import { AlbumUpdate, AlbumsService } from './albums.service';
import { AlbumVisibility } from './album.model';
import { PhotosService } from './photos/photos.service';

const MAX_ALBUM_NAME_LENGTH = 100;
const ALBUM_VISIBILITIES: readonly AlbumVisibility[] = ['PRIVATE', 'PUBLIC'];

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
    const visibility = readOptionalVisibility(body);
    return this.albumsService.create(user.id, name, visibility);
  }

  @Get()
  list(@CurrentUser() user: { id: string }) {
    return this.albumsService.listForUser(user.id);
  }

  @Get(':id')
  get(@CurrentUser() user: { id: string }, @Param('id') id: string) {
    return this.albumsService.getForUser(user.id, id);
  }

  /** `name` and/or `visibility` (D17, spec09) — at least one must be
   *  present, validated by `parseAlbumUpdate`. */
  @Patch(':id')
  update(
    @CurrentUser() user: { id: string },
    @Param('id') id: string,
    @Body() body: unknown,
  ) {
    const patch = parseAlbumUpdate(body);
    return this.albumsService.update(user.id, id, patch);
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

/** `visibility` is optional on create (D17 default is PRIVATE, applied by
 *  the repository) — validated to the enum by hand when present, never
 *  silently coerced. */
function readOptionalVisibility(body: unknown): AlbumVisibility | undefined {
  const value = (body as Record<string, unknown> | null)?.visibility;
  if (value === undefined) {
    return undefined;
  }
  if (
    typeof value !== 'string' ||
    !ALBUM_VISIBILITIES.includes(value as AlbumVisibility)
  ) {
    throw invalidField('visibility');
  }
  return value as AlbumVisibility;
}

/** PATCH /albums/:id (spec09): accepts `name` and/or `visibility`, but
 *  requires at least one — an empty/all-omitted body is a 400, not a
 *  silent no-op, so a client never wonders whether a patch it thought it
 *  sent actually did anything. */
function parseAlbumUpdate(body: unknown): AlbumUpdate {
  const record = (body as Record<string, unknown> | null) ?? {};
  const hasName = record.name !== undefined;
  const hasVisibility = record.visibility !== undefined;
  if (!hasName && !hasVisibility) {
    throw new ApiException(
      HttpStatus.BAD_REQUEST,
      'INVALID_REQUEST',
      'Debes indicar name y/o visibility',
    );
  }
  return {
    name: hasName ? readAlbumName(body) : undefined,
    visibility: hasVisibility ? readOptionalVisibility(body) : undefined,
  };
}

function invalidField(field: string): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'INVALID_REQUEST',
    `${field} no es válido`,
  );
}
