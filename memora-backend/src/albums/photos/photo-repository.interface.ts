import { Photo } from './photo.model';

export const PHOTO_REPOSITORY = Symbol('PHOTO_REPOSITORY');

export interface PhotoRepository {
  /** Sets availability to "available" internally — callers never pass it. */
  create(photo: Omit<Photo, 'id' | 'createdAt' | 'availability'>): Promise<Photo>;
  findById(id: string): Promise<Photo | null>;
  /** Backs the "Biblioteca personal" query (D11), independent of albums. */
  findByOwner(ownerId: string): Promise<Photo[]>;
  /** Removes the Photo reference only — never touches Drive. Callers are
   *  responsible for cleaning up album relations first (AlbumRepository). */
  delete(id: string): Promise<void>;
}
