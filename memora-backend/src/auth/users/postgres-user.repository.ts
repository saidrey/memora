import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Db, KYSELY } from '../../database/database.types';
import { user as mapUser } from '../../database/postgres-mappers';
import { User, UserRepository } from './user-repository.interface';

@Injectable()
export class PostgresUserRepository implements UserRepository {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async findByGoogleId(googleId: string) {
    const r = await this.db
      .selectFrom('users')
      .selectAll()
      .where('google_id', '=', googleId)
      .executeTakeFirst();
    return r ? mapUser(r) : null;
  }
  async create(i: Omit<User, 'id'>) {
    const r = await this.db
      .insertInto('users')
      .values({
        id: randomUUID(),
        google_id: i.googleId,
        email: i.email,
        name: i.name ?? null,
      })
      .returningAll()
      .executeTakeFirstOrThrow();
    return mapUser(r);
  }
}
