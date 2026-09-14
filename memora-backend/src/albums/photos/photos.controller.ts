import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../../auth/session/current-user.decorator';
import { SessionAuthGuard } from '../../auth/session/session-auth.guard';
import {
  parseAvailabilityReportsInput,
  parseAvailabilityValue,
} from './parse-availability-input';
import { parseRegisterPhotoInput } from './parse-register-photo-input';
import { PhotosService } from './photos.service';

@Controller('photos')
@UseGuards(SessionAuthGuard)
export class PhotosController {
  constructor(private readonly photosService: PhotosService) {}

  /** Registers a photo the client already uploaded to the storage provider —
   *  no bytes here. */
  @Post()
  create(@CurrentUser() user: { id: string }, @Body() body: unknown) {
    const input = parseRegisterPhotoInput(body);
    return this.photosService.register(user.id, input);
  }

  @Delete(':photoId')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: { id: string },
    @Param('photoId') photoId: string,
  ): Promise<void> {
    await this.photosService.deletePhoto(user.id, photoId);
  }

  /** spec07-disponibilidad.md (P2a): the photo's owner reports what their
   *  client observed against the storage provider. Owner-only — 404
   *  uniforme si la foto es ajena o no existe. */
  @Patch(':photoId/availability')
  reportAvailability(
    @CurrentUser() user: { id: string },
    @Param('photoId') photoId: string,
    @Body() body: unknown,
  ) {
    const availability = parseAvailabilityValue(body);
    return this.photosService.reportAvailability(user.id, photoId, availability);
  }

  /** spec07-disponibilidad.md (P2b): batch report after reviewing an album.
   *  Entries for photos the caller doesn't own are silently skipped — see
   *  PhotosService.reportAvailabilityBatch. */
  @Post('availability')
  @HttpCode(HttpStatus.NO_CONTENT)
  async reportAvailabilityBatch(
    @CurrentUser() user: { id: string },
    @Body() body: unknown,
  ): Promise<void> {
    const reports = parseAvailabilityReportsInput(body);
    await this.photosService.reportAvailabilityBatch(user.id, reports);
  }
}
