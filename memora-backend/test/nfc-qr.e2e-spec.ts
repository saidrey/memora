import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';
import { configureApp } from './../src/bootstrap';
import {
  GOOGLE_AUTH_CLIENT,
  GoogleAuthClient,
} from './../src/auth/google-auth/google-auth-client.interface';
import { withInMemoryPersistence } from './in-memory-persistence';

const CODE_OWNER = 'code-owner-nfcqr';
const CODE_OUTSIDER = 'code-outsider-nfcqr';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  const byCode: Record<
    string,
    { googleId: string; email: string; name: string }
  > = {
    [CODE_OWNER]: {
      googleId: 'google-owner-nfcqr',
      email: 'owner-nfcqr@example.com',
      name: 'Owner',
    },
    [CODE_OUTSIDER]: {
      googleId: 'google-outsider-nfcqr',
      email: 'outsider-nfcqr@example.com',
      name: 'Outsider',
    },
  };
  return {
    exchangeServerAuthCode: async (serverAuthCode: string) => {
      const identity = byCode[serverAuthCode];
      if (!identity) throw new Error('invalid code');
      return { refreshToken: `fake-refresh-${serverAuthCode}`, identity };
    },
    getDriveAccessToken: async () => ({
      accessToken: 'unused-in-this-suite',
      expiresInSeconds: 3600,
    }),
  };
}

// spec10-nfc-qr.md — same beforeAll/afterAll + sequential-awaits pattern as
// shared.e2e-spec.ts / collaborators.e2e-spec.ts (see memora-backend/CLAUDE.md).
describe('NFC/QR (e2e)', () => {
  let app: INestApplication;
  let tokenOwner: string;
  let tokenOutsider: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await withInMemoryPersistence(
      Test.createTestingModule({ imports: [AppModule] }),
    )
      .overrideProvider(GOOGLE_AUTH_CLIENT)
      .useValue(buildFakeGoogleAuthClient())
      .compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();

    const loginOwner = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: CODE_OWNER });
    tokenOwner = loginOwner.body.sessionAccessToken;

    const loginOutsider = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: CODE_OUTSIDER });
    tokenOutsider = loginOutsider.body.sessionAccessToken;
  });

  afterAll(async () => {
    await app.close();
  });

  const authed = (token: string) => `Bearer ${token}`;
  const uniqueName = (label: string) => `${label}-${randomUUID()}`;

  const createAlbum = async (token: string, name: string) => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/albums')
      .set('Authorization', authed(token))
      .send({ name });
    return response.body as { id: string };
  };

  const createShareLink = (token: string, albumId: string) =>
    request(app.getHttpServer())
      .post(`/api/v1/albums/${albumId}/share-link`)
      .set('Authorization', authed(token));

  const revokeShareLink = (token: string, albumId: string) =>
    request(app.getHttpServer())
      .delete(`/api/v1/albums/${albumId}/share-link`)
      .set('Authorization', authed(token));

  const createTag = (
    token: string,
    albumId: string,
    type: 'NFC' | 'QR' = 'QR',
  ) =>
    request(app.getHttpServer())
      .post(`/api/v1/albums/${albumId}/nfc-qr-tags`)
      .set('Authorization', authed(token))
      .send({ type });

  const getTag = (token: string, tagId: string) =>
    request(app.getHttpServer())
      .get(`/api/v1/nfc-qr-tags/${tagId}`)
      .set('Authorization', authed(token));

  const disableTag = (token: string, tagId: string) =>
    request(app.getHttpServer())
      .patch(`/api/v1/nfc-qr-tags/${tagId}/disable`)
      .set('Authorization', authed(token));

  const resolveTag = (tagToken: string) =>
    request(app.getHttpServer()).get(`/api/v1/n/${tagToken}`).redirects(0);

  describe('POST /api/v1/albums/:albumId/nfc-qr-tags', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer()).post(
        `/api/v1/albums/${album.id}/nfc-qr-tags`,
      );

      expect(response.status).toBe(401);
    });

    it('owner creates a tag with a token, enabled status, and a URL containing the token', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createTag(tokenOwner, album.id, 'NFC');

      expect(response.status).toBe(201);
      expect(response.body.type).toBe('NFC');
      expect(response.body.status).toBe('enabled');
      expect(response.body.token).toEqual(expect.any(String));
      expect(response.body.url).toContain(response.body.token);
    });

    it('a non-owner cannot create a tag (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createTag(tokenOutsider, album.id);

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });

    it('rejects an invalid type with a uniform 400', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createTag(
        tokenOwner,
        album.id,
        'BLUETOOTH' as 'QR',
      );

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });

    it('no uniqueness constraint: creating twice for the same album+type gives two different tags', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const first = await createTag(tokenOwner, album.id, 'QR');
      const second = await createTag(tokenOwner, album.id, 'QR');

      expect(second.body.id).not.toBe(first.body.id);
      expect(second.body.token).not.toBe(first.body.token);
    });
  });

  describe('GET /api/v1/nfc-qr-tags/:id — owner-only status query', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const response = await request(app.getHttpServer()).get(
        `/api/v1/nfc-qr-tags/${tag.body.id}`,
      );

      expect(response.status).toBe(401);
    });

    it('owner can query the tag', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const response = await getTag(tokenOwner, tag.body.id);

      expect(response.status).toBe(200);
      expect(response.body.id).toBe(tag.body.id);
    });

    it('a non-owner cannot query the tag (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const response = await getTag(tokenOutsider, tag.body.id);

      expect(response.status).toBe(404);
    });
  });

  describe('PATCH /api/v1/nfc-qr-tags/:id/disable', () => {
    it('a non-owner cannot disable (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const response = await disableTag(tokenOutsider, tag.body.id);

      expect(response.status).toBe(404);
    });

    it('owner disables the tag; querying it afterwards shows disabled + disabledAt', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const disable = await disableTag(tokenOwner, tag.body.id);
      expect(disable.status).toBe(204);

      const fetched = await getTag(tokenOwner, tag.body.id);
      expect(fetched.body.status).toBe('disabled');
      expect(fetched.body.disabledAt).toEqual(expect.any(String));
    });

    it('is idempotent when already disabled', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      await disableTag(tokenOwner, tag.body.id);
      const response = await disableTag(tokenOwner, tag.body.id);

      expect(response.status).toBe(204);
    });
  });

  describe('GET /api/v1/n/:token — public resolution', () => {
    it('works WITHOUT any Authorization header and redirects (302) to the shared-view path', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);
      const link = await createShareLink(tokenOwner, album.id);

      const response = await resolveTag(tag.body.token);

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        `/api/v1/shared/${link.body.token}`,
      );
    });

    it('D14: regenerating the ShareLink does not break the tag — it follows the new token', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);
      await createShareLink(tokenOwner, album.id);

      await revokeShareLink(tokenOwner, album.id);
      const regenerated = await createShareLink(tokenOwner, album.id);

      const response = await resolveTag(tag.body.token);

      expect(response.status).toBe(302);
      expect(response.headers.location).toBe(
        `/api/v1/shared/${regenerated.body.token}`,
      );
    });

    it('an unknown tag token responds with a uniform 404', async () => {
      const response = await resolveTag('not-a-real-token');

      expect(response.status).toBe(404);
      expect(response.body).toEqual({
        code: 'NOT_FOUND',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('P2: a disabled tag responds with a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);
      await createShareLink(tokenOwner, album.id);

      await disableTag(tokenOwner, tag.body.id);
      const response = await resolveTag(tag.body.token);

      expect(response.status).toBe(404);
    });

    it('D16: a tag whose album was deleted responds with a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('A borrar'));
      const tag = await createTag(tokenOwner, album.id);
      await createShareLink(tokenOwner, album.id);

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(deleteResponse.status).toBe(204);

      const response = await resolveTag(tag.body.token);
      expect(response.status).toBe(404);

      // The owner-only query also 404s afterward — the row was hard-deleted.
      const queried = await getTag(tokenOwner, tag.body.id);
      expect(queried.status).toBe(404);
    });

    it('a tag whose album has no ShareLink yet responds with a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const tag = await createTag(tokenOwner, album.id);

      const response = await resolveTag(tag.body.token);

      expect(response.status).toBe(404);
    });
  });
});
