import { Inject, Injectable } from '@nestjs/common';
import { AlbumAccessService } from './album-access.service';
import { AlbumRole } from './album-membership.model';
import { cannotLeaveAsOwner, cannotRemoveOwner } from './collaborators.errors';
import {
  MEMBERSHIP_REPOSITORY,
  MembershipRepository,
} from './membership-repository.interface';

export interface CollaboratorListItem {
  userId: string;
  role: AlbumRole;
  joinedAt: Date;
}

/** D1/D5: owner administers collaborators; a collaborator can leave (P1). */
@Injectable()
export class CollaboratorsService {
  constructor(
    @Inject(MEMBERSHIP_REPOSITORY)
    private readonly memberships: MembershipRepository,
    private readonly albumAccess: AlbumAccessService,
  ) {}

  async list(
    ownerId: string,
    albumId: string,
  ): Promise<CollaboratorListItem[]> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    const collaborators = await this.memberships.listCollaborators(albumId);
    return collaborators.map((membership) => ({
      userId: membership.userId,
      role: membership.role,
      joinedAt: membership.joinedAt,
    }));
  }

  /** Owner removes a collaborator. Owner can't remove themselves this way. */
  async remove(
    ownerId: string,
    albumId: string,
    targetUserId: string,
  ): Promise<void> {
    const album = await this.albumAccess.requireOwner(albumId, ownerId);
    if (targetUserId === album.ownerId) {
      throw cannotRemoveOwner();
    }
    await this.memberships.removeCollaborator(albumId, targetUserId);
  }

  /** P1: the collaborator leaves. Same effect as being removed (D5) — their
   *  photos stay in the album. Requires membership (404 uniform otherwise). */
  async leave(userId: string, albumId: string): Promise<void> {
    const { role } = await this.albumAccess.requireMembership(albumId, userId);
    if (role === 'owner') {
      throw cannotLeaveAsOwner();
    }
    await this.memberships.removeCollaborator(albumId, userId);
  }
}
