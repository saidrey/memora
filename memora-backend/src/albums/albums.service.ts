import { Inject, Injectable } from '@nestjs/common';
import { requireOwned } from '../common/authorization/require-owned';
import { Album } from './album.model';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from './album-repository.interface';
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

export interface AlbumDetail extends AlbumSummary {
  photos: Photo[];
}

@Injectable()
export class AlbumsService {
  constructor(
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    @Inject(PHOTO_REPOSITORY) private readonly photos: PhotoRepository,
  ) {}

  async create(ownerId: string, name: string): Promise<AlbumSummary> {
    const album = await this.albums.create({ ownerId, name });
    return this.toSummary(album, 0);
  }

  async listForOwner(ownerId: string): Promise<AlbumSummary[]> {
    const albums = await this.albums.findByOwner(ownerId);
    return Promise.all(
      albums.map(async (album) =>
        this.toSummary(album, await this.albums.countPhotos(album.id)),
      ),
    );
  }

  async getForOwner(ownerId: string, albumId: string): Promise<AlbumDetail> {
    const album = await this.requireOwnedAlbum(ownerId, albumId);
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
    const album = await this.requireOwnedAlbum(ownerId, albumId);
    const updated = await this.albums.rename(album.id, name);
    return this.toSummary(updated, await this.albums.countPhotos(updated.id));
  }

  /** Deletes the album and its photo relations only (D16) — never a Photo. */
  async delete(ownerId: string, albumId: string): Promise<void> {
    await this.requireOwnedAlbum(ownerId, albumId);
    await this.albums.delete(albumId);
  }

  private async requireOwnedAlbum(
    ownerId: string,
    albumId: string,
  ): Promise<Album> {
    const album = await this.albums.findById(albumId);
    return requireOwned(album, ownerId, 'Álbum no encontrado');
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
