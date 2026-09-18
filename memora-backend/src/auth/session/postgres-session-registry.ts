import { Inject, Injectable } from '@nestjs/common';
import { Db, KYSELY } from '../../database/database.types';
import { SessionRegistry } from './session-registry.interface';

@Injectable()
export class PostgresSessionRegistry implements SessionRegistry {
  constructor(@Inject(KYSELY) private readonly db: Db) {}
  async register(userId: string, jti: string) {
    await this.db
      .insertInto('session_jtis')
      .values({ user_id: userId, jti, created_at: new Date() })
      .onConflict((oc) => oc.columns(['user_id', 'jti']).doNothing())
      .execute();
  }
  async isActive(userId: string, jti: string) {
    return !!(await this.db
      .selectFrom('session_jtis')
      .select('jti')
      .where('user_id', '=', userId)
      .where('jti', '=', jti)
      .executeTakeFirst());
  }
  async revokeAll(userId: string) {
    await this.db
      .deleteFrom('session_jtis')
      .where('user_id', '=', userId)
      .execute();
  }
}
