import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { ShareLink } from './share-link.model';
import { ShareLinkRepository } from './share-link-repository.interface';

@Injectable()
export class InMemoryShareLinkRepository implements ShareLinkRepository {
  // Keyed by albumId, never by id/token — a `set` on the same key IS the
  // "one row per album, replace on create" behavior (P5), no extra
  // bookkeeping needed to enforce it.
  private readonly byAlbumId = new Map<string, ShareLink>();

  async create(input: { albumId: string; token: string }): Promise<ShareLink> {
    const link: ShareLink = {
      id: randomUUID(),
      albumId: input.albumId,
      token: input.token,
      status: 'active',
      createdAt: new Date(),
    };
    this.byAlbumId.set(input.albumId, link);
    return link;
  }

  async findByAlbumId(albumId: string): Promise<ShareLink | null> {
    return this.byAlbumId.get(albumId) ?? null;
  }

  async findByToken(token: string): Promise<ShareLink | null> {
    for (const link of this.byAlbumId.values()) {
      if (link.token === token) {
        return link;
      }
    }
    return null;
  }

  async revoke(albumId: string): Promise<void> {
    const existing = this.byAlbumId.get(albumId);
    if (!existing || existing.status === 'revoked') {
      return;
    }
    this.byAlbumId.set(albumId, { ...existing, status: 'revoked' });
  }

  async deleteByAlbumId(albumId: string): Promise<void> {
    this.byAlbumId.delete(albumId);
  }
}
