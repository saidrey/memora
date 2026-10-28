import { Inject, Injectable, Optional } from '@nestjs/common';
import { AlbumAccessService } from './album-access.service';
import { ALBUM_REPOSITORY, AlbumRepository } from '../album-repository.interface';
import { ALBUM_STORAGE, AlbumStorage } from '../storage/album-storage.interface';
import { drivePermissionMissing } from '../storage/album-storage.errors';
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
    @Optional() @Inject(ALBUM_REPOSITORY) private readonly albums?: AlbumRepository,
    @Optional() @Inject(ALBUM_STORAGE) private readonly storage?: AlbumStorage,
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
    const membership = await this.memberships.findCollaborator(albumId, targetUserId);
    if (!this.albums || !this.storage) {
      await this.memberships.removeCollaborator(albumId, targetUserId);
      return;
    }
    if (membership?.drivePermissionId && album.driveFolderId) {
      await this.storage.revokeFolderPermission(album.ownerId, album.driveFolderId, membership.drivePermissionId);
    } else if (membership) {
      throw drivePermissionMissing();
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
    if (!this.albums || !this.storage) {
      await this.memberships.removeCollaborator(albumId, userId);
      return;
    }
    const album = await this.albums.findById(albumId);
    const membership = await this.memberships.findCollaborator(albumId, userId);
    if (!album?.driveFolderId || !membership?.drivePermissionId) throw drivePermissionMissing();
    await this.storage.revokeFolderPermission(album.ownerId, album.driveFolderId, membership.drivePermissionId);
    await this.memberships.removeCollaborator(albumId, userId);
  }
}
