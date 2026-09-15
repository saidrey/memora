import { NotFoundException } from '@nestjs/common';
import { NfcQrResolveService } from './nfc-qr-resolve.service';
import { InMemoryNfcQrTagRepository } from './in-memory-nfc-qr-tag.repository';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { InMemoryShareLinkRepository } from '../shared/in-memory-share-link.repository';

function buildService() {
  const tagRepository = new InMemoryNfcQrTagRepository();
  const albumRepository = new InMemoryAlbumRepository();
  const shareLinkRepository = new InMemoryShareLinkRepository();
  const service = new NfcQrResolveService(
    tagRepository,
    albumRepository,
    shareLinkRepository,
  );
  return { service, tagRepository, albumRepository, shareLinkRepository };
}

const OWNER = 'owner-1';

describe('NfcQrResolveService', () => {
  it('resolves an enabled tag with an active ShareLink to the internal shared-view path', async () => {
    const { service, tagRepository, albumRepository, shareLinkRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'QR',
      token: 'tag-token-1',
    });
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'share-token-1',
    });

    const path = await service.resolve(tag.token);

    expect(path).toBe(`/api/v1/shared/${link.token}`);
  });

  it('D14: regenerating the ShareLink does NOT break the tag — resolution follows the new token', async () => {
    const { service, tagRepository, albumRepository, shareLinkRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'NFC',
      token: 'tag-token-1',
    });
    await shareLinkRepository.create({ albumId: album.id, token: 'old-share' });

    // Revoke and regenerate the ShareLink (spec09 mechanics) — the tag never
    // stored the old token, so this must not require touching the tag at all.
    await shareLinkRepository.revoke(album.id);
    const regenerated = await shareLinkRepository.create({
      albumId: album.id,
      token: 'new-share',
    });

    const path = await service.resolve(tag.token);

    expect(path).toBe(`/api/v1/shared/${regenerated.token}`);
  });

  it('an unknown tag token resolves to a uniform 404', async () => {
    const { service } = buildService();

    await expect(service.resolve('does-not-exist')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('P2: a disabled tag resolves to a uniform 404', async () => {
    const { service, tagRepository, albumRepository, shareLinkRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'QR',
      token: 'tag-token-1',
    });
    await shareLinkRepository.create({ albumId: album.id, token: 'share-1' });
    await tagRepository.disable(tag.id);

    await expect(service.resolve(tag.token)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('D16: a tag whose album was deleted resolves to a uniform 404', async () => {
    const { service, tagRepository, albumRepository, shareLinkRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'QR',
      token: 'tag-token-1',
    });
    await shareLinkRepository.create({ albumId: album.id, token: 'share-1' });
    await albumRepository.delete(album.id);

    await expect(service.resolve(tag.token)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('a tag whose album has no ShareLink resolves to a uniform 404', async () => {
    const { service, tagRepository, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'QR',
      token: 'tag-token-1',
    });

    await expect(service.resolve(tag.token)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('a tag whose album ShareLink was revoked (not regenerated) resolves to a uniform 404', async () => {
    const { service, tagRepository, albumRepository, shareLinkRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const tag = await tagRepository.create({
      albumId: album.id,
      type: 'QR',
      token: 'tag-token-1',
    });
    await shareLinkRepository.create({ albumId: album.id, token: 'share-1' });
    await shareLinkRepository.revoke(album.id);

    await expect(service.resolve(tag.token)).rejects.toThrow(
      NotFoundException,
    );
  });
});
