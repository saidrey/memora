import { NotFoundException } from '@nestjs/common';
import { SharedViewService } from './shared-view.service';
import { InMemoryShareLinkRepository } from './in-memory-share-link.repository';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { InMemoryPhotoRepository } from '../photos/in-memory-photo.repository';

function buildService() {
  const shareLinkRepository = new InMemoryShareLinkRepository();
  const albumRepository = new InMemoryAlbumRepository();
  const photoRepository = new InMemoryPhotoRepository();
  const service = new SharedViewService(
    shareLinkRepository,
    albumRepository,
    photoRepository,
  );
  return { service, shareLinkRepository, albumRepository, photoRepository };
}

const OWNER = 'owner-1';

describe('SharedViewService', () => {
  it('resolves a valid, active token to the album name and its photos', async () => {
    const { service, shareLinkRepository, albumRepository, photoRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Vacaciones',
    });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'file-1' },
    });
    await albumRepository.addPhoto(album.id, photo.id);
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'tok-1',
    });

    const view = await service.resolve(link.token);

    expect(view.name).toBe('Vacaciones');
    expect(view.photos).toEqual([
      {
        id: photo.id,
        storageRef: photo.storageRef,
        width: undefined,
        height: undefined,
        mimeType: undefined,
        capturedAt: undefined,
      },
    ]);
  });

  it('P3: lists only AVAILABLE photos — unavailable ones are omitted, not marked', async () => {
    const { service, shareLinkRepository, albumRepository, photoRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const available = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'file-available' },
    });
    const unavailable = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'file-unavailable' },
    });
    await photoRepository.updateAvailability(unavailable.id, 'unavailable');
    await albumRepository.addPhoto(album.id, available.id);
    await albumRepository.addPhoto(album.id, unavailable.id);
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'tok-1',
    });

    const view = await service.resolve(link.token);

    expect(view.photos.map((p) => p.id)).toEqual([available.id]);
  });

  it('P4: the response never contains ownerId, any user id, or any token', async () => {
    const { service, shareLinkRepository, albumRepository, photoRepository } =
      buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'file-1' },
    });
    await albumRepository.addPhoto(album.id, photo.id);
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'secret-token',
    });

    const view = await service.resolve(link.token);

    const serialized = JSON.stringify(view);
    expect(serialized).not.toContain('ownerId');
    expect(serialized).not.toContain(OWNER);
    expect(serialized).not.toContain('token');
    expect(serialized).not.toContain('secret-token');
    expect(Object.keys(view).sort()).toEqual(['name', 'photos']);
    for (const photoView of view.photos) {
      expect(Object.keys(photoView).sort()).toEqual(
        ['capturedAt', 'height', 'id', 'mimeType', 'storageRef', 'width'].sort(),
      );
    }
  });

  it('an unknown token resolves to a uniform 404', async () => {
    const { service } = buildService();

    await expect(service.resolve('does-not-exist')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('a revoked link resolves to the same uniform 404', async () => {
    const { service, shareLinkRepository, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'tok-1',
    });
    await shareLinkRepository.revoke(album.id);

    await expect(service.resolve(link.token)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('a link whose album was deleted resolves to the same uniform 404', async () => {
    const { service, shareLinkRepository, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const link = await shareLinkRepository.create({
      albumId: album.id,
      token: 'tok-1',
    });
    await albumRepository.delete(album.id);

    await expect(service.resolve(link.token)).rejects.toThrow(
      NotFoundException,
    );
  });
});
