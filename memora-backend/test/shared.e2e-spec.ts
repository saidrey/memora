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

const CODE_OWNER = 'code-owner-share';
const CODE_OUTSIDER = 'code-outsider-share';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  const byCode: Record<
    string,
    { googleId: string; email: string; name: string }
  > = {
    [CODE_OWNER]: {
      googleId: 'google-owner-share',
      email: 'owner-share@example.com',
      name: 'Owner',
    },
    [CODE_OUTSIDER]: {
      googleId: 'google-outsider-share',
      email: 'outsider-share@example.com',
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

// spec09-compartir-visor.md — one app for the whole file (beforeAll/afterAll)
// and sequential awaits, same flake-avoidance pattern documented in
// memora-backend/CLAUDE.md and already used by collaborators.e2e-spec.ts.
describe('Compartir y visor (e2e)', () => {
  let app: INestApplication;
  let tokenOwner: string;
  let tokenOutsider: string;

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
  const uniqueFileId = () => `drive-file-${randomUUID()}`;

  const createAlbum = async (
    token: string,
    name: string,
    visibility?: 'PRIVATE' | 'PUBLIC',
  ) => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/albums')
      .set('Authorization', authed(token))
      .send(visibility ? { name, visibility } : { name });
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

  const createShareLink = (token: string, albumId: string) =>
    request(app.getHttpServer())
      .post(`/api/v1/albums/${albumId}/share-link`)
      .set('Authorization', authed(token));

  const revokeShareLink = (token: string, albumId: string) =>
    request(app.getHttpServer())
      .delete(`/api/v1/albums/${albumId}/share-link`)
      .set('Authorization', authed(token));

  const getShared = (shareToken: string) =>
    request(app.getHttpServer()).get(`/api/v1/shared/${shareToken}`);

  describe('POST /api/v1/albums/:albumId/share-link', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer()).post(
        `/api/v1/albums/${album.id}/share-link`,
      );

      expect(response.status).toBe(401);
    });

    it('owner creates a share link with a token and a URL containing it', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createShareLink(tokenOwner, album.id);

      expect(response.status).toBe(201);
      expect(response.body.token).toEqual(expect.any(String));
      expect(response.body.url).toContain(response.body.token);
    });

    it('a non-owner cannot create a share link (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createShareLink(tokenOutsider, album.id);

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });

    it('P5: creating twice returns the same token, not a new one', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const first = await createShareLink(tokenOwner, album.id);
      const second = await createShareLink(tokenOwner, album.id);

      expect(second.body.token).toBe(first.body.token);
    });
  });

  describe('GET /api/v1/shared/:token — public resolution', () => {
    it('works WITHOUT any Authorization header — this is the public endpoint', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('Público'));
      const photo = await registerPhoto(tokenOwner, {
        storageRef: { fileId: uniqueFileId() },
        albumId: album.id,
      });
      const created = await createShareLink(tokenOwner, album.id);

      const response = await getShared(created.body.token);

      expect(response.status).toBe(200);
      expect(response.body.name).toEqual(expect.any(String));
      expect(
        response.body.photos.some(
          (p: { id: string }) => p.id === photo.body.id,
        ),
      ).toBe(true);
      expect(response.body.photos[0].storageRef).toEqual(
        photo.body.storageRef,
      );
    });

    it('P4: the public response never contains ownerId or any token', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      await registerPhoto(tokenOwner, {
        storageRef: { fileId: uniqueFileId() },
        albumId: album.id,
      });
      const created = await createShareLink(tokenOwner, album.id);

      const response = await getShared(created.body.token);

      const serialized = JSON.stringify(response.body);
      expect(serialized).not.toContain('ownerId');
      expect(serialized).not.toContain(created.body.token);
    });

    it('P3: only AVAILABLE photos are listed — unavailable ones are omitted', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const photo = await registerPhoto(tokenOwner, {
        storageRef: { fileId: uniqueFileId() },
        albumId: album.id,
      });
      await request(app.getHttpServer())
        .patch(`/api/v1/photos/${photo.body.id}/availability`)
        .set('Authorization', authed(tokenOwner))
        .send({ availability: 'unavailable' });
      const created = await createShareLink(tokenOwner, album.id);

      const response = await getShared(created.body.token);

      expect(
        response.body.photos.some(
          (p: { id: string }) => p.id === photo.body.id,
        ),
      ).toBe(false);
    });

    it('an unknown token responds with a uniform 404', async () => {
      const response = await getShared('not-a-real-token');

      expect(response.status).toBe(404);
      expect(response.body).toEqual({
        code: 'NOT_FOUND',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('a revoked token responds with a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createShareLink(tokenOwner, album.id);

      const revoke = await revokeShareLink(tokenOwner, album.id);
      expect(revoke.status).toBe(204);

      const response = await getShared(created.body.token);
      expect(response.status).toBe(404);
    });

    it('a token whose album was deleted responds with a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('A borrar'));
      const created = await createShareLink(tokenOwner, album.id);

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(deleteResponse.status).toBe(204);

      const response = await getShared(created.body.token);
      expect(response.status).toBe(404);
    });

    it('works the same for a PUBLIC-visibility album — visibility does not gate this endpoint (P5/D17)', async () => {
      const album = await createAlbum(
        tokenOwner,
        uniqueName('Público'),
        'PUBLIC',
      );
      const created = await createShareLink(tokenOwner, album.id);

      const response = await getShared(created.body.token);

      expect(response.status).toBe(200);
    });
  });

  describe('DELETE /api/v1/albums/:albumId/share-link', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer()).delete(
        `/api/v1/albums/${album.id}/share-link`,
      );

      expect(response.status).toBe(401);
    });

    it('a non-owner cannot revoke (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      await createShareLink(tokenOwner, album.id);

      const response = await revokeShareLink(tokenOutsider, album.id);

      expect(response.status).toBe(404);
    });

    it('revoking then creating again gives a NEW token', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const first = await createShareLink(tokenOwner, album.id);

      await revokeShareLink(tokenOwner, album.id);
      const second = await createShareLink(tokenOwner, album.id);

      expect(second.body.token).not.toBe(first.body.token);
      // The old token stays dead — it does not get reactivated.
      const oldResolved = await getShared(first.body.token);
      expect(oldResolved.status).toBe(404);
      const newResolved = await getShared(second.body.token);
      expect(newResolved.status).toBe(200);
    });

    it('is idempotent when there is nothing to revoke', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await revokeShareLink(tokenOwner, album.id);

      expect(response.status).toBe(204);
    });
  });

  describe('PATCH /api/v1/albums/:id visibility is owner-only', () => {
    it('a non-owner cannot change visibility (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOutsider))
        .send({ visibility: 'PUBLIC' });

      expect(response.status).toBe(404);
    });
  });
});
