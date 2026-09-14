import { NotFoundException } from '@nestjs/common';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { AlbumAccessService } from '../collaborators/album-access.service';
import { InMemoryMembershipRepository } from '../collaborators/in-memory-membership.repository';
import { InMemoryPhotoRepository } from './in-memory-photo.repository';
import { PhotosService } from './photos.service';

function buildService() {
  const photoRepository = new InMemoryPhotoRepository();
  const albumRepository = new InMemoryAlbumRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const service = new PhotosService(
    photoRepository,
    albumRepository,
    albumAccess,
  );
  return { service, photoRepository, albumRepository, membershipRepository };
}

const OWNER = 'owner-1';
const OTHER_USER = 'owner-2';
const COLLABORATOR = 'collaborator-1';

describe('PhotosService', () => {
  it('registers a photo owned by the caller with the D8 metadata, defaulting availability', async () => {
    const { service } = buildService();

    const photo = await service.register(OWNER, {
      storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
      width: 1080,
      height: 1920,
      mimeType: 'image/jpeg',
      sizeBytes: 204800,
      capturedAt: new Date('2026-01-01T00:00:00Z'),
    });

    expect(photo).toEqual({
      id: expect.any(String),
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
      createdAt: expect.any(Date),
      capturedAt: new Date('2026-01-01T00:00:00Z'),
      width: 1080,
      height: 1920,
      mimeType: 'image/jpeg',
      sizeBytes: 204800,
      availability: 'available',
    });
  });

  it('defaults storageRef.provider to "google-drive" when the caller omits it (spec08)', async () => {
    const { service } = buildService();

    const photo = await service.register(OWNER, {
      storageRef: { fileId: 'no-provider-given' },
    });

    expect(photo.storageRef).toEqual({
      provider: 'google-drive',
      fileId: 'no-provider-given',
    });
  });

  it('never stores geolocation — the model has no such field to set', async () => {
    const { service } = buildService();

    const photo = await service.register(OWNER, {
      storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
    });

    expect(photo).not.toHaveProperty('latitude');
    expect(photo).not.toHaveProperty('longitude');
    expect(photo).not.toHaveProperty('location');
    expect(photo).not.toHaveProperty('gps');
  });

  it('registers a photo and associates it to an owned album in one call', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Viaje',
    });

    const photo = await service.register(OWNER, {
      storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
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
      service.register(OWNER, { storageRef: { provider: 'google-drive', fileId: 'x' }, albumId: theirAlbum.id }),
    ).rejects.toThrow(NotFoundException);
  });

  it('associates and disassociates an existing photo without duplicating (N:M)', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

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
    const theirAlbum = await albumRepository.create({
      ownerId: OTHER_USER,
      name: 'X',
    });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await expect(
      service.associate(OWNER, theirAlbum.id, photo.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('associating someone else´s photo to my own album returns 404', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const myAlbum = await albumRepository.create({ ownerId: OWNER, name: 'X' });
    const theirPhoto = await photoRepository.create({
      ownerId: OTHER_USER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await expect(
      service.associate(OWNER, myAlbum.id, theirPhoto.id),
    ).rejects.toThrow(NotFoundException);
  });

  it('lists the caller´s library independent of albums (D11)', async () => {
    const { service, photoRepository } = buildService();
    await photoRepository.create({ ownerId: OWNER, storageRef: { provider: 'google-drive', fileId: 'a' } });
    await photoRepository.create({ ownerId: OWNER, storageRef: { provider: 'google-drive', fileId: 'b' } });
    await photoRepository.create({ ownerId: OTHER_USER, storageRef: { provider: 'google-drive', fileId: 'c' } });

    const library = await service.listLibrary(OWNER);

    expect(library.map((p) => p.storageRef.fileId).sort()).toEqual(['a', 'b']);
  });

  it('deleting a photo removes it from ALL albums and forgets it, but never touches Drive', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const albumA = await albumRepository.create({ ownerId: OWNER, name: 'A' });
    const albumB = await albumRepository.create({ ownerId: OWNER, name: 'B' });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
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
    const photo1 = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    const photo2 = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'y' },
    });
    await albumRepository.addPhoto(album.id, photo1.id);
    await albumRepository.addPhoto(album.id, photo2.id);

    await service.deletePhoto(OWNER, photo1.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([photo2.id]);
  });

  it('deleting someone else´s photo returns a uniform 404', async () => {
    const { service, photoRepository } = buildService();
    const theirPhoto = await photoRepository.create({
      ownerId: OTHER_USER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await expect(service.deletePhoto(OWNER, theirPhoto.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  // --- spec05-colaboradores.md: contribution and removal by role ---

  it('a collaborator can register a photo directly into the album (owner of the Photo = collaborator)', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);

    const photo = await service.register(COLLABORATOR, {
      storageRef: { provider: 'google-drive', fileId: 'collab-file' },
      albumId: album.id,
    });

    expect(photo.ownerId).toBe(COLLABORATOR);
    expect(await albumRepository.listPhotoIds(album.id)).toEqual([photo.id]);
  });

  it('a collaborator can associate their OWN existing photo to the album', async () => {
    const { service, albumRepository, photoRepository, membershipRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);
    const photo = await photoRepository.create({
      ownerId: COLLABORATOR,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await service.associate(COLLABORATOR, album.id, photo.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([photo.id]);
  });

  it('a collaborator cannot associate a photo they do not own, even into an album they belong to', async () => {
    const { service, albumRepository, photoRepository, membershipRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);
    const ownersPhoto = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await expect(
      service.associate(COLLABORATOR, album.id, ownersPhoto.id),
    ).rejects.toThrow(NotFoundException);
  });

  it("a user who isn't owner or collaborator cannot contribute to the album (uniform 404)", async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Privado',
    });

    await expect(
      service.register(OTHER_USER, { storageRef: { provider: 'google-drive', fileId: 'x' }, albumId: album.id }),
    ).rejects.toThrow(NotFoundException);
  });

  it('the owner can remove ANY photo from the album, including a collaborator´s (D4) — only the relation goes', async () => {
    const { service, albumRepository, photoRepository, membershipRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);
    const collaboratorsPhoto = await photoRepository.create({
      ownerId: COLLABORATOR,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    await albumRepository.addPhoto(album.id, collaboratorsPhoto.id);

    await service.disassociate(OWNER, album.id, collaboratorsPhoto.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([]);
    // The photo (and, by extension, the collaborator's Drive file) survives.
    await expect(
      photoRepository.findById(collaboratorsPhoto.id),
    ).resolves.toEqual(collaboratorsPhoto);
  });

  it('a collaborator can only remove their OWN contributions, not someone else´s (uniform 404)', async () => {
    const { service, albumRepository, photoRepository, membershipRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);
    const ownersPhoto = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'owner-file' },
    });
    await albumRepository.addPhoto(album.id, ownersPhoto.id);

    await expect(
      service.disassociate(COLLABORATOR, album.id, ownersPhoto.id),
    ).rejects.toThrow(NotFoundException);
    // Nothing was removed.
    expect(await albumRepository.listPhotoIds(album.id)).toEqual([
      ownersPhoto.id,
    ]);
  });

  // --- spec07-disponibilidad.md: reporte de disponibilidad ---

  it('reports a photo as unavailable and stamps availabilityCheckedAt', async () => {
    const { service, photoRepository } = buildService();
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    expect(photo.availabilityCheckedAt).toBeUndefined();

    const updated = await service.reportAvailability(
      OWNER,
      photo.id,
      'unavailable',
    );

    expect(updated.availability).toBe('unavailable');
    expect(updated.availabilityCheckedAt).toBeInstanceOf(Date);
    await expect(photoRepository.findById(photo.id)).resolves.toEqual(
      updated,
    );
  });

  it('recovers a photo: reporting "available" over a previously "unavailable" one (D9)', async () => {
    const { service, photoRepository } = buildService();
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    await service.reportAvailability(OWNER, photo.id, 'unavailable');

    const recovered = await service.reportAvailability(
      OWNER,
      photo.id,
      'available',
    );

    expect(recovered.availability).toBe('available');
  });

  it('reporting on someone else´s photo returns a uniform 404, availability untouched', async () => {
    const { service, photoRepository } = buildService();
    const theirPhoto = await photoRepository.create({
      ownerId: OTHER_USER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });

    await expect(
      service.reportAvailability(OWNER, theirPhoto.id, 'unavailable'),
    ).rejects.toThrow(NotFoundException);
    await expect(photoRepository.findById(theirPhoto.id)).resolves.toEqual(
      theirPhoto,
    );
  });

  it('reporting on a nonexistent photo returns a uniform 404', async () => {
    const { service } = buildService();

    await expect(
      service.reportAvailability(OWNER, 'no-existe', 'unavailable'),
    ).rejects.toThrow(NotFoundException);
  });

  it('batch: applies only to the caller´s own photos, an unowned/nonexistent entry does not break the rest', async () => {
    const { service, photoRepository } = buildService();
    const own1 = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'own-1' },
    });
    const own2 = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'own-2' },
    });
    const theirs = await photoRepository.create({
      ownerId: OTHER_USER,
      storageRef: { provider: 'google-drive', fileId: 'theirs' },
    });

    await service.reportAvailabilityBatch(OWNER, [
      { photoId: own1.id, availability: 'unavailable' },
      { photoId: theirs.id, availability: 'unavailable' },
      { photoId: 'no-existe', availability: 'unavailable' },
      { photoId: own2.id, availability: 'unavailable' },
    ]);

    await expect(photoRepository.findById(own1.id)).resolves.toMatchObject({
      availability: 'unavailable',
    });
    await expect(photoRepository.findById(own2.id)).resolves.toMatchObject({
      availability: 'unavailable',
    });
    // The unowned photo is untouched — not applied, no error raised above.
    await expect(photoRepository.findById(theirs.id)).resolves.toEqual(
      theirs,
    );
  });

  it('reflects availability and availabilityCheckedAt in getForUser-style reads (via the repository the album detail composes with)', async () => {
    const { service, albumRepository, photoRepository } = buildService();
    const album = await albumRepository.create({ ownerId: OWNER, name: 'A' });
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    await albumRepository.addPhoto(album.id, photo.id);

    await service.reportAvailability(OWNER, photo.id, 'unavailable');

    // AlbumsService.getForUser composes AlbumRepository.listPhotoIds +
    // PhotoRepository.findById — exercising findById here is exactly what
    // that read path does; the e2e suite exercises the full HTTP response.
    const reloaded = await photoRepository.findById(photo.id);
    expect(reloaded?.availability).toBe('unavailable');
    expect(reloaded?.availabilityCheckedAt).toBeInstanceOf(Date);
  });

  it('reflects recovery in listLibrary (D11) — unavailable photos are NOT filtered out', async () => {
    const { service, photoRepository } = buildService();
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    await service.reportAvailability(OWNER, photo.id, 'unavailable');

    const library = await service.listLibrary(OWNER);

    expect(library).toHaveLength(1);
    expect(library[0].availability).toBe('unavailable');
  });

  it('non-regression: renaming/moving in Drive (same storageRef.fileId) never touches availability — the model has no name/path field and reporting only ever keys off storageRef.fileId/photoId', async () => {
    const { service, photoRepository } = buildService();
    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'stable-drive-id' },
    });
    await service.reportAvailability(OWNER, photo.id, 'available');

    // The contract (D9): Memora never models name/path, so a Drive
    // rename/move — which by definition changes only name/path, never the
    // fileId — cannot be represented as a call into this backend at all.
    // We assert the two supporting facts directly: (1) Photo carries no
    // name/path field to change, and (2) the ONLY identifier the report
    // path uses to locate the photo is its own `id`/`storageRef.fileId` —
    // never anything name/path-shaped.
    expect(photo).not.toHaveProperty('name');
    expect(photo).not.toHaveProperty('path');
    expect(photo).not.toHaveProperty('fileName');
    expect(photo.storageRef.fileId).toBe('stable-drive-id');

    // Re-reporting "available" again (the only thing a client could do
    // after observing a rename/move — nothing changed from Drive's point of
    // view) leaves availability exactly as it was: still "available".
    const reReported = await service.reportAvailability(
      OWNER,
      photo.id,
      'available',
    );
    expect(reReported.availability).toBe('available');
    expect(reReported.storageRef.fileId).toBe('stable-drive-id');
  });

  it('a collaborator CAN remove their own contribution', async () => {
    const { service, albumRepository, photoRepository, membershipRepository } =
      buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Compartido',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);
    const ownPhoto = await photoRepository.create({
      ownerId: COLLABORATOR,
      storageRef: { provider: 'google-drive', fileId: 'x' },
    });
    await albumRepository.addPhoto(album.id, ownPhoto.id);

    await service.disassociate(COLLABORATOR, album.id, ownPhoto.id);

    expect(await albumRepository.listPhotoIds(album.id)).toEqual([]);
  });
});
