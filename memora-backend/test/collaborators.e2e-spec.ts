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

const CODE_OWNER = 'code-owner';
const CODE_COLLABORATOR = 'code-collaborator';
const CODE_OUTSIDER = 'code-outsider';

function buildFakeGoogleAuthClient(): GoogleAuthClient {
  const byCode: Record<
    string,
    { googleId: string; email: string; name: string }
  > = {
    [CODE_OWNER]: {
      googleId: 'google-owner',
      email: 'owner@example.com',
      name: 'Owner',
    },
    [CODE_COLLABORATOR]: {
      googleId: 'google-collaborator',
      email: 'collaborator@example.com',
      name: 'Collaborator',
    },
    [CODE_OUTSIDER]: {
      googleId: 'google-outsider',
      email: 'outsider@example.com',
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

// One app for the whole file (beforeAll/afterAll), per the flake fix
// documented in memora-backend/CLAUDE.md — see albums.e2e-spec.ts /
// photos.e2e-spec.ts. Requests below are awaited sequentially, never via
// Promise.all, for the same reason.
describe('Collaborators (e2e)', () => {
  let app: INestApplication;
  let tokenOwner: string;
  let tokenCollaborator: string;
  let tokenOutsider: string;
  let ownerId: string;

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
    ownerId = loginOwner.body.user.id;

    const loginCollaborator = await request(app.getHttpServer())
      .post('/api/v1/auth/google')
      .send({ serverAuthCode: CODE_COLLABORATOR });
    tokenCollaborator = loginCollaborator.body.sessionAccessToken;

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
  const uniqueDriveFileId = () => `drive-file-${randomUUID()}`; // storageRef.fileId

  const createAlbum = async (token: string, name: string) => {
    const response = await request(app.getHttpServer())
      .post('/api/v1/albums')
      .set('Authorization', authed(token))
      .send({ name });
    return response.body as { id: string };
  };

  const createInvitation = async (token: string, albumId: string) => {
    return request(app.getHttpServer())
      .post(`/api/v1/albums/${albumId}/invitations`)
      .set('Authorization', authed(token));
  };

  const acceptInvitation = async (token: string, invitationToken: string) => {
    return request(app.getHttpServer())
      .post(`/api/v1/invitations/${invitationToken}/accept`)
      .set('Authorization', authed(token));
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

  /** Owner creates an album and an accepted collaborator membership, in one shot. */
  const createAlbumWithCollaborator = async () => {
    const album = await createAlbum(tokenOwner, uniqueName('Compartido'));
    const invitation = await createInvitation(tokenOwner, album.id);
    await acceptInvitation(tokenCollaborator, invitation.body.token);
    return album;
  };

  describe('POST /api/v1/albums/:albumId/invitations', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const response = await request(app.getHttpServer()).post(
        `/api/v1/albums/${album.id}/invitations`,
      );
      expect(response.status).toBe(401);
    });

    it('owner creates a pending invitation with a URL and a bare token', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createInvitation(tokenOwner, album.id);

      expect(response.status).toBe(201);
      expect(response.body.status).toBe('pending');
      expect(response.body.token).toEqual(expect.any(String));
      expect(response.body.url).toContain(response.body.token);
      expect(response.body.expiresAt).toEqual(expect.any(String));
    });

    it('a non-owner (outsider) cannot create an invitation (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await createInvitation(tokenOutsider, album.id);

      expect(response.status).toBe(404);
      expect(response.body.code).toBe('NOT_FOUND');
    });

    it('a collaborator cannot create an invitation either — invite management is owner-only', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await createInvitation(tokenCollaborator, album.id);

      expect(response.status).toBe(404);
    });
  });

  describe('GET /api/v1/albums/:albumId/invitations', () => {
    it('owner lists invitations, seeing the token while pending', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/invitations`)
        .set('Authorization', authed(tokenOwner));

      expect(response.status).toBe(200);
      const item = response.body.find(
        (i: { id: string }) => i.id === created.body.id,
      );
      expect(item.status).toBe('pending');
      expect(item.token).toBe(created.body.token);
    });

    it('does not expose the token in clear for an already-accepted invitation', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);
      await acceptInvitation(tokenCollaborator, created.body.token);

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/invitations`)
        .set('Authorization', authed(tokenOwner));

      const item = response.body.find(
        (i: { id: string }) => i.id === created.body.id,
      );
      expect(item.status).toBe('accepted');
      expect(item.token).toBeUndefined();
    });

    it('a non-owner cannot list invitations (uniform 404)', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/invitations`)
        .set('Authorization', authed(tokenCollaborator));

      expect(response.status).toBe(404);
    });
  });

  describe('DELETE /api/v1/albums/:albumId/invitations/:invitationId', () => {
    it('owner revokes a pending invitation; it can no longer be accepted (410)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const revoke = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/invitations/${created.body.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(revoke.status).toBe(204);

      const accept = await acceptInvitation(tokenOutsider, created.body.token);
      expect(accept.status).toBe(410);
      expect(accept.body.code).toBe('INVITATION_NOT_USABLE');
    });

    it('a non-owner cannot revoke (uniform 404)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/invitations/${created.body.id}`)
        .set('Authorization', authed(tokenOutsider));

      expect(response.status).toBe(404);
    });
  });

  describe('POST /api/v1/invitations/:token/accept', () => {
    it('requires a session', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const response = await request(app.getHttpServer()).post(
        `/api/v1/invitations/${created.body.token}/accept`,
      );

      expect(response.status).toBe(401);
    });

    it('an unknown token fails with 410 INVITATION_NOT_USABLE', async () => {
      const response = await acceptInvitation(
        tokenOutsider,
        'not-a-real-token',
      );

      expect(response.status).toBe(410);
      expect(response.body.code).toBe('INVITATION_NOT_USABLE');
    });

    it('a valid pending invitation makes the caller a collaborator, and the album shows up in GET /albums with role', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const accept = await acceptInvitation(
        tokenCollaborator,
        created.body.token,
      );
      expect(accept.status).toBe(204);

      const list = await request(app.getHttpServer())
        .get('/api/v1/albums')
        .set('Authorization', authed(tokenCollaborator));
      const item = list.body.find((a: { id: string }) => a.id === album.id);
      expect(item.role).toBe('collaborator');

      const ownerList = await request(app.getHttpServer())
        .get('/api/v1/albums')
        .set('Authorization', authed(tokenOwner));
      const ownerItem = ownerList.body.find(
        (a: { id: string }) => a.id === album.id,
      );
      expect(ownerItem.role).toBe('owner');
    });

    it('accepting the same token twice is idempotent (204, no duplicate membership)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);
      await acceptInvitation(tokenCollaborator, created.body.token);

      const secondAccept = await acceptInvitation(
        tokenCollaborator,
        created.body.token,
      );
      expect(secondAccept.status).toBe(204);

      const collaborators = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/collaborators`)
        .set('Authorization', authed(tokenOwner));
      expect(collaborators.body).toHaveLength(1);
    });

    it('the owner accepting their own invitation is idempotent, does not create a duplicate/second role', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);

      const response = await acceptInvitation(tokenOwner, created.body.token);
      expect(response.status).toBe(204);

      const list = await request(app.getHttpServer())
        .get('/api/v1/albums')
        .set('Authorization', authed(tokenOwner));
      expect(
        list.body.filter((a: { id: string }) => a.id === album.id),
      ).toHaveLength(1);
    });

    it('a different user cannot reuse an already-accepted invitation (410 — single use, P6)', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));
      const created = await createInvitation(tokenOwner, album.id);
      await acceptInvitation(tokenCollaborator, created.body.token);

      const response = await acceptInvitation(
        tokenOutsider,
        created.body.token,
      );

      expect(response.status).toBe(410);
      expect(response.body.code).toBe('INVITATION_NOT_USABLE');
    });
  });

  describe('GET /api/v1/albums/:id — read by owner and collaborator', () => {
    it('a collaborator can read the album and its photos; an outsider gets a uniform 404', async () => {
      const album = await createAlbumWithCollaborator();

      const asCollaborator = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenCollaborator));
      expect(asCollaborator.status).toBe(200);

      const asOutsider = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOutsider));
      expect(asOutsider.status).toBe(404);
    });
  });

  describe('Photo contribution by a collaborator', () => {
    it('a collaborator registers a photo directly into the shared album, owned by the collaborator', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await registerPhoto(tokenCollaborator, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });

      expect(response.status).toBe(201);
      expect(response.body.ownerId).toEqual(expect.any(String));

      const detail = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(
        detail.body.photos.some(
          (p: { id: string }) => p.id === response.body.id,
        ),
      ).toBe(true);
    });

    it('an outsider cannot contribute to the album (uniform 404)', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await registerPhoto(tokenOutsider, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });

      expect(response.status).toBe(404);
    });

    it('a collaborator cannot associate a photo they do not own into the album', async () => {
      const album = await createAlbumWithCollaborator();
      const ownersPhoto = await registerPhoto(tokenOwner, {
        storageRef: { fileId: uniqueDriveFileId() },
      });

      const response = await request(app.getHttpServer())
        .post(`/api/v1/albums/${album.id}/photos`)
        .set('Authorization', authed(tokenCollaborator))
        .send({ photoId: ownersPhoto.body.id });

      expect(response.status).toBe(404);
    });
  });

  describe('DELETE /api/v1/albums/:albumId/photos/:photoId — removal by role', () => {
    it("owner removes a collaborator's photo from the album (D4) — only the relation goes", async () => {
      const album = await createAlbumWithCollaborator();
      const collaboratorPhoto = await registerPhoto(tokenCollaborator, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });

      const remove = await request(app.getHttpServer())
        .delete(
          `/api/v1/albums/${album.id}/photos/${collaboratorPhoto.body.id}`,
        )
        .set('Authorization', authed(tokenOwner));
      expect(remove.status).toBe(204);

      const library = await request(app.getHttpServer())
        .get('/api/v1/library')
        .set('Authorization', authed(tokenCollaborator));
      expect(
        library.body.some(
          (p: { id: string }) => p.id === collaboratorPhoto.body.id,
        ),
      ).toBe(true);
    });

    it('a collaborator cannot remove a photo that is not theirs (uniform 404)', async () => {
      const album = await createAlbumWithCollaborator();
      const ownersPhoto = await registerPhoto(tokenOwner, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/photos/${ownersPhoto.body.id}`)
        .set('Authorization', authed(tokenCollaborator));

      expect(response.status).toBe(404);
    });

    it('a collaborator can remove their own contribution', async () => {
      const album = await createAlbumWithCollaborator();
      const ownPhoto = await registerPhoto(tokenCollaborator, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/photos/${ownPhoto.body.id}`)
        .set('Authorization', authed(tokenCollaborator));

      expect(response.status).toBe(204);
    });
  });

  describe('Administrar colaboradores', () => {
    it('owner lists collaborators of the album', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/collaborators`)
        .set('Authorization', authed(tokenOwner));

      expect(response.status).toBe(200);
      expect(response.body).toHaveLength(1);
      expect(response.body[0].role).toBe('collaborator');
    });

    it('a non-owner cannot list collaborators (uniform 404)', async () => {
      const album = await createAlbumWithCollaborator();

      const response = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}/collaborators`)
        .set('Authorization', authed(tokenOutsider));

      expect(response.status).toBe(404);
    });

    it('owner removes a collaborator; they lose access, their historical photos remain (D5)', async () => {
      const album = await createAlbumWithCollaborator();
      const collaboratorPhoto = await registerPhoto(tokenCollaborator, {
        storageRef: { fileId: uniqueDriveFileId() },
        albumId: album.id,
      });
      const collaboratorId = (
        await request(app.getHttpServer())
          .get(`/api/v1/albums/${album.id}/collaborators`)
          .set('Authorization', authed(tokenOwner))
      ).body[0].userId;

      const remove = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/collaborators/${collaboratorId}`)
        .set('Authorization', authed(tokenOwner));
      expect(remove.status).toBe(204);

      const readAsRemoved = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenCollaborator));
      expect(readAsRemoved.status).toBe(404);

      const detailAsOwner = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(
        detailAsOwner.body.photos.some(
          (p: { id: string }) => p.id === collaboratorPhoto.body.id,
        ),
      ).toBe(true);
    });

    it('the owner cannot remove themselves via this endpoint', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/collaborators/${ownerId}`)
        .set('Authorization', authed(tokenOwner));

      expect(response.status).toBe(400);
      expect(response.body.code).toBe('CANNOT_REMOVE_OWNER');

      const ownerProfile = await request(app.getHttpServer())
        .get('/api/v1/albums')
        .set('Authorization', authed(tokenOwner));
      const ownerAlbum = ownerProfile.body.find(
        (a: { id: string }) => a.id === album.id,
      );
      expect(ownerAlbum.role).toBe('owner');
    });

    it('a collaborator can leave the album via DELETE .../collaborators/me (P1)', async () => {
      const album = await createAlbumWithCollaborator();

      const leave = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/collaborators/me`)
        .set('Authorization', authed(tokenCollaborator));
      expect(leave.status).toBe(204);

      const readAfterLeaving = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenCollaborator));
      expect(readAfterLeaving.status).toBe(404);
    });

    it('DELETE .../collaborators/me requires membership — an outsider gets a uniform 404', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('X'));

      const response = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}/collaborators/me`)
        .set('Authorization', authed(tokenOutsider));

      expect(response.status).toBe(404);
    });
  });

  describe('DELETE /api/v1/albums/:id cleans up memberships and invitations (D16)', () => {
    it('after deleting the album, its invitation token is no longer usable and the ex-collaborator has no access', async () => {
      const album = await createAlbum(tokenOwner, uniqueName('A borrar'));
      const invitation = await createInvitation(tokenOwner, album.id);
      await acceptInvitation(tokenCollaborator, invitation.body.token);

      // A second, still-pending invitation on the same album.
      const secondInvitation = await createInvitation(tokenOwner, album.id);

      const deleteResponse = await request(app.getHttpServer())
        .delete(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenOwner));
      expect(deleteResponse.status).toBe(204);

      const acceptAfterDelete = await acceptInvitation(
        tokenOutsider,
        secondInvitation.body.token,
      );
      expect(acceptAfterDelete.status).toBe(410);

      const readAsCollaborator = await request(app.getHttpServer())
        .get(`/api/v1/albums/${album.id}`)
        .set('Authorization', authed(tokenCollaborator));
      expect(readAsCollaborator.status).toBe(404);
    });
  });
});
