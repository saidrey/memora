import { TestingModuleBuilder } from '@nestjs/testing';
import { ALBUM_REPOSITORY } from '../src/albums/album-repository.interface';
import { InMemoryAlbumRepository } from '../src/albums/in-memory-album.repository';
import { INVITATION_REPOSITORY } from '../src/albums/collaborators/invitation-repository.interface';
import { InMemoryInvitationRepository } from '../src/albums/collaborators/in-memory-invitation.repository';
import { MEMBERSHIP_REPOSITORY } from '../src/albums/collaborators/membership-repository.interface';
import { InMemoryMembershipRepository } from '../src/albums/collaborators/in-memory-membership.repository';
import { NFC_QR_TAG_REPOSITORY } from '../src/albums/nfc-qr/nfc-qr-tag-repository.interface';
import { InMemoryNfcQrTagRepository } from '../src/albums/nfc-qr/in-memory-nfc-qr-tag.repository';
import { PHOTO_REPOSITORY } from '../src/albums/photos/photo-repository.interface';
import { InMemoryPhotoRepository } from '../src/albums/photos/in-memory-photo.repository';
import { SHARE_LINK_REPOSITORY } from '../src/albums/shared/share-link-repository.interface';
import { InMemoryShareLinkRepository } from '../src/albums/shared/in-memory-share-link.repository';
import { SESSION_REGISTRY } from '../src/auth/session/session-registry.interface';
import { InMemorySessionRegistry } from '../src/auth/session/in-memory-session-registry';
import { TOKEN_STORE } from '../src/auth/tokens/token-store.interface';
import { InMemoryTokenStore } from '../src/auth/tokens/in-memory-token.store';
import { USER_REPOSITORY } from '../src/auth/users/user-repository.interface';
import { InMemoryUserRepository } from '../src/auth/users/in-memory-user.repository';

/** Keeps e2e tests independent from a real database. */
export function withInMemoryPersistence(
  builder: TestingModuleBuilder,
): TestingModuleBuilder {
  return builder
    .overrideProvider(ALBUM_REPOSITORY)
    .useClass(InMemoryAlbumRepository)
    .overrideProvider(PHOTO_REPOSITORY)
    .useClass(InMemoryPhotoRepository)
    .overrideProvider(MEMBERSHIP_REPOSITORY)
    .useClass(InMemoryMembershipRepository)
    .overrideProvider(INVITATION_REPOSITORY)
    .useClass(InMemoryInvitationRepository)
    .overrideProvider(SHARE_LINK_REPOSITORY)
    .useClass(InMemoryShareLinkRepository)
    .overrideProvider(NFC_QR_TAG_REPOSITORY)
    .useClass(InMemoryNfcQrTagRepository)
    .overrideProvider(USER_REPOSITORY)
    .useClass(InMemoryUserRepository)
    .overrideProvider(TOKEN_STORE)
    .useClass(InMemoryTokenStore)
    .overrideProvider(SESSION_REGISTRY)
    .useClass(InMemorySessionRegistry);
}
