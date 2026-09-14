import { Inject, Injectable } from '@nestjs/common';
import { ApiException } from '../common/exceptions/api.exception';
import {
  driveReauthorizationRequired,
  googleAuthFailed,
  sessionRefreshInvalid,
} from './auth.errors';
import {
  DriveAccessToken,
  GOOGLE_AUTH_CLIENT,
  GoogleAuthClient,
} from './google-auth/google-auth-client.interface';
import {
  USER_REPOSITORY,
  User,
  UserRepository,
} from './users/user-repository.interface';
import { TOKEN_STORE, TokenStore } from './tokens/token-store.interface';
import { SessionRegistry } from './session/session-registry';
import { SessionTokenService } from './session/session-token.service';

export interface SessionTokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface PublicUser {
  id: string;
  email: string;
  name?: string;
}

@Injectable()
export class AuthService {
  constructor(
    @Inject(GOOGLE_AUTH_CLIENT)
    private readonly googleAuthClient: GoogleAuthClient,
    @Inject(USER_REPOSITORY) private readonly userRepository: UserRepository,
    @Inject(TOKEN_STORE) private readonly tokenStore: TokenStore,
    private readonly sessionTokenService: SessionTokenService,
    private readonly sessionRegistry: SessionRegistry,
  ) {}

  async loginWithGoogle(
    serverAuthCode: string,
  ): Promise<{ session: SessionTokenPair; user: PublicUser }> {
    const { refreshToken, identity } = await this.exchangeServerAuthCode(
      serverAuthCode,
    );

    let user = await this.userRepository.findByGoogleId(identity.googleId);
    if (!user) {
      user = await this.userRepository.create({
        googleId: identity.googleId,
        email: identity.email,
        name: identity.name,
      });
    }

    // The Google refresh token never leaves the backend from here on.
    await this.tokenStore.saveGoogleRefreshToken(user.id, refreshToken);

    return { session: this.issueSession(user.id), user: toPublicUser(user) };
  }

  refreshSession(sessionRefreshToken: string): SessionTokenPair {
    const payload = this.verifySessionRefreshToken(sessionRefreshToken);
    // No rotation for the MVP: the same refresh token stays valid until it
    // expires or logout revokes it. See README's security notes.
    return {
      accessToken: this.sessionTokenService.issueAccessToken(payload.sub),
      refreshToken: sessionRefreshToken,
    };
  }

  logout(userId: string): void {
    this.sessionRegistry.revokeAll(userId);
  }

  async getDriveAccessToken(userId: string): Promise<DriveAccessToken> {
    const refreshToken = await this.tokenStore.getGoogleRefreshToken(userId);
    if (!refreshToken) {
      throw driveReauthorizationRequired();
    }
    try {
      return await this.googleAuthClient.getDriveAccessToken(refreshToken);
    } catch (error) {
      // Defense in depth: even if a GoogleAuthClient implementation throws
      // something other than ApiException, never let it (or its message)
      // reach the client — normalize to the safe re-authorization signal.
      if (error instanceof ApiException) throw error;
      throw driveReauthorizationRequired();
    }
  }

  private async exchangeServerAuthCode(serverAuthCode: string) {
    try {
      return await this.googleAuthClient.exchangeServerAuthCode(serverAuthCode);
    } catch (error) {
      // Same defense-in-depth as getDriveAccessToken: don't trust every
      // GoogleAuthClient implementation to already throw ApiException.
      if (error instanceof ApiException) throw error;
      throw googleAuthFailed(
        'No se pudo validar el inicio de sesión con Google',
      );
    }
  }

  private issueSession(userId: string): SessionTokenPair {
    const accessToken = this.sessionTokenService.issueAccessToken(userId);
    const { token: refreshToken, jti } =
      this.sessionTokenService.issueRefreshToken(userId);
    this.sessionRegistry.register(userId, jti);
    return { accessToken, refreshToken };
  }

  private verifySessionRefreshToken(sessionRefreshToken: string) {
    let payload;
    try {
      payload = this.sessionTokenService.verifyRefreshToken(
        sessionRefreshToken,
      );
    } catch {
      throw sessionRefreshInvalid();
    }
    if (!this.sessionRegistry.isActive(payload.sub, payload.jti)) {
      throw sessionRefreshInvalid();
    }
    return payload;
  }
}

function toPublicUser(user: User): PublicUser {
  return { id: user.id, email: user.email, name: user.name };
}
