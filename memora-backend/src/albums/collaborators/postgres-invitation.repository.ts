import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Db, KYSELY } from '../../database/database.types';
import { invitation } from '../../database/postgres-mappers';
import { Invitation, InvitationStatus } from './invitation.model';
import { InvitationRepository } from './invitation-repository.interface';

@Injectable()
export class PostgresInvitationRepository implements InvitationRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async create(i: {
    albumId: string;
    token: string;
    createdBy: string;
    expiresAt: Date;
  }) {
    const r = await this.db
      .insertInto('invitations')
      .values({
        id: randomUUID(),
        album_id: i.albumId,
        token: i.token,
        created_by: i.createdBy,
        status: 'pending',
        expires_at: i.expiresAt,
        accepted_by_user_id: null,
        created_at: new Date(),
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return invitation(r);
  }
  async findById(id: string) {
    const r = await this.db
      .selectFrom('invitations')
      .selectAll()
      .where('id', '=', id)
      .executeTakeFirst();
    return r ? invitation(r) : null;
  }
  async findByToken(token: string) {
    const r = await this.db
      .selectFrom('invitations')
      .selectAll()
      .where('token', '=', token)
      .executeTakeFirst();
    return r ? invitation(r) : null;
  }
  async listByAlbum(albumId: string) {
    return (
      await this.db
        .selectFrom('invitations')
        .selectAll()
        .where('album_id', '=', albumId)
        .execute()
    ).map(invitation);
  }
  async updateStatus(
    id: string,
    status: InvitationStatus,
    acceptedByUserId?: string,
  ) {
    const r = await this.db
      .updateTable('invitations')
      .set({
        status,
        ...(acceptedByUserId ? { accepted_by_user_id: acceptedByUserId } : {}),
      })
      .where('id', '=', id)
      .returningAll()
      .executeTakeFirstOrThrow();
    return invitation(r);
  }
  async deleteAllForAlbum(albumId: string) {
    await this.db
      .deleteFrom('invitations')
      .where('album_id', '=', albumId)
      .execute();
  }
}
