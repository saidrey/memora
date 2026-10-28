'use client';
import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { DriveImage } from '@/components/drive-image';
import { Button, EmptyState, ErrorNotice, Logo } from '@/components/ui';
import { useAuth } from '@/components/auth-provider';
import { getSharedAlbum } from '@/lib/api/sharing';
import { userFacingError } from '@/lib/api/errors';
import type { SharedAlbum } from '@/lib/api/types';
export default function SharedViewer() {
  const { token } = useParams<{ token: string }>(); const { session, loading: authLoading, signIn } = useAuth(); const [album, setAlbum] = useState<SharedAlbum | null>(null); const [error, setError] = useState(''); const [authError, setAuthError] = useState('');
  useEffect(() => { void getSharedAlbum(token).then(setAlbum).catch((e) => setError(userFacingError(e, 'Este enlace ya no está disponible.'))); }, [token]);
  async function handleSignIn() { setAuthError(''); try { await signIn(); } catch (e) { setAuthError(userFacingError(e, 'No se pudo iniciar sesión.')); } }
  return <div className="shell"><header className="topbar"><Logo /><span className="subtle">Vista compartida</span></header><main className="page">{error ? <ErrorNotice>{error}</ErrorNotice> : !album ? <div className="empty">Abriendo recuerdos…</div> : <><section className="detail-hero"><span className="eyebrow" style={{ color: '#dce4ff' }}>Memora comparte</span><h1>{album.name}</h1><p className="subtle">Solo lectura · fotos protegidas</p></section>{!session ? <div className="auth-gate card"><span className="empty-orbit">⌕</span><h2>Inicia sesión para ver las fotos</h2><p className="subtle">El enlace es público, pero las imágenes de Google Drive requieren una sesión de Memora.</p><Button disabled={authLoading} onClick={() => void handleSignIn()}>{authLoading ? 'Preparando…' : 'Continuar con Google'}</Button>{authError && <ErrorNotice>{authError}</ErrorNotice>}</div> : album.photos.length ? <div className="photos">{album.photos.map((photo) => <div className="photo card" key={photo.id}><DriveImage photo={photo} /></div>)}</div> : <EmptyState title="Este álbum está esperando recuerdos">No hay fotos disponibles para mostrar.</EmptyState>}</>}</main></div>;
}
