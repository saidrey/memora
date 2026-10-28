import { apiFetch } from './client';
import type { SharedAlbum } from './types';
export const createShareLink = (albumId: string) => apiFetch<{ token: string; url: string }>(`/albums/${albumId}/share-link`, { method: 'POST' });
export const revokeShareLink = (albumId: string) => apiFetch<void>(`/albums/${albumId}/share-link`, { method: 'DELETE' });
export const getSharedAlbum = (token: string) => apiFetch<SharedAlbum>(`/shared/${encodeURIComponent(token)}`, { auth: false });
