# spec05 — Colaboradores: invitaciones y roles (backend)

**Ámbito:** memora-backend
**Estado de validación:** ✅ PASS (validado por Kiro el 2026-09-14: build OK; 70 unit + 67 e2e; criterios críticos verificados por grep dirigido). Ver "Notas de validación (Kiro)" al final.
**Backlog:** M4 (Álbumes compartidos y colaboradores) — parte backend

## Objetivo

Implementar en `memora-backend` la **colaboración en álbumes**: el Owner invita colaboradores mediante un **enlace de invitación** (D12); el invitado se une tras Google Login y pasa a **Collaborator** (D1). Los colaboradores ven todas las fotos del álbum y aportan las suyas (que viven en **su propio Drive**, multi-Drive). El Owner administra colaboradores (ver/quitar). Se respeta que quitar una foto de un colaborador solo elimina la relación (D4), y que abandonar el álbum no elimina las fotos históricas del colaborador (D5).

## Contexto y decisiones de producto que aplican

Ver `specs/producto-mvp.md`. Relevantes aquí:

- **D1** — Dos roles: **Owner** (administra álbum y colaboradores) y **Collaborator** (ve todas las fotos y aporta las suyas). Sin roles configurables en el MVP.
- **D4** — Owner quita foto de un colaborador → solo elimina la relación foto↔álbum; no toca el archivo ni la propiedad del colaborador.
- **D5** — Colaborador abandona el álbum: deja de ser colaborador y de aportar; sus fotos **permanecen** en el álbum mientras sigan disponibles y siguen siendo suyas.
- **D6** — "Guardar en mi biblioteca" (adopción) es **M5**, fuera del alcance de esta spec.
- **D12** — Invitación **solo por enlace** en el MVP (sin código). Flujo: Owner invita → Memora genera enlace → invitado abre → Google Login → acepta → pasa a Collaborator.
- **D13** — Invitaciones **expiran** y son **revocables** por el Owner. Una invitación revocada/expirada no sirve para unirse. Valor de expiración fijado por el Tech Lead y aprobado por el PO: **7 días** (P4).

Estado del código sobre el que se construye (todo PASS): `Album` tiene solo `ownerId`; autorización owner-only vía `requireOwned` (404 para ajeno/inexistente); repos en memoria detrás de interfaces con token `Symbol`; errores uniformes `{ code, message, requestId }`; validación manual (sin class-validator); guard de sesión JWT + `@CurrentUser()`; broker `POST /auth/drive-token` (cada usuario obtiene un token efímero de **su** Drive con scope `drive.file`).

## Alcance (backend)

- **Modelo de membresía** álbum↔usuario con rol (`owner` | `collaborator`). El owner actual (campo `ownerId` de `Album`) se preserva; la membresía añade a los colaboradores.
- **Invitaciones**: entidad `Invitation` (token opaco, álbum, creador, estado, expiración), su repositorio en memoria y los endpoints para crear, revocar, listar (del owner) y aceptar.
- **Aceptar invitación**: un usuario autenticado canjea el token del enlace y pasa a `collaborator` del álbum.
- **Autorización por rol**: lectura del álbum y de sus fotos habilitada para owner **y** colaboradores; gestión (renombrar, borrar álbum, invitar, quitar colaboradores) solo para el owner.
- **Aporte de fotos por colaboradores**: un colaborador puede registrar/asociar sus propias fotos al álbum (owner de la `Photo` = el colaborador; archivo en su Drive).
- **Quitar fotos**: el owner puede quitar del álbum cualquier foto (D4, solo relación); un colaborador puede quitar del álbum **sus propias** aportaciones.
- **Administrar colaboradores**: el owner lista y quita colaboradores; un colaborador puede **abandonar** el álbum (D5).
- Interfaces de repositorio (`MembershipRepository`, `InvitationRepository`) con implementación **mock en memoria**, siguiendo el patrón establecido.

## Fuera de alcance

- Adopción / "Guardar en mi biblioteca" (M5).
- Verificación de disponibilidad de las fotos del colaborador contra Drive (M6). Aquí solo se respeta que las fotos aportadas conservan su `availability`.
- Compartir/visor público sin login (M7) — el enlace de **invitación** de esta spec es para **unirse como colaborador autenticado**, no el enlace de **visor** de solo lectura.
- NFC/QR (M8).
- Subida real de bytes / optimización (app). El backend solo coordina y guarda referencias, incluido para colaboradores.
- Transferencia de propiedad del álbum o de fotos.
- Notificaciones (email/push) al invitar.

## Comportamiento esperado

### Membresía y roles
- El modelo SHALL representar la pertenencia de un usuario a un álbum con un rol: `owner` o `collaborator`.
- El **owner** de un álbum SHALL ser exactamente uno y coincidir con `Album.ownerId`. No SHALL poder haber dos owners ni degradarse el owner a colaborador en el MVP.
- Un usuario SHALL ser, para un álbum dado, o bien owner, o bien collaborator, o ninguno (sin membresía). No ambos.

### Invitar (Owner)
- El backend SHALL exponer `POST /api/v1/albums/:albumId/invitations` (autenticado, **owner-only**) que crea una invitación y devuelve la **URL de invitación** completa (construida con `APP_INVITE_BASE_URL`) **y** el **token** suelto (P2).
- El token de invitación SHALL ser opaco, aleatorio y no adivinable (no un id secuencial).
- La invitación SHALL nacer con estado `pending` y una fecha de expiración de **`INVITATION_TTL_DAYS` (default 7) días** desde su creación (P4).
- La invitación SHALL ser de **un solo uso** (P6): al aceptarse pasa a `accepted` y ya no sirve para otro usuario.
- El backend SHALL exponer `GET /api/v1/albums/:albumId/invitations` (autenticado, owner-only) que lista las invitaciones del álbum con su estado (`pending` | `accepted` | `revoked` | `expired`), sin exponer el token en claro de invitaciones ya aceptadas.
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/invitations/:invitationId` (autenticado, owner-only) que **revoca** una invitación `pending`; una invitación revocada no SHALL poder aceptarse (D13).

### Aceptar invitación (invitado autenticado)
- El backend SHALL exponer `POST /api/v1/invitations/:token/accept` (autenticado) que, con un token válido `pending` y no expirado, añade al usuario autenticado como `collaborator` del álbum.
- Aceptar una invitación ya `accepted`, `revoked` o `expired` SHALL fallar con **410 `INVITATION_NOT_USABLE`** (P5).
- Si el usuario que acepta **ya es** owner o collaborator del álbum, la operación SHALL ser **idempotente (204)** sin crear membresías duplicadas (P5).
- El flujo de Google Login previo a aceptar es responsabilidad del cliente (ya existe `POST /auth/google`); esta spec asume que el usuario llega autenticado.

### Lectura con rol (Owner o Collaborator)
- `GET /api/v1/albums/:id` y el detalle de sus fotos SHALL ser accesibles por el **owner y por los colaboradores** del álbum. Para un usuario sin membresía → **404 uniforme** (mismo criterio que M2: no revelar existencia de álbumes ajenos).
- `GET /api/v1/albums` (lista de "mis álbumes") SHALL devolver **una sola lista** con los álbumes propios (owner) y aquellos donde el usuario es colaborador, con un campo **`role`** (`owner` | `collaborator`) por álbum (P3).

### Aporte de fotos por colaboradores
- Un colaborador SHALL poder registrar una foto (`POST /api/v1/photos` con `albumId` del álbum donde colabora) y asociarla a ese álbum; la `Photo` resultante tiene como `ownerId` al **colaborador** (su archivo, su Drive).
- Un colaborador SHALL poder asociar una foto **propia** ya existente al álbum vía `POST /api/v1/albums/:albumId/photos`.
- Un colaborador NO SHALL poder asociar fotos que no le pertenezcan.
- La relación N:M foto↔álbum ya existente se reutiliza; el propietario de cada foto se conserva en `Photo.ownerId` (multi-Drive dentro de un mismo álbum).

### Quitar fotos del álbum
- El **owner** SHALL poder quitar del álbum **cualquier** foto (propia o de un colaborador) vía `DELETE /api/v1/albums/:albumId/photos/:photoId`: elimina **solo la relación** foto↔álbum; no borra la `Photo` ni el archivo de Drive del colaborador (D4).
- Un **colaborador** SHALL poder quitar del álbum **solo sus propias** aportaciones (misma ruta). Intentar quitar una foto ajena → **404 uniforme** (P5).
- `DELETE /api/v1/photos/:photoId` (borrar la referencia de la biblioteca propia) SHALL seguir siendo del propietario de la foto; para un colaborador afecta solo a sus fotos.

### Administrar colaboradores
- El backend SHALL exponer `GET /api/v1/albums/:albumId/collaborators` (autenticado, owner-only) que lista los colaboradores del álbum (identidad mínima + rol).
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/collaborators/:userId` (autenticado, owner-only) que quita a un colaborador. Tras quitarlo, deja de ver/aportar; sus fotos **históricas permanecen** en el álbum mientras estén disponibles (D5). El owner no SHALL poder quitarse a sí mismo por esta vía.
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/collaborators/me` (autenticado) para que un colaborador **abandone** el álbum (P1). Efecto idéntico a ser quitado (deja de ver/aportar; sus fotos permanecen, D5).

### Efecto de eliminar el álbum (recordatorio, ya en D16)
- Eliminar un álbum (owner) SHALL eliminar el álbum, sus membresías, sus invitaciones y sus relaciones foto↔álbum, sin borrar ninguna `Photo` ni archivo de Drive de nadie.

### Reglas transversales
- Todas las operaciones SHALL requerir sesión válida (guard existente) → 401 uniforme sin sesión.
- Álbum inexistente o sin membresía del solicitante → **404 uniforme** (patrón `requireOwned` extendido a "requiere membresía").
- El backend NO SHALL recibir, almacenar ni proxear bytes de fotos, tampoco de colaboradores.
- Los tokens de invitación NO SHALL registrarse en logs.

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO. Son vinculantes para la implementación.

- **P1 — Abandono de colaborador:** `DELETE /api/v1/albums/:albumId/collaborators/me`. El propio colaborador se quita; reutiliza el recurso de colaboradores. Efecto idéntico a ser quitado por el owner (D5): deja de ver/aportar, sus fotos históricas permanecen.

- **P2 — URL de invitación:** el backend devuelve **la URL completa** construida sobre una env var configurable **`APP_INVITE_BASE_URL`** (placeholder por defecto en dev: `https://memora.app/invite/{token}`), **y además** el `token` suelto. No hardcodear el dominio.

- **P3 — `GET /api/v1/albums`:** **una sola lista** que incluye álbumes propios (owner) y donde el usuario es colaborador, con un campo **`role`** (`owner` | `collaborator`) por álbum. Aditivo, no rompe M2.

- **P4 — Expiración de invitaciones:** **7 días** desde la creación, configurable por env **`INVITATION_TTL_DAYS`** (default `7`).

- **P5 — Códigos/estatus de error** (formato uniforme `{ code, message, requestId }`):
  - Invitación inválida / expirada / revocada / ya usada al aceptar → **410 Gone**, code **`INVITATION_NOT_USABLE`**.
  - El usuario que acepta **ya es** owner o collaborator → **204 idempotente** (no error), sin crear membresías duplicadas.
  - Colaborador intenta quitar una foto ajena o realizar una acción de gestión que no le corresponde → **404** uniforme (coherente con el patrón "no revelar" de M2), no 403.

- **P6 — Reutilización del enlace: de UN SOLO USO.** Al aceptar, la invitación pasa a `accepted` y no sirve para otro usuario. Invitar a N personas = N invitaciones/enlaces. Da trazabilidad (quién aceptó cada invitación) y encaja con la revocación individual (D13). En el MVP la invitación **no** se dirige a un usuario específico de antemano: se ata a quien la acepte primero.

## Checklist de implementación

- [ ] Modelo de **membresía** (`AlbumMembership`: albumId, userId, role, joinedAt) + `MembershipRepository` (interfaz + token `Symbol` + mock en memoria). El owner se refleja como membresía `owner` al crear el álbum (o se deriva de `Album.ownerId`; a decidir en implementación sin cambiar contrato).
- [ ] Modelo **Invitation** (id, albumId, token opaco, createdBy, status, expiresAt, acceptedByUserId?, createdAt) + `InvitationRepository` (interfaz + token + mock en memoria).
- [ ] Endpoints de invitaciones: `POST/GET/DELETE /api/v1/albums/:albumId/invitations`.
- [ ] Endpoint aceptar: `POST /api/v1/invitations/:token/accept`.
- [ ] Autorización por rol: helper que exige **membresía** (owner o collaborator) para lectura y **owner** para gestión, devolviendo 404 uniforme cuando no aplica (extender el patrón `requireOwned`).
- [ ] Lectura de álbum/fotos habilitada para colaboradores; `GET /albums` como una sola lista con campo `role` (P3).
- [ ] Aporte de fotos por colaborador (ajustar autorización en `PhotosService`/asociación N:M para aceptar owner **o** colaborador dueño de la foto).
- [ ] Quitar foto del álbum: owner (cualquiera) / colaborador (solo propias); solo relación (D4).
- [ ] Administrar colaboradores: `GET /api/v1/albums/:albumId/collaborators`, `DELETE .../:userId` (owner) y `DELETE .../me` (abandonar, P1).
- [ ] `DELETE` de álbum limpia membresías + invitaciones + relaciones (D16).
- [ ] Validación manual de entrada (patrón `requireStringField`/parsers), errores uniformes: 410 `INVITATION_NOT_USABLE`, 204 idempotente si ya es miembro, 404 para acciones sobre recursos ajenos (P5).
- [ ] `collaborators.errors.ts` con factories de `ApiException` (patrón de `auth.errors.ts`).
- [ ] Env vars nuevas documentadas (`APP_INVITE_BASE_URL`, `INVITATION_TTL_DAYS`) y añadidas a `test/jest-setup.ts` con dummy si aplica.
- [ ] Pruebas unitarias (roles, aceptar/expirar/revocar, aporte de colaborador, quitar foto por owner vs colaborador, abandonar, borrar álbum limpia todo) y e2e con **login real de ≥3 usuarios** (owner, colaborador, ajeno) siguiendo el patrón de `albums.e2e-spec.ts`.
- [ ] Documentar endpoints en el README del backend.
- [ ] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- Owner crea invitación (`pending`, con expiración); otro usuario la acepta y pasa a `collaborator`.
- Invitación revocada, expirada o ya usada NO permite unirse → **410 `INVITATION_NOT_USABLE`** (P5/P6, un solo uso).
- Colaborador ve el álbum y sus fotos; aporta fotos propias (owner de la Photo = colaborador); no puede aportar fotos ajenas ni gestionar el álbum.
- Owner quita una foto de un colaborador → desaparece la relación, la `Photo` y el archivo del colaborador permanecen (D4).
- Colaborador quita solo sus propias aportaciones; no las de otros.
- Owner lista y quita colaboradores; el colaborador quitado deja de ver/aportar y sus fotos históricas permanecen (D5).
- Colaborador abandona vía `DELETE .../collaborators/me` (P1) con el mismo efecto (D5).
- `GET /albums` devuelve una sola lista con el `role` del usuario en cada álbum (P3).
- Aceptar cuando ya se es miembro → 204 idempotente, sin duplicar membresía (P5).
- Sin sesión → 401; álbum sin membresía → 404 uniforme; invitación no usable → 410 `INVITATION_NOT_USABLE` (P5).
- Eliminar el álbum limpia membresías, invitaciones y relaciones sin borrar fotos ni Drive (D16).
- El backend nunca maneja bytes; los tokens de invitación no aparecen en logs.
- `build`, `test`, `test:e2e` pasan; endpoints documentados.

## Dependencias

- `memora-backend/spec02-autenticacion-google.md` (guard de sesión, `@CurrentUser`, `drive-token`) — PASS.
- `memora-backend/spec03-biblioteca-albumes.md` (Album, N:M, patrón owner-only) — PASS.
- `memora-backend/spec04-fotografias.md` (registro/asociación de fotos, biblioteca) — PASS.
- `producto-mvp.md` (D1, D4, D5, D12, D13).
- Habilita: **M5 — Adoptar** ("Guardar en mi biblioteca", necesita colaboradores y sus fotos en el álbum).

## Notas de validación (Kiro) — PASS

**Veredicto: PASS** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK (exit 0).
- `npm test` → **70 unit** pasan (6 suites). El `ERROR [AllExceptionsFilter] db connection string leaked` en el log es un caso de prueba intencional del filtro (verifica que no se filtren datos sensibles), no un fallo.
- `npm run test:e2e` → 67 pasan / 1 fallo aislado (`Parse Error: Expected HTTP/`) que es el **flake de transporte conocido** (supertest + apps Nest efímeras, documentado en spec04, nunca de lógica). Reejecutado `collaborators.e2e-spec.ts` en aislamiento → **29/29 e2e pasan**, incluido el caso P6 single-use que había flakeado.
- Grep dirigido a criterios sensibles: **no hay manejo de bytes** ni cliente Drive en `collaborators/` (sin multipart/Buffer/googleapis); **tokens no se loguean** (sin console/Logger en el módulo).

**Criterios de la spec (todos cumplidos):**
- Membresía y roles con `AlbumAccessService` que extiende `requireOwned` a "requiere membresía" (owner o collaborator) para lectura y "requiere owner" para gestión, con **404 uniforme** (no 403) para ajeno/inexistente.
- Invitaciones: token opaco de 256 bits (`randomBytes(32).base64url`), expiración `INVITATION_TTL_DAYS` (default 7), URL desde `APP_INVITE_BASE_URL` + token suelto. Estado listado sin exponer token de invitaciones no `pending`.
- Aceptar: **un solo uso (P6)** — al aceptar pasa a `accepted`; otro no-miembro → **410 `INVITATION_NOT_USABLE`**. Orden P5 correcto: "ya es miembro" se comprueba antes → **204 idempotente**. Expiración perezosa (`resolveEffectiveStatus`).
- Aporte de colaborador (foto propia, owner = colaborador), quitar por rol (owner cualquiera / colaborador solo propias, solo relación — D4), administrar/quitar/abandonar (`DELETE .../collaborators/me`, ruta declarada antes de `:userId`), D5 (fotos permanecen), D16 (delete de álbum limpia membresías + invitaciones).

**Nota menor (no bloqueante):** persiste el flake de transporte e2e ya documentado en spec03/spec04; no es de esta implementación. Recomendación: sin acción para el MVP.

**Detalles de calidad observados:** la lógica sensible está bien comentada (orden de checks en `accept`, por qué 410 vs 404, orden de rutas `me` vs `:userId`, `AlbumAccessService` como servicio en vez de función pura). Buen encaje con los patrones existentes.
