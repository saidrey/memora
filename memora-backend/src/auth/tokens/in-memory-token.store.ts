import { Injectable } from '@nestjs/common';
import { TokenStore } from './token-store.interface';

/** See TokenStore's doc comment for the encryption-boundary rationale. */
@Injectable()
export class InMemoryTokenStore implements TokenStore {
  private readonly refreshTokensByUserId = new Map<string, string>();

  async saveGoogleRefreshToken(
    userId: string,
    refreshToken: string,
  ): Promise<void> {
    this.refreshTokensByUserId.set(userId, refreshToken);
  }

  async getGoogleRefreshToken(userId: string): Promise<string | null> {
    return this.refreshTokensByUserId.get(userId) ?? null;
  }
}
