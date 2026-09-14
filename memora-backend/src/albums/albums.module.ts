import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { AlbumsController } from './albums.controller';
import { AlbumsService } from './albums.service';
import { ALBUM_REPOSITORY } from './album-repository.interface';
import { InMemoryAlbumRepository } from './in-memory-album.repository';
import { PHOTO_REPOSITORY } from './photos/photo-repository.interface';
import { InMemoryPhotoRepository } from './photos/in-memory-photo.repository';
import { PhotosService } from './photos/photos.service';
import { PhotosController } from './photos/photos.controller';
import { LibraryController } from './photos/library.controller';

@Module({
  imports: [AuthModule], // for SessionAuthGuard
  controllers: [AlbumsController, PhotosController, LibraryController],
  providers: [
    AlbumsService,
    PhotosService,
    { provide: ALBUM_REPOSITORY, useClass: InMemoryAlbumRepository },
    { provide: PHOTO_REPOSITORY, useClass: InMemoryPhotoRepository },
  ],
})
export class AlbumsModule {}
