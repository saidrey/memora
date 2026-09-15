import { Inject, Injectable } from '@nestjs/common';
import { Album, AlbumVisibility } from './album.model';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from './album-repository.interface';
import { AlbumAccessService } from './collaborators/album-access.service';
import { AlbumRole } from './collaborators/album-membership.model';
import {
  INVITATION_REPOSITORY,
  InvitationRepository,
} from './collaborators/invitation-repository.interface';
import {
  MEMBERSHIP_REPOSITORY,
  MembershipRepository,
} from './collaborators/membership-repository.interface';
import { Photo } from './photos/photo.model';
import {
  PHOTO_REPOSITORY,
  PhotoRepository,
} from './photos/photo-repository.interface';
import {
  SHARE_LINK_REPOSITORY,
  ShareLinkRepository,
} from './shared/share-link-repository.interface';
import {
  NFC_QR_TAG_REPOSITORY,
  NfcQrTagRepository,
} from './nfc-qr/nfc-qr-tag-repository.interface';

export interface AlbumSummary {
  id: string;
  name: string;
  visibility: AlbumVisibility;
  photoCount: number;
  createdAt: Date;
  updatedAt: Date;
}

/** PATCH /albums/:id body (spec09): both fields optional, but at least one
 *  MUST be present — enforced by the controller's parser, not here. */
export interface AlbumUpdate {
  name?: string;
  visibility?: AlbumVisibility;
}

/** GET /api/v1/albums item — role is only surfaced on the combined list (P3);
 *  create/rename responses deliberately keep the plain AlbumSummary shape
 *  (unchanged contract, not in spec05's scope for those endpoints). */
export interface AlbumListItem extends AlbumSummary {
  role: AlbumRole;
}

export interface AlbumDetail extends AlbumSummary {
  photos: Photo[];
}

@Injectable()
export class AlbumsService {
  constructor(
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    @Inject(PHOTO_REPOSITORY) private readonly photos: PhotoRepository,
    @Inject(MEMBERSHIP_REPOSITORY)
    private readonly memberships: MembershipRepository,
    @Inject(INVITATION_REPOSITORY)
    private readonly invitations: InvitationRepository,
    @Inject(SHARE_LINK_REPOSITORY)
    private readonly shareLinks: ShareLinkRepository,
    @Inject(NFC_QR_TAG_REPOSITORY)
    private readonly nfcQrTags: NfcQrTagRepository,
    private readonly albumAccess: AlbumAccessService,
  ) {}

  /** `visibility` optional (D17) — the repository defaults it to `PRIVATE`
   *  when omitted. */
  async create(
    ownerId: string,
    name: string,
    visibility?: AlbumVisibility,
  ): Promise<AlbumSummary> {
    const album = await this.albums.create({ ownerId, name, visibility });
    return this.toSummary(album, 0);
  }

  /** P3: one combined list — own albums (role 'owner') plus albums where the
   *  caller collaborates (role 'collaborator'). */
  async listForUser(userId: string): Promise<AlbumListItem[]> {
    const owned = await this.albums.findByOwner(userId);
    const collaboratingIds =
      await this.memberships.listAlbumIdsForCollaborator(userId);
    const collaborating = (
      await Promise.all(
        collaboratingIds.map((albumId) => this.albums.findById(albumId)),
      )
    ).filter((album): album is Album => album !== null);

    const ownedItems = await Promise.all(
      owned.map((album) => this.toListItem(album, 'owner')),
    );
    const collaboratingItems = await Promise.all(
      collaborating.map((album) => this.toListItem(album, 'collaborator')),
    );
    return [...ownedItems, ...collaboratingItems];
  }

  /** Owner AND collaborators can read the album + its photos. 404 uniform
   *  for anyone without a membership (spec05: extends M2's owner-only read). */
  async getForUser(userId: string, albumId: string): Promise<AlbumDetail> {
    const { album } = await this.albumAccess.requireMembership(albumId, userId);
    const photoIds = await this.albums.listPhotoIds(album.id);
    const photos = await Promise.all(
      photoIds.map((id) => this.photos.findById(id)),
    );
    return {
      ...this.toSummary(album, photoIds.length),
      photos: photos.filter((photo): photo is Photo => photo !== null),
    };
  }

  /** Owner-only. `patch.name` and/or `patch.visibility` (D17, spec09) — the
   *  controller's parser guarantees at least one is present; applying zero
   *  changes here would just be a no-op read, which is harmless but the
   *  parser never lets that happen over HTTP. */
  async update(
    ownerId: string,
    albumId: string,
    patch: AlbumUpdate,
  ): Promise<AlbumSummary> {
    let album = await this.albumAccess.requireOwner(albumId, ownerId);
    if (patch.name !== undefined) {
      album = await this.albums.rename(album.id, patch.name);
    }
    if (patch.visibility !== undefined) {
      album = await this.albums.updateVisibility(album.id, patch.visibility);
    }
    return this.toSummary(album, await this.albums.countPhotos(album.id));
  }

  /** Deletes the album, its photo relations (D16), its memberships, its
   *  invitations, and its share link (spec09) — never a Photo, never a
   *  storage file. */
  async delete(ownerId: string, albumId: string): Promise<void> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    await this.memberships.deleteAllForAlbum(albumId);
    await this.invitations.deleteAllForAlbum(albumId);
    await this.shareLinks.deleteByAlbumId(albumId);
    // spec10-nfc-qr.md (D16): NFC/QR tags are HARD-deleted (unlike the
    // tag's own soft-delete via `disable`), same defense-in-depth pattern
    // as ShareLink — NfcQrResolveService also independently 404s once the
    // album itself is gone.
    await this.nfcQrTags.deleteAllForAlbum(albumId);
    await this.albums.delete(albumId);
  }

  private async toListItem(
    album: Album,
    role: AlbumRole,
  ): Promise<AlbumListItem> {
    return {
      ...this.toSummary(album, await this.albums.countPhotos(album.id)),
      role,
    };
  }

  private toSummary(album: Album, photoCount: number): AlbumSummary {
    return {
      id: album.id,
      name: album.name,
      visibility: album.visibility,
      photoCount,
      createdAt: album.createdAt,
      updatedAt: album.updatedAt,
    };
  }
}
