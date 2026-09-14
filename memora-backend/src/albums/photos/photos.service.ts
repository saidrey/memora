import { Inject, Injectable } from '@nestjs/common';
import { requireOwned } from '../../common/authorization/require-owned';
import { Album } from '../album.model';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from '../album-repository.interface';
import { Photo } from './photo.model';
import { PHOTO_REPOSITORY, PhotoRepository } from './photo-repository.interface';

export interface RegisterPhotoInput {
  driveFileId: string;
  capturedAt?: Date;
  width?: number;
  height?: number;
  mimeType?: string;
  sizeBytes?: number;
  /** If present, the photo is associated to this album on registration. */
  albumId?: string;
}

@Injectable()
export class PhotosService {
  constructor(
    @Inject(PHOTO_REPOSITORY) private readonly photos: PhotoRepository,
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
  ) {}

  /** Registers a photo the client already uploaded to Drive — the backend
   *  never sees the bytes, only the driveFileId + metadata (D8). */
  async register(ownerId: string, input: RegisterPhotoInput): Promise<Photo> {
    if (input.albumId) {
      await this.requireOwnedAlbum(ownerId, input.albumId);
    }

    const photo = await this.photos.create({
      ownerId,
      driveFileId: input.driveFileId,
      capturedAt: input.capturedAt,
      width: input.width,
      height: input.height,
      mimeType: input.mimeType,
      sizeBytes: input.sizeBytes,
    });

    if (input.albumId) {
      await this.albums.addPhoto(input.albumId, photo.id);
    }

    return photo;
  }

  /** Associates an EXISTING photo to an album. Idempotent — no duplicate. */
  async associate(
    ownerId: string,
    albumId: string,
    photoId: string,
  ): Promise<void> {
    await this.requireOwnedAlbum(ownerId, albumId);
    await this.requireOwnedPhoto(ownerId, photoId);
    await this.albums.addPhoto(albumId, photoId);
  }

  /** Removes only the relation (D3/D4) — never the photo or the Drive file. */
  async disassociate(
    ownerId: string,
    albumId: string,
    photoId: string,
  ): Promise<void> {
    await this.requireOwnedAlbum(ownerId, albumId);
    await this.requireOwnedPhoto(ownerId, photoId);
    await this.albums.removePhoto(albumId, photoId);
  }

  /** The "Biblioteca personal" (D11): the user's photos, independent of albums. */
  async listLibrary(ownerId: string): Promise<Photo[]> {
    return this.photos.findByOwner(ownerId);
  }

  /** Forgets the photo in Memora and all its album relations — the Drive
   *  file is never touched (producto-mvp.md: Memora no es custodio). */
  async deletePhoto(ownerId: string, photoId: string): Promise<void> {
    await this.requireOwnedPhoto(ownerId, photoId);
    await this.albums.removePhotoFromAllAlbums(photoId);
    await this.photos.delete(photoId);
  }

  private async requireOwnedAlbum(
    ownerId: string,
    albumId: string,
  ): Promise<Album> {
    const album = await this.albums.findById(albumId);
    return requireOwned(album, ownerId, 'Álbum no encontrado');
  }

  private async requireOwnedPhoto(
    ownerId: string,
    photoId: string,
  ): Promise<Photo> {
    const photo = await this.photos.findById(photoId);
    return requireOwned(photo, ownerId, 'Foto no encontrada');
  }
}
