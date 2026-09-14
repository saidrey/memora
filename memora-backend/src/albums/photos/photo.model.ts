/**
 * Photo model per producto-mvp.md D8. Creation moved from "seam only" to
 * real (spec04-fotografias.md): the client registers a photo it already
 * uploaded to the storage provider; the backend never sees the bytes.
 *
 * Deliberately excluded: GPS/EXIF (D8, privacy), per-album order
 * (relation-level concern, still meaningless — M3 app doesn't reorder yet).
 */
export type PhotoAvailability = 'available' | 'unavailable';

/**
 * spec08-abstraccion-almacenamiento.md: the only storage provider in the
 * MVP is `google-drive`. The type is a union of one member on purpose — it
 * leaves room for a future value (e.g. 'b2') without widening to `string`,
 * so adding a provider is a type-level, reviewable change.
 */
export type StorageProvider = 'google-drive';

/**
 * Neutral physical reference to wherever the photo's bytes actually live.
 * Replaces the previous provider-specific single-string reference field
 * (spec08) — the domain (albums, collaborators, availability, library)
 * talks about `storageRef`, never about a concrete provider name or a
 * provider-specific id shape in prose. `fileId` carries exactly the same
 * value the old field did: a stable reference, never a name/path (spec04:
 * "referencia estable").
 */
export interface StorageRef {
  provider: StorageProvider;
  fileId: string;
}

export interface Photo {
  id: string;
  /** A photo belongs to exactly one owner (producto-mvp.md, modelo de datos). */
  ownerId: string;
  /** Neutral physical reference (spec08) — see StorageRef above. */
  storageRef: StorageRef;
  /** When Memora learned about this photo (not necessarily its capture date). */
  createdAt: Date;
  capturedAt?: Date;
  width?: number;
  height?: number;
  mimeType?: string;
  sizeBytes?: number;
  /**
   * Defaults to "available" at registration. Real verification against
   * the storage provider (D9) happens client-side (spec07); the backend only persists what
   * it's told via PhotosService.reportAvailability(Batch).
   */
  availability: PhotoAvailability;
  /**
   * Last time a client reported a verification result (spec07, P4). Absent
   * until the first report — never set at registration. Habilita heurísticas
   * futuras sin sync activa; hoy no se usa para nada más que exponerse.
   */
  availabilityCheckedAt?: Date;
}
