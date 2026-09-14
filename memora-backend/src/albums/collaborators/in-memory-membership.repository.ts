import { Injectable } from '@nestjs/common';
import { AlbumMembership } from './album-membership.model';
import { MembershipRepository } from './membership-repository.interface';

@Injectable()
export class InMemoryMembershipRepository implements MembershipRepository {
  // Nested Map (albumId -> userId -> membership) rather than the usual
  // Map<id, Set<relatedId>> N:M pattern (album-repository's photo relation):
  // a membership carries data (joinedAt) beyond mere presence, so a Set
  // isn't enough here — this is the natural extension of that pattern.
  private readonly collaboratorsByAlbumId = new Map<
    string,
    Map<string, AlbumMembership>
  >();

  async addCollaborator(
    albumId: string,
    userId: string,
  ): Promise<AlbumMembership> {
    const existing = this.collaboratorsByAlbumId.get(albumId)?.get(userId);
    if (existing) {
      return existing;
    }
    const membership: AlbumMembership = {
      albumId,
      userId,
      role: 'collaborator',
      joinedAt: new Date(),
    };
    if (!this.collaboratorsByAlbumId.has(albumId)) {
      this.collaboratorsByAlbumId.set(albumId, new Map());
    }
    this.collaboratorsByAlbumId.get(albumId)!.set(userId, membership);
    return membership;
  }

  async findCollaborator(
    albumId: string,
    userId: string,
  ): Promise<AlbumMembership | null> {
    return this.collaboratorsByAlbumId.get(albumId)?.get(userId) ?? null;
  }

  async listCollaborators(albumId: string): Promise<AlbumMembership[]> {
    return [...(this.collaboratorsByAlbumId.get(albumId)?.values() ?? [])];
  }

  async removeCollaborator(albumId: string, userId: string): Promise<void> {
    this.collaboratorsByAlbumId.get(albumId)?.delete(userId);
  }

  async listAlbumIdsForCollaborator(userId: string): Promise<string[]> {
    const albumIds: string[] = [];
    for (const [albumId, members] of this.collaboratorsByAlbumId) {
      if (members.has(userId)) {
        albumIds.push(albumId);
      }
    }
    return albumIds;
  }

  async deleteAllForAlbum(albumId: string): Promise<void> {
    this.collaboratorsByAlbumId.delete(albumId);
  }
}
