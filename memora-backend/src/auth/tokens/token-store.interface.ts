export const TOKEN_STORE = Symbol('TOKEN_STORE');

/**
 * Persists each user's Google refresh token. This IS the encryption-at-rest
 * boundary named in spec02-autenticacion-google.md: a production
 * implementation MUST encrypt before writing and decrypt after reading
 * (mechanism — KMS vs. app secret — deferred to infra, per the spec's
 * "Fuera de alcance"). The in-memory mock stores it in plaintext; it exists
 * only to prove the interface boundary for the MVP, without a real
 * database or KMS.
 */
export interface TokenStore {
  saveGoogleRefreshToken(userId: string, refreshToken: string): Promise<void>;
  getGoogleRefreshToken(userId: string): Promise<string | null>;
}
