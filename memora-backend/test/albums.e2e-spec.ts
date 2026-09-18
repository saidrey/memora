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

const CODE_USER_A = 'code-user-a';
const CODE_USER_B = 'code-user-b';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  return {
    exchangeServerAuthCode: async (serverAuthCode: string) => {
      if (serverAuthCode === CODE_USER_A) {
        return {
          refreshToken: 'fake-refresh-a',
          identity: {
            googleId: 'google-a',
            email: 'a@example.com',
            name: 'User A',
          },
        };
      }
      if (serverAuthCode === CODE_USER_B) {
        return {
          refreshToken: 'fake-refresh-b',
          identity: {
            googleId: 'google-b',
            email: 'b@example.com',
            name: 'User B',
          },
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

// One app for the whole file (not one per test): each test churns through
// several fresh Nest apps/ephemeral HTTP servers, and with this many tests
// that occasionally triggered a rare supertest/Node socket-reuse flake
// ("Parse Error: Expected HTTP/") unrelated to the code under test. Every
// test below uses a uniquely-named album (uniqueName()) so none of them
// depend on the album list being empty at the start.
describe('Albums (e2e)', () => {
  let app: INestApplication;
  let tokenA: string;
  let tokenB: string;

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
  const uniqueName = (label: string) => `${label}-${randomUUID()}`;

  describe('POST /api/v1/albums', () => {
    it('requires a session', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .send({ name: uniqueName('Vacaciones') });

      expect(response.status).toBe(401);
      expect(response.body).toEqual({
        code: 'UNAUTHORIZED',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('creates an empty album owned by the caller', async () => {
      const name = uniqueName('Vacaciones');
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name });

      expect(response.status).toBe(201);
      expect(response.body).toEqual({
        id: expect.any(String),
        name,
        visibility: 'PRIVATE',
        photoCount: 0,
        createdAt: expect.any(String),
        updatedAt: expect.any(String),
      });
    });

    it('accepts an explicit visibility (D17)', async () => {
      const name = uniqueName('Público');
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name, visibility: 'PUBLIC' });

      expect(response.status).toBe(201);
      expect(response.body.visibility).toBe('PUBLIC');
    });

    it('rejects an invalid visibility with a uniform 400', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('X'), visibility: 'NOT_A_VALUE' });

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });

    it('rejects an empty name with a uniform 400', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: '   ' });

      expect(response.status).toBe(400);
      expect(response.body).toEqual({
        code: 'INVALID_REQUEST',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('rejects a name over the length limit with a uniform 400', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: 'x'.repeat(101) });

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });
  });

  describe('GET /api/v1/albums', () => {
    it('lists only the caller´s own albums', async () => {
      const nameA = uniqueName('De A');
      const nameB = uniqueName('De B');
      await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: nameA });
      await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenB))
        .send({ name: nameB });

      const response = await request(app.getHttpServer())
        .get('/api/v1/albums')
        .set('Authorization', authed(tokenA));

      expect(response.status).toBe(200);
      const names = response.body.map((album: { name: string }) => album.name);
      expect(names).toContain(nameA);
      expect(names).not.toContain(nameB);
    });
  });

  describe('GET /api/v1/albums/:id', () => {
    it('returns the album with an empty photos list for its owner', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('Mi álbum') });

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA));

      expect(response.status).toBe(200);
      expect(response.body.photos).toEqual([]);
    });

    it('returns a uniform 404 for a nonexistent album', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/albums/does-not-exist')
        .set('Authorization', authed(tokenA));

      expect(response.status).toBe(404);
      expect(response.body).toEqual({
        code: 'NOT_FOUND',
        message: expect.any(String),
        requestId: expect.any(String),
      });
    });

    it('returns a uniform 404 (not 403) for someone else´s album', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('De A, no de B') });

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenB));

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });
  });

  describe('PATCH /api/v1/albums/:id', () => {
    it('renames an album for its owner', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('Antes') });
      const newName = uniqueName('Después');

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA))
        .send({ name: newName });

      expect(response.status).toBe(200);
      expect(response.body.name).toBe(newName);
    });

    it('a non-owner cannot rename it (uniform 404)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('De A') });

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenB))
        .send({ name: uniqueName('Intento ajeno') });

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });

    it('changes visibility for its owner (D17)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('X') });
      expect(created.body.visibility).toBe('PRIVATE');

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA))
        .send({ visibility: 'PUBLIC' });

      expect(response.status).toBe(200);
      expect(response.body.visibility).toBe('PUBLIC');
    });

    it('a non-owner cannot change visibility either (uniform 404)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('X') });

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenB))
        .send({ visibility: 'PUBLIC' });

      expect(response.status).toBe(404);
    });

    it('rejects a body with neither name nor visibility (uniform 400)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('X') });

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA))
        .send({});

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });

    it('rejects an invalid visibility value (uniform 400)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('X') });

      const response = await request(app.getHttpServer())
        .patch(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA))
        .send({ visibility: 'nope' });

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('INVALID_REQUEST');
    });
  });

  describe('DELETE /api/v1/albums/:id', () => {
    it('deletes an album for its owner', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('A borrar') });

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA));
      expect(deleteResponse.status).toBe(204);

      const getResponse = await request(app.getHttpServer())
        .get(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA));
      expect(getResponse.status).toBe(404);
    });

    it('a non-owner cannot delete it (uniform 404, album survives)', async () => {
      const created = await request(app.getHttpServer())
        .post('/api/v1/albums')
        .set('Authorization', authed(tokenA))
        .send({ name: uniqueName('De A') });

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenB));
      expect(deleteResponse.status).toBe(404);

      const getResponse = await request(app.getHttpServer())
        .get(`/api/v1/albums/${created.body.id}`)
        .set('Authorization', authed(tokenA));
      expect(getResponse.status).toBe(200);
    });
  });
});
