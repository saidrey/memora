import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Db, KYSELY } from '../../database/database.types';
import { shareLink } from '../../database/postgres-mappers';
import { ShareLink } from './share-link.model';
import { ShareLinkRepository } from './share-link-repository.interface';

@Injectable()
export class PostgresShareLinkRepository implements ShareLinkRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async create(i: { albumId: string; token: string }) {
    const r = await this.db
      .insertInto('share_links')
      .values({
        id: randomUUID(),
        album_id: i.albumId,
        token: i.token,
        status: 'active',
        created_at: new Date(),
      })
      .onConflict((oc) =>
        oc
          .column('album_id')
          .doUpdateSet({
            id: randomUUID(),
            token: i.token,
            status: 'active',
            created_at: new Date(),
          }),
      )
      .returningAll()
      .executeTakeFirstOrThrow();
    return shareLink(r);
  }
  async findByAlbumId(albumId: string) {
    const r = await this.db
      .selectFrom('share_links')
      .selectAll()
      .where('album_id', '=', albumId)
      .executeTakeFirst();
    return r ? shareLink(r) : null;
  }
  async findByToken(token: string) {
    const r = await this.db
      .selectFrom('share_links')
      .selectAll()
      .where('token', '=', token)
      .executeTakeFirst();
    return r ? shareLink(r) : null;
  }
  async revoke(albumId: string) {
    await this.db
      .updateTable('share_links')
      .set({ status: 'revoked' })
      .where('album_id', '=', albumId)
      .where('status', '=', 'active')
      .execute();
  }
  async deleteByAlbumId(albumId: string) {
    await this.db
      .deleteFrom('share_links')
      .where('album_id', '=', albumId)
      .execute();
  }
}
