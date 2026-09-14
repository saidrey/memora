import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { requireOwned } from '../../common/authorization/require-owned';
import { Album } from '../album.model';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from '../album-repository.interface';
import { AlbumRole } from './album-membership.model';
import {
  MEMBERSHIP_REPOSITORY,
  MembershipRepository,
} from './membership-repository.interface';

/**
 * Extends the `requireOwned` pattern (src/common/authorization/require-owned.ts)
 * to roles: "requires membership" (owner OR collaborator) for reads, and
 * "requires owner" for management — both 404 uniformly (never 403) when the
 * album doesn't exist or the caller has no membership, so a request never
 * reveals that someone else's album exists.
 *
 * This can't be a standalone pure function like `requireOwned` because
 * resolving a role needs two repository reads (the album, then the
 * membership row); it's implemented as an injectable service instead, and
 * reused by AlbumsService, PhotosService and CollaboratorsService/
 * InvitationsService — all within AlbumsModule.
 */
@Injectable()
export class AlbumAccessService {
  constructor(
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    @Inject(MEMBERSHIP_REPOSITORY)
    private readonly memberships: MembershipRepository,
  ) {}

  /** null if the album doesn't exist or the user has no membership at all. */
  async getRole(albumId: string, userId: string): Promise<AlbumRole | null> {
    const album = await this.albums.findById(albumId);
    if (!album) return null;
    return this.roleForAlbum(album, userId);
  }

  /** 404 uniform unless the caller is the owner OR a collaborator. */
  async requireMembership(
    albumId: string,
    userId: string,
  ): Promise<{ album: Album; role: AlbumRole }> {
    const album = await this.albums.findById(albumId);
    const role = album ? await this.roleForAlbum(album, userId) : null;
    if (!album || !role) {
      throw new NotFoundException('Álbum no encontrado');
    }
    return { album, role };
  }

  /** 404 uniform unless the caller is the owner. Same message as requireOwned. */
  async requireOwner(albumId: string, userId: string): Promise<Album> {
    const album = await this.albums.findById(albumId);
    return requireOwned(album, userId, 'Álbum no encontrado');
  }

  private async roleForAlbum(
    album: Album,
    userId: string,
  ): Promise<AlbumRole | null> {
    if (album.ownerId === userId) return 'owner';
    const membership = await this.memberships.findCollaborator(
      album.id,
      userId,
    );
    return membership ? 'collaborator' : null;
  }
}
