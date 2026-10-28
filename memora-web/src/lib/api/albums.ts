import { apiFetch } from './client';
import type { AlbumDetail, AlbumListItem, AlbumVisibility } from './types';
export const listAlbums = () => apiFetch<AlbumListItem[]>('/albums');
export const getAlbum = (id: string) => apiFetch<AlbumDetail>(`/albums/${id}`);
export const createAlbum = (name: string) => apiFetch<AlbumDetail>('/albums', { method: 'POST', body: { name } });
export const updateAlbum = (id: string, patch: { name?: string; visibility?: AlbumVisibility }) => apiFetch<AlbumDetail>(`/albums/${id}`, { method: 'PATCH', body: patch });
export const deleteAlbum = (id: string) => apiFetch<void>(`/albums/${id}`, { method: 'DELETE' });
export const addPhotoToAlbum = (albumId: string, photoId: string) => apiFetch<void>(`/albums/${albumId}/photos`, { method: 'POST', body: { photoId } });
export const removePhotoFromAlbum = (albumId: string, photoId: string) => apiFetch<void>(`/albums/${albumId}/photos/${photoId}`, { method: 'DELETE' });
