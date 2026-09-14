# spec05 — Colaboradores: invitaciones y roles (backend)

**Ámbito:** memora-backend
**Estado de validación:** BORRADOR (pendiente de aprobación del PO de las decisiones abiertas P1–P6)
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
- **D13** — Invitaciones **expiran** y son **revocables** por el Owner. Una invitación revocada/expirada no sirve para unirse. El valor de expiración lo define el Tech Lead (se consulta al PO si tiene impacto de UX → ver P4).

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
- El backend SHALL exponer `POST /api/v1/albums/:albumId/invitations` (autenticado, **owner-only**) que crea una invitación y devuelve el **token de invitación** y la **URL de invitación** (ver P2 para el formato de URL).
- El token de invitación SHALL ser opaco, aleatorio y no adivinable (no un id secuencial).
- La invitación SHALL nacer con estado `pending` y una fecha de expiración (ver P4).
- El backend SHALL exponer `GET /api/v1/albums/:albumId/invitations` (autenticado, owner-only) que lista las invitaciones del álbum con su estado (`pending` | `accepted` | `revoked` | `expired`) sin exponer el token en claro de invitaciones ya aceptadas (ver P6).
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/invitations/:invitationId` (autenticado, owner-only) que **revoca** una invitación `pending`; una invitación revocada no SHALL poder aceptarse (D13).

### Aceptar invitación (invitado autenticado)
- El backend SHALL exponer `POST /api/v1/invitations/:token/accept` (autenticado) que, con un token válido `pending` y no expirado, añade al usuario autenticado como `collaborator` del álbum.
- Aceptar una invitación ya `accepted`, `revoked` o `expired` SHALL fallar con error uniforme (ver P5 para el código/estatus).
- Si el usuario que acepta **ya es** owner o collaborator del álbum, la operación SHALL ser idempotente / rechazada de forma controlada (ver P5), sin crear membresías duplicadas.
- El flujo de Google Login previo a aceptar es responsabilidad del cliente (ya existe `POST /auth/google`); esta spec asume que el usuario llega autenticado.

### Lectura con rol (Owner o Collaborator)
- `GET /api/v1/albums/:id` y el detalle de sus fotos SHALL ser accesibles por el **owner y por los colaboradores** del álbum. Para un usuario sin membresía → **404 uniforme** (mismo criterio que M2: no revelar existencia de álbumes ajenos).
- `GET /api/v1/albums` (lista de "mis álbumes") SHALL incluir, además de los álbumes propios (owner), los álbumes donde el usuario es colaborador, distinguiendo el rol del usuario en cada uno (campo `role` en la respuesta). (Ver P3.)

### Aporte de fotos por colaboradores
- Un colaborador SHALL poder registrar una foto (`POST /api/v1/photos` con `albumId` del álbum donde colabora) y asociarla a ese álbum; la `Photo` resultante tiene como `ownerId` al **colaborador** (su archivo, su Drive).
- Un colaborador SHALL poder asociar una foto **propia** ya existente al álbum vía `POST /api/v1/albums/:albumId/photos`.
- Un colaborador NO SHALL poder asociar fotos que no le pertenezcan.
- La relación N:M foto↔álbum ya existente se reutiliza; el propietario de cada foto se conserva en `Photo.ownerId` (multi-Drive dentro de un mismo álbum).

### Quitar fotos del álbum
- El **owner** SHALL poder quitar del álbum **cualquier** foto (propia o de un colaborador) vía `DELETE /api/v1/albums/:albumId/photos/:photoId`: elimina **solo la relación** foto↔álbum; no borra la `Photo` ni el archivo de Drive del colaborador (D4).
- Un **colaborador** SHALL poder quitar del álbum **solo sus propias** aportaciones (misma ruta). Intentar quitar una foto ajena → 404/403 uniforme (ver P5).
- `DELETE /api/v1/photos/:photoId` (borrar la referencia de la biblioteca propia) SHALL seguir siendo del propietario de la foto; para un colaborador afecta solo a sus fotos.

### Administrar colaboradores
- El backend SHALL exponer `GET /api/v1/albums/:albumId/collaborators` (autenticado, owner-only) que lista los colaboradores del álbum (identidad mínima + rol).
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/collaborators/:userId` (autenticado, owner-only) que quita a un colaborador. Tras quitarlo, deja de ver/aportar; sus fotos **históricas permanecen** en el álbum mientras estén disponibles (D5). El owner no SHALL poder quitarse a sí mismo por esta vía.
- El backend SHALL exponer una vía para que un colaborador **abandone** el álbum (ver P1 para la forma exacta del endpoint). Efecto idéntico a ser quitado (deja de ver/aportar; sus fotos permanecen, D5).

### Efecto de eliminar el álbum (recordatorio, ya en D16)
- Eliminar un álbum (owner) SHALL eliminar el álbum, sus membresías, sus invitaciones y sus relaciones foto↔álbum, sin borrar ninguna `Photo` ni archivo de Drive de nadie.

### Reglas transversales
- Todas las operaciones SHALL requerir sesión válida (guard existente) → 401 uniforme sin sesión.
- Álbum inexistente o sin membresía del solicitante → **404 uniforme** (patrón `requireOwned` extendido a "requiere membresía").
- El backend NO SHALL recibir, almacenar ni proxear bytes de fotos, tampoco de colaboradores.
- Los tokens de invitación NO SHALL registrarse en logs.

## Decisiones de producto abiertas (requieren OK del PO)

> Estas no están cerradas en D1–D16. Cada una lleva opciones, recomendación del Tech Lead e impacto. La spec se congela cuando el PO decide.

- **P1 — ¿Cómo abandona un colaborador?**
  - (a) `DELETE /api/v1/albums/:albumId/collaborators/me` (el propio colaborador se quita).
  - (b) `POST /api/v1/albums/:albumId/leave`.
  - **Recomendación:** (a) — reutiliza la misma ruta/recurso de administración; `me` es explícito y REST-consistente. **Impacto:** bajo; solo naming del endpoint.

- **P2 — Formato de la URL de invitación que devuelve el backend.**
  - (a) El backend devuelve solo el `token`; el cliente construye el enlace.
  - (b) El backend devuelve una URL completa basada en una env var (p. ej. `https://memora.app/invite/{token}`).
  - **Recomendación:** (b) con base configurable (`APP_INVITE_BASE_URL`), devolviendo también el `token` suelto. **Impacto:** define dónde "aterriza" el enlace (app/web) — es una decisión de distribución; en el MVP el dominio final puede no existir aún, así que la env var evita hardcodear. Necesito tu confirmación del dominio/base placeholder.

- **P3 — `GET /api/v1/albums`: ¿incluir los álbumes donde soy colaborador?**
  - (a) Sí, una sola lista con campo `role` (`owner`/`collaborator`).
  - (b) No; los álbumes compartidos se listan en un endpoint aparte (`GET /api/v1/albums/shared`).
  - **Recomendación:** (a) — una lista unificada con `role` es lo que la UI de "mis álbumes" suele querer y evita un segundo endpoint. **Impacto:** cambia la forma de la respuesta de un endpoint existente (añade `role`); es aditivo, no rompe M2.

- **P4 — Expiración de las invitaciones (D13 delega el valor al Tech Lead).**
  - Propuesta: **7 días** de validez desde la creación.
  - **Recomendación:** 7 días — suficiente para compartir por mensajería sin dejar enlaces vivos indefinidamente. Configurable por env (`INVITATION_TTL_DAYS`, default 7). **Impacto:** UX — si es muy corto, el invitado no llega a aceptar; si es muy largo, enlaces vivos más tiempo. ¿7 días te sirve?

- **P5 — Códigos/estatus de error para casos de colaboración.** Propuesta (formato uniforme `{ code, message, requestId }`):
  - Invitación inválida/expirada/revocada al aceptar → **410 Gone** `INVITATION_NOT_USABLE` (o 404 `NOT_FOUND` si prefieres no distinguir).
  - Ya eres miembro al aceptar → **200/204 idempotente** (no error) devolviendo el álbum, o **409** `ALREADY_MEMBER`.
  - Colaborador intenta quitar foto ajena o gestionar → **404** (patrón "no revelar", coherente con M2) en vez de 403.
  - **Recomendación:** 410 `INVITATION_NOT_USABLE` para invitaciones no usables (mensaje claro para el invitado); idempotente (204) si ya es miembro; **404** para acciones no permitidas sobre recursos ajenos (coherencia con el patrón owner-only existente). **Impacto:** afecta a la UX del cliente (qué mensaje mostrar). Si prefieres uniformar todo a 404, lo hago.

- **P6 — Reutilización del enlace de invitación: ¿de un solo uso o multiuso?**
  - (a) **Un solo uso**: al aceptar, la invitación pasa a `accepted` y no sirve para otro usuario. Invitar a N personas = N enlaces.
  - (b) **Multiuso hasta expirar/revocar**: un mismo enlace sirve para varios invitados hasta que expira o se revoca.
  - **Recomendación:** (a) un solo uso — más control y trazabilidad (sabes quién aceptó cada invitación), encaja con "revocable" de D13 y evita reenvíos no deseados. **Impacto:** de producto/UX real. Multiuso es más cómodo para "comparto un link en un grupo", pero pierde control individual y complica la revocación selectiva. Necesito tu decisión.

## Checklist de implementación (se completa tras aprobar P1–P6)

- [ ] Modelo de **membresía** (`AlbumMembership`: albumId, userId, role, joinedAt) + `MembershipRepository` (interfaz + token `Symbol` + mock en memoria). El owner se refleja como membresía `owner` al crear el álbum (o se deriva de `Album.ownerId`; a decidir en implementación sin cambiar contrato).
- [ ] Modelo **Invitation** (id, albumId, token opaco, createdBy, status, expiresAt, acceptedByUserId?, createdAt) + `InvitationRepository` (interfaz + token + mock en memoria).
- [ ] Endpoints de invitaciones: `POST/GET/DELETE /api/v1/albums/:albumId/invitations`.
- [ ] Endpoint aceptar: `POST /api/v1/invitations/:token/accept`.
- [ ] Autorización por rol: helper que exige **membresía** (owner o collaborator) para lectura y **owner** para gestión, devolviendo 404 uniforme cuando no aplica (extender el patrón `requireOwned`).
- [ ] Lectura de álbum/fotos habilitada para colaboradores; `GET /albums` con `role` (según P3).
- [ ] Aporte de fotos por colaborador (ajustar autorización en `PhotosService`/asociación N:M para aceptar owner **o** colaborador dueño de la foto).
- [ ] Quitar foto del álbum: owner (cualquiera) / colaborador (solo propias); solo relación (D4).
- [ ] Administrar colaboradores: `GET/DELETE /api/v1/albums/:albumId/collaborators/...` + abandonar (según P1).
- [ ] `DELETE` de álbum limpia membresías + invitaciones + relaciones (D16).
- [ ] Validación manual de entrada (patrón `requireStringField`/parsers), errores uniformes según P5.
- [ ] `collaborators.errors.ts` con factories de `ApiException` (patrón de `auth.errors.ts`).
- [ ] Env vars nuevas documentadas (`APP_INVITE_BASE_URL`, `INVITATION_TTL_DAYS`) y añadidas a `test/jest-setup.ts` con dummy si aplica.
- [ ] Pruebas unitarias (roles, aceptar/expirar/revocar, aporte de colaborador, quitar foto por owner vs colaborador, abandonar, borrar álbum limpia todo) y e2e con **login real de ≥3 usuarios** (owner, colaborador, ajeno) siguiendo el patrón de `albums.e2e-spec.ts`.
- [ ] Documentar endpoints en el README del backend.
- [ ] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- Owner crea invitación (`pending`, con expiración); otro usuario la acepta y pasa a `collaborator`.
- Invitación revocada o expirada NO permite unirse (según P5/P6).
- Colaborador ve el álbum y sus fotos; aporta fotos propias (owner de la Photo = colaborador); no puede aportar fotos ajenas ni gestionar el álbum.
- Owner quita una foto de un colaborador → desaparece la relación, la `Photo` y el archivo del colaborador permanecen (D4).
- Colaborador quita solo sus propias aportaciones; no las de otros.
- Owner lista y quita colaboradores; el colaborador quitado deja de ver/aportar y sus fotos históricas permanecen (D5).
- Colaborador abandona (P1) con el mismo efecto (D5).
- `GET /albums` refleja el rol del usuario en cada álbum (según P3).
- Sin sesión → 401; álbum sin membresía → 404 uniforme; errores de colaboración con el código/estatus aprobado (P5).
- Eliminar el álbum limpia membresías, invitaciones y relaciones sin borrar fotos ni Drive (D16).
- El backend nunca maneja bytes; los tokens de invitación no aparecen en logs.
- `build`, `test`, `test:e2e` pasan; endpoints documentados.

## Dependencias

- `memora-backend/spec02-autenticacion-google.md` (guard de sesión, `@CurrentUser`, `drive-token`) — PASS.
- `memora-backend/spec03-biblioteca-albumes.md` (Album, N:M, patrón owner-only) — PASS.
- `memora-backend/spec04-fotografias.md` (registro/asociación de fotos, biblioteca) — PASS.
- `producto-mvp.md` (D1, D4, D5, D12, D13).
- Habilita: **M5 — Adoptar** ("Guardar en mi biblioteca", necesita colaboradores y sus fotos en el álbum).
