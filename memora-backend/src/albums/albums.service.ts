import { Inject, Injectable } from '@nestjs/common';
import { Album } from './album.model';
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

export interface AlbumSummary {
  id: string;
  name: string;
  photoCount: number;
  createdAt: Date;
  updatedAt: Date;
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
    private readonly albumAccess: AlbumAccessService,
  ) {}

  async create(ownerId: string, name: string): Promise<AlbumSummary> {
    const album = await this.albums.create({ ownerId, name });
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

  async rename(
    ownerId: string,
    albumId: string,
    name: string,
  ): Promise<AlbumSummary> {
    const album = await this.albumAccess.requireOwner(albumId, ownerId);
    const updated = await this.albums.rename(album.id, name);
    return this.toSummary(updated, await this.albums.countPhotos(updated.id));
  }

  /** Deletes the album, its photo relations (D16), its memberships and its
   *  invitations — never a Photo, never a storage file. */
  async delete(ownerId: string, albumId: string): Promise<void> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    await this.memberships.deleteAllForAlbum(albumId);
    await this.invitations.deleteAllForAlbum(albumId);
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
      photoCount,
      createdAt: album.createdAt,
      updatedAt: album.updatedAt,
    };
  }
}
