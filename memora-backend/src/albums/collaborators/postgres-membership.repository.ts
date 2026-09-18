import { Inject, Injectable } from '@nestjs/common';
import { Db, KYSELY } from '../../database/database.types';
import { membership } from '../../database/postgres-mappers';
import { AlbumMembership } from './album-membership.model';
import { MembershipRepository } from './membership-repository.interface';

@Injectable()
export class PostgresMembershipRepository implements MembershipRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async addCollaborator(albumId: string, userId: string) {
    const r = await this.db
      .insertInto('memberships')
      .values({ album_id: albumId, user_id: userId, joined_at: new Date() })
      .onConflict((oc) => oc.columns(['album_id', 'user_id']).doNothing())
      .returningAll()
      .executeTakeFirst();
    return membership(
      r ??
        (await this.db
          .selectFrom('memberships')
          .selectAll()
          .where('album_id', '=', albumId)
          .where('user_id', '=', userId)
          .executeTakeFirstOrThrow()),
    );
  }
  async findCollaborator(albumId: string, userId: string) {
    const r = await this.db
      .selectFrom('memberships')
      .selectAll()
      .where('album_id', '=', albumId)
      .where('user_id', '=', userId)
      .executeTakeFirst();
    return r ? membership(r) : null;
  }
  async listCollaborators(albumId: string) {
    return (
      await this.db
        .selectFrom('memberships')
        .selectAll()
        .where('album_id', '=', albumId)
        .execute()
    ).map(membership);
  }
  async removeCollaborator(albumId: string, userId: string) {
    await this.db
      .deleteFrom('memberships')
      .where('album_id', '=', albumId)
      .where('user_id', '=', userId)
      .execute();
  }
  async listAlbumIdsForCollaborator(userId: string) {
    return (
      await this.db
        .selectFrom('memberships')
        .select('album_id')
        .where('user_id', '=', userId)
        .execute()
    ).map((r) => r.album_id);
  }
  async deleteAllForAlbum(albumId: string) {
    await this.db
      .deleteFrom('memberships')
      .where('album_id', '=', albumId)
      .execute();
  }
}
