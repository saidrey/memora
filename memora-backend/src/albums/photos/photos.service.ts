import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { requireOwned } from '../../common/authorization/require-owned';
import {
  ALBUM_REPOSITORY,
  AlbumRepository,
} from '../album-repository.interface';
import { AlbumAccessService } from '../collaborators/album-access.service';
import { Photo, PhotoAvailability, StorageProvider } from './photo.model';
import {
  PHOTO_REPOSITORY,
  PhotoRepository,
} from './photo-repository.interface';

/** spec08: the MVP has exactly one provider and the client doesn't choose
 *  it — this is the default applied when `storageRef.provider` is omitted. */
const DEFAULT_STORAGE_PROVIDER: StorageProvider = 'google-drive';

export interface RegisterPhotoInput {
  /**
   * `provider` is optional — the MVP has a single provider and defaults to
   * it (spec08, "Nota de contrato de API": "el cliente envía storageRef ...
   * a resolver en implementación, manteniéndolo simple"). Kept as a field
   * (not hardcoded away) so the shape already matches the multi-provider
   * future without a breaking change later.
   */
  storageRef: { fileId: string; provider?: StorageProvider };
  capturedAt?: Date;
  width?: number;
  height?: number;
  mimeType?: string;
  sizeBytes?: number;
  /** If present, the photo is associated to this album on registration. */
  albumId?: string;
}

/** One entry of the batch body in POST /api/v1/photos/availability
 *  (spec07-disponibilidad.md, P2b). */
export interface AvailabilityReport {
  photoId: string;
  availability: PhotoAvailability;
}

@Injectable()
export class PhotosService {
  constructor(
    @Inject(PHOTO_REPOSITORY) private readonly photos: PhotoRepository,
    @Inject(ALBUM_REPOSITORY) private readonly albums: AlbumRepository,
    private readonly albumAccess: AlbumAccessService,
  ) {}

  /** Registers a photo the client already uploaded to the storage provider —
   *  the backend never sees the bytes, only the storageRef + metadata (D8).
   *  The photo's owner is always the caller — a collaborator's contribution
   *  lives in THEIR own storage, multi-provider-account within one album
   *  (spec05). */
  async register(ownerId: string, input: RegisterPhotoInput): Promise<Photo> {
    if (input.albumId) {
      // Owner OR collaborator may contribute — membership, not ownership,
      // of the ALBUM (spec05). Ownership of the PHOTO itself is unaffected.
      await this.albumAccess.requireMembership(input.albumId, ownerId);
    }

    const photo = await this.photos.create({
      ownerId,
      storageRef: {
        provider: input.storageRef.provider ?? DEFAULT_STORAGE_PROVIDER,
        fileId: input.storageRef.fileId,
      },
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

  /** Associates an EXISTING, own photo to an album the caller can contribute
   *  to (owner or collaborator). Idempotent — no duplicate. A collaborator
   *  can never associate someone else's photo (requireOwnedPhoto below still
   *  enforces that regardless of album role). */
  async associate(
    ownerId: string,
    albumId: string,
    photoId: string,
  ): Promise<void> {
    await this.albumAccess.requireMembership(albumId, ownerId);
    await this.requireOwnedPhoto(ownerId, photoId);
    await this.albums.addPhoto(albumId, photoId);
  }

  /** Removes only the relation (D3/D4) — never the photo or its storage file.
   *  The OWNER of the album may remove any photo (D4); a COLLABORATOR may
   *  only remove their own contributions — removing someone else's is a
   *  uniform 404 (P5), same as the album/photo-not-found case. */
  async disassociate(
    callerId: string,
    albumId: string,
    photoId: string,
  ): Promise<void> {
    const { role } = await this.albumAccess.requireMembership(
      albumId,
      callerId,
    );
    const photo = await this.photos.findById(photoId);
    if (!photo || (role === 'collaborator' && photo.ownerId !== callerId)) {
      throw new NotFoundException('Foto no encontrada');
    }
    await this.albums.removePhoto(albumId, photoId);
  }

  /** The "Biblioteca personal" (D11): the user's photos, independent of albums. */
  async listLibrary(ownerId: string): Promise<Photo[]> {
    return this.photos.findByOwner(ownerId);
  }

  /** Forgets the photo in Memora and all its album relations — its storage
   *  file is never touched (producto-mvp.md: Memora no es custodio). Always
   *  the photo's own owner, unaffected by album roles (spec05: "sigue
   *  siendo del propietario de la foto, sin cambios de contrato"). */
  async deletePhoto(ownerId: string, photoId: string): Promise<void> {
    await this.requireOwnedPhoto(ownerId, photoId);
    await this.albums.removePhotoFromAllAlbums(photoId);
    await this.photos.delete(photoId);
  }

  /**
   * spec07-disponibilidad.md (P1/P2a): the OWNER of the photo reports what
   * their client observed against the storage provider (the backend never
   * checks it itself — see the module-level note above). Recovering from
   * `unavailable` back to `available` is the same call, no special
   * transition handling needed (D9) — any valid value over any prior state
   * is accepted.
   */
  async reportAvailability(
    ownerId: string,
    photoId: string,
    availability: PhotoAvailability,
  ): Promise<Photo> {
    await this.requireOwnedPhoto(ownerId, photoId);
    return this.photos.updateAvailability(photoId, availability);
  }

  /**
   * spec07-disponibilidad.md (P2b): batch report after reviewing an album.
   * Each entry is evaluated independently against the CALLER's ownership —
   * an entry for a photo that doesn't exist or isn't the caller's is
   * silently skipped (not applied, doesn't throw) so it can never fail the
   * rest of the batch or reveal whether an unowned photoId exists.
   */
  async reportAvailabilityBatch(
    ownerId: string,
    reports: AvailabilityReport[],
  ): Promise<void> {
    for (const report of reports) {
      const photo = await this.photos.findById(report.photoId);
      if (!photo || photo.ownerId !== ownerId) {
        continue;
      }
      await this.photos.updateAvailability(report.photoId, report.availability);
    }
  }

  private async requireOwnedPhoto(
    ownerId: string,
    photoId: string,
  ): Promise<Photo> {
    const photo = await this.photos.findById(photoId);
    return requireOwned(photo, ownerId, 'Foto no encontrada');
  }
}
