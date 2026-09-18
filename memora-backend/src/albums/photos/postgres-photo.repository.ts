import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Photo, PhotoAvailability } from './photo.model';
import { PhotoRepository } from './photo-repository.interface';
import { Db, KYSELY } from '../../database/database.types';
import { photo } from '../../database/postgres-mappers';

@Injectable()
export class PostgresPhotoRepository implements PhotoRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async create(i: Omit<Photo, 'id' | 'createdAt' | 'availability'>) {
    const r = await this.db
      .insertInto('photos')
      .values({
        id: randomUUID(),
        owner_id: i.ownerId,
        storage_provider: i.storageRef.provider,
        storage_file_id: i.storageRef.fileId,
        created_at: new Date(),
        captured_at: i.capturedAt ?? null,
        width: i.width ?? null,
        height: i.height ?? null,
        mime_type: i.mimeType ?? null,
        size_bytes: i.sizeBytes ?? null,
        availability: 'available',
        availability_checked_at: i.availabilityCheckedAt ?? null,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return photo(r);
  }
  async findById(id: string) {
    const r = await this.db
      .selectFrom('photos')
      .selectAll()
      .where('id', '=', id)
      .executeTakeFirst();
    return r ? photo(r) : null;
  }
  async findByOwner(ownerId: string) {
    return (
      await this.db
        .selectFrom('photos')
        .selectAll()
        .where('owner_id', '=', ownerId)
        .execute()
    ).map(photo);
  }
  async delete(id: string) {
    await this.db.deleteFrom('photos').where('id', '=', id).execute();
  }
  async updateAvailability(id: string, availability: PhotoAvailability) {
    const r = await this.db
      .updateTable('photos')
      .set({ availability, availability_checked_at: new Date() })
      .where('id', '=', id)
      .returningAll()
      .executeTakeFirstOrThrow();
    return photo(r);
  }
}
