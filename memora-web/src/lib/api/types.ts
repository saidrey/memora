export type AlbumRole = 'owner' | 'collaborator';
export type AlbumVisibility = 'PRIVATE' | 'PUBLIC';
export type Availability = 'available' | 'unavailable';

export interface User { id: string; email: string; name?: string }
export interface Session { accessToken: string; refreshToken: string; user: User }
export interface StorageRef { provider: 'google-drive'; fileId: string }
export interface Photo {
  id: string; storageRef: StorageRef; width?: number; height?: number;
  mimeType?: string; capturedAt?: string; availability?: Availability;
}
export interface AlbumSummary { id: string; ownerId: string; name: string; photoCount: number; visibility: AlbumVisibility; createdAt: string; updatedAt: string }
export interface AlbumListItem extends AlbumSummary { role: AlbumRole }
export interface AlbumDetail extends AlbumSummary { photos: Photo[] }
export interface SharedAlbum { name: string; photos: Photo[] }
export interface Invitation { id: string; token?: string; url?: string; status: 'pending' | 'accepted' | 'revoked' | 'expired'; expiresAt: string; createdAt: string }
export interface Collaborator { userId: string; role: AlbumRole; joinedAt: string }
