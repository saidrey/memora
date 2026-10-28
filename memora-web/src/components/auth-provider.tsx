'use client';

import Script from 'next/script';
import { createContext, useContext, useEffect, useState } from 'react';
import { configureSession } from '@/lib/api/client';
import { loginWithGoogle, logout as apiLogout } from '@/lib/api/auth';
import type { Session } from '@/lib/api/types';

declare global {
  interface Window {
    google?: { accounts: { oauth2: { initCodeClient: (config: { client_id: string; scope: string; ux_mode: 'popup'; callback: (response: { code?: string; error?: string }) => void }) => { requestCode: () => void } } } };
  }
}

type AuthContextValue = { session: Session | null; loading: boolean; signIn: () => Promise<void>; signOut: () => Promise<void> };
const AuthContext = createContext<AuthContextValue | null>(null);
const STORAGE_KEY = 'memora.session';

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const restored = JSON.parse(saved) as Session;
        configureSession({
          accessToken: restored.accessToken,
          refreshToken: restored.refreshToken,
        });
        queueMicrotask(() => setSession(restored));
      }
    } catch { localStorage.removeItem(STORAGE_KEY); }
    queueMicrotask(() => setLoading(false));
  }, []);

  useEffect(() => {
    configureSession({
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
      onSessionRefreshed: (access, refresh) => {
        setSession((current) => {
          if (!current) return current;
          const next = { ...current, accessToken: access, refreshToken: refresh };
          localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
          return next;
        });
      },
      onSessionInvalidated: () => { localStorage.removeItem(STORAGE_KEY); setSession(null); },
    });
  }, [session]);

  async function signIn() {
    const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
    if (!clientId) throw new Error('Falta NEXT_PUBLIC_GOOGLE_CLIENT_ID.');
    if (!window.google) throw new Error('Google Identity Services todavía no está listo.');
    const google = window.google;
    await new Promise<void>((resolve, reject) => {
      const client = google.accounts.oauth2.initCodeClient({
        client_id: clientId,
        scope: 'openid email profile https://www.googleapis.com/auth/drive.file',
        ux_mode: 'popup',
        callback: async (response) => {
          if (!response.code) { reject(new Error('No se pudo completar el acceso con Google.')); return; }
          try {
            const next = await loginWithGoogle(response.code);
            // Configure the API client before publishing the session so a
            // dashboard request cannot race the session effect.
            configureSession({
              accessToken: next.accessToken,
              refreshToken: next.refreshToken,
            });
            setSession(next);
            localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
            resolve();
          } catch (error) { reject(error); }
        },
      });
      client.requestCode();
    });
  }

  async function signOut() {
    try { if (session) await apiLogout(); } catch { /* the local session still must be cleared */ }
    localStorage.removeItem(STORAGE_KEY);
    setSession(null);
  }

  return <AuthContext.Provider value={{ session, loading, signIn, signOut }}><Script src="https://accounts.google.com/gsi/client" strategy="afterInteractive" />{children}</AuthContext.Provider>;
}
export function useAuth() { const value = useContext(AuthContext); if (!value) throw new Error('useAuth must be used inside AuthProvider'); return value; }
