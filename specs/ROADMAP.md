# ROADMAP de specs — Memora (secuencia de trabajo)

> **Para qué sirve.** Es la **cola de trabajo**: dice qué spec toca a continuación para que el PO no tenga que recordarlo. Basta con decir **"continuemos con la siguiente spec"** y el agente `spec-writer` lee este archivo, ubica el siguiente ítem `⬜ PENDIENTE` y arranca por ahí.
>
> **Orden de capas (regla del PO):** se completa **todo el backend primero**, luego **app**, luego **web**. No se mezclan capas: no se arranca la parte de app de un módulo hasta que el backend correspondiente esté PASS y el PO dé el visto para pasar de capa.
>
> **Cómo se marca el estado:** ⬜ PENDIENTE · 🟡 EN CURSO (spec escrita/aprobada o en implementación) · ✅ PASS (validado por Kiro). El `spec-writer` y el `spec-validator` actualizan este archivo al avanzar.

---

## FASE 1 — BACKEND (en curso)

| # | Módulo | Spec | Estado |
|---|--------|------|--------|
| 1 | M0 Fundación | `memora-backend/spec01-fundacion-backend.md` | ✅ PASS |
| 2 | M1 Auth Google | `memora-backend/spec02-autenticacion-google.md` | ✅ PASS |
| 3 | M2 Álbumes/Biblioteca | `memora-backend/spec03-biblioteca-albumes.md` | ✅ PASS |
| 4 | M3 Fotos | `memora-backend/spec04-fotografias.md` | ✅ PASS |
| 5 | **M4 Colaboradores** | `memora-backend/spec05-colaboradores.md` | ✅ PASS |
| 6 | M5 Adoptar / "Guardar en mi biblioteca" | `memora-backend/spec06-adoptar.md` | ⏸️ DIFERIDA A POST-MVP (no viable de forma transparente con `drive.file`; decisión del PO 2026-09-14) |
| 7 | **M6 Disponibilidad de archivos (Drive)** | `memora-backend/spec07-disponibilidad.md` | ✅ PASS |
| 8 | **Abstracción de almacenamiento (`PhotoStorage`)** | `memora-backend/spec08-abstraccion-almacenamiento.md` | ✅ PASS |
| 9 | **M7 Compartir / Visor** | `memora-backend/spec09-compartir-visor.md` | ✅ PASS |
| 10 | **M8 NFC/QR** (parte backend: asociar + resolución) | `memora-backend/spec10-nfc-qr.md` | ✅ PASS (with notes) |
| 11 | A1.5 deuda backend: `SessionRegistry` → interfaz + mock | `memora-backend/spec11-session-registry-interface.md` | ✅ PASS |

**✅ FASE 1 (BACKEND) CERRADA** (2026-09-14). Todos los ítems no diferidos están PASS; M5 ⏸️ diferida a post-MVP. **➡️ SIGUIENTE:** FASE 2 (app), que arranca cuando el PO lo indique — ítem **A** (M3 app: seleccionar/optimizar/subir fotos con `drive-token`).

> Cuando **todos** los ítems no diferidos de FASE 1 estén ✅ PASS, el PO decide pasar a FASE 2. M5 queda fuera del alcance del MVP hasta nueva decisión.

---

## FASE 2 — APP (Flutter) — arranca cuando el PO lo indique

Orden tentativo (se detalla al llegar; cada uno tendrá su spec en `memora-app/`):

| # | Alcance | Estado |
|---|---------|--------|
| A | M3 app: seleccionar fotos, optimizar (D15), subir bytes directo a Drive usando `drive-token` — `memora-app/spec03-fotografias.md` | ✅ VALIDADO EN DISPOSITIVO (PO, 2026-09-14: sube a carpeta "Memora" en Drive) |
| B | UI de álbumes: crear/ver/abrir/renombrar/eliminar (consume M2/M3 backend) — `memora-app/spec04-ui-albumes.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide en dispositivo) |
| C | UI de colaboradores: invitar/aceptar/administrar/abandonar (consume M4 backend) — `memora-app/spec05-ui-colaboradores.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide) |
| D | ~~UI de adopción "Guardar en mi biblioteca" (consume M5)~~ | ⏸️ DIFERIDA (M5 fuera del MVP) |
| E | A1.5 refresh de sesión en app + A1.6 re-autorización de Drive (D10) — `memora-app/spec06-sesion-y-reauth-drive.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide) |
| F | Compartir/visor desde app + NFC/QR (consume M7/M8) — `memora-app/spec07-compartir-nfc-qr.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide) |
| G | Visor de foto a pantalla completa in-app (zoom/pan/swipe) — `memora-app/spec08-visor-foto-inapp.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide) |
| H | Programar etiqueta NFC física desde la app (M8, escritura NDEF nativa) — `memora-app/spec09-programar-nfc.md` | 🟡 EN CURSO (spec APROBADA → pendiente de que Claude implemente y el PO valide) |

Ya PASS en app: fundación (`memora-app/spec01`), login Google (`memora-app/spec02`).

---

## FASE 3 — WEB (Next.js) — EN PAUSA hasta aviso del PO

| # | Alcance | Estado |
|---|---------|--------|
| W1 | Visor público (acceso enlace/QR/NFC sin login, D2) | ⬜ PENDIENTE |
| W2 | Plataforma autenticada (ver/crear/gestionar álbumes, compartir, colaboradores, gestión básica de fotos) | ⬜ PENDIENTE |

Ya PASS en web: fundación (`memora-web/spec01`).

---

## Reglas de avance (para los agentes)

1. "Siguiente spec" = el primer ítem `⬜ PENDIENTE` de la **fase activa** (hoy: FASE 1 backend), respetando el orden de la tabla. **Se saltan los ítems ⏸️ DIFERIDOS** (no cuentan para el MVP hasta nueva decisión del PO).
2. No se salta de fase: FASE 2 solo empieza cuando FASE 1 está completa **y** el PO lo autoriza. Igual FASE 2 → FASE 3.
3. Al **congelar** una spec nueva, el `spec-writer` la marca 🟡 y le asigna su número de archivo real.
4. Al dar **PASS**, el `spec-validator` marca ✅ aquí y en `ESTADO.md`/`backlog-mvp.md`, y actualiza el índice de `CONTEXTO-KIRO.md`.
5. La fuente de verdad del **contenido** de cada módulo sigue siendo `producto-mvp.md` (D1–D16) y `backlog-mvp.md`; este archivo solo ordena la **secuencia**.
