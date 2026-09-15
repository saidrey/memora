import { NotFoundException } from '@nestjs/common';
import { AlbumsService } from './albums.service';
import { InMemoryAlbumRepository } from './in-memory-album.repository';
import { InMemoryPhotoRepository } from './photos/in-memory-photo.repository';
import { AlbumAccessService } from './collaborators/album-access.service';
import { InMemoryMembershipRepository } from './collaborators/in-memory-membership.repository';
import { InMemoryInvitationRepository } from './collaborators/in-memory-invitation.repository';
import { InMemoryShareLinkRepository } from './shared/in-memory-share-link.repository';
import { InMemoryNfcQrTagRepository } from './nfc-qr/in-memory-nfc-qr-tag.repository';

function buildService() {
  const albumRepository = new InMemoryAlbumRepository();
  const photoRepository = new InMemoryPhotoRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const invitationRepository = new InMemoryInvitationRepository();
  const shareLinkRepository = new InMemoryShareLinkRepository();
  const nfcQrTagRepository = new InMemoryNfcQrTagRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const service = new AlbumsService(
    albumRepository,
    photoRepository,
    membershipRepository,
    invitationRepository,
    shareLinkRepository,
    nfcQrTagRepository,
    albumAccess,
  );
  return {
    service,
    albumRepository,
    photoRepository,
    membershipRepository,
    invitationRepository,
    shareLinkRepository,
    nfcQrTagRepository,
  };
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
      visibility: 'PRIVATE',
      photoCount: 0,
      createdAt: expect.any(Date),
      updatedAt: expect.any(Date),
    });
  });

  it('creates an album with an explicit visibility (D17)', async () => {
    const { service } = buildService();

    const album = await service.create(OWNER, 'Público', 'PUBLIC');

    expect(album.visibility).toBe('PUBLIC');
  });

  it('lists only the caller´s own albums, with role "owner"', async () => {
    const { service } = buildService();
    await service.create(OWNER, 'Mío 1');
    await service.create(OWNER, 'Mío 2');
    await service.create(OTHER_USER, 'De otra persona');

    const albums = await service.listForUser(OWNER);

    expect(albums).toHaveLength(2);
    expect(albums.map((a) => a.name).sort()).toEqual(['Mío 1', 'Mío 2']);
    expect(albums.every((a) => a.role === 'owner')).toBe(true);
  });

  it('gets an owned album with its (currently empty) photos', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'Mi álbum');

    const detail = await service.getForUser(OWNER, created.id);

    expect(detail.photos).toEqual([]);
    expect(detail.photoCount).toBe(0);
  });

  it('renames an album owned by the caller', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'Nombre viejo');

    const renamed = await service.update(OWNER, created.id, {
      name: 'Nombre nuevo',
    });

    expect(renamed.name).toBe('Nombre nuevo');
  });

  it('returns 404 for a nonexistent album', async () => {
    const { service } = buildService();

    await expect(service.getForUser(OWNER, 'does-not-exist')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('returns 404 (not 403) for someone else´s album, to a get/update/delete alike', async () => {
    const { service } = buildService();
    const theirs = await service.create(OTHER_USER, 'No es tuyo');

    await expect(service.getForUser(OWNER, theirs.id)).rejects.toThrow(
      NotFoundException,
    );
    await expect(
      service.update(OWNER, theirs.id, { name: 'Intento de renombrar' }),
    ).rejects.toThrow(NotFoundException);
    await expect(service.delete(OWNER, theirs.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  // --- spec09-compartir-visor.md: visibility (D17) ---

  it('changes visibility for the owner via update()', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'X');
    expect(created.visibility).toBe('PRIVATE');

    const updated = await service.update(OWNER, created.id, {
      visibility: 'PUBLIC',
    });

    expect(updated.visibility).toBe('PUBLIC');
    expect(updated.name).toBe('X'); // untouched when not sent
  });

  it('a non-owner cannot change visibility either (uniform 404)', async () => {
    const { service } = buildService();
    const theirs = await service.create(OTHER_USER, 'No es tuyo');

    await expect(
      service.update(OWNER, theirs.id, { visibility: 'PUBLIC' }),
    ).rejects.toThrow(NotFoundException);
  });

  it('update() can change name and visibility together in one call', async () => {
    const { service } = buildService();
    const created = await service.create(OWNER, 'Antes');

    const updated = await service.update(OWNER, created.id, {
      name: 'Después',
      visibility: 'PUBLIC',
    });

    expect(updated.name).toBe('Después');
    expect(updated.visibility).toBe('PUBLIC');
  });

  it('deleting an album removes only ITS photo relations — a photo in two albums stays in the other (D16)', async () => {
    const { service, albumRepository, photoRepository } = buildService();

    const photo = await photoRepository.create({
      ownerId: OWNER,
      storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
    });
    const albumA = await service.create(OWNER, 'Álbum A');
    const albumB = await service.create(OWNER, 'Álbum B');
    await albumRepository.addPhoto(albumA.id, photo.id);
    await albumRepository.addPhoto(albumB.id, photo.id);

    await service.delete(OWNER, albumA.id);

    // Album A is gone entirely.
    await expect(service.getForUser(OWNER, albumA.id)).rejects.toThrow(
      NotFoundException,
    );

    // Album B keeps the photo — the relation to A's deletion didn't leak.
    const remaining = await service.getForUser(OWNER, albumB.id);
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

  // --- spec05-colaboradores.md: membership-aware reads and cascade delete ---

  it('includes albums where the caller collaborates, with role "collaborator"', async () => {
    const { service, membershipRepository } = buildService();
    const owned = await service.create(OWNER, 'Mío');
    const theirs = await service.create(OTHER_USER, 'De otra persona');
    await membershipRepository.addCollaborator(theirs.id, OWNER);

    const albums = await service.listForUser(OWNER);

    expect(albums).toHaveLength(2);
    const roleById = new Map(albums.map((a) => [a.id, a.role]));
    expect(roleById.get(owned.id)).toBe('owner');
    expect(roleById.get(theirs.id)).toBe('collaborator');
  });

  it('lets a collaborator (not just the owner) read the album detail', async () => {
    const { service, membershipRepository } = buildService();
    const theirs = await service.create(OTHER_USER, 'De otra persona');
    await membershipRepository.addCollaborator(theirs.id, OWNER);

    const detail = await service.getForUser(OWNER, theirs.id);

    expect(detail.photos).toEqual([]);
  });

  it('a user with no membership at all still gets a uniform 404', async () => {
    const { service, membershipRepository } = buildService();
    const theirs = await service.create(OTHER_USER, 'De otra persona');
    // A third, unrelated user — never made a collaborator.
    await membershipRepository.addCollaborator(theirs.id, 'someone-else');

    await expect(service.getForUser(OWNER, theirs.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('deleting an album cleans up its memberships and invitations too (D16)', async () => {
    const { service, membershipRepository, invitationRepository } =
      buildService();
    const album = await service.create(OWNER, 'A borrar');
    await membershipRepository.addCollaborator(album.id, OTHER_USER);
    await invitationRepository.create({
      albumId: album.id,
      token: 'a-token',
      createdBy: OWNER,
      expiresAt: new Date(Date.now() + 86_400_000),
    });

    await service.delete(OWNER, album.id);

    expect(await membershipRepository.listCollaborators(album.id)).toEqual([]);
    expect(await invitationRepository.listByAlbum(album.id)).toEqual([]);
  });

  it('deleting an album also removes its share link (spec09)', async () => {
    const { service, shareLinkRepository } = buildService();
    const album = await service.create(OWNER, 'A borrar');
    await shareLinkRepository.create({ albumId: album.id, token: 'tok-1' });

    await service.delete(OWNER, album.id);

    expect(await shareLinkRepository.findByAlbumId(album.id)).toBeNull();
  });

  it('deleting an album also hard-deletes its NFC/QR tags (spec10, D16)', async () => {
    const { service, nfcQrTagRepository } = buildService();
    const album = await service.create(OWNER, 'A borrar');
    const tag = await nfcQrTagRepository.create({
      albumId: album.id,
      type: 'NFC',
      token: 'nfc-tok-1',
    });

    await service.delete(OWNER, album.id);

    expect(await nfcQrTagRepository.findById(tag.id)).toBeNull();
  });
});
