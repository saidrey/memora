import { NotFoundException } from '@nestjs/common';
import { InMemoryAlbumRepository } from '../in-memory-album.repository';
import { AlbumAccessService } from './album-access.service';
import { InMemoryMembershipRepository } from './in-memory-membership.repository';
import { CollaboratorsService } from './collaborators.service';

function buildService() {
  const albumRepository = new InMemoryAlbumRepository();
  const membershipRepository = new InMemoryMembershipRepository();
  const albumAccess = new AlbumAccessService(
    albumRepository,
    membershipRepository,
  );
  const service = new CollaboratorsService(membershipRepository, albumAccess);
  return { service, albumRepository, membershipRepository };
}

const OWNER = 'owner-1';
const COLLABORATOR = 'collaborator-1';
const OTHER_USER = 'other-1';

describe('CollaboratorsService', () => {
  it('lists collaborators with their role and joinedAt', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);

    const list = await service.list(OWNER, album.id);

    expect(list).toEqual([
      {
        userId: COLLABORATOR,
        role: 'collaborator',
        joinedAt: expect.any(Date),
      },
    ]);
  });

  it('only the owner can list collaborators (uniform 404 otherwise)', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(service.list(OTHER_USER, album.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('the owner removes a collaborator; they lose membership', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);

    await service.remove(OWNER, album.id, COLLABORATOR);

    expect(
      await membershipRepository.findCollaborator(album.id, COLLABORATOR),
    ).toBeNull();
  });

  it('the owner cannot remove themselves via this endpoint', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(service.remove(OWNER, album.id, OWNER)).rejects.toMatchObject({
      getStatus: expect.any(Function),
    });
  });

  it('only the owner can remove a collaborator (uniform 404 otherwise)', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);

    await expect(
      service.remove(OTHER_USER, album.id, COLLABORATOR),
    ).rejects.toThrow(NotFoundException);
  });

  it('a collaborator can leave the album (D5 — same effect as being removed)', async () => {
    const { service, albumRepository, membershipRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });
    await membershipRepository.addCollaborator(album.id, COLLABORATOR);

    await service.leave(COLLABORATOR, album.id);

    expect(
      await membershipRepository.findCollaborator(album.id, COLLABORATOR),
    ).toBeNull();
  });

  it('leaving requires membership — a stranger gets a uniform 404', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(service.leave(OTHER_USER, album.id)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('the owner cannot leave their own album via this endpoint', async () => {
    const { service, albumRepository } = buildService();
    const album = await albumRepository.create({
      ownerId: OWNER,
      name: 'Álbum',
    });

    await expect(service.leave(OWNER, album.id)).rejects.toMatchObject({
      getStatus: expect.any(Function),
    });
  });
});
