import { NotFoundException } from '@nestjs/common';
import { AlbumsService } from './albums.service';
import { InMemoryAlbumRepository } from './in-memory-album.repository';
import { InMemoryPhotoRepository } from './photos/in-memory-photo.repository';

function buildService() {
  const albumRepository = new InMemoryAlbumRepository();
  const photoRepository = new InMemoryPhotoRepository();
  const service = new AlbumsService(albumRepository, photoRepository);
  return { service, albumRepository, photoRepository };
}

const OWNER = 'owner-1';
const OTHER_USER = 'owner-2';

describe('AlbumsService', () => {
  it('creates an album owned by the caller, empty by default', async () => {
    const { service } = buildService();

    const album = await service.create(OWNER, 'Vacaciones');

    expect(album).toEqual({
      id: expect.any(String),
      name: 'Vacaciones',
      photoCount: 0,
      createdAt: expect.any(Date),
      updatedAt: expect.any(Date),
    });
  });

  it('lists only the caller´s own albums', async () => {
    const { service } = buildService();
    await service.create(OWNER, 'Mío 1');
    await service.create(OWNER, 'Mío 2');
    await service.create(OTHER_USER, 'De otra persona');

    const albums = await service.listForOwner(OWNER);

    expect(albums).toHaveLength(2);
    expect(albums.map((a) => a.name).sort()).toEqual(['Mío 1', 'Mío 2']);
  });

  it('gets an owned album with its (currently empty) photos', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'Mi álbum');

    const detail = await service.getForOwner(OWNER, created.id);

    expect(detail.photos).toEqual([]);
    expect(detail.photoCount).toBe(0);
  });

  it('renames an album owned by the caller', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'Nombre viejo');

    const renamed = await service.rename(OWNER, created.id, 'Nombre nuevo');

    expect(renamed.name).toBe('Nombre nuevo');
  });

  it('returns 404 for a nonexistent album', async () => {
    const { service } = buildService();

    await expect(service.getForOwner(OWNER, 'does-not-exist')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('returns 404 (not 403) for someone else´s album, to a get/rename/delete alike', async () => {
    const { service } = buildService();
    const theirs = await service.create(OTHER_USER, 'No es tuyo');

    await expect(service.getForOwner(OWNER, theirs.id)).rejects.toThrow(
      NotFoundException,
    );
    await expect(
      service.rename(OWNER, theirs.id, 'Intento de renombrar'),
    ).rejects.toThrow(NotFoundException);
    await expect(service.delete(OWNER, theirs.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('deleting an album removes only ITS photo relations — a photo in two albums stays in the other (D16)', async () => {
    const { service, albumRepository, photoRepository } = buildService();

    const photo = await photoRepository.create({
      ownerId: OWNER,
      driveFileId: 'drive-file-1',
    });
    const albumA = await service.create(OWNER, 'Álbum A');
    const albumB = await service.create(OWNER, 'Álbum B');
    await albumRepository.addPhoto(albumA.id, photo.id);
    await albumRepository.addPhoto(albumB.id, photo.id);

    await service.delete(OWNER, albumA.id);

    // Album A is gone entirely.
    await expect(service.getForOwner(OWNER, albumA.id)).rejects.toThrow(
      NotFoundException,
    );

    // Album B keeps the photo — the relation to A's deletion didn't leak.
    const remaining = await service.getForOwner(OWNER, albumB.id);
    expect(remaining.photos.map((p) => p.id)).toEqual([photo.id]);

    // The photo itself was never touched.
    await expect(photoRepository.findById(photo.id)).resolves.toEqual(photo);
  });

  it('adding the same photo to an album twice does not duplicate it', async () => {
    const { albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'X' });

    await albumRepository.addPhoto(album.id, 'photo-1');
    await albumRepository.addPhoto(album.id, 'photo-1');

    expect(await albumRepository.countPhotos(album.id)).toBe(1);
  });
});
