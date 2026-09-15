<p align="center">
  <a href="http://nestjs.com/" target="blank"><img src="https://nestjs.com/img/logo-small.svg" width="120" alt="Nest Logo" /></a>
</p>

<p align="center">Backend de Memora — NestJS 10 + TypeScript.</p>

## Contrato base de la API

Implementa `specs/global/spec02-contrato-api.md` y
`specs/memora-backend/spec01-fundacion-backend.md`.

- **Versionado** — todos los recursos se sirven bajo el prefijo `/api/v1`
  (configurado en `src/bootstrap.ts` vía `app.setGlobalPrefix('api/v1')`).
- **Salud** — `GET /api/v1/health` responde `200 { "status": "ok" }` sin
  autenticación (`src/health`). Además, `GET /health` (sin versionar) expone
  la misma respuesta para probes de infraestructura (load balancers, uptime
  checks); se registra directamente en el adaptador HTTP en
  `src/bootstrap.ts`, fuera del enrutado de Nest, para poder coexistir con
  `/api/v1/health` sin colisionar con el prefijo global.
- **Correlación de peticiones** — `src/common/middleware/request-id.middleware.ts`
  reutiliza el header `x-request-id` si el cliente lo envía, o genera uno
  (`crypto.randomUUID()`) si no. Siempre se refleja en la respuesta.
- **Formato de error uniforme** — `src/common/filters/all-exceptions.filter.ts`
  captura cualquier excepción (HTTP o no) y responde
  `{ code, message, requestId }` con el status HTTP correspondiente. `code`
  se deriva del texto estándar del status HTTP (p. ej. `404` → `NOT_FOUND`).
  Un recurso inexistente pasa por `src/not-found` (controlador comodín) y
  responde 404 con este mismo formato.

`src/bootstrap.ts` centraliza esta configuración (`configureApp`) y la usan
tanto `main.ts` como el bootstrap de los tests e2e, para que ambos ejerzan
exactamente el mismo pipeline.

## Aislamiento de proveedores externos

Regla: la lógica de negocio y los controladores dependen siempre de
interfaces, nunca de una implementación concreta. Una implementación por
interfaz, sin fábricas ni indirección especulativa.

Las interfaces de integración se introdujeron en
`specs/memora-backend/spec02-autenticacion-google.md`, la primera spec que
realmente las consume (ver esa sección más abajo).

## Autenticación con Google (spec02-autenticacion-google)

Implementa `specs/memora-backend/spec02-autenticacion-google.md`: login con
Google (flujo híbrido de acceso offline), sesión propia con JWT, y el
backend como *broker* de tokens de Drive.

### Flujo

```
1. Cliente hace Google Sign-In (acceso offline + scope drive.file)
   -> obtiene un serverAuthCode
2. POST /api/v1/auth/google { serverAuthCode }
   -> el backend canjea el code con Google, crea/recupera el usuario,
      guarda el refresh token de Google (nunca sale del backend) y
      responde { sessionAccessToken, sessionRefreshToken, user }
3. POST /api/v1/auth/refresh { sessionRefreshToken } -> nuevo sessionAccessToken
4. POST /api/v1/auth/logout (Bearer sessionAccessToken) -> revoca la sesión
5. POST /api/v1/auth/drive-token (Bearer sessionAccessToken)
   -> { driveAccessToken, expiresIn } — access token de Drive efímero,
      scope drive.file (el que el cliente ya pidió en el paso 1)
6. El cliente sube los bytes DIRECTO a Drive con ese driveAccessToken
```

### Interfaces (aislamiento de proveedores) — `src/auth/`

| Frontera | Interfaz | Implementación |
|---|---|---|
| Google OAuth | `GoogleAuthClient` (`google-auth/google-auth-client.interface.ts`) | `GoogleOAuthClient`, con la librería oficial `google-auth-library`. Mockeable vía DI en tests. |
| Usuarios | `UserRepository` (`users/user-repository.interface.ts`) | `InMemoryUserRepository` (mock en memoria) |
| Refresh token de Google | `TokenStore` (`tokens/token-store.interface.ts`) | `InMemoryTokenStore` — **frontera de cifrado documentada**: guarda el refresh token en texto plano en memoria; una implementación real DEBE cifrar antes de escribir y descifrar al leer (KMS vs. secreto de app, pendiente de infraestructura). |

**4ª pieza de estado — revocación de sesión.** Revocar la sesión (logout)
requiere saber qué refresh-token de sesión sigue vigente por usuario. Eso
no encaja en ninguna de las tres interfaces de arriba (son sobre
proveedores externos; esto es estado interno de sesión). Desde
`spec11-session-registry-interface.md` (cierra la deuda A1.5, FASE 1) sigue
el mismo patrón "mock ahora, Postgres/Redis después": `SessionRegistry`
(`session/session-registry.interface.ts`, token `SESSION_REGISTRY`) +
`InMemorySessionRegistry` (`session/in-memory-session-registry.ts`) —
antes era una clase concreta `session-registry.ts` inyectada directo, la
única pieza de estado del backend fuera de este patrón; ya no.

### Sesión JWT

Un solo secreto de firma (`JWT_SESSION_SECRET`); el claim `type`
(`session_access` / `session_refresh`) impide usar un access token como
refresh y viceversa. **Duraciones por defecto (a revisar por Kiro):**
access **15 minutos**, refresh **30 días**. Configurables por
`JWT_SESSION_ACCESS_TTL` / `JWT_SESSION_REFRESH_TTL`.

El refresh de sesión **no rota** en este MVP: el mismo refresh token sigue
siendo válido hasta que expira o hasta `logout` (que revoca todos los
refresh activos del usuario). Rotación (invalidar el refresh usado y emitir
uno nuevo en cada `/auth/refresh`) sería más seguro pero no se implementó
por mínima complejidad — señalado para que Kiro decida si es necesario para
producción.

### Códigos de error específicos

`AllExceptionsFilter` ahora respeta un `code` explícito cuando la excepción
lo trae (`src/common/exceptions/api.exception.ts`), en vez de derivarlo
siempre del status HTTP — necesario porque dos 401 distintos necesitan
distinguirse:

- `GOOGLE_AUTH_FAILED` (401) — code inválido/usado o identidad no verificable.
- `SESSION_REFRESH_INVALID` (401) — refresh de sesión inválido, expirado o revocado.
- `DRIVE_REAUTHORIZATION_REQUIRED` (401) — sin refresh de Google guardado, o Google lo rechazó (revocado por el usuario).
- `INVALID_REQUEST` (400) — falta `serverAuthCode` / `sessionRefreshToken`.
- Sin JWT de sesión válido en un endpoint protegido → 401 genérico `UNAUTHORIZED` (vía `SessionAuthGuard`).

### Seguridad

- El `serverAuthCode`, el refresh token de Google y los JWT de sesión
  **nunca se registran en logs**: todo fallo de estas rutas se captura y se
  relanza como un `ApiException` con mensaje fijo y genérico — el error
  original (que podría traer datos sensibles) se descarta, no se loguea.
  Cubierto por tests (unit + e2e) que espían `console.log/error/warn` y
  verifican que los valores sensibles nunca aparecen.
- Client ID/secret de Google y el secreto de firma del JWT se leen de
  variables de entorno (`@nestjs/config`, carga `.env` automáticamente) —
  ver `.env.example`. Nada hardcodeado.
- Validación de entrada manual (sin `class-validator`) por ser un único
  campo string por endpoint — decisión de mínima complejidad, no un hueco
  de seguridad (sigue rechazando con 400 cualquier body sin el campo).

### Tests

- `src/auth/auth.service.spec.ts` — unit, con `GoogleAuthClient` fake:
  alta/recuperación de usuario, refresh, logout revoca la sesión, broker de
  Drive (éxito, sin autorización previa, Google revocado), y que nada
  sensible se loguea.
- `test/auth.e2e-spec.ts` — e2e con `GOOGLE_AUTH_CLIENT` sobreescrito vía
  `overrideProvider`: login (éxito/400/401), guard en rutas protegidas,
  refresh, logout invalida el refresh, y el mismo chequeo de "nunca se
  loguea nada sensible" sobre el flujo HTTP completo.

## Biblioteca y álbumes (spec03-biblioteca-albumes)

Implementa `specs/memora-backend/spec03-biblioteca-albumes.md`: entidad
Álbum, modelo mínimo de Foto y la relación N:M Foto↔Álbum
(`producto-mvp.md`: una foto pertenece a un único propietario pero puede
estar en varios álbumes sin duplicarse). En esta spec la creación real de
fotos quedó fuera de alcance (era M3) — **spec04-fotografias.md la completa**,
ver esa sección más abajo para el estado actual (`src/albums/`).

### Endpoints — `/api/v1/albums`, todos protegidos por `SessionAuthGuard`

| Método | Ruta | Qué hace |
|---|---|---|
| `POST` | `/albums` | Crea un álbum (`{ name }`); el usuario autenticado queda como owner. Puede quedar vacío. |
| `GET` | `/albums` | Lista los álbumes del usuario (id, name, photoCount, fechas). |
| `GET` | `/albums/:id` | Álbum + sus fotos (referencias). Ver spec04 para cómo se agregan. |
| `PATCH` | `/albums/:id` | Renombra (`{ name }`), solo el owner. |
| `DELETE` | `/albums/:id` | Borra el álbum **y solo sus relaciones foto↔álbum** — ninguna foto, ninguna relación de esas fotos con OTROS álbumes, ningún archivo de Drive (D16). |

**Álbum inexistente o ajeno → 404 en ambos casos** (mismo `code: NOT_FOUND`,
para no revelar que un álbum ajeno existe). Sin sesión → 401. Nombre
vacío/>100 caracteres → 400 `INVALID_REQUEST`. Todo en el formato uniforme
`{ code, message, requestId }` — reutilizando `NotFoundException` /
`BadRequestException` de Nest (el filtro global ya deriva el `code`
correcto); no hizo falta inventar códigos nuevos, a diferencia de auth,
porque aquí no hay dos 404/400 distintos que distinguir.

### Modelo y relación N:M — `src/albums/`

- **`Album`** (`album.model.ts`): `id, ownerId, name, createdAt, updatedAt`.
- **`Photo`** (`photos/photo.model.ts`): modelo mínimo per `producto-mvp.md`
  D8. En spec03 excluía disponibilidad; **spec04 la añade** (ver más abajo).
  Sigue excluyendo GPS/EXIF (D8, privacidad).
- **`AlbumRepository`** (mock en memoria, `in-memory-album.repository.ts`)
  posee tanto los álbumes como la relación N:M (`Set<photoId>` por álbum —
  añadir la misma foto dos veces no la duplica). `delete(albumId)` borra
  el álbum y **solo** su propio `Set` de relaciones; el resto de álbumes de
  esa foto quedan intactos.
- **`PhotoRepository`** (mock en memoria) — en spec03 no tenía ruta HTTP;
  **spec04 la completa** (registro, borrado) — ver más abajo.

### Tests

- `src/albums/albums.service.spec.ts` — unit: crear/listar/obtener/renombrar,
  404 uniforme para álbum ajeno o inexistente (get/rename/delete),
  **una foto en 2 álbumes sobrevive al borrar uno** (D16), y que añadir la
  misma foto dos veces no la duplica.
- `test/albums.e2e-spec.ts` — e2e de los 5 endpoints: éxito, 401 sin sesión,
  400 nombre inválido/demasiado largo, 404 inexistente/ajeno (get/patch/delete).

### Nota de infraestructura de tests (no es un bug de negocio) — actualizada en spec04

`test/albums.e2e-spec.ts` y `test/photos.e2e-spec.ts` usan **una sola app
Nest por archivo** (`beforeAll`/`afterAll`) en vez de una por test. Con
muchos tests creando/cerrando una app+servidor HTTP efímero cada uno, se
reproduce de forma intermitente un `Parse Error: Expected HTTP/` (o
`ECONNRESET`) de supertest/Node — un socket reciclado de un servidor
anterior, no un fallo de la lógica de negocio.

**Actualización (spec04):** la deuda que quedó señalada en spec03 se
confirmó real — al sumar `photos.e2e-spec.ts` (4 archivos e2e en total, más
volumen de peticiones), `test/app.e2e-spec.ts` (que SÍ seguía con una app
por test) empezó a mostrar el mismo flake en corridas de stress. Como sus
tests no mutan estado compartido, se migró también a `beforeAll`/`afterAll`
— cambio mecánico, sin tocar su lógica.

Durante el diagnóstico salieron dos hallazgos más, uno real y evitable, otro
residual:
- **Un proceso `jest` de una sesión de diagnóstico anterior (spec03) quedó
  colgado 4+ horas** consumiendo un puerto/handle y disparando el load
  promedio del sistema — al matarlo, corridas que tardaban 300+ s (timeout
  de hooks) volvieron a ~4 s. Si algo así vuelve a pasar, revisar `ps aux |
  grep jest` antes de dar por bueno un flake.
- Un test de `photos.e2e-spec.ts` disparaba 3 peticiones **concurrentes**
  (`Promise.all`) justo tras un `DELETE` — era el que más fallaba de todos.
  Cambiado a secuencial: las peticiones concurrentes contra el mismo
  servidor efímero de test parecen presionar más el pool de conexiones de
  supertest/Node.

Con ambos corregidos, 38 tests e2e en 30 corridas seguidas: ~5/30 con **un**
fallo aislado de transporte (`Parse Error: Expected HTTP/`, `ECONNRESET`),
nunca dos veces el mismo test, nunca un fallo de aserción real sobre la
lógica de negocio. Tasa similar a la ya documentada y aceptada en spec03 —
no empeoró, pero tampoco se eliminó del todo. Profundizar más (p. ej.
forzar `Connection: close` globalmente, o unificar los 4 archivos en una
sola app compartida) es un cambio de infraestructura de tests más grande;
lo señalo para que Kiro decida si vale la pena antes de que seguir creciendo
la suite lo vuelva a agravar.

`test/auth.e2e-spec.ts` **no** se tocó: sus tests sí mutan estado de sesión
compartido (login/logout con la misma identidad de usuario falsa) — compartir
una sola app entre ellos introduciría dependencias de orden de ejecución
(p. ej. el test de logout revocaría una sesión que otro test posterior
podría necesitar). No ha mostrado el flake en ninguna corrida de stress
hecha hasta ahora. Si llegara a mostrarlo, requeriría generar identidades de
usuario únicas por test antes de poder compartir la app de forma segura —
señalado para Kiro, no resuelto aquí por no haber evidencia de que haga falta.

## Fotografías (spec04-fotografias)

Implementa `specs/memora-backend/spec04-fotografias.md`: registro de fotos y
coordinación de subida (Opción A) — el backend **nunca** recibe, guarda ni
proxea bytes de imágenes; el cliente sube directo a Drive del usuario (con
el token efímero de `POST /auth/drive-token`, spec02) y solo informa al
backend la referencia (`driveFileId`) + metadatos.

### Endpoints — todos protegidos por `SessionAuthGuard`

| Método | Ruta | Qué hace |
|---|---|---|
| `POST` | `/api/v1/photos` | Registra una foto ya subida a Drive (`{ driveFileId, ...metadatos, albumId? }`). Owner = usuario autenticado. Asocia a `albumId` de una vez si viene (404 si ese álbum no es tuyo). |
| `DELETE` | `/api/v1/photos/:photoId` | Olvida la foto en Memora y la quita de **todos** los álbumes. El archivo de Drive nunca se toca. |
| `GET` | `/api/v1/library` | Biblioteca personal (D11): fotos del usuario, independiente de a qué álbumes pertenezcan. |
| `POST` | `/api/v1/albums/:albumId/photos` | Asocia una foto ya existente (`{ photoId }`) a un álbum (N:M). Idempotente — asociar dos veces no duplica. |
| `DELETE` | `/api/v1/albums/:albumId/photos/:photoId` | Quita solo la relación (D3/D4) — nunca borra la foto ni el archivo. |

Foto o álbum ajeno/inexistente → 404 uniforme (mismo criterio que M2:
no revela que el recurso ajeno existe). Sin sesión → 401. `driveFileId`
faltante o un campo opcional con tipo/valor inválido (ancho negativo, fecha
no parseable, etc.) → 400 `INVALID_REQUEST`.

### Modelo `Photo` completo (D8) — `src/albums/photos/`

```
id, ownerId, driveFileId, createdAt, capturedAt?, width?, height?,
mimeType?, sizeBytes?, availability ("available" | "unavailable")
```

- **Sin geolocalización** — el tipo TypeScript no tiene campo para ello; no
  es una validación de entrada, es que no existe dónde guardarlo.
- **`availability`** por defecto `"available"` al registrar — `PhotoRepository.create()`
  la fija internamente, ningún caller la pasa. La verificación real contra
  Drive (D9/M6) queda fuera de esta spec; aquí solo se transporta el campo.
- Solo `driveFileId` es obligatorio en el registro; el resto de metadatos
  son opcionales (el cliente podría no tener todos, p. ej. si falla leer
  dimensiones de un formato raro) — decisión de implementación, no bloqueante.

### Relación N:M completa — `src/albums/photos/photos.service.ts`

`PhotosService` depende de `AlbumRepository` **y** `PhotoRepository` (la
relación en sí sigue viviendo en `AlbumRepository`, como en M2). Añadido en
esta spec: `AlbumRepository.removePhotoFromAllAlbums(photoId)` — recorre
todos los álbumes quitando esa foto de cada uno; lo usa `DELETE /photos/:id`
para cumplir "borrar una foto la quita de todos los álbumes" sin necesitar
un índice inverso (a esta escala, in-memory, recorrer todos los álbumes es
suficiente — no se optimizó de más).

`src/common/authorization/require-owned.ts` (nuevo, genérico): el chequeo
"existe y es del usuario, si no 404" se repetía en `AlbumsService` y ahora
también en `PhotosService` (álbum Y foto) — se extrajo como 2º+3º consumidor,
mismo criterio que `requireStringField` en M2.

### Tests

- `src/albums/photos/photos.service.spec.ts` — unit: registro con metadatos
  y sin geolocalización, registro+asociación en un paso, asociar/desasociar
  sin duplicar, **borrar una foto la quita de todos sus álbumes sin afectar
  una foto hermana ni el propio archivo**, biblioteca filtrada por owner,
  404 uniforme en las combinaciones álbum/foto ajenos.
- `test/photos.e2e-spec.ts` — e2e de los 5 endpoints (éxito + 400/401/404),
  con el patrón `beforeAll`/`afterAll` (ver nota de infraestructura arriba).

## Colaboradores (spec05-colaboradores)

Implementa `specs/memora-backend/spec05-colaboradores.md`: roles Owner/
Collaborator por álbum (D1), invitación por enlace de un solo uso (D12/D13),
lectura y aporte de fotos por colaboradores (multi-Drive dentro de un mismo
álbum), y administración de colaboradores (D5). Todo dentro de
`src/albums/` — colaboradores viven en el subdirectorio nuevo
`src/albums/collaborators/`.

### Endpoints

Todos protegidos por `SessionAuthGuard` (401 sin sesión).

| Método | Ruta | Quién | Qué hace |
|---|---|---|---|
| `POST` | `/api/v1/albums/:albumId/invitations` | owner | Crea invitación `pending`, expira a `INVITATION_TTL_DAYS` días (default 7). Responde `{ id, token, url, status, expiresAt, createdAt }` — `url` construida sobre `APP_INVITE_BASE_URL`. |
| `GET` | `/api/v1/albums/:albumId/invitations` | owner | Lista invitaciones con su estado. El `token`/`url` solo se incluyen mientras la invitación sigue `pending`. |
| `DELETE` | `/api/v1/albums/:albumId/invitations/:invitationId` | owner | Revoca una invitación `pending`. Idempotente si ya no estaba `pending` (accepted/revoked/expired). |
| `POST` | `/api/v1/invitations/:token/accept` | autenticado | Canjea el token. 204 si queda como collaborator (o si ya era miembro — idempotente). 410 `INVITATION_NOT_USABLE` si el token es desconocido, o la invitación está `accepted`/`revoked`/`expired` y el caller **no** es ya miembro. |
| `GET` | `/api/v1/albums` | autenticado | **Cambiado (P3, aditivo):** una sola lista, propios + donde colabora, con campo `role` (`'owner'|'collaborator'`) por álbum. |
| `GET` | `/api/v1/albums/:id` | owner o collaborator | **Cambiado:** antes owner-only; ahora abierto a membresía. 404 uniforme sin membresía. |
| `POST` | `/api/v1/photos` (con `albumId`) | owner o collaborator del álbum | **Cambiado:** un colaborador puede aportar; `Photo.ownerId` sigue siendo quien registra (su Drive). |
| `POST` | `/api/v1/albums/:albumId/photos` | owner o collaborator del álbum, dueño de la foto | **Cambiado:** requiere membresía en el álbum (antes owner-only) + seguir siendo dueño de la foto (sin cambios). |
| `DELETE` | `/api/v1/albums/:albumId/photos/:photoId` | owner (cualquier foto) / collaborator (solo las suyas) | **Cambiado:** antes solo el owner podía; ahora el owner quita cualquiera (D4) y el colaborador solo sus propias aportaciones — foto ajena → 404 uniforme. |
| `DELETE` | `/api/v1/photos/:photoId` | dueño de la foto | Sin cambios de contrato. |
| `GET` | `/api/v1/albums/:albumId/collaborators` | owner | Lista `{ userId, role, joinedAt }` de cada colaborador. |
| `DELETE` | `/api/v1/albums/:albumId/collaborators/:userId` | owner | Quita a un colaborador (D5: sus fotos históricas quedan). El owner no puede quitarse a sí mismo → 400 `CANNOT_REMOVE_OWNER`. |
| `DELETE` | `/api/v1/albums/:albumId/collaborators/me` | collaborator (P1) | El propio colaborador abandona; mismo efecto que ser quitado (D5). Requiere membresía → 404 uniforme si no eres miembro. El owner no puede "abandonar" su propio álbum por aquí → 400 `CANNOT_LEAVE_AS_OWNER`. |
| `DELETE` | `/api/v1/albums/:id` | owner | **Cambiado (D16):** además del álbum y sus relaciones foto↔álbum, ahora también borra sus membresías y sus invitaciones. Nunca borra `Photo` ni Drive. |

Álbum inexistente o sin membresía del solicitante → 404 uniforme, nunca 403
(mismo criterio que M2, extendido a "requiere membresía" en vez de solo
"requiere ownership"). Token de invitación inválido/expirado/revocado/ya
usado → 410 `INVITATION_NOT_USABLE`. El owner no puede quitarse a sí mismo
ni abandonar su propio álbum → 400 (`CANNOT_REMOVE_OWNER` /
`CANNOT_LEAVE_AS_OWNER`).

### Modelo y decisiones de implementación tomadas dentro de la spec (aprobada, sin nada pendiente de Kiro)

- **`AlbumMembership` (`src/albums/collaborators/album-membership.model.ts`)**
  — la fila de **owner nunca se persiste**: se deriva de `Album.ownerId` al
  vuelo (`AlbumAccessService`). `MembershipRepository` solo guarda filas
  `role: 'collaborator'`. La spec dejaba esto explícitamente abierto ("sin
  cambiar contrato") — se eligió derivar porque no hay transferencia de
  propiedad en el MVP, así que una fila de owner persistida nunca cambiaría
  y sería puro estado duplicado que sincronizar sin beneficio.
- **`AlbumAccessService`** (`src/albums/collaborators/album-access.service.ts`)
  — extiende el patrón `requireOwned` a "requiere membresía": `getRole`,
  `requireMembership` (404 uniforme si no hay owner ni collaborator) y
  `requireOwner` (mismo 404 que `requireOwned`, para las rutas de gestión).
  No es una función pura como `requireOwned` porque resolver el rol necesita
  dos lecturas de repositorio (álbum + membresía) — es un servicio
  inyectable, reutilizado por `AlbumsService`, `PhotosService`,
  `InvitationsService` y `CollaboratorsService`, todos dentro de
  `AlbumsModule`.
- **`PhotosService`** — `register`/`associate` ahora exigen membresía en el
  álbum (owner o collaborator) en vez de ownership; la propiedad de la
  `Photo` en sí no cambia (sigue siendo `requireOwned` sobre la foto).
  `disassociate` ahora resuelve el rol primero: el owner puede quitar
  cualquier foto (D4), un collaborator solo las que él mismo aportó — si
  intenta quitar una ajena, 404 uniforme (mismo mensaje que "foto no
  encontrada", para no revelar que existe).
- **`GET /albums` vs. `POST/PATCH /albums` y `GET /albums/:id`** — el campo
  `role` (P3) solo se añadió al endpoint de **lista**, tal como pide la
  spec explícitamente ("aditivo, no rompe M2"). Deliberadamente **no** se
  añadió a la respuesta de creación/renombrado ni al detalle de álbum — no
  estaba en el alcance de P3 y habría roto los `toEqual` exactos de
  `test/albums.e2e-spec.ts` (spec03) sin necesidad.
- **`AlbumsService.getForOwner`/`listForOwner` renombrados a `getForUser`/
  `listForUser`** — reflejan que ya no son owner-only. Es un cambio interno
  (no afecta contrato HTTP); se actualizaron todos los call sites y los
  tests unitarios existentes.
- **Orden de checks en `POST /invitations/:token/accept`** (la spec da dos
  reglas — P5 410 para no-pending, P5 204 idempotente si ya eres miembro —
  sin fijar el orden cuando ambas podrían aplicar): se decidió comprobar
  **primero** si el caller ya es miembro (owner o collaborator) — si lo es,
  204 sin mirar el estado de la invitación. Solo si NO es miembro se evalúa
  si la invitación sigue `pending` y no expirada (si no, 410). Esto hace
  que re-aceptar tu propio enlace ya usado sea idempotente incluso si el
  token quedó `accepted`, y sigue cumpliendo P6 (un tercero no puede usar
  ese mismo token, porque no es miembro y el token ya no está `pending`).
- **Expiración de invitaciones (`'expired'`)** se detecta de forma
  **perezosa**: el repositorio en memoria no tiene reloj propio, así que
  `InvitationsService` compara `expiresAt` con `Date.now()` en cada lectura
  (`list`/`accept`/`revoke`) y persiste la transición a `'expired'` la
  primera vez que la detecta.
- **Exposición del token en `GET .../invitations`**: solo se incluye
  `token`/`url` mientras la invitación está `pending`. La spec solo exige
  ocultarlo para las `accepted` ("sin exponer el token en claro de
  invitaciones ya aceptadas"); se optó por ocultarlo también en
  `revoked`/`expired` (más conservador — ya no sirven, no hay razón para
  seguir mostrando un secreto muerto) — no contradice la spec, la extiende
  en la dirección más segura.
- **Revocar una invitación no-`pending`** (spec no define el error): se
  hizo idempotente — revocar una ya `accepted`/`revoked`/`expired` no lanza
  error, simplemente no hace nada (ya no es usable de todas formas).
- **`DELETE .../collaborators/me` llamado por el propio owner** (caso no
  cubierto explícitamente por la spec, que describe este endpoint para
  colaboradores): se rechaza con 400 `CANNOT_LEAVE_AS_OWNER` en vez de ser
  un no-op silencioso — evita que un owner "abandone" su álbum sin que pase
  nada, lo cual sería una confusión de UX en el cliente.
- **`AlbumRole` como `'owner' | 'collaborator'`** vive en
  `album-membership.model.ts` y se reexporta desde ahí — un solo lugar,
  sin duplicar el union type entre repositorio, servicio y controladores.
- **`ConfigModule` se hizo `isGlobal: true`** en `AuthModule` (antes
  `ConfigModule.forRoot()` sin más opciones) para que `InvitationsService`
  (en `AlbumsModule`) pueda inyectar `ConfigService` sin que `AlbumsModule`
  tenga que volver a registrar/importar `ConfigModule` — mismo patrón ya
  usado por `GoogleOAuthClient`/`SessionTokenService`, ahora disponible sin
  fricción a cualquier módulo futuro.

### Tests

- `src/albums/collaborators/album-access.service.spec.ts` — cubierto
  indirectamente vía los specs de `AlbumsService`/`PhotosService`/
  `InvitationsService`/`CollaboratorsService` (todos lo inyectan); no tiene
  spec propio porque no añade lógica de negocio más allá de componer
  `AlbumRepository` + `MembershipRepository`.
- `src/albums/collaborators/invitations.service.spec.ts` — unit: crear con
  URL/token/TTL (default y configurado), owner-only al crear/listar/
  revocar, aceptar (feliz, idempotente para ya-miembro incluyendo el propio
  owner, 410 para revocada/expirada/desconocida, un tercero no puede reusar
  una ya aceptada), expiración detectada perezosamente y persistida, token
  oculto tras aceptar pero visible mientras `pending`, revocar es
  idempotente.
- `src/albums/collaborators/collaborators.service.spec.ts` — unit: listar,
  quitar colaborador (owner-only, no puede quitarse a sí mismo), abandonar
  (requiere membresía, el owner no puede abandonar por aquí).
- `src/albums/albums.service.spec.ts` — ampliado: listado combinado con
  `role`, lectura por collaborator, 404 uniforme sin membresía, borrar
  álbum limpia membresías + invitaciones.
- `src/albums/photos/photos.service.spec.ts` — ampliado: colaborador
  registra/asocia fotos propias, no puede asociar ajenas, un no-miembro no
  puede aportar, el owner quita cualquier foto (incluida la de un
  colaborador, D4), el colaborador solo quita las suyas.
- `test/collaborators.e2e-spec.ts` — e2e con **3 usuarios reales** (owner,
  collaborator, outsider) vía un fake `GoogleAuthClient` con 3 códigos,
  patrón `beforeAll`/`afterAll`, sin `Promise.all` en peticiones
  concurrentes (mismo criterio que `photos.e2e-spec.ts`, ver nota de
  infraestructura arriba). Cubre los criterios de validación de la spec:
  ciclo completo de invitación (crear/listar/revocar/aceptar), 410 por
  token inválido/revocado/reusado, lectura y aporte por collaborator,
  quitar foto ajena vs. propia, administrar y abandonar colaboradores,
  limpieza de membresías/invitaciones al borrar el álbum.

### Env vars nuevas

Opcionales, con default en código — no hace falta configurarlas en dev:

- `APP_INVITE_BASE_URL` (default `https://memora.app/invite/{token}`) — debe
  contener el placeholder `{token}`; nunca hardcodear el dominio.
- `INVITATION_TTL_DAYS` (default `7`).

## Disponibilidad (spec07-disponibilidad)

Implementa `specs/memora-backend/spec07-disponibilidad.md`: disponibilidad
**perezosa** (D9) de las fotos — no hay sync activa (ni polling ni
webhooks). El campo `Photo.availability` ya existía desde spec04; esta spec
define cómo se actualiza, quién lo verifica y cómo se expone.

### Hallazgo que fija el diseño (P1)

El backend **no maneja bytes** y no tiene, ni añade aquí, ningún cliente que
lea archivos de Drive — con scope `drive.file`, solo el **propietario** de
un archivo puede verificar su existencia (su token no ve archivos ajenos),
así que el owner de un álbum no podría verificar la disponibilidad de una
foto aportada por un colaborador aunque quisiera. Por tanto: **el cliente
verifica contra Drive** (con su `drive-token` de spec02, foto por foto,
usando `driveFileId`) y **reporta el resultado**; el backend solo
**persiste** ese reporte. No hay ninguna llamada saliente a la Drive API en
este backend — verificable por grep (`googleapis`/`drive.files` no aparece
fuera de `google-oauth.client.ts`, que solo emite el token efímero de
spec02, nunca lee archivos).

### Endpoints — todos protegidos por `SessionAuthGuard`, owner-only sobre la foto

| Método | Ruta | Qué hace |
|---|---|---|
| `PATCH` | `/api/v1/photos/:photoId/availability` | Reporte individual (`{ availability: 'available' \| 'unavailable' }`). Devuelve la `Photo` actualizada. |
| `POST` | `/api/v1/photos/availability` | Reporte batch (`{ reports: [{ photoId, availability }] }`) tras revisar un álbum completo. `204 No Content`. |

- Foto ajena o inexistente en el endpoint individual → **404 uniforme**
  (mismo criterio que el resto del backend, nunca 403).
- En el batch, cada entrada se evalúa contra el propietario que llama: una
  entrada de foto ajena o inexistente **se ignora silenciosamente** — no
  lanza error ni rompe el resto del batch (así no se revela si un
  `photoId` ajeno existe, y una sola entrada mala no descarta las demás).
- Reportar `available` sobre una foto `unavailable` la **recupera** (D9) —
  no hay restricción de transición; cualquier valor sobre cualquier estado
  anterior es válido.
- Body validado a mano (`src/albums/photos/parse-availability-input.ts`),
  mismo patrón que `parse-register-photo-input.ts`: `400 INVALID_REQUEST`
  si `availability` no es `'available'`/`'unavailable'`, o si `reports` no
  es un array de entradas con esa forma.

### Modelo — `Photo.availabilityCheckedAt?: Date` (P4)

Se añadió junto a `availability` (`photo.model.ts`). Se estampa con
`new Date()` en cada reporte aplicado (`PhotoRepository.updateAvailability`,
implementado en `in-memory-photo.repository.ts` con el mismo patrón que
`rename()` de `in-memory-album.repository.ts`: un `requirePhoto()` privado
que lanza si el id no existe — nunca debería dispararse en la práctica
porque los callers de `PhotosService` ya comprobaron ownership/existencia
antes de llamar). Ausente hasta el primer reporte — no se fija al registrar
la foto.

### Exposición — el backend marca, no filtra (P3)

`GET /api/v1/albums/:id` (vía `AlbumsService.getForUser`) y
`GET /api/v1/library` (vía `PhotosService.listLibrary`) ya devolvían
objetos `Photo` completos sin mapear a DTO — añadir el campo al modelo
bastó para exponerlo ahí sin tocar esos servicios/controllers. Ninguno de
los dos filtra fotos `unavailable`; el cliente decide cómo mostrarlas.
Verificado con un test e2e explícito (no se dio por hecho).

### No-regresión: renombrar/mover en Drive no afecta disponibilidad

El backend nunca modela nombre/ruta (D8: sin GPS/EXIF, y tampoco hay campo
de nombre/ruta en `Photo`) y todos los métodos de reporte localizan la foto
por `id`/`driveFileId`, nunca por nombre — así que esto se cumple por
construcción. Cubierto por un test explícito en
`src/albums/photos/photos.service.spec.ts` que deja constancia del
contrato (el modelo no tiene campo de nombre/ruta que cambiar, y re-reportar
`available` tras un rename/move hipotético dejaría el estado exactamente
igual).

### Tests

- `src/albums/photos/photos.service.spec.ts` — ampliado: reportar
  `unavailable` con `availabilityCheckedAt` estampado, recuperar
  (`unavailable` → `available`, D9), 404 uniforme al reportar sobre foto
  ajena/inexistente, batch con mezcla de fotos propias y ajenas (las
  propias se aplican, la ajena no rompe nada), reflejo en la lectura que
  compone `getForUser`/en `listLibrary` sin filtrar, y el test de
  no-regresión de renombrar/mover.
- `test/photos.e2e-spec.ts` — ampliado: login real de dos usuarios (ya
  existente en el archivo), reporte individual (éxito, recuperación, 400
  valor inválido, 401 sin sesión, 404 ajena/inexistente), batch (éxito,
  entrada ajena ignorada sin romper el resto, 400 shape inválido, 401), y
  un test dedicado a que `GET /albums/:id` y `GET /library` incluyan
  `availability`/`availabilityCheckedAt` sin filtrar fotos `unavailable`.

## Abstracción de almacenamiento (spec08)

Implementa `specs/memora-backend/spec08-abstraccion-almacenamiento.md`:
desacopla el dominio del proveedor concreto de almacenamiento (hoy Google
Drive, el único del MVP) detrás de una referencia física neutral y una
interfaz de coordinación. **No** es una migración — Google Drive sigue
siendo el único proveedor; solo queda detrás de una interfaz reemplazable.
El backend sigue sin manejar bytes.

### Referencia física neutral — `Photo.storageRef`

`src/albums/photos/photo.model.ts` reemplaza el antiguo `driveFileId: string`
por:

```ts
type StorageProvider = 'google-drive'; // único valor en el MVP
interface StorageRef { provider: StorageProvider; fileId: string }
```

`Photo.storageRef: StorageRef` sustituye a `Photo.driveFileId`. `fileId`
lleva exactamente el mismo valor que antes (referencia estable, nunca
nombre/ruta — spec04); `provider` es nuevo y deja lugar a un futuro valor
(p. ej. `'b2'`) sin ensanchar el tipo a `string`.

### Contrato de API (cambio aditivo, sin clientes en producción aún)

- **Entrada** `POST /api/v1/photos`: el cliente envía
  `storageRef: { fileId, provider? }`. `provider` es opcional — si se omite,
  `PhotosService.register` aplica el default `'google-drive'` (único valor
  del MVP); si se envía, debe ser exactamente `'google-drive'` o el parseo
  (`parse-register-photo-input.ts`) responde 400 `INVALID_REQUEST`. Se eligió
  esta forma (en vez de "fileId suelto + provider implícito") porque ya deja
  el body con la forma final multi-provider, sin necesitar otro cambio de
  contrato cuando se añada un segundo proveedor.
- **Salida** `GET /api/v1/albums/:id` y `GET /api/v1/library`: cada `Photo`
  expone `storageRef: { provider, fileId }` en vez de `driveFileId`. Ambos
  endpoints devuelven objetos `Photo` completos sin DTO intermedio (mismo
  patrón que expuso `availability`/`availabilityCheckedAt` en spec07), así
  que el cambio de modelo bastó — verificado con tests e2e explícitos en
  ambos endpoints, no asumido.

### Interfaz `PhotoStorage` — `src/albums/photos/storage/`

Mismo patrón de DI que `PhotoRepository`/`AlbumRepository`: interfaz +
token `Symbol('PHOTO_STORAGE')` + una implementación registrada en
`AlbumsModule`.

| Operación | Estado en el MVP |
|---|---|
| `getUploadAuthorization(userId)` | Implementada — envuelve `AuthService.getDriveAccessToken` (el broker `drive-token` de spec02), sin duplicar la lógica de refresh-token. |
| `getReadReference(photo)` | Implementada — devuelve `{ provider, fileId }` neutral; no llama a Drive, el cliente/visor resuelve la lectura con su propio token. |
| `describe(photo)` / `exists(photo)` | Declaradas, NO soportadas server-side en el MVP — la verificación real la hace el cliente y la reporta (spec07-disponibilidad). Lanzan `STORAGE_OPERATION_UNSUPPORTED`. |
| `download`/`stream` | Declaradas, NO implementadas — el backend no maneja bytes (Opción A). `STORAGE_OPERATION_UNSUPPORTED`. |
| `copy` | Declarada, NO implementada — es M5 (`spec06-adoptar.md`), diferido. `STORAGE_OPERATION_UNSUPPORTED`. |
| `delete` | Declarada, NO implementada — Memora nunca borra del Drive del usuario por principio (`producto-mvp.md`, "no custodio"). `STORAGE_OPERATION_UNSUPPORTED`. |

Todas las operaciones no soportadas fallan con el contrato de error uniforme
del backend (`{ code: 'STORAGE_OPERATION_UNSUPPORTED', message, requestId }`,
HTTP 501) vía `photo-storage.errors.ts` — nunca un error crudo. Fábrica y
patrón calcados de `auth.errors.ts`/las funciones de error de
`collaborators/`.

### `GoogleDrivePhotoStorage` — única implementación viva

`src/albums/photos/storage/google-drive-photo-storage.ts` inyecta
`AuthService` (no `GoogleAuthClient` directamente) para reusar
`getDriveAccessToken` sin duplicar el lookup del refresh token guardado ni
añadir ninguna llamada real a la API de Drive — el backend sigue sin
consultarla. `AuthModule` tuvo que exportar `AuthService` (antes solo
exportaba `SessionAuthGuard` y su dependencia `SessionTokenService`) para
que `AlbumsModule` (que ya importa `AuthModule` para el guard) pueda
inyectarlo aquí — mismo patrón ya documentado: "exportar también las
dependencias que el consumidor necesita".

`GoogleDrivePhotoStorage` está registrada en `AlbumsModule` con el token
`PHOTO_STORAGE`, pero ningún servicio la inyecta todavía — es la
abstracción en paralelo que pide la spec para uso interno/futuro (M7,
futuros servicios), no un reemplazo del endpoint HTTP `POST
/auth/drive-token`, que sigue existiendo igual y sin tocar.

### Pureza del dominio — verificada, no asumida

`src/albums/domain-storage-neutrality.spec.ts` escanea todo `.ts` bajo
`src/albums` (excluyendo `photos/storage/`, los `*.module.ts` de wiring de
DI, y los propios `*.spec.ts`) y falla si aparece literalmente `Drive` o
`driveFileId` — así que álbumes, colaboradores, disponibilidad y biblioteca
no pueden volver a acoplarse al proveedor concreto sin que un test lo marque
en rojo. `Drive` solo puede aparecer en `photos/storage/` (la implementación
concreta) y en `auth/` (el broker real, spec02) — nunca en el resto del
dominio.

### Fuera de alcance (explícito, decisión del PO)

Migrar fotos existentes; añadir Backblaze B2 (documentado como dirección
futura seria, no implementado); cambiar scopes OAuth; implementar M5
(copia); implementar borrado real en Drive; hacer que el backend maneje
bytes o consulte la Drive API. Ver la spec para el detalle completo de la
dirección futura (B2 como candidato a storage principal, Drive pasando a
respaldo).

### Tests

- `src/albums/photos/storage/google-drive-photo-storage.spec.ts` — unit:
  `getUploadAuthorization` delega en `AuthService` y propaga sus errores sin
  envolver nada; `getReadReference` no llama a Drive; cada operación no
  soportada (`describe`/`exists`/`download`/`stream`/`copy`/`delete`) lanza
  `STORAGE_OPERATION_UNSUPPORTED` con status 501.
- `src/albums/photos/photos.service.spec.ts` — ampliado: el registro
  defaultea `storageRef.provider` a `'google-drive'` cuando el caller no lo
  envía.
- `src/albums/domain-storage-neutrality.spec.ts` — el grep automatizado
  descrito arriba.
- `test/photos.e2e-spec.ts` — todos los tests migrados de `driveFileId` a
  `storageRef`; test explícito de que `POST /photos` asigna
  `provider: 'google-drive'`, y de que `GET /albums/:id` expone `storageRef`
  en cada foto (además del ya existente para `GET /library`).
- `test/collaborators.e2e-spec.ts` — migrado a `storageRef` sin cambios de
  comportamiento.

## Compartir y visor (spec09-compartir-visor)

Implementa `specs/memora-backend/spec09-compartir-visor.md`: `Album.visibility`
(D17) y un **enlace de compartición** de solo lectura que expone la
resolución **pública** del visor. Es el **primer endpoint público** de este
backend — todo lo demás sigue protegido por `SessionAuthGuard`.

### Visibilidad del álbum (D17)

`Album.visibility: 'PRIVATE' | 'PUBLIC'` (`src/albums/album.model.ts`),
default `'PRIVATE'` al crear. Fijable opcionalmente en `POST /albums`;
cambiable con `PATCH /albums/:id` (owner-only). Reflejada en todas las
respuestas de álbum (`AlbumsService.toSummary`).

**Importante — `visibility` NO controla el acceso al enlace de
compartición en el MVP.** Un álbum `PRIVATE` es igual de visible por su
enlace que uno `PUBLIC` (P5): el campo solo marca intención de producto
para un futuro catálogo/descubrimiento, que aquí explícitamente NO se
implementa. No lo confundas con un control de acceso real.

`PATCH /albums/:id` ahora acepta `name` y/o `visibility` (antes solo
`name`) — al menos uno de los dos debe venir, o 400 `INVALID_REQUEST`
(`parseAlbumUpdate` en `albums.controller.ts`). Ambos pueden cambiar en la
misma llamada.

### Endpoints — gestión del enlace (autenticado, owner-only)

| Método | Ruta | Qué hace |
|---|---|---|
| `POST` | `/api/v1/albums/:albumId/share-link` | Crea el enlace o **devuelve el existente** si ya hay uno activo (P5, uno por álbum). Responde `{ token, url }` — `url` construida sobre `APP_SHARE_BASE_URL`. |
| `DELETE` | `/api/v1/albums/:albumId/share-link` | Revoca el enlace. Idempotente si no había enlace o ya estaba revocado. |

No hay un `GET` dedicado de "estado del enlace" — el propio `POST`
idempotente lo cubre (ver más abajo, "Decisiones").

### Endpoint público — resolución del visor

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/api/v1/shared/:token` | **PÚBLICO — sin `SessionAuthGuard`, sin sesión.** Dado un token válido y activo, devuelve `{ name, photos: [...] }` de solo lectura. |

- Token inexistente, revocado, o cuyo álbum fue eliminado → **404 uniforme**
  (`{ code: 'NOT_FOUND', message, requestId }`), sin distinguir el caso (P1).
- Solo lista fotos con `availability === 'available'` — las `unavailable`
  se **omiten** del array, nunca se marcan (P3). Esto es distinto de las
  vistas autenticadas (`GET /albums/:id`, `GET /library`), que sí muestran
  `unavailable` marcada (spec07).
- Superficie mínima (P4): cada foto expone `{ id, storageRef, width?,
  height?, mimeType?, capturedAt? }`. **NUNCA** `ownerId`, ningún id de
  usuario, email/nombre de personas, lista de colaboradores, el token del
  share-link, ni ningún otro token. `Photo.id` (UUID de Memora) SÍ se
  incluye — es un identificador de lista, no una identidad de persona.
- El backend no sirve bytes: el visor pide los bytes al proveedor con
  `storageRef` (spec08).

### Cómo queda público sin ningún mecanismo especial

Este backend **nunca registra un guard global** (`APP_GUARD`) — cada
controller aplica `@UseGuards(SessionAuthGuard)` explícitamente sobre sí
mismo. `SharedController` (`src/albums/shared/shared.controller.ts`)
simplemente **no lleva ese decorador** — no hace falta ningún "opt-out",
la ausencia del guard ES el mecanismo. Sigue heredando el contrato de
error uniforme y la correlación `x-request-id` porque `configureApp()`
(`src/bootstrap.ts`) los aplica de forma global, independiente de los
guards.

### Modelo — `src/albums/shared/`

- **`ShareLink`** (`share-link.model.ts`): `{ id, albumId, token, status:
  'active'|'revoked', createdAt }`. Mismo patrón de token opaco que
  `Invitation` (spec05): `randomBytes(32).toString('base64url')`.
- **`ShareLinkRepository`** (interfaz + `Symbol` + mock en memoria,
  `in-memory-share-link.repository.ts`): guarda **como mucho una fila por
  `albumId`** (`Map<albumId, ShareLink>`) — eso, por construcción, es lo
  que hace "un enlace por álbum" (P5). `create()` siempre genera una fila
  nueva (nuevo id/token) que **reemplaza** cualquier fila anterior (activa
  o revocada) de ese álbum — así "revocar y volver a crear" da un token
  nuevo en vez de reactivar el viejo.
- **`ShareLinksService`** — gestión owner-only (`createOrGetExisting`,
  `revoke`), vía `AlbumAccessService.requireOwner`. Lee
  `APP_SHARE_BASE_URL` con `ConfigService`, nunca `process.env` directo
  (mismo patrón que `InvitationsService`/`APP_INVITE_BASE_URL`).
- **`SharedViewService`** — resolución pública: busca el `ShareLink` por
  token, exige `status === 'active'` y que el álbum todavía exista, filtra
  fotos disponibles y proyecta al DTO mínimo (`SharedAlbumView`/
  `SharedPhotoView`). Nunca reutiliza `AlbumDetail`/`Photo` tal cual (esos
  sí llevan `ownerId`).

### Invalidación (D16)

`AlbumsService.delete()` ahora también llama a
`shareLinks.deleteByAlbumId(albumId)`, igual que ya hacía con membresías e
invitaciones (spec05). Es **defensa en profundidad**, no el único
mecanismo: `SharedViewService.resolve()` además comprueba que el álbum
siga existiendo antes de servir nada, así que aunque la fila del
`ShareLink` sobreviviera por cualquier motivo, la resolución seguiría
dando 404.

### Decisiones tomadas dentro de la spec (sin nada pendiente de Kiro)

- **"Estado del enlace consultable"** (ítem del checklist, la spec deja
  la forma abierta): se decidió **no** añadir un `GET` dedicado. El propio
  `POST .../share-link` ya es idempotente (P5: crea o devuelve el
  existente) — volver a llamarlo es cómo un owner consulta el
  token/URL vigente sin duplicar nada. Un `GET` habría expuesto exactamente
  la misma forma (`{ token, url }`) sin ninguna diferencia de
  comportamiento, así que se evitó una segunda ruta para la misma lectura.
- **`name`/`visibility` en `PATCH /albums/:id`**: se decidió aceptar
  ambos campos opcionalmente en el mismo body (en vez de, p. ej., separar
  en dos endpoints o exigir siempre ambos) — exigiendo que **al menos
  uno** venga (400 si no). Evita diseñar un PATCH parcial genérico
  (JSON Merge Patch, etc.) que esta spec no pedía, y mantiene la firma
  simple: `AlbumsService.update(ownerId, albumId, { name?, visibility? })`
  reemplaza al antiguo `rename()` (renombrado porque ahora hace más que
  renombrar).
- **Limpieza del `ShareLink` al borrar el álbum**: la spec ofrecía dos
  caminos igual de válidos (borrar la fila, o dejar que la resolución
  compruebe la existencia del álbum). Se implementaron **los dos** —ver
  "Invalidación" arriba— porque el segundo ya estaba pagado (mismo patrón
  que `SharedViewService` necesita de todos modos para revocación) y el
  primero evita dejar filas huérfanas acumulándose en el mock in-memory.
- **`visibility` no gatea el enlace**: explícito en la spec (P5) pero
  fácil de mal-implementar por accidente — `SharedViewService` no lee
  `Album.visibility` en absoluto. Cubierto por un test e2e dedicado
  (`test/shared.e2e-spec.ts`, "works the same for a PUBLIC-visibility
  album") para dejar constancia de que un `PRIVATE` no bloquea la
  resolución.

### Tests

- `src/albums/shared/share-links.service.spec.ts` — unit: token opaco +
  URL con `APP_SHARE_BASE_URL` (y fallback al default de dev), P5 (crear
  dos veces da el mismo token; revocar+crear da uno nuevo), revocar es
  idempotente, crear/revocar son owner-only (404 uniforme).
- `src/albums/shared/shared-view.service.spec.ts` — unit: resolución feliz
  con el DTO mínimo, solo fotos `available` (P3), aserción explícita de
  que la respuesta NO contiene `ownerId`/ids de usuario/tokens (P4, por
  grep del JSON serializado + comparación exacta de claves), 404 uniforme
  para token inexistente/revocado/álbum eliminado.
- `src/albums/albums.service.spec.ts` — ampliado: `visibility` default
  `PRIVATE` y explícito al crear, `update()` cambia nombre y/o visibilidad
  (owner-only, 404 para ajeno), borrar álbum también limpia su
  `ShareLink`.
- `test/albums.e2e-spec.ts` — ampliado: `visibility` en `POST /albums`
  (default, explícito, 400 con valor inválido), `PATCH /albums/:id` con
  `visibility` (owner-only, 400 sin `name` ni `visibility`, 400 con valor
  inválido).
- `test/shared.e2e-spec.ts` — e2e con 2 usuarios reales (owner, outsider),
  mismo patrón `beforeAll`/`afterAll` sin `Promise.all`: **`GET
  /api/v1/shared/:token` funciona sin header `Authorization`** (la prueba
  central de que es realmente público), P4 (sin `ownerId` ni tokens en la
  respuesta), P3 (fotos `unavailable` omitidas), 404 uniforme para token
  inexistente/revocado/álbum eliminado, P5 (crear dos veces da el mismo
  token; revocar+crear da uno nuevo y el viejo sigue muerto), gestión del
  enlace y cambio de `visibility` son owner-only (404 para un tercero).

### Env vars nuevas

- `APP_SHARE_BASE_URL` (default `https://memora.app/s/{token}`) — debe
  contener el placeholder `{token}`; nunca hardcodear el dominio. Mismo
  patrón que `APP_INVITE_BASE_URL` (spec05).

### Fuera de alcance (explícito, decisión del PO)

UI del visor (web/app); NFC/QR (M8, reutilizará este mismo enlace);
adopción (M5); que el backend sirva/proxee bytes de imágenes; catálogo o
descubrimiento público de álbumes (aunque `visibility` ya existe en el
modelo, preparándolo).

## NFC/QR (spec10-nfc-qr)

Implementa `specs/memora-backend/spec10-nfc-qr.md`: etiquetas físicas
(NFC) o códigos QR con una URL **estable e irreversible** (D14) que
resuelven al enlace de compartición (spec09) del álbum, sin depender de
que ese enlace nunca cambie.

### Por qué el tag no guarda el ShareLink directamente

Un `ShareLink` puede revocarse/regenerarse (su token cambia). Si una
etiqueta NFC pegada físicamente en un sitio, o un QR ya impreso, tuvieran
grabado el token del `ShareLink`, regenerar ese enlace **rompería** la
etiqueta. Por eso `NfcQrTag` se asocia al **álbum**, no al `ShareLink`:
la resolución es **indirecta** — `tag → albumId → el ShareLink que esté
activo en ese momento` (`src/albums/nfc-qr/nfc-qr-resolve.service.ts`).
Revocar y regenerar el `ShareLink` del álbum nunca rompe un tag ya
grabado — cubierto por un test e2e explícito ("regenerando el ShareLink
no rompe el tag").

### Endpoints — gestión del tag (autenticado, owner-only)

| Método | Ruta | Qué hace |
|---|---|---|
| `POST` | `/api/v1/albums/:albumId/nfc-qr-tags` | Crea **siempre** una fila nueva (`type: 'NFC'\|'QR'` en el body) — token aleatorio, `status: 'enabled'`. Responde `{ id, albumId, type, token, status, url, createdAt, updatedAt }`. |
| `GET` | `/api/v1/nfc-qr-tags/:id` | Consulta el tag por su **id interno** de Memora. |
| `PATCH` | `/api/v1/nfc-qr-tags/:id/disable` | Bloqueo soft (P2): marca `disabled`, setea `disabledAt`. Idempotente. **No reactivable** en el MVP (la estructura lo permitiría, no está implementado). |

**Sin restricción de unicidad**, a diferencia de `ShareLink` (uno por
álbum): cada `POST` crea una fila nueva con su propio `id`/`token`, sin
importar cuántos tags (del mismo `type` o de otro) ya existan para ese
álbum — un álbum puede tener varias etiquetas NFC y/o varios QR a la vez.

### Endpoint público — resolución

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/api/v1/n/:token` | **PÚBLICO — sin `SessionAuthGuard`, sin sesión.** Busca el tag por su **token opaco** (lo grabado físicamente en el NFC/QR, no el `id` interno). Si el tag existe y está `enabled`, el álbum existe, y el `ShareLink` del álbum existe y está `active` → **redirección HTTP 302** a `GET /api/v1/shared/:shareToken`. En cualquier otro caso → **404 uniforme**, sin distinguir el motivo (mismo criterio P1 de spec09). |

Mismo mecanismo que `SharedController` (spec09) para ser público: este
backend nunca registra un guard global, así que `NfcQrResolveController`
simplemente no lleva `@UseGuards(SessionAuthGuard)`. Hereda el contrato
de error uniforme y `x-request-id` de `configureApp()`.

### Dos desviaciones deliberadas del texto literal de la spec (documentadas, sin impacto de producto)

La propia spec de Kiro tiene dos imprecisiones de redacción en su
sección normativa (no en sus decisiones P1–P3, que están completas y
sin ambigüedad); ambas se resolvieron así, sin necesitar una vuelta al
PO porque el resto del documento ya deja clara la intención real:

1. **Colisión de rutas.** El texto describe el endpoint público con la
   **misma ruta** que el owner-only de consulta:
   `GET /api/v1/nfc-qr-tags/:id` aparece dos veces con significados
   incompatibles (una vez autenticado/por `id`, otra vez público/por
   `token`). Ambos no pueden coexistir en la misma ruta. Se implementó
   con dos rutas distintas: `GET /api/v1/nfc-qr-tags/:id` (owner-only,
   por `id` interno, en `nfc-qr-tag.controller.ts`) y
   `GET /api/v1/n/:token` (pública, por `token` opaco, en
   `nfc-qr-resolve.controller.ts`) — que además coincide exactamente con
   el placeholder de URL que la spec sí deja inequívoco en **P1**:
   `https://memora.app/n/{token}`.
2. **Env var de la URL.** P1 dice literalmente "placeholder
   `APP_SHARE_BASE_URL`" pero le da la forma `/n/{token}` — reusar
   `APP_SHARE_BASE_URL` (que spec09 ya fijó con forma `/s/{token}`)
   cambiaría silenciosamente el contrato de spec09. Se usa una env var
   **propia**, `APP_NFC_QR_BASE_URL` (default
   `https://memora.app/n/{token}`), mismo patrón que
   `APP_INVITE_BASE_URL`/`APP_SHARE_BASE_URL`.

Una tercera imprecisión, de redacción únicamente (sin afectar la
implementación): la spec dice "un tag por tipo por álbum" y en la misma
frase describe lo contrario ("para múltiples NFC o QR, se crea más de
una fila con el mismo `type`"). El checklist y el propio `POST`
("crea una nueva etiqueta", nunca "crea o devuelve la existente") dejan
claro que la intención real es **sin restricción de unicidad** — así se
implementó (ver arriba).

Una decisión de implementación adicional, sin ambigüedad de producto de
por medio: la redirección pública apunta al endpoint **propio** del
backend (`/api/v1/shared/:shareToken`) en vez del dominio placeholder
externo `https://memora.app/...` de `APP_SHARE_BASE_URL` — ese dominio
no existe todavía en el MVP (no hay frontend real), así que redirigir
ahí no sería verificable end-to-end ni funcional para nadie que probara
el enlace hoy. Redirigir al propio `/shared/:shareToken` mantiene el
comportamiento observable ("un 302 al ShareLink activo del álbum")
siendo además comprobable en los tests e2e.

### Invalidación (D16)

Al eliminar un álbum, `AlbumsService.delete()` ahora también llama a
`nfcQrTags.deleteAllForAlbum(albumId)` — **hard-delete** (a diferencia
del soft-delete de `disable()`), tal como pide la spec para este caso.
Es defensa en profundidad, no el único mecanismo:
`NfcQrResolveService.resolve()` además comprueba que el álbum siga
existiendo antes de redirigir a nada.

### Modelo — `src/albums/nfc-qr/`

- **`NfcQrTag`** (`nfc-qr-tag.model.ts`): `{ id, albumId, type:
  'NFC'|'QR', token, status: 'enabled'|'disabled', createdAt, updatedAt,
  disabledAt? }`. Token opaco de 256 bits, mismo generador que
  `ShareLink`/`Invitation` (`randomBytes(32).toString('base64url')`).
- **`NfcQrTagRepository`** (interfaz + `Symbol` + mock en memoria,
  `in-memory-nfc-qr-tag.repository.ts`): keyed por `id`, **sin** ninguna
  clave compuesta por `albumId`+`type` — a propósito, para no imponer la
  unicidad que la spec no pide.
- **`NfcQrTagsService`** — gestión owner-only (`create`, `get`,
  `disable`), vía `AlbumAccessService.requireOwner` (resuelto desde el
  `albumId` del propio tag para las rutas por `id`).
- **`NfcQrResolveService`** — resolución pública indirecta (tag →
  álbum → `ShareLink` activo), devuelve la ruta a redirigir o lanza el
  404 uniforme.

### Tests

- `src/albums/nfc-qr/nfc-qr-tags.service.spec.ts` — unit: token opaco +
  `enabled` al crear, URL con `APP_NFC_QR_BASE_URL` (y fallback al
  default de dev), sin restricción de unicidad (dos tags del mismo tipo
  coexisten), `get`/`create`/`disable` son owner-only (404), `disable`
  es idempotente y estampa `disabledAt`.
- `src/albums/nfc-qr/nfc-qr-resolve.service.spec.ts` — unit: resolución
  feliz a la ruta interna `/api/v1/shared/:shareToken`, regenerar el
  `ShareLink` no rompe la resolución (D14), 404 uniforme para token
  desconocido / tag `disabled` / álbum eliminado (D16) / álbum sin
  `ShareLink` / `ShareLink` revocado sin regenerar.
- `test/nfc-qr.e2e-spec.ts` — e2e con 2 usuarios reales (owner,
  outsider), mismo patrón `beforeAll`/`afterAll`: **`GET /api/v1/n/:token`
  funciona sin header `Authorization` y responde 302** con `Location`
  exacto (la prueba central de que es realmente público); gestión
  (crear/consultar/bloquear) es owner-only; 400 para un `type` inválido;
  D14 (regenerar el ShareLink no rompe el tag); 404 uniforme para token
  desconocido, tag bloqueado, y álbum eliminado (verificando además que
  la consulta owner-only del tag también da 404 tras el hard-delete).

### Env vars nuevas

- `APP_NFC_QR_BASE_URL` (default `https://memora.app/n/{token}`) — debe
  contener el placeholder `{token}`; nunca hardcodear el dominio. Variable
  propia, no reutiliza `APP_SHARE_BASE_URL` (ver "desviaciones" arriba).

### Fuera de alcance (explícito, decisión del PO)

Generación real de imágenes QR o escritura NFC real (es responsabilidad
del cliente app/web); reactivación de un tag `disabled` (la estructura
lo permite, no se implementa en el MVP); cualquier UI.

## Desarrollo

```bash
cp .env.example .env   # setea GOOGLE_CLIENT_ID/SECRET y JWT_SESSION_SECRET
npm run start:dev      # http://localhost:3000/api/v1/health
npm run build
npm run test
npm run test:e2e
```

**Nota de rendimiento:** `isolatedModules: true` en `tsconfig.json` es
necesario — sin él, `ts-jest` type-checkea el proyecto completo (incluyendo
los tipos de `google-auth-library`, muy pesados) en cada test, llevando
`npm run test` de ~1s a ~5 minutos. `npm run build` sigue haciendo el
type-check completo normalmente.
