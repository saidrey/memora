export const GOOGLE_AUTH_CLIENT = Symbol('GOOGLE_AUTH_CLIENT');

export interface GoogleIdentity {
  googleId: string;
  email: string;
  name?: string;
}

export interface GoogleTokenExchangeResult {
  refreshToken: string;
  identity: GoogleIdentity;
}

export interface DriveAccessToken {
  accessToken: string;
  expiresInSeconds: number;
}

/**
 * Boundary with Google OAuth. The real implementation (GoogleOAuthClient)
 * uses Google's own official `google-auth-library`; tests inject a fake
 * instead of hitting the network.
 */
export interface GoogleAuthClient {
  /**
   * Exchanges a one-time serverAuthCode (from the client's offline-access
   * Google Sign-In) for a Google refresh token and the user's verified
   * identity. Implementations must never log the code or the returned
   * tokens.
   */
  exchangeServerAuthCode(
    serverAuthCode: string,
  ): Promise<GoogleTokenExchangeResult>;

  /**
   * Uses a previously stored Google refresh token to mint a short-lived
   * Drive access token. The scope is whatever was granted at consent time
   * (drive.file, requested by the client during sign-in) — it isn't
   * re-specified here because Google doesn't accept a scope override on
   * refresh.
   */
  getDriveAccessToken(refreshToken: string): Promise<DriveAccessToken>;
}
