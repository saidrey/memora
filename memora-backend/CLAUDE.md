# memora-backend — convenciones y gotchas

NestJS 10, Node 20, TypeScript. Backend = única puerta de entrada a la
lógica; nunca maneja bytes de fotos (solo referencias/metadatos — ver
`producto-mvp.md`, principio "Memora no es custodio").

Para el estado de lo implementado spec por spec, ver `README.md` de esta
carpeta (ahí se documenta el avance porque `specs/` no se edita).

## Reglas de entorno

- No modificar `.npmrc`. No `npm install -g`. No cambiar config global de npm.
- Mantener NestJS 10 / Node 20.
- `@nestjs/jwt` fijado en **11.0.2** — la 12.x es ESM-only y rompe este
  proyecto CJS (`SyntaxError: Cannot use import statement outside a module`).
  No actualizar sin resolver antes la incompatibilidad ESM/CJS.
- `tsconfig.json` debe mantener `"isolatedModules": true`. Sin eso, ts-jest
  type-checkea el programa completo en cada test file — con dependencias de
  tipos pesadas (p. ej. `google-auth-library`) eso pasó de ~1s a ~300s por
  test run.

## Patrones establecidos (seguirlos, no reinventarlos)

- **Repository pattern con DI tokens**: interfaz + `Symbol('X_REPOSITORY')` +
  implementación in-memory. Nada de DB/SDKs de proveedores reales todavía —
  eso es una migración futura que no debe tocar la lógica de negocio.
- **`requireOwned<T extends {ownerId}>()`**
  (`src/common/authorization/require-owned.ts`) para checks de propiedad:
  recurso ajeno o inexistente → 404 uniforme (nunca 403 — no revelar
  existencia de recursos de otros usuarios).
- **`requireStringField()`** (`src/common/validation/`) para validar campos
  de entrada — no se usa `class-validator`, es una elección deliberada de
  mínima complejidad.
- **Contrato de error uniforme** `{ code, message, requestId }` vía
  `AllExceptionsFilter` — `ApiException(status, code, message)` para fijar un
  `code` explícito; si no, se deriva del status HTTP.
- **Relaciones N:M** (p. ej. álbum↔foto) se modelan como
  `Map<id, Set<relatedId>>` en el repositorio in-memory — el `Set` evita
  duplicados por construcción.
- Módulos que necesiten reusar `SessionAuthGuard` deben importar
  `AuthModule`, que exporta tanto el guard como `SessionTokenService` (su
  dependencia). Exportar solo el guard rompe la DI en el módulo consumidor.
- **Endpoints batch con ownership por entrada** (spec07-disponibilidad.md,
  `POST /photos/availability`): cuando un body trae un array de entradas
  que cada una necesita su propio check de `requireOwned`, NO se usa
  `requireOwned` (que lanza) por entrada — se resuelve `findById` +
  comparación de `ownerId` inline y se hace `continue` en silencio si no
  aplica. Objetivo: una entrada ajena/inexistente no debe romper el resto
  del batch ni revelar (con un 404 parcial) que ese id existe. La
  validación de **forma** del body (que `reports` sea un array, que cada
  entrada tenga los campos esperados) sí sigue siendo un 400 normal — solo
  la ownership por entrada es "silenciosa"; no confundir ambos niveles.
- **Repositorio in-memory: métodos de "update" que asumen existencia ya
  comprobada** (p. ej. `InMemoryPhotoRepository.updateAvailability`, mismo
  patrón que `InMemoryAlbumRepository.rename`): un `requireX()` privado que
  lanza un `Error` genérico (no `NotFoundException`) si el id no existe. Es
  intencional que nunca debería dispararse en producción — el 404 real ya
  lo lanzó la capa de servicio (`requireOwned`) antes de llamar al
  repositorio; este throw es solo una red de seguridad de programación, no
  un camino de error de negocio.

## Tests

- Los e2e usan `beforeAll`/`afterAll` (una app Nest por archivo de test, no
  por test) — con `beforeEach`/`afterEach` aparece un flake intermitente de
  socket (`Parse Error: Expected HTTP/`, `ECONNRESET`) al crecer la suite.
  Ver la nota de infraestructura de tests en `README.md` para el detalle
  completo y la tasa residual aceptada.
- Evitar `Promise.all()` para disparar requests concurrentes de supertest
  dentro de un mismo test — aumenta la probabilidad de ese mismo flake.
  Preferir awaits secuenciales.
- Si un test se ve "colgado" o cascada de fallos sin relación aparente con el
  código: correr `ps aux | grep jest` antes de asumir un bug de lógica — ya
  hubo un proceso jest huérfano de una sesión anterior corriendo 4+ horas que
  causó timeouts de 300s+ en toda la suite.
- Escribir tests unitarios Y e2e para cada endpoint/comportamiento nuevo.
- Antes de reportar terminado: `npm run build`, `npm run test`,
  `npm run test:e2e` deben pasar limpio.

## Autorización (fase actual)

Desde spec05-colaboradores.md hay dos niveles: **membresía** (owner o
collaborator — lectura de álbum/fotos, aporte de fotos propias) y
**ownership estricto** (gestión del álbum: rename/delete/invitar/quitar
colaboradores; y ownership de `Photo`, que nunca cambia con el rol). Ver
`src/albums/collaborators/album-access.service.ts` (`AlbumAccessService`):
extiende `requireOwned` con `requireMembership` (404 uniforme sin owner ni
collaborator) y `requireOwner` (delega en `requireOwned`, mismo mensaje).
No es una función pura porque resolver el rol necesita dos lecturas de
repositorio (álbum + membresía in-memory) — es un servicio inyectable
compartido por `AlbumsService`, `PhotosService`, `InvitationsService` y
`CollaboratorsService`, todos dentro de `AlbumsModule`. El README tiene el
detalle completo de decisiones (fila de owner derivada vs. persistida,
orden de checks al aceptar invitación, expiración perezosa, etc.) en la
sección "Colaboradores (spec05-colaboradores)" — no lo dupliques aquí, solo
el patrón reusable:

- **Membresía N:M con datos extra**: cuando la relación N:M lleva algo más
  que "existe/no existe" (aquí, `joinedAt`), el patrón `Map<id, Set<id>>`
  (álbum↔foto) no alcanza — se extendió a `Map<id, Map<id, Entity>>`
  (`in-memory-membership.repository.ts`). Sigue siendo el mismo espíritu
  (evitar duplicados por construcción), solo con un `Map` interior en vez
  de un `Set`.
- **`ConfigModule` es `isGlobal: true`** desde `AuthModule` (se cambió ahí
  al añadir `InvitationsService`, que necesita `ConfigService` en
  `AlbumsModule` sin volver a registrar `ConfigModule`). Cualquier módulo
  nuevo puede inyectar `ConfigService` sin importar nada extra.
- Al escribir un servicio que combina "requiere rol" + "requiere ser dueño
  de OTRA entidad" (p. ej. `PhotosService.associate`: membresía en el álbum
  + ownership de la foto), resuelve primero la membresía (404 si no hay) y
  luego aplica `requireOwned` sobre la segunda entidad — no intentes
  colapsar ambos checks en uno, son conceptualmente distintos (rol vs.
  propiedad) y la spec puede diferenciarlos en el futuro.

## Abstracción de proveedor de almacenamiento (spec08)

- `Photo.storageRef: { provider, fileId }` reemplazó `Photo.driveFileId:
  string`. `PhotoStorage` (token `Symbol('PHOTO_STORAGE')`,
  `src/albums/photos/storage/`) sigue el mismo patrón de interfaz+token que
  `PhotoRepository`/`AlbumRepository` — antes de tocar este código, ver la
  sección "Abstracción de almacenamiento (spec08)" del README (contrato de
  API completo, tabla de operaciones soportadas/no soportadas).
- **Exportar un `Service` completo desde un módulo, no solo sus
  dependencias**: `AlbumsModule` necesitaba inyectar `AuthService` en
  `GoogleDrivePhotoStorage` (para reusar `getDriveAccessToken` sin duplicar
  el lookup del refresh token). `AuthModule` solo exportaba
  `SessionAuthGuard` + `SessionTokenService` (su dependencia) — hubo que
  añadir `AuthService` a `exports`. Mismo principio ya documentado arriba
  ("exportar también las dependencias que el consumidor necesita"), pero
  aquí lo que se exporta es un servicio completo, no solo la dependencia de
  un guard — si un módulo futuro necesita otro servicio de `AuthModule`,
  añadirlo a `exports` es el patrón, no crear una interfaz nueva para eso.
- **Operaciones "declaradas pero no soportadas" en una interfaz de
  proveedor**: cuando una interfaz fija intención para el futuro (M5, un
  storage propio) pero el MVP no la implementa, no se omite el método ni se
  hace un no-op silencioso — se implementa lanzando un `ApiException`
  uniforme con un código propio (aquí `STORAGE_OPERATION_UNSUPPORTED`, 501)
  vía una factory en `photo-storage.errors.ts`, mismo patrón que
  `auth.errors.ts`. Así el contrato queda fijado en el tipo Y en el
  comportamiento en runtime, sin sobre-ingeniería (no hace falta una clase
  `NotImplementedPhotoStorage` ni feature flags).
- **Test de pureza de dominio por grep, no por convención**:
  `src/albums/domain-storage-neutrality.spec.ts` escanea `.ts` bajo
  `src/albums` (excluyendo `photos/storage/`, `*.module.ts` y `*.spec.ts`) y
  falla si aparece `Drive`/`driveFileId` literal. Si se añade un segundo
  proveedor de almacenamiento en el futuro, este test es la señal temprana
  de que algo fuera de `photos/storage/` se acopló al nombre del proveedor
  concreto — no lo debilites para que pase, corrige el acoplamiento.
