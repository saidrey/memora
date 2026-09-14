import { ConfigService } from '@nestjs/config';
import { NotFoundException } from '@nestjs/common';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { AlbumAccessService } from './album-access.service';
import { InMemoryMembershipRepository } from './in-memory-membership.repository';
import { InMemoryInvitationRepository } from './in-memory-invitation.repository';
import { InvitationsService } from './invitations.service';

function buildService(configValues: Record<string, string> = {}) {
  const albumRepository = new InMemoryAlbumRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const invitationRepository = new InMemoryInvitationRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const configService = {
    get: (key: string) => configValues[key],
  } as unknown as ConfigService;
  const service = new InvitationsService(
    invitationRepository,
    membershipRepository,
    albumAccess,
    configService,
  );
  return {
    service,
    albumRepository,
    membershipRepository,
    invitationRepository,
  };
}

const OWNER = 'owner-1';
const INVITEE = 'invitee-1';
const OTHER_USER = 'other-1';

describe('InvitationsService', () => {
  it('creates a pending invitation with the full URL (built from APP_INVITE_BASE_URL) and the token', async () => {
    const { service, albumRepository } = buildService({
      APP_INVITE_BASE_URL: 'https://memora.test/invite/{token}',
    });
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    const invitation = await service.create(OWNER, album.id);

    expect(invitation.status).toBe('pending');
    expect(invitation.token).toEqual(expect.any(String));
    expect(invitation.token.length).toBeGreaterThan(20);
    expect(invitation.url).toBe(
      `https://memora.test/invite/${invitation.token}`,
    );
  });

  it('defaults APP_INVITE_BASE_URL and INVITATION_TTL_DAYS when unset', async () => {
    const { service, albumRepository, invitationRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    const invitation = await service.create(OWNER, album.id);

    expect(invitation.url).toBe(
      `https://memora.app/invite/${invitation.token}`,
    );
    const stored = await invitationRepository.findById(invitation.id);
    const days =
      (stored!.expiresAt.getTime() - stored!.createdAt.getTime()) /
      (24 * 60 * 60 * 1000);
    expect(days).toBeCloseTo(7, 1);
  });

  it('respects a configured INVITATION_TTL_DAYS', async () => {
    const { service, albumRepository, invitationRepository } = buildService({
      INVITATION_TTL_DAYS: '1',
    });
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    const invitation = await service.create(OWNER, album.id);
    const stored = await invitationRepository.findById(invitation.id);
    const days =
      (stored!.expiresAt.getTime() - stored!.createdAt.getTime()) /
      (24 * 60 * 60 * 1000);
    expect(days).toBeCloseTo(1, 1);
  });

  it('only the owner can create an invitation (uniform 404 for a collaborator or a stranger)', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await membershipRepository.addCollaborator(album.id, INVITEE);

    await expect(service.create(INVITEE, album.id)).rejects.toThrow(
      NotFoundException,
    );
    await expect(service.create(OTHER_USER, album.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('accepting a valid pending invitation adds the caller as a collaborator', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    await service.accept(INVITEE, invitation.token);

    const membership = await membershipRepository.findCollaborator(
      album.id,
      INVITEE,
    );
    expect(membership).not.toBeNull();
  });

  it('accepting marks the invitation accepted and records who accepted it (single-use, P6)', async () => {
    const { service, albumRepository, invitationRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    await service.accept(INVITEE, invitation.token);

    const stored = await invitationRepository.findById(invitation.id);
    expect(stored!.status).toBe('accepted');
    expect(stored!.acceptedByUserId).toBe(INVITEE);
  });

  it('a second, different user can no longer use an already-accepted invitation → 410 INVITATION_NOT_USABLE', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);
    await service.accept(INVITEE, invitation.token);

    try {
      await service.accept(OTHER_USER, invitation.token);
      fail('expected accept to throw');
    } catch (error) {
      expect((error as { getStatus(): number }).getStatus()).toBe(410);
      expect(
        (error as { getResponse(): { code: string } }).getResponse().code,
      ).toBe('INVITATION_NOT_USABLE');
    }
  });

  it('re-accepting your own already-accepted invitation is idempotent (204 — no throw, no duplicate membership)', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);
    await service.accept(INVITEE, invitation.token);

    await expect(
      service.accept(INVITEE, invitation.token),
    ).resolves.toBeUndefined();

    const memberships = await membershipRepository.listCollaborators(album.id);
    expect(memberships.filter((m) => m.userId === INVITEE)).toHaveLength(1);
  });

  it('the owner accepting their own invitation is idempotent (already a member)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    await expect(
      service.accept(OWNER, invitation.token),
    ).resolves.toBeUndefined();
  });

  it('accepting a revoked invitation fails with 410 INVITATION_NOT_USABLE', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);
    await service.revoke(OWNER, album.id, invitation.id);

    await expect(service.accept(INVITEE, invitation.token)).rejects.toThrow();
    try {
      await service.accept(INVITEE, invitation.token);
    } catch (error) {
      expect((error as { getStatus(): number }).getStatus()).toBe(410);
    }
  });

  it('accepting an expired invitation fails with 410 INVITATION_NOT_USABLE', async () => {
    const { service, albumRepository, invitationRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    // Bypass the service to plant an already-expired invitation directly.
    const expired = await invitationRepository.create({
      albumId: album.id,
      token: 'expired-token',
      createdBy: OWNER,
      expiresAt: new Date(Date.now() - 1000),
    });

    await expect(service.accept(INVITEE, expired.token)).rejects.toThrow();
    try {
      await service.accept(INVITEE, expired.token);
    } catch (error) {
      expect((error as { getStatus(): number }).getStatus()).toBe(410);
    }
    const stored = await invitationRepository.findById(expired.id);
    expect(stored!.status).toBe('expired'); // lazily persisted
  });

  it('accepting an unknown token fails with 410 INVITATION_NOT_USABLE', async () => {
    const { service } = buildService();

    try {
      await service.accept(INVITEE, 'no-such-token');
      fail('expected accept to throw');
    } catch (error) {
      expect((error as { getStatus(): number }).getStatus()).toBe(410);
    }
  });

  it('lists invitations for the owner, reflecting a lazily-detected expiry', async () => {
    const { service, albumRepository, invitationRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await invitationRepository.create({
      albumId: album.id,
      token: 'old-token',
      createdBy: OWNER,
      expiresAt: new Date(Date.now() - 1000),
    });
    await service.create(OWNER, album.id);

    const list = await service.list(OWNER, album.id);

    expect(list).toHaveLength(2);
    const statuses = list.map((i) => i.status).sort();
    expect(statuses).toEqual(['expired', 'pending']);
  });

  it('never exposes the token for an already-accepted invitation', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);
    await service.accept(INVITEE, invitation.token);

    const list = await service.list(OWNER, album.id);

    const accepted = list.find((i) => i.id === invitation.id);
    expect(accepted?.status).toBe('accepted');
    expect(accepted?.token).toBeUndefined();
    expect(accepted?.url).toBeUndefined();
  });

  it('exposes the token/url for a still-pending invitation', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    const list = await service.list(OWNER, album.id);

    const pending = list.find((i) => i.id === invitation.id);
    expect(pending?.token).toBe(invitation.token);
    expect(pending?.url).toBe(invitation.url);
  });

  it('only the owner can list invitations (uniform 404 otherwise)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(service.list(OTHER_USER, album.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('revokes a pending invitation; it can no longer be accepted', async () => {
    const { service, albumRepository, invitationRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    await service.revoke(OWNER, album.id, invitation.id);

    const stored = await invitationRepository.findById(invitation.id);
    expect(stored!.status).toBe('revoked');
  });

  it('revoking is idempotent for an already non-pending invitation (no error)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);
    await service.revoke(OWNER, album.id, invitation.id);

    await expect(
      service.revoke(OWNER, album.id, invitation.id),
    ).resolves.toBeUndefined();
  });

  it('only the owner can revoke (uniform 404 otherwise)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const invitation = await service.create(OWNER, album.id);

    await expect(
      service.revoke(OTHER_USER, album.id, invitation.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('revoking an unknown invitationId returns a uniform 404', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(
      service.revoke(OWNER, album.id, 'does-not-exist'),
    ).rejects.toThrow(NotFoundException);
  });
});
