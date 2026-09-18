import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';
import { configureApp } from './../src/bootstrap';
import { REQUEST_ID_HEADER } from './../src/common/middleware/request-id.middleware';
import { withInMemoryPersistence } from './in-memory-persistence';

describe('Memora backend (e2e)', () => {
  let app: INestApplication;

  // One app for the whole file, not one per test — see the flake note in
  // specs/memora-backend/spec03-biblioteca-albumes.md / albums.e2e-spec.ts.
  // None of these tests mutate shared state, so reuse is safe.
  beforeAll(async () => {
    const moduleFixture: TestingModule = await withInMemoryPersistence(
      Test.createTestingModule({ imports: [AppModule] }),
    ).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('GET /health (unversioned, for infra probes)', () => {
    it('responds 200 with an operational status, without authentication', () => {
      return request(app.getHttpServer())
        .get('/health')
        .expect(200)
        .expect({ status: 'ok' });
    });
  });

  describe('GET /api/v1/health', () => {
    it('responds 200 with an operational status, without authentication', () => {
      return request(app.getHttpServer())
        .get('/api/v1/health')
        .expect(200)
        .expect({ status: 'ok' });
    });

    it('includes a request id header even when the client sends none', async () => {
      const response = await request(app.getHttpServer()).get('/api/v1/health');
      expect(response.headers[REQUEST_ID_HEADER]).toEqual(expect.any(String));
      expect(response.headers[REQUEST_ID_HEADER].length).toBeGreaterThan(0);
    });

    it('reuses the request id sent by the client', async () => {
      const clientRequestId = 'client-supplied-id-123';
      const response = await request(app.getHttpServer())
        .get('/api/v1/health')
        .set(REQUEST_ID_HEADER, clientRequestId);

      expect(response.headers[REQUEST_ID_HEADER]).toBe(clientRequestId);
    });
  });

  describe('unknown resource', () => {
    it('returns a uniform 404 error body', async () => {
      const response = await request(app.getHttpServer()).get(
        '/api/v1/does-not-exist',
      );

      expect(response.status).toBe(404);
      expect(response.body).toEqual({
        code: 'NOT_FOUND',
        message: expect.any(String),
        requestId: expect.any(String),
      });
      expect(response.headers[REQUEST_ID_HEADER]).toBe(response.body.requestId);
    });
  });
});
