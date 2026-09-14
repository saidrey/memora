import { NotFoundException } from '@nestjs/common';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { InMemoryPhotoRepository } from './in-memory-photo.repository';
import { PhotosService } from './photos.service';

function buildService() {
  const photoRepository = new InMemoryPhotoRepository();
  const albumRepository = new InMemoryAlbumRepository();
  const service = new PhotosService(photoRepository, albumRepository);
  return { service, photoRepository, albumRepository };
}

const OWNER = 'owner-1';
const OTHER_USER = 'owner-2';

describe('PhotosService', () => {
  it('registers a photo owned by the caller with the D8 metadata, defaulting availability', async () => {
    const { service } = buildService();

    const photo = await service.register(OWNER, {
      driveFileId: 'drive-file-1',
      width: 1080,
      height: 1920,
      mimeType: 'image/jpeg',
      sizeBytes: 204800,
      capturedAt: new Date('2026-01-01T00:00:00Z'),
    });

    expect(photo).toEqual({
      id: expect.any(String),
      ownerId: OWNER,
      driveFileId: 'drive-file-1',
      createdAt: expect.any(Date),
      capturedAt: new Date('2026-01-01T00:00:00Z'),
      width: 1080,
      height: 1920,
      mimeType: 'image/jpeg',
      sizeBytes: 204800,
      availability: 'available',
    });
  });

  it('never stores geolocation — the model has no such field to set', async () => {
    const { service } = buildService();

    const photo = await service.register(OWNER, { driveFileId: 'drive-file-1' });

    expect(photo).not.toHaveProperty('latitude');
    expect(photo).not.toHaveProperty('longitude');
    expect(photo).not.toHaveProperty('location');
    expect(photo).not.toHaveProperty('gps');
  });

  it('registers a photo and associates it to an owned album in one call', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'Viaje' });

    const photo = await service.register(OWNER, {
      driveFileId: 'drive-file-1',
      albumId: album.id,
    });

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([photo.id]);
  });

  it('registering with someone else´s albumId returns a uniform 404', async () => {
    const { service, albumRepository } = buildService();
    const theirAlbum = await albumRepository.create({
      ownerId: OTHER_USER,
      name: 'No es tuyo',
    });

    await expect(
      service.register(OWNER, { driveFileId: 'x', albumId: theirAlbum.id }),
    ).rejects.toThrow(NotFoundException);
  });

  it('associates and disassociates an existing photo without duplicating (N:M)', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'Álbum' });
    const photo = await photoRepository.create({ ownerId: OWNER, driveFileId: 'x' });

    await service.associate(OWNER, album.id, photo.id);
    await service.associate(OWNER, album.id, photo.id); // twice — no duplicate

    expect(await albumRepository.countPhotos(album.id)).toBe(1);

    await service.disassociate(OWNER, album.id, photo.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([]);
    // The photo itself and the Drive file are untouched.
    await expect(photoRepository.findById(photo.id)).resolves.toEqual(photo);
  });

  it('associating a photo to someone else´s album returns 404', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const theirAlbum = await albumRepository.create({ ownerId: OTHER_USER, name: 'X' });
    const photo = await photoRepository.create({ ownerId: OWNER, driveFileId: 'x' });

    await expect(
      service.associate(OWNER, theirAlbum.id, photo.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('associating someone else´s photo to my own album returns 404', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const myAlbum = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const theirPhoto = await photoRepository.create({
      ownerId: OTHER_USER,
      driveFileId: 'x',
    });

    await expect(
      service.associate(OWNER, myAlbum.id, theirPhoto.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('lists the caller´s library independent of albums (D11)', async () => {
    const { service, photoRepository } = buildService();
    await photoRepository.create({ ownerId: OWNER, driveFileId: 'a' });
    await photoRepository.create({ ownerId: OWNER, driveFileId: 'b' });
    await photoRepository.create({ ownerId: OTHER_USER, driveFileId: 'c' });

    const library = await service.listLibrary(OWNER);

    expect(library.map((p) => p.driveFileId).sort()).toEqual(['a', 'b']);
  });

  it('deleting a photo removes it from ALL albums and forgets it, but never touches Drive', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const albumA = await albumRepository.create({ ownerId: OWNER, name: 'A' });
    const albumB = await albumRepository.create({ ownerId: OWNER, name: 'B' });
    const photo = await photoRepository.create({ ownerId: OWNER, driveFileId: 'x' });
    await albumRepository.addPhoto(albumA.id, photo.id);
    await albumRepository.addPhoto(albumB.id, photo.id);

    await service.deletePhoto(OWNER, photo.id);

    expect(await albumRepository.listPhotoIds(albumA.id)).toEqual([]);
    expect(await albumRepository.listPhotoIds(albumB.id)).toEqual([]);
    await expect(photoRepository.findById(photo.id)).resolves.toBeNull();
    // "Never touches Drive" is true by construction: PhotoRepository only
    // ever forgets the reference — there is no Drive client anywhere in
    // this service to call.
  });

  it('deleting one photo does not affect a sibling photo in the same album', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'A' });
    const photo1 = await photoRepository.create({ ownerId: OWNER, driveFileId: 'x' });
    const photo2 = await photoRepository.create({ ownerId: OWNER, driveFileId: 'y' });
    await albumRepository.addPhoto(album.id, photo1.id);
    await albumRepository.addPhoto(album.id, photo2.id);

    await service.deletePhoto(OWNER, photo1.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([photo2.id]);
  });

  it('deleting someone else´s photo returns a uniform 404', async () => {
    const { service, photoRepository } = buildService();
    const theirPhoto = await photoRepository.create({
      ownerId: OTHER_USER,
      driveFileId: 'x',
    });

    await expect(service.deletePhoto(OWNER, theirPhoto.id)).rejects.toThrow(
      NotFoundException,
    );
  });
});
