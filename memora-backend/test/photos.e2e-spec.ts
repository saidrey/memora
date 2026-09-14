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

const CODE_USER_A = 'code-user-a';
const CODE_USER_B = 'code-user-b';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  return {
    exchangeServerAuthCode: async (serverAuthCode: string) => {
      if (serverAuthCode === CODE_USER_A) {
        return {
          refreshToken: 'fake-refresh-a',
          identity: { googleId: 'google-a', email: 'a@example.com', name: 'User A' },
        };
      }
      if (serverAuthCode === CODE_USER_B) {
        return {
          refreshToken: 'fake-refresh-b',
          identity: { googleId: 'google-b', email: 'b@example.com', name: 'User B' },
        };
      }
      throw new Error('invalid code');
    },
    getDriveAccessToken: async () => ({
      accessToken: 'unused-in-this-suite',
      expiresInSeconds: 3600,
    }),
  };
}

// One app for the whole file, per the flake fix documented in
// specs/memora-backend/spec03-biblioteca-albumes.md — see albums.e2e-spec.ts.
describe('Photos & Library (e2e)', () => {
  let app: INestApplication;
  let tokenA: string;
  let tokenB: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(GOOGLE_AUTH_CLIENT)
      .useValue(buildFakeGoogleAuthClient())
      .compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();

    const loginA = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: CODE_USER_A });
    tokenA = loginA.body.sessionAccessToken;

    const loginB = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: CODE_USER_B });
    tokenB = loginB.body.sessionAccessToken;
  });

  afterAll(async () => {
    await app.close();
  });

  const authed = (token: string) => `Bearer ${token}`;
  const uniqueDriveFileId = () => `drive-file-${randomUUID()}`;

  const createAlbum = async (token: string, name: string) => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/albums')
      .set('Authorization', authed(token))
      .send({ name });
    return response.body as { id: string };
  };

  const registerPhoto = async (
    token: string,
    body: Record<string, unknown>,
  ) => {
    return request(app.getHttpServer())
      .post('/api/v1/photos')
      .set('Authorization', authed(token))
      .send(body);
  };

  describe('POST /api/v1/photos', () => {
    it('requires a session', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/photos')
        .send({ driveFileId: uniqueDriveFileId() });

      expect(response.status).toBe(401);
      expect(response.body.code).toBe('UNAUTHORIZED');
    });

    it('registers a photo owned by the caller with D8 metadata, no geolocation', async () => {
      const driveFileId = uniqueDriveFileId();
      const response = await registerPhoto(tokenA, {
        driveFileId,
        width: 1080,
        height: 1920,
        mimeType: 'image/jpeg',
        sizeBytes: 204800,
        capturedAt: '2026-01-01T00:00:00.000Z',
      });

      expect(response.status).toBe(201);
      expect(response.body).toEqual({
        id: expect.any(String),
        ownerId: expect.any(String),
        driveFileId,
        createdAt: expect.any(String),
        capturedAt: '2026-01-01T00:00:00.000Z',
        width: 1080,
        height: 1920,
        mimeType: 'image/jpeg',
        sizeBytes: 204800,
        availability: 'available',
      });
      expect(response.body).not.toHaveProperty('latitude');
      expect(response.body).not.toHaveProperty('longitude');
    });

    it('rejects a missing driveFileId with a uniform 400', async () => {
      const response = await registerPhoto(tokenA, {});

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });

    it('rejects an invalid optional field (e.g. negative width) with a uniform 400', async () => {
      const response = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
        width: -10,
      });

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });

    it('registers and associates to an owned album in one call', async () => {
      const album = await createAlbum(tokenA, `Álbum-${randomUUID()}`);

      const response = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
        albumId: album.id,
      });
      expect(response.status).toBe(201);

      const albumDetail = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenA));
      expect(albumDetail.body.photos.map((p: { id: string }) => p.id)).toEqual(
        [response.body.id],
      );
    });

    it('registering into someone else´s album returns a uniform 404', async () => {
      const theirAlbum = await createAlbum(tokenB, `De B-${randomUUID()}`);

      const response = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
        albumId: theirAlbum.id,
      });

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });
  });

  describe('POST/DELETE /api/v1/albums/:albumId/photos', () => {
    it('associates and disassociates without duplicating, without touching the photo', async () => {
      const album = await createAlbum(tokenA, `Álbum-${randomUUID()}`);
      const photo = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
      });

      const associate = () =>
        request(app.getHttpServer())
          .post(`/api/v1/albums/${album.id}/photos`)
          .set('Authorization', authed(tokenA))
          .send({ photoId: photo.body.id });

      expect((await associate()).status).toBe(204);
      expect((await associate()).status).toBe(204); // twice — idempotent

      const detail = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenA));
      expect(detail.body.photoCount).toBe(1);

      const disassociate = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/photos/${photo.body.id}`)
        .set('Authorization', authed(tokenA));
      expect(disassociate.status).toBe(204);

      const afterRemoval = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenA));
      expect(afterRemoval.body.photoCount).toBe(0);

      // The photo itself still exists (only the relation was removed).
      const library = await request(app.getHttpServer())
        .get('/api/v1/library')
        .set('Authorization', authed(tokenA));
      expect(
        library.body.some((p: { id: string }) => p.id === photo.body.id),
      ).toBe(true);
    });

    it('a non-owner cannot associate a photo to my album (uniform 404)', async () => {
      const album = await createAlbum(tokenA, `Álbum-${randomUUID()}`);
      const photo = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
      });

      const response = await request(app.getHttpServer())
        .post(`/api/v1/albums/${album.id}/photos`)
        .set('Authorization', authed(tokenB))
        .send({ photoId: photo.body.id });

      expect(response.status).toBe(404);
    });
  });

  describe('GET /api/v1/library', () => {
    it('returns only the caller´s own photos, independent of albums', async () => {
      const driveFileId = uniqueDriveFileId();
      await registerPhoto(tokenA, { driveFileId });
      await registerPhoto(tokenB, { driveFileId: uniqueDriveFileId() });

      const response = await request(app.getHttpServer())
        .get('/api/v1/library')
        .set('Authorization', authed(tokenA));

      expect(response.status).toBe(200);
      const driveFileIds = response.body.map(
        (p: { driveFileId: string }) => p.driveFileId,
      );
      expect(driveFileIds).toContain(driveFileId);
    });

    it('requires a session', async () => {
      const response = await request(app.getHttpServer()).get(
        '/api/v1/library',
      );
      expect(response.status).toBe(401);
    });
  });

  describe('DELETE /api/v1/photos/:photoId', () => {
    it('forgets the photo and removes it from every album, without a Drive call', async () => {
      const albumA = await createAlbum(tokenA, `A-${randomUUID()}`);
      const albumB = await createAlbum(tokenA, `B-${randomUUID()}`);
      const photo = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
      });
      await request(app.getHttpServer())
        .post(`/api/v1/albums/${albumA.id}/photos`)
        .set('Authorization', authed(tokenA))
        .send({ photoId: photo.body.id });
      await request(app.getHttpServer())
        .post(`/api/v1/albums/${albumB.id}/photos`)
        .set('Authorization', authed(tokenA))
        .send({ photoId: photo.body.id });

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/photos/${photo.body.id}`)
        .set('Authorization', authed(tokenA));
      expect(deleteResponse.status).toBe(204);

      // Sequential, not Promise.all: concurrent requests against the same
      // supertest/ephemeral server proved more likely to trip the socket
      // flake documented above — one at a time is just as valid a check.
      const detailA = await request(app.getHttpServer())
        .get(`/api/v1/albums/${albumA.id}`)
        .set('Authorization', authed(tokenA));
      const detailB = await request(app.getHttpServer())
        .get(`/api/v1/albums/${albumB.id}`)
        .set('Authorization', authed(tokenA));
      const library = await request(app.getHttpServer())
        .get('/api/v1/library')
        .set('Authorization', authed(tokenA));

      expect(detailA.body.photoCount).toBe(0);
      expect(detailB.body.photoCount).toBe(0);
      expect(
        library.body.some((p: { id: string }) => p.id === photo.body.id),
      ).toBe(false);
    });

    it('a non-owner cannot delete my photo (uniform 404, photo survives)', async () => {
      const photo = await registerPhoto(tokenA, {
        driveFileId: uniqueDriveFileId(),
      });

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/photos/${photo.body.id}`)
        .set('Authorization', authed(tokenB));
      expect(response.status).toBe(404);

      const library = await request(app.getHttpServer())
        .get('/api/v1/library')
        .set('Authorization', authed(tokenA));
      expect(
        library.body.some((p: { id: string }) => p.id === photo.body.id),
      ).toBe(true);
    });
  });
});
