import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Album, AlbumVisibility } from './album.model';
import { AlbumRepository } from './album-repository.interface';
import { Db, KYSELY } from '../database/database.types';
import { album } from '../database/postgres-mappers';

@Injectable()
export class PostgresAlbumRepository implements AlbumRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async create(i: {
    ownerId: string;
    name: string;
    visibility?: AlbumVisibility;
  }): Promise<Album> {
    const now = new Date();
    const row = await this.db
      .insertInto('albums')
      .values({
        id: randomUUID(),
        owner_id: i.ownerId,
        name: i.name,
        visibility: i.visibility ?? 'PRIVATE',
        created_at: now,
        updated_at: now,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return album(row);
  }
  async findById(id: string) {
    const r = await this.db
      .selectFrom('albums')
      .selectAll()
      .where('id', '=', id)
      .executeTakeFirst();
    return r ? album(r) : null;
  }
  async findByOwner(ownerId: string) {
    return (
      await this.db
        .selectFrom('albums')
        .selectAll()
        .where('owner_id', '=', ownerId)
        .execute()
    ).map(album);
  }
  async rename(id: string, name: string) {
    return this.update(id, { name });
  }
  async updateVisibility(id: string, visibility: AlbumVisibility) {
    return this.update(id, { visibility });
  }
  private async update(
    id: string,
    values: { name?: string; visibility?: AlbumVisibility },
  ) {
    const r = await this.db
      .updateTable('albums')
      .set({ ...values, updated_at: new Date() })
      .where('id', '=', id)
      .returningAll()
      .executeTakeFirstOrThrow();
    return album(r);
  }
  async delete(id: string) {
    await this.db.deleteFrom('albums').where('id', '=', id).execute();
  }
  async addPhoto(albumId: string, photoId: string) {
    await this.db
      .insertInto('album_photos')
      .values({ album_id: albumId, photo_id: photoId })
      .onConflict((oc) => oc.columns(['album_id', 'photo_id']).doNothing())
      .execute();
  }
  async removePhoto(albumId: string, photoId: string) {
    await this.db
      .deleteFrom('album_photos')
      .where('album_id', '=', albumId)
      .where('photo_id', '=', photoId)
      .execute();
  }
  async listPhotoIds(albumId: string) {
    const rows = await this.db
      .selectFrom('album_photos')
      .select('photo_id')
      .where('album_id', '=', albumId)
      .execute();
    return rows.map((r) => r.photo_id);
  }
  async countPhotos(albumId: string) {
    const r = await this.db
      .selectFrom('album_photos')
      .select(({ fn }) => fn.countAll<number>().as('count'))
      .where('album_id', '=', albumId)
      .executeTakeFirstOrThrow();
    return Number(r.count);
  }
  async removePhotoFromAllAlbums(photoId: string) {
    await this.db
      .deleteFrom('album_photos')
      .where('photo_id', '=', photoId)
      .execute();
  }
}
