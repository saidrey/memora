import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Db, KYSELY } from '../../database/database.types';
import { tag } from '../../database/postgres-mappers';
import { NfcQrTag, NfcQrTagType } from './nfc-qr-tag.model';
import { NfcQrTagRepository } from './nfc-qr-tag-repository.interface';

@Injectable()
export class PostgresNfcQrTagRepository implements NfcQrTagRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async create(i: { albumId: string; type: NfcQrTagType; token: string }) {
    const now = new Date();
    const r = await this.db
      .insertInto('nfc_qr_tags')
      .values({
        id: randomUUID(),
        album_id: i.albumId,
        type: i.type,
        token: i.token,
        status: 'enabled',
        created_at: now,
        updated_at: now,
        disabled_at: null,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return tag(r);
  }
  async findById(id: string) {
    const r = await this.db
      .selectFrom('nfc_qr_tags')
      .selectAll()
      .where('id', '=', id)
      .executeTakeFirst();
    return r ? tag(r) : null;
  }
  async findByToken(token: string) {
    const r = await this.db
      .selectFrom('nfc_qr_tags')
      .selectAll()
      .where('token', '=', token)
      .executeTakeFirst();
    return r ? tag(r) : null;
  }
  async disable(id: string) {
    const existing = await this.findById(id);
    if (existing?.status === 'disabled') return existing;
    const r = await this.db
      .updateTable('nfc_qr_tags')
      .set({
        status: 'disabled',
        disabled_at: new Date(),
        updated_at: new Date(),
      })
      .where('id', '=', id)
      .returningAll()
      .executeTakeFirstOrThrow();
    return tag(r);
  }
  async deleteAllForAlbum(albumId: string) {
    await this.db
      .deleteFrom('nfc_qr_tags')
      .where('album_id', '=', albumId)
      .execute();
  }
}
