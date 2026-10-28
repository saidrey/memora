'use client';
import { useEffect, useState } from 'react';
import { loadDrivePhoto } from '@/lib/api/drive';
import type { Photo } from '@/lib/api/types';
export function DriveImage({ photo }: { photo: Photo }) {
  const [src, setSrc] = useState(''); const [failed, setFailed] = useState(photo.availability === 'unavailable');
  const [expanded, setExpanded] = useState(false);
  // A failed image must not automatically retry when its error state changes.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { let active = true; if (!failed) void loadDrivePhoto(photo).then((url) => { if (active) setSrc(url); }).catch(() => { if (active) setFailed(true); }); return () => { active = false; }; }, [photo.id]);
  useEffect(() => () => { if (src) URL.revokeObjectURL(src); }, [src]);
  if (failed) return <div className="photo-unavailable">Foto no disponible</div>;
  if (!src) return <div className="photo-unavailable">Cargando recuerdo…</div>;
   return <>
    <button className="photo-open" type="button" onClick={() => setExpanded(true)} aria-label="Ver foto en grande">
      {/* Blob URLs from Drive cannot use Next's static image optimizer. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" />
    </button>
    {expanded && <div className="lightbox" role="dialog" aria-modal="true" aria-label="Foto ampliada" onClick={() => setExpanded(false)}>
      <button className="lightbox-close" type="button" onClick={() => setExpanded(false)} aria-label="Cerrar foto">×</button>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img className="lightbox-image" src={src} alt="" onClick={(event) => event.stopPropagation()} />
    </div>}
  </>;
}
