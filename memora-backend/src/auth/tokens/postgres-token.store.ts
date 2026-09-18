import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Db, KYSELY } from '../../database/database.types';
import { decryptToken, encryptToken, encryptionKey } from './token-encryption';
import { TokenStore } from './token-store.interface';

@Injectable()
export class PostgresTokenStore implements TokenStore {
  private readonly key: Buffer;
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    config: ConfigService,
  ) {
    this.key = encryptionKey(config.get<string>('TOKEN_ENCRYPTION_KEY'));
  }
  async saveGoogleRefreshToken(userId: string, refreshToken: string) {
    const encrypted = encryptToken(refreshToken, this.key);
    await this.db
      .insertInto('refresh_tokens')
      .values({
        user_id: userId,
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        auth_tag: encrypted.authTag,
        updated_at: new Date(),
      })
      .onConflict((oc) =>
        oc
          .column('user_id')
          .doUpdateSet({
            ciphertext: encrypted.ciphertext,
            nonce: encrypted.nonce,
            auth_tag: encrypted.authTag,
            updated_at: new Date(),
          }),
      )
      .execute();
  }
  async getGoogleRefreshToken(userId: string) {
    const r = await this.db
      .selectFrom('refresh_tokens')
      .selectAll()
      .where('user_id', '=', userId)
      .executeTakeFirst();
    return r
      ? decryptToken(
          { ciphertext: r.ciphertext, nonce: r.nonce, authTag: r.auth_tag },
          this.key,
        )
      : null;
  }
}
