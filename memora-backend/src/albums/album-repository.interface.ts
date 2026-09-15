import { Album, AlbumVisibility } from './album.model';

export const ALBUM_REPOSITORY = Symbol('ALBUM_REPOSITORY');

/**
 * Owns both the Album entity and the Photo↔Album N:M relation (producto-mvp.md:
 * "una foto puede pertenecer a múltiples álbumes... sin duplicar el
 * archivo"). The relation methods have no HTTP endpoint yet (adding a photo
 * to an album is M3) — they exist so this spec's delete-isolation behavior
 * (D16) can be modeled and tested now, and so M3 has a repository to call.
 */
export interface AlbumRepository {
  /** `visibility` defaults to `'PRIVATE'` when omitted (spec09, D17) —
   *  same pattern as `PhotoRepository.create()` defaulting `availability`. */
  create(input: {
    ownerId: string;
    name: string;
    visibility?: AlbumVisibility;
  }): Promise<Album>;
  findById(id: string): Promise<Album | null>;
  findByOwner(ownerId: string): Promise<Album[]>;
  rename(id: string, name: string): Promise<Album>;
  /** spec09/D17: owner-only, changeable independently of the name. */
  updateVisibility(id: string, visibility: AlbumVisibility): Promise<Album>;
  /** Deletes the album AND its photo relations. Never touches Photo entities. */
  delete(id: string): Promise<void>;

  /** Idempotent: adding the same photo twice does not duplicate it (Set-backed). */
  addPhoto(albumId: string, photoId: string): Promise<void>;
  removePhoto(albumId: string, photoId: string): Promise<void>;
  listPhotoIds(albumId: string): Promise<string[]>;
  countPhotos(albumId: string): Promise<number>;

  /**
   * Removes this photo's relation from EVERY album it's in (used when a
   * Photo itself is deleted — spec04-fotografias.md). Idempotent; never
   * touches the Photo entity or any other photo's relations.
   */
  removePhotoFromAllAlbums(photoId: string): Promise<void>;
}
