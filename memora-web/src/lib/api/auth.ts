import { apiFetch } from './client';
import type { Session, User } from './types';

export async function loginWithGoogle(serverAuthCode: string): Promise<Session> {
  const data = await apiFetch<{ sessionAccessToken: string; sessionRefreshToken: string; user: User }>('/auth/google', {
    method: 'POST', body: { serverAuthCode, redirectUri: window.location.origin }, auth: false,
  });
  return { accessToken: data.sessionAccessToken, refreshToken: data.sessionRefreshToken, user: data.user };
}
export async function logout(): Promise<void> { await apiFetch('/auth/logout', { method: 'POST' }); }
export async function getDriveToken(): Promise<{ driveAccessToken: string; expiresIn: number }> {
  return apiFetch('/auth/drive-token', { method: 'POST' });
}
