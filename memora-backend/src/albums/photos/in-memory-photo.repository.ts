import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { Photo } from './photo.model';
import { PhotoRepository } from './photo-repository.interface';

@Injectable()
export class InMemoryPhotoRepository implements PhotoRepository {
  private readonly photosById = new Map<string, Photo>();

  async create(
    input: Omit<Photo, 'id' | 'createdAt' | 'availability'>,
  ): Promise<Photo> {
    const photo: Photo = {
      id: randomUUID(),
      createdAt: new Date(),
      availability: 'available',
      ...input,
    };
    this.photosById.set(photo.id, photo);
    return photo;
  }

  async findById(id: string): Promise<Photo | null> {
    return this.photosById.get(id) ?? null;
  }

  async findByOwner(ownerId: string): Promise<Photo[]> {
    return [...this.photosById.values()].filter((p) => p.ownerId === ownerId);
  }

  async delete(id: string): Promise<void> {
    this.photosById.delete(id);
  }
}
