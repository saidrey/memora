import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from '../album-repository.interface';
import { Photo, StorageRef } from '../photos/photo.model';
import {
  PHOTO_REPOSITORY,
  PhotoRepository,
} from '../photos/photo-repository.interface';
import {
  SHARE_LINK_REPOSITORY,
  ShareLinkRepository,
} from './share-link-repository.interface';

/**
 * P4 — minimum public surface. Deliberately excludes: `ownerId` / any user
 * id, collaborator identity/list, the share-link token, and any other
 * token. `Photo.id` IS included — it's Memora's own UUID for the photo (a
 * list key for the client), never a person's identity, so it doesn't
 * violate P4 the way `ownerId` would.
 */
export interface SharedPhotoView {
  id: string;
  storageRef: StorageRef;
  width?: number;
  height?: number;
  mimeType?: string;
  capturedAt?: Date;
}

export interface SharedAlbumView {
  name: string;
  photos: SharedPhotoView[];
}

/**
 * Backs the ONE public, unauthenticated endpoint of this backend
 * (`GET /api/v1/shared/:token` — see `shared.controller.ts`, which is
 * deliberately NOT decorated with `@UseGuards(SessionAuthGuard)`).
 *
 * P1: an unknown token, a revoked link, or a link whose album was deleted
 * all resolve to the exact same uniform 404 — never distinguished, so a
 * request can't be used to probe whether some album/token used to exist.
 */
@Injectable()
export class SharedViewService {
  constructor(
    @Inject(SHARE_LINK_REPOSITORY)
    private readonly shareLinks: ShareLinkRepository,
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    @Inject(PHOTO_REPOSITORY) private readonly photos: PhotoRepository,
  ) {}

  async resolve(token: string): Promise<SharedAlbumView> {
    const link = await this.shareLinks.findByToken(token);
    if (!link || link.status !== 'active') {
      throw shareNotFound();
    }

    const album = await this.albums.findById(link.albumId);
    if (!album) {
      // Album deleted (D16) — the link row may still linger (or may have
      // been cleaned up by AlbumsService.delete; either way this check
      // alone is enough to guarantee the 404, defense in depth).
      throw shareNotFound();
    }

    const photoIds = await this.albums.listPhotoIds(album.id);
    const photos = await Promise.all(
      photoIds.map((id) => this.photos.findById(id)),
    );
    // P3: unavailable photos are OMITTED entirely, never marked — unlike
    // the authenticated views (GET /albums/:id, GET /library), which keep
    // showing them marked `unavailable` (spec07).
    const availablePhotos = photos.filter(
      (photo): photo is Photo =>
        photo !== null && photo.availability === 'available',
    );

    return {
      name: album.name,
      photos: availablePhotos.map((photo) => ({
        id: photo.id,
        storageRef: photo.storageRef,
        width: photo.width,
        height: photo.height,
        mimeType: photo.mimeType,
        capturedAt: photo.capturedAt,
      })),
    };
  }
}

function shareNotFound(): NotFoundException {
  // Same message/shape as every other uniform 404 in this backend — P1
  // requires this NOT to reveal which of "unknown token" / "revoked" /
  // "album deleted" actually happened.
  return new NotFoundException('Álbum no encontrado');
}
