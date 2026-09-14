import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Credentials, OAuth2Client } from 'google-auth-library';
import { driveReauthorizationRequired, googleAuthFailed } from '../auth.errors';
import {
  DriveAccessToken,
  GoogleAuthClient,
  GoogleTokenExchangeResult,
} from './google-auth-client.interface';

/**
 * Real GoogleAuthClient, backed by Google's own official `google-auth-library`.
 * Never logs the serverAuthCode, refresh tokens, or access tokens it
 * handles — failures are converted to generic ApiExceptions and the
 * underlying error (which could echo request details) is discarded, not
 * logged.
 */
@Injectable()
export class GoogleOAuthClient implements GoogleAuthClient {
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly client: OAuth2Client;

  constructor(configService: ConfigService) {
    const clientId = configService.get<string>('GOOGLE_CLIENT_ID');
    const clientSecret = configService.get<string>('GOOGLE_CLIENT_SECRET');
    if (!clientId || !clientSecret) {
      throw new Error(
        'GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are not configured',
      );
    }
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.client = new OAuth2Client({ clientId, clientSecret });
  }

  async exchangeServerAuthCode(
    serverAuthCode: string,
  ): Promise<GoogleTokenExchangeResult> {
    let tokens: Credentials;
    try {
      // A serverAuthCode obtained from a NATIVE app (Android/iOS) has no
      // associated redirect_uri; the code is bound to the native OAuth
      // client, not a web redirect. Passing 'postmessage' (the WEB flow's
      // value) causes redirect_uri_mismatch. So we exchange the code
      // without a redirect_uri for the native/offline flow.
      ({ tokens } = await this.client.getToken({ code: serverAuthCode }));
    } catch {
      throw googleAuthFailed(
        'No se pudo validar el inicio de sesión con Google',
      );
    }

    if (!tokens.refresh_token || !tokens.access_token) {
      throw googleAuthFailed(
        'Google no otorgó acceso offline para este usuario',
      );
    }

    // Identity comes from the userinfo endpoint using the access token, not
    // from an id_token: the app only requests the drive.file scope in its
    // server authorization, so Google does not always return an id_token on
    // this exchange. Fetching userinfo with the access token is the robust
    // way to get the verified account id + email regardless.
    const identity = await this.fetchIdentity(tokens.access_token);

    return {
      refreshToken: tokens.refresh_token,
      identity,
    };
  }

  private async fetchIdentity(
    accessToken: string,
  ): Promise<GoogleTokenExchangeResult['identity']> {
    interface GoogleUserInfo {
      sub?: string;
      email?: string;
      name?: string;
    }
    let data: GoogleUserInfo;
    try {
      const client = new OAuth2Client();
      client.setCredentials({ access_token: accessToken });
      const response = await client.request<GoogleUserInfo>({
        url: 'https://www.googleapis.com/oauth2/v3/userinfo',
      });
      data = response.data;
    } catch {
      throw googleAuthFailed('No se pudo verificar la identidad de Google');
    }

    if (!data?.sub || !data.email) {
      throw googleAuthFailed('No se pudo verificar la identidad de Google');
    }

    return { googleId: data.sub, email: data.email, name: data.name };
  }

  async getDriveAccessToken(refreshToken: string): Promise<DriveAccessToken> {
    const client = new OAuth2Client({
      clientId: this.clientId,
      clientSecret: this.clientSecret,
    });
    client.setCredentials({ refresh_token: refreshToken });

    let accessToken: string | null | undefined;
    try {
      ({ token: accessToken } = await client.getAccessToken());
    } catch {
      throw driveReauthorizationRequired();
    }

    if (!accessToken) {
      throw driveReauthorizationRequired();
    }

    const expiryDate = client.credentials.expiry_date;
    const expiresInSeconds = expiryDate
      ? Math.max(0, Math.round((expiryDate - Date.now()) / 1000))
      : 3600;

    return { accessToken, expiresInSeconds };
  }
}
