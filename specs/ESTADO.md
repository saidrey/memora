# Memora — Estado del proyecto (punto de retomada)

Documento de arranque para retomar el trabajo en una sesión nueva. La fuente de verdad son las specs y documentos de esta carpeta; el historial de chat NO es necesario.

## Roles
- **Founder/PO:** el usuario. Decide producto y reglas de negocio.
- **Kiro (Tech Lead):** especifica, valida contra criterios, no inventa reglas de producto.
- **Claude:** implementa según specs y reporta.
- Ciclo: Kiro escribe spec → PO aprueba → Claude implementa → Kiro valida (PASS / PASS WITH NOTES / CHANGES REQUIRED).

## Documentos clave (leer primero)
- **`specs/CONTEXTO-KIRO.md` — MAPA DE ARRANQUE EN FRÍO. Léelo primero: es el único documento necesario para arrancar; los demás se consultan bajo demanda vía sus punteros.**
- `specs/producto-mvp.md` — fuente de verdad funcional (decisiones D1–D16, principios, modelo N:M).
- `specs/backlog-mvp.md` — backlog maestro por módulos (M0–M9) con estado.
- `specs/README.md` — convenciones, decisiones técnicas fijadas, pendientes.

## Metodología con agentes (persistencia entre sesiones)
Para no repetir el arranque en frío cada sesión, el conocimiento se destila en `specs/CONTEXTO-KIRO.md` (mapa+punteros, no resumen sustituto: la fuente de verdad de producto sigue siendo `producto-mvp.md`). Dos agentes custom de Kiro (en `.kiro/agents/`) arrancan leyendo ese mapa:
- **`spec-writer`** — Tech Lead que escribe/refina specs en `specs/`. No inventa producto; trae al PO resumen ejecutivo + decisiones abiertas (opciones+recomendación+impacto). Solo escribe en `specs/`, nunca código.
- **`spec-validator`** — valida lo que implementa Claude con protocolo quirúrgico (build+tests+grep dirigido) y emite PASS / PASS WITH NOTES / CHANGES REQUIRED. Solo lectura de código.
Se seleccionan desde el agent picker del panel de chat. Claude sigue usando Engram (memoria propia de Claude Code); Kiro se apoya en los archivos del repo.

## Stack y reglas técnicas
- Monorepo: `memora-app` (Flutter), `memora-web` (Next.js), `memora-backend` (NestJS 10 + TS).
- Clientes solo hablan con la API del backend. Excepción: subida directa de bytes a Google Drive del usuario (Opción A: el backend nunca maneja bytes).
- Identidad: JWT propio. DB: Postgres (Neon) cuando toque; **por ahora mocks en memoria detrás de interfaces**.
- Aislamiento de entorno: cada subproyecto Node tiene su `.npmrc` (registro público). NO usar `npm -g`, NO cambiar config global, NO tocar `.npmrc`, NO cambiar versión de NestJS/Node.
- Ejecutar OpenSpec/otras herramientas: no aplica (OpenSpec fue removido; usamos specs numeradas en `specs/`).

## Estado de implementación (backend primero, luego app, luego web)

Completado y validado PASS:
- Fundación monorepo + contrato API (`/api/v1`, errores uniformes, correlación, `/health`).
- Auth Google backend (login híbrido, JWT sesión, broker `drive-token` scope `drive.file`). Login real probado en Android físico.
- App: fundación + login Google (probado en dispositivo real).
- Web: fundación (en pausa de desarrollo, sigue siendo parte del MVP).
- **M2** Álbumes backend (`spec03`) — crear/listar/abrir/renombrar/eliminar, N:M foto↔álbum.
- **M3 backend** Fotos (`spec04`) — registro por referencia, biblioteca, asociar/quitar N:M, borrar sin tocar Drive.
- **M4 backend** Colaboradores (`spec05`) — invitación por enlace un solo uso (D12/D13), aceptar, roles Owner/Collaborator (D1), aporte multi-Drive, administrar/quitar/abandonar (D5), D16. PASS 2026-09-14 (70 unit + 67 e2e).
- **M6 backend** Disponibilidad (`spec07`) — verificación perezosa (D9): cliente verifica → backend persiste; reporte individual + batch owner-only, recuperación, `availabilityCheckedAt`, expuesto sin filtrar en álbum/biblioteca. PASS 2026-09-14 (78 unit + 77 e2e).
- **Abstracción de almacenamiento** (`spec08`) — `PhotoStorage` (interfaz + token) con `GoogleDrivePhotoStorage`; `Photo.driveFileId` → `storageRef {provider, fileId}`; ops no soportadas → 501 `STORAGE_OPERATION_UNSUPPORTED`; test de neutralidad de dominio. No migra nada. PASS 2026-09-14 (89 unit + 77 e2e).
- **M7 backend** Compartir/visor (`spec09`) — `Album.visibility` (`PRIVATE`|`PUBLIC`, default `PRIVATE`, D17), enlace estable (uno por álbum, P5), endpoint público `GET /shared/:token` (sin guard: solo fotos disponibles, superficie sin PII, 404 uniforme), test de neutralidad. PASS 2026-09-14 (107 unit + 99 e2e).
- **M8 backend** NFC/QR (`spec10`) — entidad `NfcQrTag` (token opaco 256-bit, soft-delete), endpoints owner-only crear/disable/consultar, endpoint público `GET /n/:token` (sin guard) → redirección 302 al ShareLink activo (resolución indirecta tag→álbum→ShareLink, D14), 404 uniforme. PASS WITH NOTES 2026-09-14 (124 unit + 116 e2e). Notas: rutas separadas por colisión, env var propia, 302 a endpoint interno (deuda menor: en prod debe ir a URL frontend).
- **A1.5 deuda backend** (`spec11`) — `SessionRegistry` elevado a interfaz + token `SESSION_REGISTRY` + `InMemorySessionRegistry`; sin cambio de comportamiento (logout sigue revocando). PASS 2026-09-14 (124 unit + 116 e2e, mismos conteos). **Cierra FASE 1 (backend).**

**Diferido (fuera del MVP hasta nueva decisión):**
- **M5 — Adoptar** ("Guardar en mi biblioteca", D6): ⏸️ diferido a post-MVP (2026-09-14). Confirmado en `spec06-adoptar.md` que la copia cross-Drive no es viable de forma transparente con `drive.file` sin romper decisiones técnicas. En el MVP las fotos de colaboradores se ven mientras estén disponibles en su Drive (D5+D9); no hay copia.

**✅ FASE 1 (BACKEND) CERRADA** (2026-09-14): todos los ítems no diferidos del backend están PASS; M5 ⏸️ diferida a post-MVP.

Siguiente (FASE 2 — app, arranca cuando el PO lo indique):
1. **M3 app** — seleccionar fotos, optimizar (D15), subir bytes directo a Drive con `drive-token`.
2. UI de álbumes / colaboradores (consume M2/M3/M4 backend).
3. A1.5 (parte app): refresco automático del JWT + A1.6 re-autorización de Drive (D10).
Después: web (en pausa).

## Convenciones de validación (para optimizar tokens)
- Validación quirúrgica: correr `npm run build` + tests + grep dirigido a los criterios críticos; lectura profunda de código solo si un test falla o la spec es sensible (auth, borrados, adopción).
- Backend corre en puerto 3000; matar procesos colgados al terminar (`lsof -ti:3000`).
- Tests del backend necesitan env: `JWT_SESSION_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (valores dummy sirven para tests).

## Deuda técnica conocida (no bloqueante)
- Flake residual de e2e (supertest + apps Nest efímeras); `auth.e2e` sin migrar a beforeAll a propósito (muta sesión).
- ~~`SessionRegistry` es provider en memoria; elevar a interfaz antes de desplegar.~~ ✅ Resuelto (spec11: ahora es interfaz + `InMemorySessionRegistry`; falta el adaptador a datastore real, p. ej. Redis/Postgres, antes de desplegar).
- Cifrado real del refresh token en `TokenStore` (hoy frontera documentada).
