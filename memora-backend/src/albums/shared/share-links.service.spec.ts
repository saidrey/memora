import { NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ShareLinksService } from './share-links.service';
import { InMemoryShareLinkRepository } from './in-memory-share-link.repository';
import { AlbumAccessService } from '../collaborators/album-access.service';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { InMemoryMembershipRepository } from '../collaborators/in-memory-membership.repository';

function buildService(configValues: Record<string, string> = {}) {
  const albumRepository = new InMemoryAlbumRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const shareLinkRepository = new InMemoryShareLinkRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const configService = {
    get: (key: string) => configValues[key],
  } as unknown as ConfigService;
  const service = new ShareLinksService(
    shareLinkRepository,
    albumAccess,
    configService,
  );
  return { service, albumRepository, shareLinkRepository };
}

const OWNER = 'owner-1';
const OUTSIDER = 'outsider-1';

describe('ShareLinksService', () => {
  it('creates a share link with an opaque token and a URL built from APP_SHARE_BASE_URL', async () => {
    const { service, albumRepository } = buildService({
      APP_SHARE_BASE_URL: 'https://example.test/s/{token}',
    });
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const link = await service.createOrGetExisting(OWNER, album.id);

    expect(link.token).toEqual(expect.any(String));
    expect(link.token.length).toBeGreaterThan(20);
    expect(link.url).toBe(`https://example.test/s/${link.token}`);
  });

  it('falls back to the dev default URL when APP_SHARE_BASE_URL is not set', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const link = await service.createOrGetExisting(OWNER, album.id);

    expect(link.url).toBe(`https://memora.app/s/${link.token}`);
  });

  it('P5: creating twice returns the SAME token — one link per album', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const first = await service.createOrGetExisting(OWNER, album.id);
    const second = await service.createOrGetExisting(OWNER, album.id);

    expect(second.token).toBe(first.token);
  });

  it('revoke() then createOrGetExisting() again produces a NEW token, never reactivating the old one', async () => {
    const { service, albumRepository, shareLinkRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const first = await service.createOrGetExisting(OWNER, album.id);

    await service.revoke(OWNER, album.id);
    const second = await service.createOrGetExisting(OWNER, album.id);

    expect(second.token).not.toBe(first.token);
    const stored = await shareLinkRepository.findByAlbumId(album.id);
    expect(stored?.token).toBe(second.token);
    expect(stored?.status).toBe('active');
  });

  it('revoke() is idempotent — revoking twice, or revoking when nothing exists, does not throw', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    await expect(service.revoke(OWNER, album.id)).resolves.toBeUndefined();
    await service.createOrGetExisting(OWNER, album.id);
    await service.revoke(OWNER, album.id);
    await expect(service.revoke(OWNER, album.id)).resolves.toBeUndefined();
  });

  it('creating is owner-only (uniform 404 for a non-owner)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    await expect(
      service.createOrGetExisting(OUTSIDER, album.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('revoking is owner-only (uniform 404 for a non-owner)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    await service.createOrGetExisting(OWNER, album.id);

    await expect(service.revoke(OUTSIDER, album.id)).rejects.toThrow(
      NotFoundException,
    );
  });
});
