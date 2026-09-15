export const SESSION_REGISTRY = Symbol('SESSION_REGISTRY');

/**
 * Tracks which session refresh-token jtis are currently valid per user, so
 * logout can revoke a session even though JWTs are otherwise stateless.
 *
 * Same interface + Symbol-token pattern as every other piece of state in
 * this backend (UserRepository, TokenStore, AlbumRepository, ...) — this
 * used to be the one exception, injected by concrete class
 * (spec11-session-registry-interface.md closes that gap). The only
 * implementation today is `InMemorySessionRegistry`
 * (`in-memory-session-registry.ts`), a mock kept in the process's memory;
 * this interface is the frontier a future real datastore (Redis, Postgres)
 * would sit behind, without AuthService ever changing.
 */
export interface SessionRegistry {
  /** Marks a refresh-token jti as active for this user. Idempotent. */
  register(userId: string, jti: string): void;

  /** Whether this jti is still an active refresh session for this user. */
  isActive(userId: string, jti: string): boolean;

  /** Logout: revokes every active session refresh token for this user. */
  revokeAll(userId: string): void;
}
