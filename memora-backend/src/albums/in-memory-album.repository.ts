import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { Album } from './album.model';
import { AlbumRepository } from './album-repository.interface';

@Injectable()
export class InMemoryAlbumRepository implements AlbumRepository {
  private readonly albumsById = new Map<string, Album>();
  private readonly photoIdsByAlbumId = new Map<string, Set<string>>();

  async create(input: { ownerId: string; name: string }): Promise<Album> {
    const now = new Date();
    const album: Album = {
      id: randomUUID(),
      ownerId: input.ownerId,
      name: input.name,
      createdAt: now,
      updatedAt: now,
    };
    this.albumsById.set(album.id, album);
    this.photoIdsByAlbumId.set(album.id, new Set());
    return album;
  }

  async findById(id: string): Promise<Album | null> {
    return this.albumsById.get(id) ?? null;
  }

  async findByOwner(ownerId: string): Promise<Album[]> {
    return [...this.albumsById.values()].filter((a) => a.ownerId === ownerId);
  }

  async rename(id: string, name: string): Promise<Album> {
    const updated: Album = {
      ...this.requireAlbum(id),
      name,
      updatedAt: new Date(),
    };
    this.albumsById.set(id, updated);
    return updated;
  }

  async delete(id: string): Promise<void> {
    this.albumsById.delete(id);
    // Only this album's relations — photos, and their relations to any
    // OTHER album, are left untouched (D16).
    this.photoIdsByAlbumId.delete(id);
  }

  async addPhoto(albumId: string, photoId: string): Promise<void> {
    this.requireAlbum(albumId);
    this.photoIdsByAlbumId.get(albumId)?.add(photoId);
  }

  async removePhoto(albumId: string, photoId: string): Promise<void> {
    this.photoIdsByAlbumId.get(albumId)?.delete(photoId);
  }

  async listPhotoIds(albumId: string): Promise<string[]> {
    return [...(this.photoIdsByAlbumId.get(albumId) ?? [])];
  }

  async countPhotos(albumId: string): Promise<number> {
    return this.photoIdsByAlbumId.get(albumId)?.size ?? 0;
  }

  async removePhotoFromAllAlbums(photoId: string): Promise<void> {
    for (const photoIds of this.photoIdsByAlbumId.values()) {
      photoIds.delete(photoId);
    }
  }

  private requireAlbum(id: string): Album {
    const album = this.albumsById.get(id);
    if (!album) {
      throw new Error(`Album ${id} not found`);
    }
    return album;
  }
}
