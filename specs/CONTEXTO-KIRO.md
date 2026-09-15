# CONTEXTO-KIRO — Mapa de arranque en frío (Tech Lead)

> **Qué es este documento.** Un **mapa con punteros** para que Kiro (o un agente con rol Tech Lead) arranque en frío leyendo **un solo archivo** en vez de releer todo. **NO es un resumen que reemplace las fuentes de verdad.** Es un índice: dice *qué existe y dónde está la verdad completa*.
>
> **Regla de precedencia (crítica, no negociable).** Ante cualquier duda de **producto**, la fuente de verdad es **`producto-mvp.md`** (decisiones D1–D17), nunca este mapa. Ante cualquier duda de **estado**, la fuente es **`ESTADO.md`** y las specs con su sello de validación. Ante cualquier duda de **convenciones**, la fuente es **`README.md`** (raíz) y **`specs/README.md`**. Si este mapa y una fuente se contradicen, **gana la fuente**; corrige este mapa.
>
> **Este documento no cierra decisiones ni inventa reglas.** Solo apunta a dónde están.

---

## 0. Cómo usar este mapa (protocolo de arranque)

1. Lee este archivo completo (es corto a propósito).
2. Para saber **qué toca ahora**, lee `specs/ROADMAP.md` (la cola de trabajo). "Siguiente spec" = primer ítem PENDIENTE de la fase activa (backend → app → web).
3. Identifica el módulo/spec en el que vas a trabajar (sección 4 y 5).
4. Abre **solo** las fuentes que ese trabajo requiera (los punteros de las secciones 2, 3 y 6). No releas todo.
5. Si vas a tocar código, usa el **Mapa de código** (sección 6) para saber qué patrón replicar antes de leer archivos.

---

## 1. Roles y ciclo de trabajo

- **Founder/PO** (el usuario): decide producto y reglas de negocio. Única autoridad sobre D1–D17.
- **Kiro (Tech Lead):** especifica, valida contra criterios, **no inventa reglas de producto**. Si falta una decisión, la pregunta con **opciones + recomendación + impacto**.
- **Claude:** implementa según specs y reporta. No redefine producto.
- **Ciclo (metodología vigente desde 2026-09-14):** Kiro escribe spec → PO aprueba (incl. decisiones abiertas) → Kiro entrega prompt a Claude → Claude implementa → **el PO valida en el dispositivo/entorno real**. **Kiro ya NO valida por defecto** (no se corre `spec-validator`) para ahorrar tokens; la validación por Kiro queda **opcional/bajo demanda** si el PO la pide. (La FASE 1 backend ya cerrada sí fue validada por Kiro en su momento.)
- **Capas, en orden:** backend primero → app → web.

> Fuente completa del rol y ciclo: `ESTADO.md` §Roles y `specs/README.md`.

---

## 2. Modelo mental del producto (para orientarte, NO para decidir)

- **Principio central:** Memora **no es custodio**. Las fotos viven en el Google Drive de su dueño; Memora guarda **referencias y relaciones**, nunca los bytes ni copias (salvo la adopción explícita de M5). Memora nunca borra de Drive automáticamente.
- **Modelo de datos:** una **Photo** tiene **un** dueño y **un** archivo en su Drive; puede estar en **varios álbumes** (relación **N:M** foto↔álbum, sin duplicar). Un **Album** tiene **un** owner y puede reunir fotos de varios Drives (multi-Drive con colaboradores).
- **Roles de álbum (D1):** **Owner** (administra álbum + colaboradores) y **Collaborator** (ve todo, aporta lo suyo). Sin roles configurables en el MVP.

> **La verdad funcional completa está en `producto-mvp.md`.** Este mapa solo da el modelo mental.

---

## 3. Índice de decisiones de producto D1–D17 (punteros, NO el texto)

Cada línea es un recordatorio de una línea. **El texto vinculante está en `producto-mvp.md`.** Ante cualquier matiz, lee ahí.

| ID | Tema (una línea) |
|----|------------------|
| D1 | Permisos: dos roles Owner/Collaborator, no configurables. |
| D2 | Visibilidad del visor: acceso por enlace (enlace/QR/NFC), no indexable; gestión requiere auth. |
| D3 | Usuario borra su foto → solo quita relación foto↔álbum; archivo queda en su Drive. |
| D4 | Owner quita foto de un colaborador → solo relación; no toca archivo ni propiedad. |
| D5 | Colaborador abandona → deja de aportar; sus fotos permanecen mientras estén disponibles. |
| D6 | Adoptar / "Guardar en mi biblioteca" (M5): ⏸️ **DIFERIDO a post-MVP** (no viable con `drive.file`). En el MVP fotos de colaboradores visibles mientras estén disponibles en su Drive. |
| D7 | App (captura + gestión completa) y Web (visor + plataforma auth); sin paridad 100%. |
| D8 | Metadatos mínimos de foto; **NO** geolocalización GPS/EXIF. |
| D9 | Cambios en Drive: verificación **perezosa**, sin sync activa; `fileId` estable (renombrar/mover no rompe). |
| D10 | Autorización Drive revocada → se pide re-autorizar; no hay logout forzado. |
| D11 | Biblioteca personal = solo fotos que Memora conoce (no todo el Drive); álbumes = agrupaciones. |
| D12 | Invitación de colaboradores: **solo enlace** (sin código) en el MVP. |
| D13 | Invitaciones expiran y son revocables por el owner. |
| D14 | NFC/QR: se asocian a un álbum ya creado; resuelven vía URL estable de Memora. |
| D15 | Optimización automática con buenos defaults; el usuario no elige calidad/resolución. |
| D16 | Eliminar álbum = eliminar la agrupación y relaciones, **no** las fotografías. |
| D17 | Visibilidad del álbum `PRIVATE`/`PUBLIC` (default PRIVATE), fijable al crear y por PATCH (owner). KISS: sin catálogo/descubrimiento; ambos se ven por enlace de compartición. |

> Precisiones adicionales aprobadas (estructura de Drive organizativa, viabilidad de M5, web parte del MVP) también en `producto-mvp.md` §Precisiones.

---

## 4. Estado de implementación (resumen; la verdad está en ESTADO.md + specs)

**PASS (validado):** Fundación monorepo + contrato API · Auth Google backend (login real en Android) · App fundación + login · Web fundación (en pausa de prioridad) · **M2** álbumes (spec03) · **M3 backend** fotos (spec04) · **M4 backend** colaboradores (spec05) · **M6 backend** disponibilidad (spec07) · **Abstracción `PhotoStorage`** (spec08). Últimos tres PASS 2026-09-14.

**✅ FASE 1 (backend) CERRADA** (2026-09-14): M2, M3, M4, M6, abstracción `PhotoStorage`, M7 (visor), M8 (NFC/QR) y A1.5 deuda (`SessionRegistry` tras interfaz) todos PASS. **M5 Adoptar: ⏸️ diferido a post-MVP** (copia cross-Drive no viable con `drive.file`). **Siguiente: FASE 2 (app)** cuando el PO lo indique — M3 app (seleccionar/optimizar/subir con `drive-token`), UI de álbumes/colaboradores, A1.5+A1.6 en app.

> Estado detallado y deuda técnica: `ESTADO.md`. Estado por ítem verificable: `backlog-mvp.md`.

---

## 5. Índice de specs (dónde está cada una y su estado)

Numeración **independiente por carpeta**. Estados los asigna Kiro.

**`specs/global/`**
- `spec01-estructura-monorepo.md`, `spec02-contrato-api.md`.

**`specs/memora-backend/`**
- `spec01-fundacion-backend.md` — PASS.
- `spec02-autenticacion-google.md` — PASS (login real en dispositivo).
- `spec03-biblioteca-albumes.md` — PASS (M2).
- `spec04-fotografias.md` — PASS (M3 backend).
- `spec05-colaboradores.md` — PASS (M4 backend).
- `spec06-adoptar.md` — ⏸️ DIFERIDA a post-MVP (M5; análisis técnico conservado).
- `spec07-disponibilidad.md` — PASS (M6 backend).
- `spec08-abstraccion-almacenamiento.md` — PASS (abstracción `PhotoStorage`; `Photo.driveFileId` → `Photo.storageRef {provider, fileId}`).
- `spec09-compartir-visor.md` — PASS (enlace de compartición público `GET /shared/:token`, `visibility` del álbum D17).
- `spec10-nfc-qr.md` — PASS WITH NOTES (M8: `NfcQrTag` token opaco 256-bit + soft-delete; owner-only crear/disable/consultar `GET /nfc-qr-tags/:id`; público `GET /n/:token` → 302 al ShareLink activo, resolución indirecta, 404 uniforme; env `APP_NFC_QR_BASE_URL`).
- `spec11-session-registry-interface.md` — PASS (deuda A1.5 backend: `SessionRegistry` → interfaz + token `SESSION_REGISTRY` + `InMemorySessionRegistry`; sin cambio de comportamiento). **Cierra FASE 1 backend.**

**`specs/memora-app/`**
- `spec01-fundacion-app.md`, `spec02-login-google.md` — PASS.
- `spec03-fotografias.md` — ✅ VALIDADO EN DISPOSITIVO por el PO (M3 app: seleccionar/optimizar D15 sin GPS/subir bytes a Drive carpeta "Memora"/registrar con `storageRef`; detecta `DRIVE_REAUTHORIZATION_REQUIRED`).
- `spec04-ui-albumes.md` — APROBADA, en implementación (UI de álbumes app: lista propios+colaborando con rol, crear, detalle con miniaturas de Drive vía drive-token, renombrar/visibility/eliminar owner-only, agregar fotos reusando spec03/quitar del álbum; Navigator nativo; extiende ApiClient con PATCH/DELETE).
- `spec05-ui-colaboradores.md` — APROBADA (M4 app: invitar por enlace/administrar/quitar/revocar owner-only, aceptar por token, abandonar; consume backend spec05).
- `spec06-sesion-y-reauth-drive.md` — APROBADA (A1.5 refresh automático del JWT centralizado en `ApiClient` + A1.6 reconectar Drive sin logout, D10; consume backend spec02).
- `spec07-compartir-nfc-qr.md` — APROBADA (M7/M8 app: compartir enlace + QR en cliente `qr_flutter` + gestionar tags NFC/QR owner-only; escritura NFC física y visor anónimo fuera de alcance —visor es web FASE 3).
- `spec08-visor-foto-inapp.md` — APROBADA (visor de foto a pantalla completa in-app: full-res desde Drive con drive-token, zoom/pan/swipe con `photo_view`, `unavailable` M6; se abre desde el detalle de álbum spec04).
- `spec09-programar-nfc.md` — APROBADA (M8 escritura NFC nativa con `nfc_manager`: escribe NDEF URI `https://memora.app/n/{token}` obtenido del backend, verifica, bloqueo solo-lectura solo Android —iOS Core NFC no lo soporta).

**`specs/memora-web/`**
- `spec01-fundacion-web.md` — EN PAUSA (prioridad, no exclusión).

> Formato de cada spec y estados de validación: `specs/README.md`.

---

## 6. Mapa de código del backend (patrones a replicar)

Raíz del backend: `memora-backend/`. NestJS 10 + TypeScript, Express. **Todos los repos son mocks en memoria detrás de interfaces con token `Symbol`** (migrables a Postgres/Neon sin tocar lógica). Prefijo global de API: `/api/v1` (en `src/bootstrap.ts`).

**Estructura por feature-módulo.** Cada módulo: `X.model.ts` (interface entidad) · `x-repository.interface.ts` (interface + `export const X_REPOSITORY = Symbol(...)` + doc) · `in-memory-x.repository.ts` (`@Injectable()` implementa la interface) · `x.service.ts` (lógica + ownership) · `x.controller.ts` (HTTP) · `x.service.spec.ts` (unit). Providers de repo: `{ provide: TOKEN, useClass: InMemoryImpl }`; inyección con `@Inject(TOKEN)`.

**Módulos actuales** (`src/app.module.ts`, orden fijo, `NotFoundModule` último por catch-all): `HealthModule, AuthModule, AlbumsModule, NotFoundModule`. **Fotos no es módulo aparte**: vive en `src/albums/photos/` y se registra en `AlbumsModule`.

**Autenticación / autorización:**
- Guard: `src/auth/session/session-auth.guard.ts` — `SessionAuthGuard`, Bearer JWT, setea `request.user = { id }`, 401 si falta/invalid. Se aplica con `@UseGuards(SessionAuthGuard)`.
- Usuario en controllers: decorador `@CurrentUser()` (`src/auth/session/current-user.decorator.ts`) → `{ id: string }`.
- JWT: `src/auth/session/session-token.service.ts` (tokens `session_access`/`session_refresh`, secreto `JWT_SESSION_SECRET`).
- **Patrón owner-only (404 para ajeno/inexistente):** `src/common/authorization/require-owned.ts` → `requireOwned(entity, ownerId, msg)`. **404 deliberado, no 403** (no revelar existencia). Los services lo envuelven (`AlbumsService.requireOwnedAlbum`, `PhotosService.requireOwned*`). **M4 extiende esto a "requiere membresía" (owner o collaborator) para lecturas.**

**Errores uniformes `{ code, message, requestId }`:**
- `src/common/exceptions/api.exception.ts` — `ApiException(status, code, message)`.
- `src/common/filters/all-exceptions.filter.ts` — normaliza todo; deriva `code` del status (404→`NOT_FOUND`, etc.) o usa el `code` de `ApiException`; `requestId` del header.
- `src/common/middleware/request-id.middleware.ts` — `x-request-id` (reusa o genera).
- Errores por módulo en factories: `src/auth/auth.errors.ts` es el patrón (M4 debería crear `collaborators.errors.ts` igual).

**Validación de entrada:** **manual, sin class-validator** (no está instalado, no hay `ValidationPipe` global). Helpers: `src/common/validation/require-string-field.ts` (`requireStringField`, lanza `INVALID_REQUEST` 400) y parsers dedicados tipo `src/albums/photos/parse-register-photo-input.ts`.

**Relación N:M foto↔álbum:** vive en el **AlbumRepository** (`InMemoryAlbumRepository.photoIdsByAlbumId: Map<albumId, Set<photoId>>`), no en Photo ni Album. Idempotente (Set). Borrar álbum limpia solo sus relaciones (D16); borrar foto llama `removePhotoFromAllAlbums` antes de `photos.delete`. La pertenencia de fotos es del lado álbum → las reglas de colaboración giran en torno al álbum.

**Entidades clave:**
- `Album` (`src/albums/album.model.ts`): `{ id, ownerId, name, createdAt, updatedAt, visibility 'PRIVATE'|'PUBLIC'` default `PRIVATE`}. Colaboradores viven en membership (M4), no en Album (D1, D17).
- `Photo` (`src/albums/photos/photo.model.ts`): `{ id, ownerId, storageRef, createdAt, capturedAt?, width?, height?, mimeType?, sizeBytes?, availability, availabilityCheckedAt? }`. `storageRef = { provider: 'google-drive', fileId }` (spec08, referencia neutral; el dominio NO usa `driveFileId` ni menciona "Drive"). `availability` default `'available'`.

**Abstracción de almacenamiento (spec08):** interfaz `PhotoStorage` (token `PHOTO_STORAGE`) en `src/albums/photos/storage/`, con `GoogleDrivePhotoStorage` (única impl, envuelve `AuthService.getDriveAccessToken`). Ops del MVP: `getUploadAuthorization`, `getReadReference`. Ops declaradas no soportadas (`describe/exists/download/stream/copy/delete`) → 501 `STORAGE_OPERATION_UNSUPPORTED`. Regla normativa: el dominio no referencia "Drive" ni `driveFileId` (verificado por `domain-storage-neutrality.spec.ts`). Para operar sobre el archivo, usar `PhotoStorage`; para referenciarlo, `Photo.storageRef`.

**Broker drive-token:** `POST /api/v1/auth/drive-token` (`AuthController.getDriveToken`, guard + `@CurrentUser`) → `{ driveAccessToken, expiresIn }`. `AuthService.getDriveAccessToken(userId)` usa el refresh token guardado; sin él → 401 `DRIVE_REAUTHORIZATION_REQUIRED`. Scope `drive.file`. **El backend nunca ve los bytes.** En M4 cada colaborador usa su propio drive-token contra su propio Drive.

**Endpoints existentes** (todos bajo `/api/v1`, con guard salvo auth público):
- Auth: `POST /auth/google`, `POST /auth/refresh`, `POST /auth/logout` (204), `POST /auth/drive-token`.
- Albums: `POST /albums`, `GET /albums`, `GET /albums/:id`, `PATCH /albums/:id`, `DELETE /albums/:id` (204), `POST /albums/:albumId/photos`, `DELETE /albums/:albumId/photos/:photoId`.
- Photos: `POST /photos`, `DELETE /photos/:photoId` (204).
- Library: `GET /library`.
- Compartir (M7): `POST /albums/:albumId/share-link`, `DELETE /albums/:albumId/share-link`; **público sin guard** `GET /shared/:token`.
- NFC/QR (M8): `POST /albums/:albumId/nfc-qr-tags`, `PATCH /nfc-qr-tags/:id/disable` (204), `GET /nfc-qr-tags/:id`; **público sin guard** `GET /n/:token` (redirección 302). Los **dos** controllers públicos del backend son `SharedController` y `NfcQrResolveController` (no llevan `@UseGuards`).

---

## 7. Convenciones de validación y comandos (backend)

- **Validación quirúrgica (ahorro de tokens):** corre `npm run build` + tests + **grep dirigido** a los criterios críticos de la spec. Lee código completo **solo** si un test falla o la spec es sensible (auth, borrados, adopción).
- Comandos (en `memora-backend/`): `npm run build`, `npm test` (unit), `npm run test:e2e`.
- **Tests requieren env** (dummy sirve): `JWT_SESSION_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`. Ya están en `test/jest-setup.ts` con `??=`.
- **Tests e2e:** una sola app Nest por archivo (`beforeAll/afterAll`); simular usuario = **login real** (override `GOOGLE_AUTH_CLIENT` con fake → `POST /auth/google` → usar `sessionAccessToken` como Bearer). Para M4 usar ≥3 usuarios (owner, colaborador, ajeno).
- Backend corre en **puerto 3000**; matar procesos colgados al terminar: `lsof -ti:3000 | xargs kill` si aplica.
- **Deuda de test-infra conocida (no bloqueante):** flake residual de transporte en e2e (supertest + apps Nest efímeras), ~1 fallo aislado por varias corridas, nunca de lógica.

---

## 8. Reglas de entorno (no negociables)

- Aislamiento: cada subproyecto Node tiene su `.npmrc` (registro público). **NO** `npm -g`, **NO** tocar `.npmrc`, **NO** cambiar versión de NestJS/Node. Backend **NestJS 10 / Node 20**.
- Clientes hablan solo con la API del backend. Única excepción: subida directa de **bytes** cliente→Drive (el backend nunca maneja bytes).
- Identidad: JWT propio. DB objetivo: Postgres (Neon); **hoy mocks en memoria** detrás de interfaces.

> Fuente completa: `README.md` (raíz) §Aislamiento y §Regla de acceso; `specs/README.md` §Decisiones técnicas fijadas.

---

## 9. Memoria de Claude (Engram) — nota informativa

Claude Code usa **Engram** (memoria persistente, plugin de Claude Code, DB en `~/.engram/`) en este repo. Guarda el **diario de implementación de Claude** (qué implementó, resultados de build/tests, gotchas), organizado en el proyecto `memora`. **No** contiene las decisiones de producto D1–D17 (esas viven solo en `producto-mvp.md`). Kiro no se engancha a Engram; para Kiro la fuente de verdad son los archivos del repo. Al preparar prompts para Claude, se puede pedirle que consulte/guarde en Engram, pero **no sustituye** las specs ni este mapa.

---

## 10. Mantenimiento de este mapa

- Este archivo se actualiza cuando cambie el **estado** (nueva spec PASS), aparezca un **patrón de código nuevo** que Claude deba replicar, o el PO cierre nuevas decisiones. Se actualiza el índice/puntero, **no** se copia el texto de la fuente.
- Si detectas contradicción entre este mapa y una fuente, **corrige el mapa** (la fuente manda).
