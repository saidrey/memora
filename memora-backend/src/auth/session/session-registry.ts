import { Injectable } from '@nestjs/common';

/**
 * Tracks which session refresh-token jtis are currently valid per user, so
 * logout can revoke a session even though JWTs are otherwise stateless.
 *
 * NOTE: this is a 4th piece of state beyond the three interfaces named in
 * spec02-autenticacion-google.md (GoogleAuthClient, UserRepository,
 * TokenStore). It's kept as a plain in-memory provider rather than a formal
 * Provider interface, since the spec doesn't name one for session
 * revocation — flagged for Kiro in case it should become one for
 * consistency with an eventual move to a real datastore (e.g. Redis).
 */
@Injectable()
export class SessionRegistry {
  private readonly activeJtiByUser = new Map<string, Set<string>>();

  register(userId: string, jti: string): void {
    const jtis = this.activeJtiByUser.get(userId) ?? new Set<string>();
    jtis.add(jti);
    this.activeJtiByUser.set(userId, jtis);
  }

  isActive(userId: string, jti: string): boolean {
    return this.activeJtiByUser.get(userId)?.has(jti) ?? false;
  }

  /** Logout: revokes every active session refresh token for this user. */
  revokeAll(userId: string): void {
    this.activeJtiByUser.delete(userId);
  }
}
