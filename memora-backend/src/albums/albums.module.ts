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
import { SHARE_LINK_REPOSITORY } from './shared/share-link-repository.interface';
import { InMemoryShareLinkRepository } from './shared/in-memory-share-link.repository';
import { ShareLinksService } from './shared/share-links.service';
import { ShareLinkController } from './shared/share-link.controller';
import { SharedViewService } from './shared/shared-view.service';
import { SharedController } from './shared/shared.controller';
import { NFC_QR_TAG_REPOSITORY } from './nfc-qr/nfc-qr-tag-repository.interface';
import { InMemoryNfcQrTagRepository } from './nfc-qr/in-memory-nfc-qr-tag.repository';
import { NfcQrTagsService } from './nfc-qr/nfc-qr-tags.service';
import { NfcQrResolveService } from './nfc-qr/nfc-qr-resolve.service';
import { NfcQrTagsController } from './nfc-qr/nfc-qr-tags.controller';
import { NfcQrTagController } from './nfc-qr/nfc-qr-tag.controller';
import { NfcQrResolveController } from './nfc-qr/nfc-qr-resolve.controller';

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
    ShareLinkController,
    // SharedController is one of TWO controllers in this module (and this
    // backend) without @UseGuards(SessionAuthGuard) — see its own doc
    // comment (spec09-compartir-visor.md, D2). NfcQrResolveController
    // (spec10-nfc-qr.md) is the other one.
    SharedController,
    NfcQrTagsController,
    NfcQrTagController,
    NfcQrResolveController,
  ],
  providers: [
    AlbumsService,
    PhotosService,
    AlbumAccessService,
    InvitationsService,
    CollaboratorsService,
    ShareLinksService,
    SharedViewService,
    NfcQrTagsService,
    NfcQrResolveService,
    { provide: ALBUM_REPOSITORY, useClass: InMemoryAlbumRepository },
    { provide: PHOTO_REPOSITORY, useClass: InMemoryPhotoRepository },
    { provide: PHOTO_STORAGE, useClass: GoogleDrivePhotoStorage },
    { provide: MEMBERSHIP_REPOSITORY, useClass: InMemoryMembershipRepository },
    { provide: INVITATION_REPOSITORY, useClass: InMemoryInvitationRepository },
    { provide: SHARE_LINK_REPOSITORY, useClass: InMemoryShareLinkRepository },
    { provide: NFC_QR_TAG_REPOSITORY, useClass: InMemoryNfcQrTagRepository },
  ],
})
export class AlbumsModule {}
