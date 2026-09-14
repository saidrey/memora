import {
  Body,
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
import { parseRegisterPhotoInput } from './parse-register-photo-input';
import { PhotosService } from './photos.service';

@Controller('photos')
@UseGuards(SessionAuthGuard)
export class PhotosController {
  constructor(private readonly photosService: PhotosService) {}

  /** Registers a photo the client already uploaded to Drive — no bytes here. */
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
}
