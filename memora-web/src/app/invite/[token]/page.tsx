'use client';
import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useAuth } from '@/components/auth-provider';
import { Button, ErrorNotice, Logo } from '@/components/ui';
import { acceptInvitation } from '@/lib/api/collaborators';
import { userFacingError } from '@/lib/api/errors';
export default function InvitePage() {
  const { token } = useParams<{ token: string }>(); const { session } = useAuth(); const router = useRouter(); const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  async function accept() { setBusy(true); try { await acceptInvitation(token); router.push('/dashboard'); } catch (e) { setError(userFacingError(e, 'No se pudo aceptar la invitación.')); } finally { setBusy(false); } }
  return <div className="shell"><header className="topbar"><Logo /></header><main className="page"><div className="card" style={{ maxWidth: 560, margin: '80px auto', textAlign: 'center' }}><span className="eyebrow">Invitación</span><h1>Te han invitado a colaborar</h1><p className="subtle">Únete para ver el álbum y aportar tus propios recuerdos desde Google Drive.</p>{!session ? <Button onClick={() => router.push('/')}>Inicia sesión para continuar</Button> : <Button disabled={busy} onClick={() => void accept()}>{busy ? 'Aceptando…' : 'Aceptar invitación'}</Button>}{error && <ErrorNotice>{error}</ErrorNotice>}</div></main></div>;
}
