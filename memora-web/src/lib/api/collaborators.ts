import { apiFetch } from './client';
import type { Collaborator, Invitation } from './types';
export const listCollaborators = (albumId: string) => apiFetch<Collaborator[]>(`/albums/${albumId}/collaborators`);
export const removeCollaborator = (albumId: string, userId: string) => apiFetch<void>(`/albums/${albumId}/collaborators/${userId}`, { method: 'DELETE' });
export const leaveAlbum = (albumId: string) => apiFetch<void>(`/albums/${albumId}/collaborators/me`, { method: 'DELETE' });
export const createInvitation = (albumId: string) => apiFetch<Invitation>(`/albums/${albumId}/invitations`, { method: 'POST' });
export const listInvitations = (albumId: string) => apiFetch<Invitation[]>(`/albums/${albumId}/invitations`);
export const revokeInvitation = (albumId: string, invitationId: string) => apiFetch<void>(`/albums/${albumId}/invitations/${invitationId}`, { method: 'DELETE' });
export const acceptInvitation = (token: string) => apiFetch<void>(`/invitations/${encodeURIComponent(token)}/accept`, { method: 'POST' });
