import { NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NfcQrTagsService } from './nfc-qr-tags.service';
import { InMemoryNfcQrTagRepository } from './in-memory-nfc-qr-tag.repository';
import { AlbumAccessService } from '../collaborators/album-access.service';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { InMemoryMembershipRepository } from '../collaborators/in-memory-membership.repository';

function buildService(configValues: Record<string, string> = {}) {
  const albumRepository = new InMemoryAlbumRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const tagRepository = new InMemoryNfcQrTagRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const configService = {
    get: (key: string) => configValues[key],
  } as unknown as ConfigService;
  const service = new NfcQrTagsService(tagRepository, albumAccess, configService);
  return { service, albumRepository, tagRepository };
}

const OWNER = 'owner-1';
const OUTSIDER = 'outsider-1';

describe('NfcQrTagsService', () => {
  it('creates a tag with an opaque token, enabled status, and a URL built from APP_NFC_QR_BASE_URL', async () => {
    const { service, albumRepository } = buildService({
      APP_NFC_QR_BASE_URL: 'https://example.test/n/{token}',
    });
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const tag = await service.create(OWNER, album.id, 'QR');

    expect(tag.type).toBe('QR');
    expect(tag.status).toBe('enabled');
    expect(tag.token).toEqual(expect.any(String));
    expect(tag.token.length).toBeGreaterThan(20);
    expect(tag.url).toBe(`https://example.test/n/${tag.token}`);
  });

  it('falls back to the dev default URL when APP_NFC_QR_BASE_URL is not set', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const tag = await service.create(OWNER, album.id, 'NFC');

    expect(tag.url).toBe(`https://memora.app/n/${tag.token}`);
  });

  it('no uniqueness constraint: two tags of the SAME type for the SAME album coexist with different tokens', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    const first = await service.create(OWNER, album.id, 'QR');
    const second = await service.create(OWNER, album.id, 'QR');

    expect(second.id).not.toBe(first.id);
    expect(second.token).not.toBe(first.token);
  });

  it('creating is owner-only (uniform 404 for a non-owner)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    await expect(service.create(OUTSIDER, album.id, 'QR')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('get() returns the tag for its owner', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const created = await service.create(OWNER, album.id, 'NFC');

    const fetched = await service.get(OWNER, created.id);

    expect(fetched).toEqual(created);
  });

  it('get() is owner-only (uniform 404 for a non-owner, and for an unknown id)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const created = await service.create(OWNER, album.id, 'NFC');

    await expect(service.get(OUTSIDER, created.id)).rejects.toThrow(
      NotFoundException,
    );
    await expect(service.get(OWNER, 'does-not-exist')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('P2: disable() marks the tag disabled and stamps disabledAt', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const created = await service.create(OWNER, album.id, 'QR');

    await service.disable(OWNER, created.id);

    const fetched = await service.get(OWNER, created.id);
    expect(fetched.status).toBe('disabled');
    expect(fetched.disabledAt).toBeInstanceOf(Date);
  });

  it('disable() is idempotent — disabling twice does not throw', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const created = await service.create(OWNER, album.id, 'QR');

    await service.disable(OWNER, created.id);
    await expect(service.disable(OWNER, created.id)).resolves.toBeUndefined();
  });

  it('disable() is owner-only (uniform 404 for a non-owner)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const created = await service.create(OWNER, album.id, 'QR');

    await expect(service.disable(OUTSIDER, created.id)).rejects.toThrow(
      NotFoundException,
    );
  });
});
