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
import { PHOTO_STORAGE } from './photos/storage/photo-storage.interface';
import { GoogleDrivePhotoStorage } from './photos/storage/google-drive-photo-storage';
import { MEMBERSHIP_REPOSITORY } from './collaborators/membership-repository.interface';
import { InMemoryMembershipRepository } from './collaborators/in-memory-membership.repository';
import { INVITATION_REPOSITORY } from './collaborators/invitation-repository.interface';
import { InMemoryInvitationRepository } from './collaborators/in-memory-invitation.repository';
import { AlbumAccessService } from './collaborators/album-access.service';
import { InvitationsService } from './collaborators/invitations.service';
import { CollaboratorsService } from './collaborators/collaborators.service';
import { InvitationsController } from './collaborators/invitations.controller';
import { AcceptInvitationController } from './collaborators/accept-invitation.controller';
import { CollaboratorsController } from './collaborators/collaborators.controller';

@Module({
  // ConfigModule is registered as global from AuthModule (isGlobal: true) —
  // InvitationsService injects ConfigService without importing ConfigModule
  // again here.
  imports: [AuthModule], // for SessionAuthGuard
  controllers: [
    AlbumsController,
    PhotosController,
    LibraryController,
    InvitationsController,
    AcceptInvitationController,
    CollaboratorsController,
  ],
  providers: [
    AlbumsService,
    PhotosService,
    AlbumAccessService,
    InvitationsService,
    CollaboratorsService,
    { provide: ALBUM_REPOSITORY, useClass: InMemoryAlbumRepository },
    { provide: PHOTO_REPOSITORY, useClass: InMemoryPhotoRepository },
    { provide: PHOTO_STORAGE, useClass: GoogleDrivePhotoStorage },
    { provide: MEMBERSHIP_REPOSITORY, useClass: InMemoryMembershipRepository },
    { provide: INVITATION_REPOSITORY, useClass: InMemoryInvitationRepository },
  ],
})
export class AlbumsModule {}
