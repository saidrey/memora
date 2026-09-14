# Memora — Backlog Maestro Funcional del MVP

Checklist funcional del MVP, agrupado por módulos. Cada ítem está redactado como algo **verificable por el usuario**. Sirve para validar que el MVP esté realmente completo. Basado en `producto-mvp.md` (fuente de verdad de producto).

**Leyenda de estado:**
- ✅ IMPLEMENTADO (spec PASS)
- 🟡 PARCIAL
- ⬜ PENDIENTE (decidido en producto, sin implementar)

**Prioridad actual del PO:** app + backend primero; web en pausa (su fundación ya está PASS).

---

## M0 — Fundación (transversal)
- ✅ F0.1 Monorepo con `memora-app`, `memora-web`, `memora-backend`.
- ✅ F0.2 Contrato base de API (`/api/v1`, errores uniformes, correlación, `/health`).
- ✅ F0.3 App y web conectan con el backend (capa API + estado de conectividad).

## M1 — Cuenta y autenticación
- ✅ A1.1 Iniciar sesión con Google (sin email/password).
- ✅ A1.2 Cuenta Memora ligada a identidad Google.
- ✅ A1.3 Autorizar Drive (scope `drive.file`).
- ✅ A1.4 Cerrar sesión.
- 🟡 A1.5 Sesión expirada: la app renueva el acceso automáticamente (refresh del JWT). *(backend listo; falta en app)*
- ⬜ A1.6 Autorización de Drive revocada: al operar contra Drive, se pide re-autorizar sin perder la cuenta (D10).

## M2 — Biblioteca personal y álbumes
- 🟡 B2.1 Crear un álbum. *(backend ✅ spec03; falta UI app)*
- 🟡 B2.2 Ver la lista de mis álbumes. *(backend ✅; falta UI app)*
- 🟡 B2.3 Abrir un álbum y ver sus fotos. *(backend ✅; falta UI app — fotos llegan en M3)*
- 🟡 B2.4 Ver mi Biblioteca personal (D11). *(repositorio listo; endpoint HTTP y UI en M3)*
- ✅ B2.5 Una foto puede estar en varios álbumes sin duplicarse (N:M) (D11). *(modelo backend + tests)*
- 🟡 B2.6 Editar nombre del álbum. *(backend ✅; falta UI app)*
- ✅ B2.7 Eliminar álbum → elimina agrupación y relaciones, no las fotos (D16). *(backend + test)*

## M3 — Fotografías
- ⬜ P3.1 Seleccionar fotos del dispositivo (sin modificar/eliminar originales). *(app)*
- ⬜ P3.2 Optimización automática antes de subir (D15). *(app)*
- 🟡 P3.3 Subir la foto al Drive del usuario. *(backend coordina ✅ spec04; subida real de bytes = app)*
- ✅ P3.4 Memora registra `fileId` + metadatos mínimos (D8) y la relación con el álbum. *(backend spec04)*
- 🟡 P3.5 Ver las fotos dentro del álbum (thumbnails/preview). *(backend expone referencias ✅; UI = app)*
- ✅ P3.6 Agregar más fotos a un álbum existente en cualquier momento. *(backend spec04)*
- ✅ P3.7 Quitar una foto propia de un álbum → solo la relación, no el archivo (D3). *(backend spec04)*
- ✅ (extra) Biblioteca personal `GET /library` (D11) y borrar foto de la biblioteca sin tocar Drive. *(backend spec04)*

## M4 — Álbumes compartidos y colaboradores
- ⬜ C4.1 Owner invita colaborador mediante enlace de invitación (D12).
- ⬜ C4.2 Invitado abre enlace → Google Login → acepta → pasa a Collaborator.
- ⬜ C4.3 Invitaciones con expiración y revocables por el Owner (D13).
- ⬜ C4.4 Collaborator ve todas las fotos del álbum y aporta las suyas (permisos D1).
- ⬜ C4.5 Fotos del colaborador se guardan en SU propio Drive (multi-Drive).
- ⬜ C4.6 Owner administra colaboradores (ver lista, quitar).
- ⬜ C4.7 Owner quita del álbum una foto de un colaborador → solo la relación, no el archivo ajeno (D4).
- ⬜ C4.8 Colaborador abandona el álbum: deja de aportar; sus fotos históricas permanecen mientras estén disponibles (D5).

## M5 — Adoptar / "Guardar en mi biblioteca"
- ⬜ G5.1 El Owner selecciona una foto de un colaborador y la "Guarda en mi biblioteca" → crea una **copia** en el Drive del Owner (D6).
- ⬜ G5.2 La copia pertenece al Owner y sobrevive aunque el colaborador se vaya o borre su original.
- ⬜ G5.3 El original del colaborador queda intacto.

## M6 — Disponibilidad de archivos (Drive)
- ⬜ D6.1 Al mostrar una foto, Memora verifica disponibilidad (perezosa, sin sync activa) (D9).
- ⬜ D6.2 Archivo borrado/en papelera/sin permisos → se marca "no disponible" y no se muestra como disponible.
- ⬜ D6.3 Renombrar/mover en Drive NO rompe la referencia (usa `fileId`).
- ⬜ D6.4 Si el archivo vuelve a estar disponible, se puede revalidar/recuperar.

## M7 — Compartir y visor
- ⬜ V7.1 Compartir un álbum genera un enlace estable de acceso al visor.
- ⬜ V7.2 Cualquiera con el enlace puede ver el álbum sin login (D2); no es indexable/descubrible.
- ⬜ V7.3 Visor: abrir álbum, ver y navegar fotos, responsive móvil. *(web)*
- ⬜ V7.4 La gestión/modificación del álbum requiere autenticación.

## M8 — NFC y QR
- ⬜ N8.1 Asociar un NFC a un álbum ya creado; el NFC contiene la URL estable `https://memora.app/n/{identifier}` (D14).
- ⬜ N8.2 Asociar un QR al mismo álbum; QR y NFC llevan al mismo álbum.
- ⬜ N8.3 Memora resuelve el identificador → álbum (nunca apunta directo a Drive; identificador no revela info sensible).
- ⬜ N8.4 Posibilidad de bloquear el NFC tras programarlo.

## M9 — Plataformas
- ⬜ X9.1 App Flutter: captura + gestión completa (login, Drive, álbumes, fotos, compartir, colaboradores, NFC/QR) (D7).
- ⬜ X9.2 Web Next.js — Visor (M7) + Plataforma autenticada (ver/crear/gestionar álbumes, compartir, colaboradores, gestión básica de fotos) (D7). *(en pausa según prioridad)*

---

## Dependencias (orden lógico de construcción)

```
M0 (fundación) ─ ✅ hecho
      │
M1 (auth) ─ ✅ (falta A1.5 refresh, A1.6 re-auth Drive)
      │
      ├── M2 (biblioteca + álbumes) ──┐
      │                               │
      └── M3 (fotos: subir/optimizar) ┘  (M3 necesita M2 para asociar a álbum)
                    │
        ┌───────────┼─────────────┬───────────────┐
        │           │             │               │
     M4 (colab)  M6 (disponib.) M7 (visor)   M8 (NFC/QR)
        │
     M5 (adoptar)  (necesita M4)
```

- M2 y M3 son la base; casi todo lo demás depende de tener álbumes + fotos.
- M4 (colaboradores) habilita M5 (adoptar).
- M7 (visor) y M8 (NFC/QR) dependen de que exista un álbum con fotos.
- M9 es transversal (dónde vive cada capacidad).

## Orden de especificación recomendado (Tech Lead)
1. M2 — Biblioteca + Álbumes (crear/ver/abrir/eliminar).
2. M3 — Fotos (seleccionar/optimizar/subir/ver, quitar).
3. M6 — Disponibilidad (se integra con la visualización de M3).
4. M4 — Colaboradores (invitación/aceptar/permisos/abandonar).
5. M5 — Adoptar.
6. M7 — Visor (web) + M8 — NFC/QR.
7. M9 — completar reparto web cuando se reactive.
