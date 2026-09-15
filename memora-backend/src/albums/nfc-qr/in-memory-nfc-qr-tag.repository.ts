import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { NfcQrTag, NfcQrTagType } from './nfc-qr-tag.model';
import { NfcQrTagRepository } from './nfc-qr-tag-repository.interface';

@Injectable()
export class InMemoryNfcQrTagRepository implements NfcQrTagRepository {
  // Keyed by id, NOT by albumId/type — several tags can coexist for the
  // same album (see nfc-qr-tag.model.ts). Nothing here dedups by construction.
  private readonly byId = new Map<string, NfcQrTag>();

  async create(input: {
    albumId: string;
    type: NfcQrTagType;
    token: string;
  }): Promise<NfcQrTag> {
    const now = new Date();
    const tag: NfcQrTag = {
      id: randomUUID(),
      albumId: input.albumId,
      type: input.type,
      token: input.token,
      status: 'enabled',
      createdAt: now,
      updatedAt: now,
    };
    this.byId.set(tag.id, tag);
    return tag;
  }

  async findById(id: string): Promise<NfcQrTag | null> {
    return this.byId.get(id) ?? null;
  }

  async findByToken(token: string): Promise<NfcQrTag | null> {
    for (const tag of this.byId.values()) {
      if (tag.token === token) {
        return tag;
      }
    }
    return null;
  }

  async disable(id: string): Promise<NfcQrTag> {
    const existing = this.requireTag(id);
    if (existing.status === 'disabled') {
      return existing;
    }
    const updated: NfcQrTag = {
      ...existing,
      status: 'disabled',
      disabledAt: new Date(),
      updatedAt: new Date(),
    };
    this.byId.set(id, updated);
    return updated;
  }

  async deleteAllForAlbum(albumId: string): Promise<void> {
    for (const tag of this.byId.values()) {
      if (tag.albumId === albumId) {
        this.byId.delete(tag.id);
      }
    }
  }

  // Safety net only, mirrors InMemoryAlbumRepository.rename /
  // InMemoryPhotoRepository.updateAvailability: the service layer already
  // guarantees existence via NfcQrTagsService.requireOwnedTag before
  // calling this, so this should never actually throw in production.
  private requireTag(id: string): NfcQrTag {
    const tag = this.byId.get(id);
    if (!tag) {
      throw new Error(`NfcQrTag ${id} not found`);
    }
    return tag;
  }
}
