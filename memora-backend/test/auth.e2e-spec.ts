import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';
import { configureApp } from './../src/bootstrap';
import { REQUEST_ID_HEADER } from './../src/common/middleware/request-id.middleware';
import {
  GOOGLE_AUTH_CLIENT,
  GoogleAuthClient,
} from './../src/auth/google-auth/google-auth-client.interface';

const VALID_CODE = 'valid-server-auth-code';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  return {
    exchangeServerAuthCode: async (serverAuthCode: string) => {
      if (serverAuthCode !== VALID_CODE) {
        throw new Error('invalid code');
      }
      return {
        refreshToken: 'fake-google-refresh-token',
        identity: {
          googleId: 'google-e2e-user',
          email: 'e2e@example.com',
          name: 'E2E User',
        },
      };
    },
    getDriveAccessToken: async () => ({
      accessToken: 'fake-drive-access-token',
      expiresInSeconds: 3600,
    }),
  };
}

describe('Auth (e2e)', () => {
  let app: INestApplication;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(GOOGLE_AUTH_CLIENT)
      .useValue(buildFakeGoogleAuthClient())
      .compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  describe('POST /api/v1/auth/google', () => {
    it('logs the user in and returns a session + user', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({ serverAuthCode: VALID_CODE });

      expect(response.status).toBe(201);
      expect(response.body).toEqual({
        sessionAccessToken: expect.any(String),
        sessionRefreshToken: expect.any(String),
        user: {
          id: expect.any(String),
          email: 'e2e@example.com',
          name: 'E2E User',
        },
      });
    });

    it('rejects a missing serverAuthCode with a uniform 400', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({});

      expect(response.status).toBe(400);
      expect(response.body).toEqual({
        code: 'INVALID_REQUEST',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('rejects an invalid serverAuthCode with a uniform 401', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({ serverAuthCode: 'not-the-valid-code' });

      expect(response.status).toBe(401);
      expect(response.body).toEqual({
        code: 'GOOGLE_AUTH_FAILED',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });
  });

  describe('protected endpoints', () => {
    it('POST /api/v1/auth/drive-token rejects a request with no session', async () => {
      const response = await request(app.getHttpServer()).post(
        '/api/v1/auth/drive-token',
      );

      expect(response.status).toBe(401);
      expect(response.body).toEqual({
        code: 'UNAUTHORIZED',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('POST /api/v1/auth/drive-token returns an ephemeral Drive token for a logged-in user', async () => {
      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({ serverAuthCode: VALID_CODE });

      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/drive-token')
        .set('Authorization', `Bearer ${login.body.sessionAccessToken}`);

      expect(response.status).toBe(201);
      expect(response.body).toEqual({
        driveAccessToken: 'fake-drive-access-token',
        expiresIn: 3600,
      });
    });
  });

  describe('POST /api/v1/auth/refresh', () => {
    it('issues a new access token for a valid session refresh token', async () => {
      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({ serverAuthCode: VALID_CODE });

      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ sessionRefreshToken: login.body.sessionRefreshToken });

      expect(response.status).toBe(201);
      expect(response.body.sessionAccessToken).toEqual(expect.any(String));
    });

    it('rejects a garbage refresh token with a uniform 401', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ sessionRefreshToken: 'garbage' });

      expect(response.status).toBe(401);
      expect(response.body).toEqual({
        code: 'SESSION_REFRESH_INVALID',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });
  });

  describe('POST /api/v1/auth/logout', () => {
    it('revokes the session so its refresh token can no longer be used', async () => {
      const login = await request(app.getHttpServer())
        .post('/api/v1/auth/google')
        .send({ serverAuthCode: VALID_CODE });

      const logoutResponse = await request(app.getHttpServer())
        .post('/api/v1/auth/logout')
        .set('Authorization', `Bearer ${login.body.sessionAccessToken}`);
      expect(logoutResponse.status).toBe(204);

      const refreshAfterLogout = await request(app.getHttpServer())
        .post('/api/v1/auth/refresh')
        .send({ sessionRefreshToken: login.body.sessionRefreshToken });

      expect(refreshAfterLogout.status).toBe(401);
      expect(refreshAfterLogout.body.code).toBe('SESSION_REFRESH_INVALID');
    });
  });

  it('never logs the serverAuthCode or any token across the whole flow', async () => {
    const logSpy = jest
      .spyOn(console, 'log')
      .mockImplementation(() => undefined);
    const errorSpy = jest
      .spyOn(console, 'error')
      .mockImplementation(() => undefined);
    const warnSpy = jest
      .spyOn(console, 'warn')
      .mockImplementation(() => undefined);

    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: VALID_CODE });
    await request(app.getHttpServer())
      .post('/api/v1/auth/drive-token')
      .set('Authorization', `Bearer ${login.body.sessionAccessToken}`);

    const allLoggedText = [
      ...logSpy.mock.calls,
      ...errorSpy.mock.calls,
      ...warnSpy.mock.calls,
    ]
      .flat()
      .map((value) => JSON.stringify(value))
      .join('\n');

    expect(allLoggedText).not.toContain(VALID_CODE);
    expect(allLoggedText).not.toContain('fake-google-refresh-token');
    expect(allLoggedText).not.toContain(login.body.sessionAccessToken);
    expect(allLoggedText).not.toContain(login.body.sessionRefreshToken);

    logSpy.mockRestore();
    errorSpy.mockRestore();
    warnSpy.mockRestore();
  });
});
