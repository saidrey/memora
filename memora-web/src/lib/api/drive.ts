import { getDriveToken } from './auth';
import type { Photo } from './types';

let cached: { token: string; expiresAt: number } | null = null;
async function token(): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 10_000) return cached.token;
  const next = await getDriveToken();
  cached = { token: next.driveAccessToken, expiresAt: Date.now() + next.expiresIn * 1000 };
  return cached.token;
}
export async function loadDrivePhoto(photo: Photo): Promise<string> {
  if (photo.availability === 'unavailable') throw new Error('PHOTO_UNAVAILABLE');
  const response = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(photo.storageRef.fileId)}?alt=media`, {
    headers: { Authorization: `Bearer ${await token()}` }, cache: 'no-store',
  });
  if (!response.ok) throw new Error('PHOTO_UNAVAILABLE');
  return URL.createObjectURL(await response.blob());
}
