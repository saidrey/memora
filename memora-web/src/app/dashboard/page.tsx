'use client';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/components/auth-provider';
import { Button, EmptyState, ErrorNotice, Logo } from '@/components/ui';
import { createAlbum, listAlbums } from '@/lib/api/albums';
import { userFacingError } from '@/lib/api/errors';
import type { AlbumListItem } from '@/lib/api/types';

export default function Dashboard() {
  const { session, loading: authLoading, signOut } = useAuth(); const router = useRouter();
  const [albums, setAlbums] = useState<AlbumListItem[]>([]); const [loading, setLoading] = useState(true); const [error, setError] = useState(''); const [name, setName] = useState(''); const [creating, setCreating] = useState(false);
  async function load() { try { setError(''); setAlbums(await listAlbums()); } catch (e) { setError(userFacingError(e, 'No pudimos cargar tus álbumes.')); } finally { setLoading(false); } }
  useEffect(() => { if (!authLoading && !session) router.replace('/'); if (session) void Promise.resolve().then(load); }, [authLoading, session, router]);
  if (authLoading || !session) return <div className="shell"><div className="empty">Preparando tu biblioteca…</div></div>;
  async function submit(event: React.FormEvent) { event.preventDefault(); if (!name.trim()) return; setCreating(true); try { const album = await createAlbum(name.trim()); setName(''); await load(); router.push(`/albums/${album.id}`); } catch (e) { setError(userFacingError(e, 'No se pudo crear el álbum.')); } finally { setCreating(false); } }
  return <div className="shell"><header className="topbar"><Logo /><div className="top-actions"><span className="user-chip">{session.user.name || session.user.email}</span><Button variant="quiet" onClick={() => void signOut()}>Salir</Button></div></header><main className="page"><div className="page-heading"><div><span className="eyebrow">Tu espacio</span><h1>Mis álbumes</h1><p className="subtle">{albums.length} álbumes · guarda lo que merece quedarse.</p></div></div><form className="card form" onSubmit={submit}><input className="input" maxLength={100} value={name} onChange={(e) => setName(e.target.value)} placeholder="Nombre del nuevo álbum" /><Button disabled={creating}>{creating ? 'Creando…' : 'Crear álbum'}</Button></form>{error && <ErrorNotice>{error}</ErrorNotice>}{loading ? <div className="empty">Cargando tu biblioteca…</div> : albums.length === 0 ? <EmptyState title="Todo empieza con un álbum">Crea el primero para guardar tus recuerdos.</EmptyState> : <div className="grid">{albums.map((album) => <Link key={album.id} href={`/albums/${album.id}`} className="card album-card"><div><span className="role">{album.role === 'owner' ? 'Propio' : 'Colaborativo'}</span><h2>{album.name}</h2></div><div className="album-meta"><span>{album.photoCount} {album.photoCount === 1 ? 'foto' : 'fotos'}</span><span>→</span></div></Link>)}</div>}</main></div>;
}
