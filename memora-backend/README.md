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

**Nota para Kiro** — 4ª pieza de estado no nombrada en la spec: revocar la
sesión (logout) requiere saber qué refresh-token de sesión sigue vigente por
usuario. Eso no encaja en ninguna de las tres interfaces de arriba (son
sobre proveedores externos; esto es estado interno de sesión). Se implementó
como `session/session-registry.ts`, un provider en memoria simple, **sin**
elevarlo a una interfaz formal — si se quiere el mismo patrón de
"mock ahora, Postgres/Redis después" para la revocación de sesión, habría
que convertirlo en una 4ª interfaz.

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
