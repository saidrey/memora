import Link from 'next/link';
import Image from 'next/image';
export function Logo() {
  return <Link href="/" className="brand" aria-label="Memora"><Image src="/memora-logo.png" alt="Memora" width={112} height={40} priority /></Link>;
}
export function Button({ children, variant = 'primary', ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'quiet' | 'danger' }) { return <button className={`button button-${variant}`} {...props}>{children}</button>; }
export function ErrorNotice({ children }: { children: React.ReactNode }) { return <div className="notice error">{children}</div>; }
export function EmptyState({ title, children }: { title: string; children: React.ReactNode }) { return <div className="empty"><span className="empty-orbit">✦</span><h3>{title}</h3><p>{children}</p></div>; }
