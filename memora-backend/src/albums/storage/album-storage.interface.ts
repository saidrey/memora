export const ALBUM_STORAGE = Symbol('ALBUM_STORAGE');

export interface AlbumFolder {
  folderId: string;
}

export interface AlbumStorage {
  createFolder(ownerId: string, name: string): Promise<AlbumFolder>;
  deleteFolder(ownerId: string, folderId: string): Promise<void>;
  shareFolder(ownerId: string, folderId: string, email: string): Promise<{ permissionId: string }>;
  revokeFolderPermission(ownerId: string, folderId: string, permissionId: string): Promise<void>;
  getUploadAuthorization(userId: string, folderId: string): Promise<{
    provider: 'google-drive';
    accessToken: string;
    expiresInSeconds: number;
    folderId: string;
  }>;
}

/** Keeps existing direct unit tests provider-neutral; production wiring uses GoogleDriveAlbumStorage. */
export class NoopAlbumStorage implements AlbumStorage {
  async createFolder(): Promise<AlbumFolder> { return { folderId: '' }; }
  async deleteFolder(): Promise<void> {}
  async shareFolder(): Promise<{ permissionId: string }> { return { permissionId: 'local-permission' }; }
  async revokeFolderPermission(): Promise<void> {}
  async getUploadAuthorization(): Promise<never> { throw new Error('No upload authorization provider configured'); }
}
