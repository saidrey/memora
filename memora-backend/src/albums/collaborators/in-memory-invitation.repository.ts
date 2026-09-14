import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { Invitation, InvitationStatus } from './invitation.model';
import { InvitationRepository } from './invitation-repository.interface';

@Injectable()
export class InMemoryInvitationRepository implements InvitationRepository {
  private readonly byId = new Map<string, Invitation>();

  async create(input: {
    albumId: string;
    token: string;
    createdBy: string;
    expiresAt: Date;
  }): Promise<Invitation> {
    const invitation: Invitation = {
      id: randomUUID(),
      albumId: input.albumId,
      token: input.token,
      createdBy: input.createdBy,
      status: 'pending',
      expiresAt: input.expiresAt,
      createdAt: new Date(),
    };
    this.byId.set(invitation.id, invitation);
    return invitation;
  }

  async findById(id: string): Promise<Invitation | null> {
    return this.byId.get(id) ?? null;
  }

  async findByToken(token: string): Promise<Invitation | null> {
    for (const invitation of this.byId.values()) {
      if (invitation.token === token) {
        return invitation;
      }
    }
    return null;
  }

  async listByAlbum(albumId: string): Promise<Invitation[]> {
    return [...this.byId.values()].filter((i) => i.albumId === albumId);
  }

  async updateStatus(
    id: string,
    status: InvitationStatus,
    acceptedByUserId?: string,
  ): Promise<Invitation> {
    const existing = this.byId.get(id);
    if (!existing) {
      throw new Error(`Invitation ${id} not found`);
    }
    const updated: Invitation = {
      ...existing,
      status,
      acceptedByUserId: acceptedByUserId ?? existing.acceptedByUserId,
    };
    this.byId.set(id, updated);
    return updated;
  }

  async deleteAllForAlbum(albumId: string): Promise<void> {
    for (const [id, invitation] of this.byId) {
      if (invitation.albumId === albumId) {
        this.byId.delete(id);
      }
    }
  }
}
