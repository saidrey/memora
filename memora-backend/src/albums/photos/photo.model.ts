/**
 * Photo model per producto-mvp.md D8. Creation moved from "seam only" to
 * real (spec04-fotografias.md): the client registers a photo it already
 * uploaded to Drive; the backend never sees the bytes.
 *
 * Deliberately excluded: GPS/EXIF (D8, privacy), per-album order
 * (relation-level concern, still meaningless — M3 app doesn't reorder yet).
 */
export type PhotoAvailability = 'available' | 'unavailable';

export interface Photo {
  id: string;
  /** A photo belongs to exactly one owner (producto-mvp.md, modelo de datos). */
  ownerId: string;
  /** Stable reference — never a name/path (spec04: "referencia estable"). */
  driveFileId: string;
  /** When Memora learned about this photo (not necessarily its capture date). */
  createdAt: Date;
  capturedAt?: Date;
  width?: number;
  height?: number;
  mimeType?: string;
  sizeBytes?: number;
  /**
   * Defaults to "available" at registration. Real verification against
   * Drive (D9) is M6 — this spec only carries the field.
   */
  availability: PhotoAvailability;
}
