/**
 * spec09-compartir-visor.md, D17: marks the ALBUM's product-level intent
 * ("¿este álbum se piensa como privado o público?"). Defaults to `PRIVATE`.
 * Deliberately does NOT gate the share-link resolution in the MVP — a
 * `PRIVATE` album is still viewable by anyone holding its share-link token,
 * exactly like a `PUBLIC` one (P5: visibility "no multiplica enlaces", it's
 * not an access-control switch yet). No catalog/discovery reads this field
 * — it exists only to be set/read, in preparation for a future where it
 * does gate something (e.g. a public catalog).
 */
export type AlbumVisibility = 'PRIVATE' | 'PUBLIC';

export interface Album {
  id: string;
  ownerId: string;
  name: string;
  visibility: AlbumVisibility;
  createdAt: Date;
  updatedAt: Date;
}
