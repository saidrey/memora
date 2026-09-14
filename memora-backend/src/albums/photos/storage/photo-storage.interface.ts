import { Photo, StorageProvider } from '../photo.model';

export const PHOTO_STORAGE = Symbol('PHOTO_STORAGE');

/**
 * Whatever the client needs to upload bytes directly to the provider
 * (spec08: "el backend no maneja bytes" — Opción A). Today this is exactly
 * what `POST /auth/drive-token` already returns; `PhotoStorage` just wraps
 * it behind a provider-neutral shape for internal/future callers.
 */
export interface UploadAuthorization {
  provider: StorageProvider;
  accessToken: string;
  expiresInSeconds: number;
}

/**
 * Neutral data a client/viewer needs to ask the PROVIDER for the bytes —
 * the concrete read mechanism (which endpoint, which auth) is resolved by
 * the client with its own token, never by the backend (spec08, M7 habilitador).
 */
export interface ReadReference {
  provider: StorageProvider;
  fileId: string;
}

/**
 * Coordination/authorization interface over the concrete storage provider
 * (spec08-abstraccion-almacenamiento.md). The backend never handles bytes,
 * so most operations here are about brokering access, not transferring
 * data — see each method's doc for what's actually implemented in the MVP
 * vs. declared-but-unsupported.
 *
 * Same DI pattern as PhotoRepository/AlbumRepository: interface + Symbol
 * token + one concrete implementation (GoogleDrivePhotoStorage) registered
 * in AlbumsModule.
 */
export interface PhotoStorage {
  /** Implemented (MVP): wraps the existing drive-token broker
   *  (AuthService.getDriveAccessToken) so the client can upload directly. */
  getUploadAuthorization(userId: string): Promise<UploadAuthorization>;

  /** Implemented (MVP): neutral reference for a client/viewer to fetch the
   *  bytes itself — no backend call to the provider happens here. */
  getReadReference(photo: Photo): Promise<ReadReference>;

  /**
   * Declared, NOT supported server-side in the MVP: real verification
   * against the provider requires the file's owner-scoped token, which the
   * backend never holds server-side for arbitrary photos (spec07-
   * disponibilidad.md, P1). The client verifies and reports instead
   * (PhotosService.reportAvailability(Batch)). Throws
   * STORAGE_OPERATION_UNSUPPORTED.
   */
  describe(photo: Photo): Promise<unknown>;

  /** Declared, NOT supported server-side in the MVP — same reasoning as
   *  `describe`. Throws STORAGE_OPERATION_UNSUPPORTED. */
  exists(photo: Photo): Promise<boolean>;

  /** Declared, NOT implemented: the backend never handles bytes (Opción A).
   *  Throws STORAGE_OPERATION_UNSUPPORTED. */
  download(photo: Photo): Promise<unknown>;

  /** Declared, NOT implemented — same reasoning as `download`. Throws
   *  STORAGE_OPERATION_UNSUPPORTED. */
  stream(photo: Photo): Promise<unknown>;

  /** Declared, NOT implemented: this is M5 (spec06-adoptar.md), explicitly
   *  diferido. Throws STORAGE_OPERATION_UNSUPPORTED. */
  copy(photo: Photo, destinationOwnerId: string): Promise<Photo>;

  /** Declared, NOT implemented: Memora never deletes from the user's own
   *  Drive, by product principle ("Memora no es custodio") — a future,
   *  Memora-owned storage could support this under a separate product
   *  decision. Throws STORAGE_OPERATION_UNSUPPORTED. */
  delete(photo: Photo): Promise<void>;
}
