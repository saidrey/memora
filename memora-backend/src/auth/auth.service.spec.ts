import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { GoogleAuthClient } from './google-auth/google-auth-client.interface';
import { InMemoryUserRepository } from './users/in-memory-user.repository';
import { InMemoryTokenStore } from './tokens/in-memory-token.store';
import { SessionRegistry } from './session/session-registry';
import { SessionTokenService } from './session/session-token.service';
import { ApiException } from '../common/exceptions/api.exception';

const SENTINEL_CODE = 'sentinel-server-auth-code-should-never-be-logged';
const SENTINEL_REFRESH_TOKEN =
  'sentinel-google-refresh-token-should-never-be-logged';

function buildFakeGoogleAuthClient(
  overrides: Partial<GoogleAuthClient> = {},
): GoogleAuthClient {
  return {
    exchangeServerAuthCode: async () => ({
      refreshToken: SENTINEL_REFRESH_TOKEN,
      identity: {
        googleId: 'google-1',
        email: 'user@example.com',
        name: 'User',
      },
    }),
    getDriveAccessToken: async () => ({
      accessToken: 'drive-access-token',
      expiresInSeconds: 3600,
    }),
    ...overrides,
  };
}

function buildAuthService(googleAuthClient: GoogleAuthClient) {
  const configService = new ConfigService({
    JWT_SESSION_SECRET: 'unit-test-secret',
    JWT_SESSION_ACCESS_TTL: '1h',
    JWT_SESSION_REFRESH_TTL: '7d',
  });
  const sessionTokenService = new SessionTokenService(
    new JwtService(),
    configService,
  );
  const userRepository = new InMemoryUserRepository();
  const tokenStore = new InMemoryTokenStore();
  const sessionRegistry = new SessionRegistry();

  const authService = new AuthService(
    googleAuthClient,
    userRepository,
    tokenStore,
    sessionTokenService,
    sessionRegistry,
  );

  return { authService, userRepository, tokenStore, sessionRegistry };
}

describe('AuthService', () => {
  it('logs a new user in with Google, storing the refresh token and issuing a session', async () => {
    const { authService, tokenStore } = buildAuthService(
      buildFakeGoogleAuthClient(),
    );

    const { session, user } = await authService.loginWithGoogle(SENTINEL_CODE);

    expect(user.email).toBe('user@example.com');
    expect(session.accessToken).toEqual(expect.any(String));
    expect(session.refreshToken).toEqual(expect.any(String));
    await expect(tokenStore.getGoogleRefreshToken(user.id)).resolves.toBe(
      SENTINEL_REFRESH_TOKEN,
    );
  });

  it('recovers the same user on a second Google login instead of duplicating it', async () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());

    const first = await authService.loginWithGoogle(SENTINEL_CODE);
    const second = await authService.loginWithGoogle(SENTINEL_CODE);

    expect(second.user.id).toBe(first.user.id);
  });

  it('never logs the serverAuthCode or the Google refresh token', async () => {
    const logSpy = jest
      .spyOn(console, 'log')
      .mockImplementation(() => undefined);
    const errorSpy = jest
      .spyOn(console, 'error')
      .mockImplementation(() => undefined);
    const warnSpy = jest
      .spyOn(console, 'warn')
      .mockImplementation(() => undefined);

    const { authService } = buildAuthService(buildFakeGoogleAuthClient());
    await authService.loginWithGoogle(SENTINEL_CODE);

    const allLoggedText = [
      ...logSpy.mock.calls,
      ...errorSpy.mock.calls,
      ...warnSpy.mock.calls,
    ]
      .flat()
      .map((value) => JSON.stringify(value))
      .join('\n');

    expect(allLoggedText).not.toContain(SENTINEL_CODE);
    expect(allLoggedText).not.toContain(SENTINEL_REFRESH_TOKEN);

    logSpy.mockRestore();
    errorSpy.mockRestore();
    warnSpy.mockRestore();
  });

  it('refreshes the session access token with a valid session refresh token', async () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());
    const { session } = await authService.loginWithGoogle(SENTINEL_CODE);

    const refreshed = authService.refreshSession(session.refreshToken);

    expect(refreshed.accessToken).toEqual(expect.any(String));
    expect(refreshed.refreshToken).toBe(session.refreshToken);
  });

  it('rejects a session refresh token after logout', async () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());
    const { session, user } = await authService.loginWithGoogle(SENTINEL_CODE);

    authService.logout(user.id);

    expect(() => authService.refreshSession(session.refreshToken)).toThrow(
      ApiException,
    );
  });

  it('rejects a malformed/garbage session refresh token', () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());

    expect(() => authService.refreshSession('not-a-real-token')).toThrow(
      ApiException,
    );
  });

  it('returns a Drive access token for a user with a stored Google refresh token', async () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());
    const { user } = await authService.loginWithGoogle(SENTINEL_CODE);

    const token = await authService.getDriveAccessToken(user.id);

    expect(token).toEqual({
      accessToken: 'drive-access-token',
      expiresInSeconds: 3600,
    });
  });

  it('signals re-authorization when the user never granted Drive access', async () => {
    const { authService } = buildAuthService(buildFakeGoogleAuthClient());

    await expect(
      authService.getDriveAccessToken('never-logged-in-user'),
    ).rejects.toThrow(ApiException);
  });

  it('signals re-authorization when Google rejects the stored refresh token', async () => {
    const googleAuthClient = buildFakeGoogleAuthClient({
      getDriveAccessToken: async () => {
        throw new Error('invalid_grant');
      },
    });
    const { authService } = buildAuthService(googleAuthClient);
    const { user } = await authService.loginWithGoogle(SENTINEL_CODE);

    await expect(authService.getDriveAccessToken(user.id)).rejects.toThrow(
      ApiException,
    );
  });
});
