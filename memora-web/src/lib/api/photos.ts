import { apiFetch } from './client';
import type { Photo } from './types';
export const listLibrary = () => apiFetch<Photo[]>('/library');
export const registerPhoto = (storageRef: { fileId: string; provider?: 'google-drive' }, metadata: Record<string, unknown> = {}) => apiFetch<Photo>('/photos', { method: 'POST', body: { storageRef, ...metadata } });
export const reportAvailability = (photoId: string, availability: 'available' | 'unavailable') => apiFetch<Photo>(`/photos/${photoId}/availability`, { method: 'PATCH', body: { availability } });
