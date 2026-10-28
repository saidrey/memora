import { Injectable } from '@nestjs/common';
import { AuthService } from '../../auth/auth.service';
import { albumStorageFailed } from './album-storage.errors';
import { AlbumStorage } from './album-storage.interface';

const DRIVE_FILES = 'https://www.googleapis.com/drive/v3/files';

@Injectable()
export class GoogleDriveAlbumStorage implements AlbumStorage {
  constructor(private readonly auth: AuthService) {}

  async createFolder(ownerId: string, name: string) {
    const token = await this.auth.getDriveAccessToken(ownerId);
    const response = await fetch(DRIVE_FILES, { method: 'POST', headers: { Authorization: `Bearer ${token.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ name, mimeType: 'application/vnd.google-apps.folder' }) });
    if (!response.ok) throw albumStorageFailed();
    const body = (await response.json()) as { id?: string };
    if (!body.id) throw albumStorageFailed();
    return { folderId: body.id };
  }

  async deleteFolder(ownerId: string, folderId: string) {
    const token = await this.auth.getDriveAccessToken(ownerId);
    const response = await fetch(`${DRIVE_FILES}/${encodeURIComponent(folderId)}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token.accessToken}` } });
    if (!response.ok && response.status !== 404) throw albumStorageFailed();
  }

  async shareFolder(ownerId: string, folderId: string, email: string) {
    const token = await this.auth.getDriveAccessToken(ownerId);
    const response = await fetch(`${DRIVE_FILES}/${encodeURIComponent(folderId)}/permissions?sendNotificationEmail=true`, { method: 'POST', headers: { Authorization: `Bearer ${token.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ type: 'user', role: 'writer', emailAddress: email }) });
    if (!response.ok) throw albumStorageFailed();
    const body = (await response.json()) as { id?: string };
    if (!body.id) throw albumStorageFailed();
    return { permissionId: body.id };
  }

  async revokeFolderPermission(ownerId: string, folderId: string, permissionId: string) {
    const token = await this.auth.getDriveAccessToken(ownerId);
    const response = await fetch(`${DRIVE_FILES}/${encodeURIComponent(folderId)}/permissions/${encodeURIComponent(permissionId)}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token.accessToken}` } });
    if (!response.ok && response.status !== 404) throw albumStorageFailed();
  }

  async getUploadAuthorization(userId: string, folderId: string) {
    const token = await this.auth.getDriveAccessToken(userId);
    return { provider: 'google-drive' as const, accessToken: token.accessToken, expiresInSeconds: token.expiresInSeconds, folderId };
  }
}
