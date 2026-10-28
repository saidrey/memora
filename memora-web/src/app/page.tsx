'use client';
import { useEffect, useState } from 'react';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/components/auth-provider';
import { userFacingError } from '@/lib/api/errors';

export default function Home() {
  const { session, loading, signIn } = useAuth();
  const router = useRouter();
  const [error, setError] = useState('');
  useEffect(() => {
    if (session) router.replace('/dashboard');
  }, [router, session]);
  if (session) return null;
  async function handleSignIn() {
    setError('');
    try {
      await signIn();
    } catch (e) {
      setError(userFacingError(e, e instanceof Error ? e.message : 'No se pudo iniciar sesión.'));
    }
  }
  return <main className="login-shell">
    <Image className="login-backdrop" src="/login-back.png" alt="" fill priority sizes="100vw" />
    <section className="login-content" aria-label="Iniciar sesión en Memora">
      <div className="login-brand-art"><Image src="/memora-logo.png" alt="Memora" width={460} height={310} priority /></div>
      <div className="login-copy"><p>Pequeños momentos,</p><strong>grandes recuerdos</strong></div>
      <button className="google-login" type="button" disabled={loading} onClick={() => void handleSignIn()}>
        <Image src="/google.svg" alt="" width={24} height={24} />
        <span>{loading ? 'Conectando con Google…' : 'Continuar con Google'}</span>
        <span className="google-arrow" aria-hidden>›</span>
      </button>
      {error && <div className="login-error" role="alert">{error}</div>}
      <div className="login-features" aria-label="Funciones de Memora">
        <div><span>⌾</span><p>Captura<br />tus momentos</p></div>
        <div><span>♧</span><p>Comparte<br />con quienes amas</p></div>
        <div><span>♡</span><p>Revive<br />siempre</p></div>
      </div>
      <footer className="login-footer">MÁS QUE FOTOS,<br />HISTORIAS QUE SIEMPRE VIVEN <b>♥</b></footer>
    </section>
  </main>;
}
