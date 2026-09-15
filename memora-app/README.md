# memora_app

## Capa de acceso a la API

Implementa `specs/memora-app/spec01-fundacion-app.md`. Toda comunicación con
`memora-backend` pasa por `lib/api/`:

- **`api_config.dart`** — `apiBaseUrl`, configurable vía
  `--dart-define=API_BASE_URL=...`. Por defecto apunta al backend local
  (`http://localhost:3000/api/v1`, el default de `memora-backend`).
  En el **emulador de Android**, `localhost` es el propio emulador, no el
  host — usa `--dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1`.
- **`api_client.dart`** — `ApiClient.getJson(path)`, único punto de entrada
  HTTP hacia el backend. Antepone la base URL y normaliza cualquier error
  (de red o HTTP no-2xx) a `ApiException` con `{ code, message, requestId,
  statusCode }`. Ningún otro archivo debe usar `http.get` directo contra el
  backend.
- **`health_api.dart`** — `HealthApi.getHealth()`: `GET /api/v1/health` a
  través de `ApiClient`.
- **`api_exception.dart`** — `ApiException` (formato uniforme de
  `global/spec02-contrato-api.md`).

## Login con Google (spec02-login-google)

Implementa `specs/memora-app/spec02-login-google.md`: Google Sign-In nativo
con `google_sign_in` **v7+** (API separada de autenticación/autorización —
no la API previa), obtención del `serverAuthCode`, canje con
`memora-backend`, y sesión propia persistida de forma segura. `lib/auth/`:

- **`google_sign_in_config.dart`** — `googleServerClientId` (Web client ID,
  usado como `serverClientId`) y `googleIosClientId`, ambos configurables
  vía `--dart-define` con los valores de la spec como default. Ninguno es
  secreto.
- **`google_auth_service.dart`** — `GoogleAuthService.signInAndAuthorizeServer()`:
  `GoogleSignIn.instance.authenticate()` (identidad, interactivo) seguido de
  `account.authorizationClient.authorizeServer([drive.file])` (autorización
  de servidor, offline) — el patrón v7 correcto; **no** usa `signIn()` ni
  `serverAuthCode` desde el resultado de autenticación (API pre-v7,
  prohibida por la spec). `signOut()` limpia la sesión local de Google.
- **`auth_api.dart`** — `loginWithGoogle(serverAuthCode)` → `POST
  /auth/google`; `logout()` → `POST /auth/logout`. Todo vía `ApiClient`.
- **`session_storage.dart`** — persiste `{accessToken, refreshToken, user}`
  con `flutter_secure_storage` (Keychain/Keystore). Nunca `SharedPreferences`
  ni almacenamiento en claro.
- **`auth_controller.dart`** — `ChangeNotifier` (sin dependencia extra de
  gestión de estado) con `status` (`unknown` → `unauthenticated` /
  `authenticating` → `authenticated`), `user` y `errorMessage`. `bootstrap()`
  restaura la sesión guardada al abrir la app (sin validarla contra el
  backend — refresco automático está fuera de alcance de esta spec).

`lib/api/api_client.dart` ahora adjunta `Authorization: Bearer <token>` en
toda petición cuando hay sesión (`setAccessToken`), y soporta `postJson`
además de `getJson`.

`lib/screens/home_screen.dart` reemplaza la pantalla mínima de spec01: sigue
mostrando el estado del backend (`HealthApi`, igual que antes) y añade el
login/logout — botón "Iniciar sesión con Google", datos del usuario +
"Cerrar sesión" si hay sesión, y el mensaje de error/cancelación. Una sola
pantalla porque la app aún no tiene navegación entre rutas y la spec pide
"pantalla mínima"; no es diseño final.

### Configuración nativa (valores públicos, no secretos)

- **Android** — package `app.memora.memora_app` y SHA-1 de debug ya
  registrados en Google Cloud por el PO (según la spec). El `serverClientId`
  (Web client ID) se pasa en runtime desde Dart; no se necesita
  `google-services.json` ni cambios en `AndroidManifest.xml`.
- **iOS** — `ios/Runner/Info.plist` con `GIDClientID` (iOS client ID) y
  `CFBundleURLTypes` con el esquema de URL invertido
  (`com.googleusercontent.apps.<iOS client ID sin el sufijo .apps.googleusercontent.com>`).
  Son valores nativos de plist: **no** pueden venir de `--dart-define` (los
  lee el SDK nativo antes de que Flutter/Dart arranque) — por eso están
  hardcodeados ahí, a diferencia del `serverClientId` de Dart, que sí es
  configurable.

### Seguridad

- El `serverAuthCode` y los JWT de sesión nunca se registran en logs — ni
  `GoogleAuthService` ni `AuthController` los pasan a ningún `print`/log; los
  errores capturados se traducen a mensajes fijos, sin incluir el error
  original.
- Los JWT viven solo en `flutter_secure_storage`.

## Fotografías: seleccionar, optimizar y subir a Drive (spec03-fotografias)

Implementa `specs/memora-app/spec03-fotografias.md`: el usuario selecciona
una o varias fotos de la galería, la app las optimiza automáticamente (D15)
sin filtrar geolocalización (D8), pide un token de Drive al backend, sube
los bytes **directo a Google Drive del usuario** (Opción A — el backend
nunca ve los bytes) y registra cada foto con `POST /api/v1/photos`. `lib/photos/`:

- **`photo_optimizer.dart`** — `PhotoOptimizer.optimize(bytes)`: aplica los
  defaults fijos aprobados (decisión 3, el usuario no elige nada) — lado
  mayor ≤ 2048px (solo reduce, nunca amplía), JPEG ~85%, orientación EXIF
  aplicada y EXIF/GPS eliminado del resultado. Trabaja siempre sobre una
  copia en memoria; nunca abre el original para escritura. La función pura
  `computeTargetDimensions(width, height)` está separada para ser
  unit-testeable sin dispositivo (ver "Tests" más abajo — el porqué de esta
  separación es un gotcha real de `flutter_image_compress`, documentado en
  `CLAUDE.md`).
- **`drive_token_api.dart`** — `DriveTokenApi.getDriveToken()`: `POST
  /api/v1/auth/drive-token` vía `ApiClient` (Bearer de sesión ya adjunto) →
  `DriveToken { accessToken, expiresAt }`. Un 401
  `DRIVE_REAUTHORIZATION_REQUIRED` se mapea a
  `DriveReauthorizationRequiredException` (nunca se propaga el
  `ApiException` genérico a la UI).
- **`drive_upload_service.dart`** — `DriveUploadService.uploadFile(...)`:
  sube los bytes optimizados directo a Google Drive (API v3, `files.create`
  multipart) usando `package:http` **directamente contra
  `googleapis.com`** — la única excepción deliberada a "todo pasa por
  `ApiClient`", porque Drive es otro host con su propio token
  (`driveAccessToken`, scope `drive.file`) que nunca debe llegar al backend.
  No se agrega el SDK de Google Drive (spec01: aislamiento de proveedores).
  Resuelve/crea la carpeta única "Memora" en "Mi unidad" (decisión 1:
  búsqueda por `name + mimeType folder + trashed=false`, si no existe se
  crea) y cachea su `fileId` en la instancia — vive más allá de un solo lote
  (la carpeta no cambia durante la sesión), pero nunca se persiste en disco.
- **`photos_api.dart`** — `PhotosApi.registerPhoto(...)`: `POST
  /api/v1/photos` vía `ApiClient` con `storageRef: { fileId }` (**nunca**
  `driveFileId`; `provider` se omite, el backend asume `'google-drive'`) +
  metadatos mínimos (`width/height/mimeType/sizeBytes`) y `albumId?`
  opcional; nunca geolocalización. Modela `Photo`/`StorageRef` de la
  respuesta.
- **`photo_upload_controller.dart`** — `PhotoUploadController`
  (`ChangeNotifier`, patrón de `AuthController`): orquesta el lote
  (decisión 4) — N fotos **en secuencia** (no paralelo), cada una
  optimizar → token de Drive (una vez por lote, renovado si expira según
  `expiresIn`) → subir a Drive → registrar en backend, con estado por foto
  (`queued/optimizing/uploading/registering/done/error`) y errores
  parciales: una foto que falla no detiene ni corrompe el resto del lote.
  Si el backend responde `DRIVE_REAUTHORIZATION_REQUIRED`, marca la(s)
  foto(s) afectada(s) como error con un mensaje claro ("hace falta
  reconectar Google Drive") y deja de pedir tokens nuevos por el resto del
  lote (evita repetir una llamada que fallará igual) — **sin** cerrar la
  sesión de la app (D10); la re-autorización real es spec A1.6, fuera de
  alcance aquí.

`lib/screens/home_screen.dart` añade, bajo la sección de usuario autenticado,
un botón "Agregar fotos" (abre el selector del sistema con
`image_picker`), la lista de progreso por foto y un resumen final —
consistente con el resto de la pantalla (funcional, sin diseño).

### Permisos nativos

- **iOS** — `NSPhotoLibraryUsageDescription` en `Info.plist` (requerido por
  política de App Store aunque, al llamar `pickMultiImage` con
  `requestFullMetadata: false`, el `PHPicker` de iOS 14+ no llega a pedir
  permiso de biblioteca en tiempo de ejecución).
- **Android** — sin cambios en `AndroidManifest.xml`: `image_picker`
  (0.8.13+23) no declara ni pide permisos de almacenamiento para su flujo
  base (usa el Photo Picker del sistema / `ACTION_GET_CONTENT`); el
  `minSdkVersion` por defecto de Flutter (24) ya cumple el mínimo del
  plugin (SDK 24+).

### Reglas duras verificadas

- El backend **nunca** recibe los bytes de la foto: solo ve `drive-token`
  y `POST /photos`.
- El `driveAccessToken` va solo a la API de Drive, nunca se persiste, nunca
  se loguea.
- Ningún `print`/log expone tokens (`driveAccessToken`, Bearer de sesión)
  ni rutas de archivo.
- No se agrega el SDK de Google Drive.

## UI de álbumes (spec04-ui-albumes)

Implementa `specs/memora-app/spec04-ui-albumes.md` (decisiones A–E cerradas
por el PO, 2026-09-14): lista de álbumes (propios + colaborando), crear
álbum, ver detalle con miniaturas de Drive, agregar/quitar fotos, y
renombrar/cambiar visibilidad/eliminar (owner-only). Primer uso de
`Navigator` nativo en la app (decisión E) — `lib/screens/home_screen.dart`
ahora tiene un botón "Álbumes" (visible solo autenticado) que abre el stack
lista → detalle → crear.

- **`lib/api/api_client.dart`** — se agregaron `patchJson(path, body)`,
  `delete(path)` y `getJsonList(path)` (para `GET /albums`, que responde un
  **array JSON suelto**, no un objeto — a diferencia de todos los demás
  endpoints usados hasta ahora). `_send` es ahora genérico por método
  (`GET/POST/PATCH/DELETE`) y devuelve `dynamic` (`Map`, `List` o `null`);
  cada método público decide y castea la forma esperada. El mapeo a
  `ApiException` (incluyendo tolerar un 204 sin cuerpo) es el mismo para
  los cuatro métodos.
- **`lib/photos/photo_models.dart`** — `Photo` ahora incluye `availability`
  (`PhotoAvailability.available`/`.unavailable`, default `available` si el
  campo falta en la respuesta) sin romper ningún uso existente (parámetro
  opcional con default).
- **`lib/albums/album_models.dart`** — `AlbumVisibility`
  (`PRIVATE`/`PUBLIC`), `AlbumRole` (`owner`/`collaborator`),
  `AlbumSummary`, `AlbumListItem` (`AlbumSummary` + `role`) y `AlbumDetail`
  (`AlbumSummary` + `photos: List<Photo>`). **`AlbumDetail` NO tiene
  `role`** — el backend (`memora-backend/src/albums/albums.service.ts`,
  `AlbumDetail extends AlbumSummary`) deliberadamente no lo incluye, solo
  el endpoint de lista combinada (`AlbumListItem`) lo hace. Por eso
  `AlbumsController.loadAlbumDetail` recibe el `role` como parámetro,
  provisto por la pantalla de lista al navegar (nunca inferido ni asumido).
- **`lib/albums/albums_api.dart`** — `AlbumsApi` (patrón `*Api`):
  `createAlbum`, `listAlbums`, `getAlbumDetail`, `updateAlbum` (valida en
  Dart que venga `name` y/o `visibility` antes de llamar — igual lanza si
  el backend devuelve 400 igualmente), `deleteAlbum`,
  `addPhotoToAlbum`/`removePhotoFromAlbum`. Un 404 en cualquier operación
  se mapea a `AlbumNotAvailableException` (mensaje genérico "no
  disponible", nunca revela si el álbum existe pero es ajeno o no existe).
  Un 400 al crear/editar (backend o validación local) se mapea a
  `AlbumValidationException` con un mensaje claro.
- **`lib/albums/albums_controller.dart`** — `AlbumsController`
  (`ChangeNotifier`, patrón `AuthController`): estado de la lista
  (`albums`, `isLoadingList`, `listErrorMessage`) y estado del álbum
  actualmente abierto (`albumDetail`, `currentAlbumRole`, `isLoadingDetail`,
  `detailErrorMessage`, `isMutating`, `mutationErrorMessage`). Cada
  mutación (crear/renombrar/cambiar visibilidad/eliminar/quitar foto)
  refresca automáticamente la lista y/o el detalle según corresponda —
  ninguna pantalla necesita orquestar el refresco a mano.
- **`lib/albums/drive_thumbnail_service.dart`** — `DriveThumbnailService`
  (decisión A): descarga miniaturas con `GET
  https://www.googleapis.com/drive/v3/files/{fileId}?alt=media` +
  `Authorization: Bearer <driveAccessToken>` (mismo patrón "sin SDK de
  Drive, `http` directo contra `googleapis.com`" que
  `DriveUploadService`) — nunca `thumbnailLink`/`webContentLink` (piden
  auth de Google aparte y caducan). Caché **en memoria únicamente**
  (`Map<fileId, bytes>`, sin expiración ni límite de tamaño — suficiente
  para una sesión con un álbum abierto a la vez; no hay caché en disco).
  Comparte la **misma instancia** de `DriveTokenApi` que
  `PhotoUploadController` (es un wrapper sin estado sobre `ApiClient`, así
  que compartirla no cuesta nada), pero mantiene su **propio** `DriveToken`
  cacheado — decisión explícita: los dos tienen ciclos de vida distintos
  (un lote de subida es corto y descarta su caché al terminar; la pantalla
  de detalle sigue pidiendo miniaturas mientras esté abierta) y
  `POST /auth/drive-token` es barato e idempotente, así que la rara
  coincidencia de pedir token dos veces al mismo tiempo es un costo
  aceptable por no acoplar ambos controllers con estado mutable
  compartido.
- **`lib/albums/screens/albums_list_screen.dart`**,
  **`create_album_screen.dart`**, **`album_detail_screen.dart`** —
  pantallas mínimas funcionales (sin diseño final), primer stack de
  `Navigator.push`/`pop` de la app:
  - Lista: nombre, `photoCount` y chip de rol por álbum; acción "crear
    álbum" (ícono `+` en el AppBar).
  - Crear: solo pide el nombre (≤100 chars, contador nativo del
    `TextField`) — la visibilidad NO se pide (decisión D), el álbum nace
    `PRIVATE` (no se manda `visibility` en el `POST`).
  - Detalle: grid de miniaturas (`GridView.builder`, 3 columnas); una foto
    con `availability == unavailable` se pinta con un overlay oscuro +
    ícono `cloud_off` (marcada, no oculta); botón flotante "Agregar
    fotos" que llama `PhotoUploadController.pickAndUploadPhotos(albumId:
    ...)` y refresca el detalle al terminar; cada miniatura tiene un
    botón "×" para quitarla del álbum. Las acciones de administración
    (renombrar, cambiar visibilidad, eliminar) están en el `AppBar` **solo
    si `role == owner`** — para `collaborator` no se agregan a la lista de
    `actions` en absoluto (ocultas, no solo deshabilitadas: no hay ningún
    botón inerte que un futuro cambio pudiera reactivar por error).
    Eliminar pide confirmación con un diálogo que aclara explícitamente
    que las fotos NO se borran de Drive ni de la biblioteca (D16).

### Reglas duras verificadas

- Todas las llamadas nuevas pasan por `ApiClient` (`AlbumsApi`,
  `AlbumsController`) — `DriveThumbnailService` es la única excepción,
  igual que `DriveUploadService` (mismo host, mismo tipo de token, misma
  justificación ya documentada).
- El `driveAccessToken` de las miniaturas nunca se manda al backend, nunca
  se persiste, nunca se loguea — vive solo en el `DriveToken` cacheado en
  memoria de `DriveThumbnailService`.
- 404 en cualquier operación de álbum → `AlbumNotAvailableException` →
  "Este álbum no está disponible." (nunca se distingue ajeno de
  inexistente).
- 400 al crear/editar → `AlbumValidationException` con mensaje claro.
- Un `collaborator` nunca ve botones de renombrar/visibilidad/eliminar en
  el detalle del álbum (ni deshabilitados: no existen en el árbol de
  widgets).
- No se agregó el SDK de Google Drive.

### Mensaje distinto para sesión expirada (post-validación en dispositivo)

Al validar spec04 en dispositivo, listar/crear álbumes falló con el mensaje
genérico "Ocurrió un error" tras dejar la sesión abierta un rato — el
backend respondía **401 `UNAUTHORIZED`** (el JWT de sesión había expirado;
el refresco automático era la spec A1.5, entonces todavía pendiente —
implementada después en spec06-sesion-y-reauth-drive, ver más abajo). No era un bug de spec04: los e2e de `memora-backend` para
álbumes pasan igual (18/18) y el contrato coincide field-by-field con los
modelos de la app. Se agregó un mensaje específico, **"Tu sesión expiró.
Vuelve a iniciar sesión."**, tanto en `AlbumsController` como en
`PhotoUploadController` (mismo problema en ambos, cualquier llamada al
backend puede recibir este 401) — sin implementar refresh ni auto-logout,
solo una mejora de mensaje. Cubierto con un test en cada controller
(`albums_controller_test.dart`, `photo_upload_controller_test.dart`).
Desde spec06 (más abajo), este mensaje pasó a ser una red de seguridad: la
mayoría de estos 401 ahora se resuelven de forma transparente por el
interceptor de refresh de `ApiClient` antes de que el controller siquiera
vea el error; el mensaje solo aparece si el refresh también falla (el
refresh token venció/fue revocado) o si el 401 llega en el reintento después
de un refresh exitoso.

## Sesión: refresh automático y re-autorización de Drive (spec06-sesion-y-reauth-drive)

Implementa `specs/memora-app/spec06-sesion-y-reauth-drive.md`: refresco
automático del JWT de sesión (A1.5) y re-autorización de Google Drive (A1.6)
sin cerrar nunca la sesión de la app (D10).

- **`lib/api/api_client.dart`** — interceptor de 401 en `_send`: cuando
  cualquier request recibe un 401 cuyo `code` NO es
  `DRIVE_REAUTHORIZATION_REQUIRED` (ese sigue su camino sin tocar esto, ver
  spec03/spec04), intenta `POST /auth/refresh` una única vez (parámetro
  interno `isRetry` evita recursión) y, si funciona, reintenta la request
  original una vez más. Refreshes concurrentes coalescen en una sola llamada
  real (`Future<bool>? _refreshInFlight`). El refresh en sí NO pasa por
  `_send` (evita recursión y un Bearer irrelevante): usa `_httpClient`
  directo. Si el refresh token no existe o el refresh falla, se invoca
  `onSessionInvalidated` y de todos modos se propaga el 401 original (red de
  seguridad si la UI no llega a reaccionar al hook a tiempo). Nuevos campos
  públicos mutables `onSessionRefreshed`/`onSessionInvalidated` y
  `setRefreshToken` — mismo patrón minimalista que `setAccessToken`,
  `ApiClient` sigue sin saber nada de `SessionStorage`.
- **`lib/auth/auth_controller.dart`** — conecta esos dos hooks en el
  constructor: `onSessionRefreshed` persiste los tokens nuevos en
  `SessionStorage` bajo el `user` actual (sin tocar `status`);
  `onSessionInvalidated` limpia todo (storage, tokens en `ApiClient`, `user`,
  `status = unauthenticated`, mensaje "Tu sesión expiró...") — deliberadamente
  NO llama `authApi.logout()` (la sesión ya está muerta en el backend) ni
  `googleAuthService.signOut()` (no hace falta cerrar la cuenta de Google del
  dispositivo por esto). `bootstrap()`/`signIn()`/`signOut()` ahora también
  setean/limpian el refresh token en `ApiClient`. Nuevo método
  `reconnectDrive()`: reutiliza `GoogleAuthService.signInAndAuthorizeServer()`
  + `AuthApi.loginWithGoogle()` — el mismo canal que el login, porque no
  existe (ni se creó) un endpoint dedicado de "reconectar Drive": `POST
  /auth/google` hace upsert del usuario y sobrescribe el refresh token de
  Google guardado en el backend. Nunca cambia `status` ni `user` en caso de
  cancelación/error (D10); usa su propio campo `driveReconnectErrorMessage`
  en vez de pisar `errorMessage` (login normal).
- **`lib/auth/drive_reconnect_prompt.dart`** — helper reutilizable
  `promptDriveReconnect(context, authController)`: diálogo explicando la
  reconexión (sin `TextField`, no aplica el gotcha de `autofocus`), diálogo
  de carga no descartable mientras corre `reconnectDrive()`, y un
  `SnackBar` con el resultado. Devuelve `true`/`false`.
- **`lib/photos/photo_upload_controller.dart`** — cada `PhotoUploadItem`
  ahora trackea `failedDueToDriveReauth` (true solo si ESE ítem falló
  específicamente por `DRIVE_REAUTHORIZATION_REQUIRED`, no por cualquier
  otro error) y el controller expone `hasDriveReauthFailures` y
  `Future<void> retryAfterDriveReconnect({String? albumId})`: reprocesa EN
  SECUENCIA (mismo pipeline que el lote original, vía `_processItem`) solo
  los ítems marcados así, dejando intactos los ya `done` o fallidos por otra
  razón. Resetea `_driveReauthorizationRequired` primero para no
  auto-bloquearse con el cortocircuito del intento anterior.
- **`lib/screens/home_screen.dart`** — bajo el resumen del lote de fotos, si
  `hasDriveReauthFailures` es true, ofrece un botón "Reconectar Google
  Drive" que llama `promptDriveReconnect` y, si tiene éxito,
  `retryAfterDriveReconnect()`.
- **`lib/albums/drive_thumbnail_service.dart`** — nuevo `clearCache()`
  (vacía el `Map` de bytes Y el `DriveToken` cacheado) para usar tras un
  reconnect exitoso.
- **`lib/albums/screens/album_detail_screen.dart`** — cada `_PhotoTile`
  ahora reporta a la pantalla (`onReauthRequired`, vía
  `Future.catchError` sobre `_thumbnailFuture` que re-lanza el error sin
  tragarlo) si su miniatura falló por reauth; la pantalla muestra un banner
  con botón "Reconectar Google Drive" (mismo patrón que los banners de error
  ya existentes). Al reconectar con éxito: `driveThumbnailService.clearCache()`
  + incrementa un `_epoch` propio de la pantalla, usado como sufijo del
  `ValueKey` de cada tile (`'${photo.id}#$_epoch'`) — **decisión explícita
  distinta a solo `clearCache()`**: vaciar la caché de bytes NO alcanza para
  forzar un nuevo intento, porque `_PhotoTileState._thumbnailFuture` es
  `late final` y el `State` sigue vivo (mismo `photo.id` → Flutter reutiliza
  el `State` existente, ver el gotcha de key-por-id de spec04 en
  `CLAUDE.md`); el epoch en la key fuerza a Flutter a crear un `State` nuevo
  (y por lo tanto un `_thumbnailFuture` nuevo) para las mismas fotos.
  `AlbumDetailScreen`/`AlbumsListScreen` ahora reciben también
  `authController` (se propaga desde `HomeScreen`) solo para poder llamar
  `promptDriveReconnect`.

### D10 verificado en todo el flujo de reconexión de Drive

`AuthController.reconnectDrive()` nunca toca `status` ni `user` salvo en el
único caso de éxito (donde solo actualiza `user` con la respuesta, sin cambiar
`status`); cancelar el picker de Google o cualquier error (`GoogleSignInException`,
`GoogleServerAuthorizationException`, `ApiException`, cualquier otra
excepción) deja la sesión de la app completamente intacta. Cubierto con test
(`test/auth_controller_test.dart`).

### Reglas duras verificadas

- Ningún token (access, refresh, `serverAuthCode`, `driveAccessToken`) se
  loguea en ningún punto nuevo de este flujo.
- El refresh de sesión y la reconexión de Drive pasan siempre por
  `ApiClient`/`AuthApi` — la única llamada `http` directa nueva es la del
  propio `_performRefresh` dentro de `ApiClient` (no otro archivo), por la
  razón ya documentada (evitar recursión en `_send`).
- Ningún endpoint nuevo en el backend: reconectar Drive reutiliza `POST
  /auth/google` tal cual, sin tocar `memora-backend/`.

## UI de colaboradores (spec05-ui-colaboradores)

Implementa `specs/memora-app/spec05-ui-colaboradores.md`: que el owner
invite por enlace (D12) y comparta el enlace con el share sheet del sistema,
vea y quite colaboradores, revoque invitaciones (D13); que cualquier usuario
autenticado acepte una invitación pegando su token o enlace; y que un
colaborador pueda abandonar el álbum (D5). Extiende el mismo
`AlbumDetailScreen` de spec04 en vez de crear una pantalla de administración
separada (recomendación explícita de la spec), y añade una única pantalla
nueva para el flujo de aceptar (el otro caso que la spec sí preveía como
pantalla aparte).

- **`lib/albums/collaborator_models.dart`** — `InvitationStatus`
  (`pending`/`accepted`/`revoked`/`expired`), `InvitationCreated` (respuesta
  de crear, siempre con `token`/`url`), `InvitationListItem` (respuesta de
  listar — `token`/`url` **nullable**, el backend solo los incluye si
  `status == pending`), `CollaboratorListItem` (`userId`, `role`,
  `joinedAt`).
- **`lib/albums/collaborators_api.dart`** — `CollaboratorsApi` (patrón
  `*Api`): `createInvitation`, `listInvitations`, `revokeInvitation`,
  `acceptInvitation` (acepta token bare o URL completa — ver
  `CollaboratorsApi.extractToken`, público y testeado por separado),
  `listCollaborators`, `removeCollaborator`, `leaveAlbum`. Un 404 en
  cualquier operación de álbum/colaboradores se mapea a la MISMA
  `AlbumNotAvailableException` de `albums_api.dart` (reusada, no
  duplicada — el shape del error es idéntico). Un 410
  `INVITATION_NOT_USABLE` al aceptar se mapea a la nueva
  `InvitationNotUsableException` (nunca un `ApiException` genérico hacia la
  UI). Un 400 `CANNOT_REMOVE_OWNER`/`CANNOT_LEAVE_AS_OWNER` se mapea a
  `CollaboratorActionNotAllowedException` con un mensaje fijo — en la
  práctica no debería dispararse nunca desde esta UI (el owner nunca
  aparece como "quitable" en su propia lista, y "abandonar" solo se ofrece
  a un `collaborator`), es una red de seguridad.
- **`lib/albums/albums_controller.dart`** — extendido (no un segundo
  `ChangeNotifier`) con el estado de colaboradores/invitaciones del álbum
  actualmente abierto: `collaborators`, `invitations`,
  `isLoadingCollaborators`, `collaboratorsErrorMessage`, y los métodos
  `loadCollaboratorsAndInvitations`, `createInvitation`,
  `revokeInvitation`, `removeCollaborator`, `leaveCurrentAlbum` — todos
  operan sobre `currentAlbumId` y refrescan la(s) lista(s) correspondiente(s)
  tras cada mutación exitosa, mismo criterio que las mutaciones de spec04.
  `acceptInvitation(tokenOrInvitationUrl)` es la excepción deliberada: NO
  depende de `currentAlbumId`/`currentAlbumRole` (el usuario no sabe ni
  tiene abierto el álbum al que se está uniendo hasta que la aceptación
  tiene éxito) — en éxito, refresca `albums` (la lista general) para que el
  álbum nuevo aparezca de inmediato.
- **`lib/albums/screens/album_detail_screen.dart`** — el body pasó de un
  `Column` con un `GridView.builder` en un `Expanded` a un único
  `CustomScrollView` (`SliverGrid.builder` para las fotos +
  `SliverToBoxAdapter` para la sección de colaboradores debajo) — necesario
  para tener un solo scroll en la pantalla en vez de dos áreas
  scrolleables compitiendo por espacio fijo. Sección **owner-only** nueva
  bajo la grilla: botón "Invitar" (crea la invitación y abre un diálogo con
  la `url` seleccionable, `expiresAt` formateada, y un botón "Compartir" que
  llama `SharePlus.instance.share(ShareParams(text: url))` — la API actual,
  no deprecada, de `share_plus` 13.x), lista de colaboradores con "quitar"
  (confirmación), lista de invitaciones pendientes (`isPending`) con
  "revocar" (confirmación, aunque la spec no la exige explícitamente para
  revocar — se agregó por consistencia con el resto de acciones
  destructivas de la pantalla). Para `collaborator`: sección visible con la
  única acción "Abandonar álbum", confirmación que aclara explícitamente
  que las fotos ya aportadas permanecen en el álbum (D5), mismo estilo que
  el diálogo de eliminar álbum (D16).
- **`lib/albums/screens/accept_invitation_screen.dart`** (nueva pantalla,
  la única excepción a "todo en `AlbumDetailScreen`" — la propia spec la
  preveía aparte): campo de texto para pegar el enlace completo o el token
  + botón "Aceptar". Al aceptar con éxito: `SnackBar` de confirmación y
  `pushReplacement` a `AlbumsListScreen` (ya refrescada por
  `AlbumsController.acceptInvitation`) para que el usuario vea el álbum
  nuevo de inmediato. Es un `Navigator.push` real (no un `showDialog`), así
  que su `TextField` SÍ usa `autofocus: true` con seguridad — el gotcha de
  `autofocus`/`showDialog` documentado en `CLAUDE.md` no aplica aquí.
- **`lib/screens/home_screen.dart`** — nuevo botón "Unirme a un álbum" bajo
  "Álbumes", visible solo autenticado, abre `AcceptInvitationScreen`.
- **`pubspec.yaml`** — se agregó `share_plus: ^13.3.0` (share sheet del
  sistema, decisión de la spec — antes no había ningún mecanismo de
  compartir en la app).

### Limitación real de PII marcada para Kiro

`GET /api/v1/albums/:albumId/collaborators` (`memora-backend`,
`CollaboratorsService.list`) responde `{ userId, role, joinedAt }` — **sin
email ni nombre**. La spec asumía "nombre/email según lo exponga el
backend"; el backend no expone ninguno de los dos hoy. La UI muestra el
`userId` (un id interno) tal cual, sin inventar datos que el backend no da.
Esto es una limitación de UX real (no se puede saber "quién" es un
colaborador por nombre/email desde esta pantalla) — queda marcado para una
posible spec futura de backend que agregue email a este endpoint; no se
resolvió unilateralmente agregando un endpoint nuevo.

### Otra imprecisión de la spec (no normativa, ya corregida en la implementación)

spec05 dice `GET /api/v1/albums/:albumId/collaborators` es "owner o
miembro". Verificado contra el código real
(`memora-backend/src/albums/collaborators/collaborators.service.ts`):
`CollaboratorsService.list` llama `albumAccess.requireOwner`, no
`requireMembership` — es **owner-only**, igual que
`GET .../invitations`. La sección completa de colaboradores/invitaciones
en el detalle del álbum es 100% owner-only en esta implementación, alineada
al contrato real en vez de al texto de la spec.

### Reglas duras verificadas

- Toda llamada nueva pasa por `ApiClient` (`CollaboratorsApi`) — cero
  llamadas `http` directas en este flujo.
- Ningún token (Bearer de sesión, token de invitación) se loguea en ningún
  punto de este flujo.
- Las acciones de administración de colaboradores/invitaciones son
  100% owner-only, ocultas (no deshabilitadas) para `collaborator` — mismo
  criterio que renombrar/visibilidad/eliminar de spec04.
- Ningún endpoint nuevo en el backend ni SDK de Google Drive agregado.

(Tests y qué queda sin cubrir sin dispositivo: ver la sección "Desarrollo"
más abajo, mismo criterio consolidado que las specs anteriores.)

## Compartir y NFC/QR (spec07-compartir-nfc-qr.md)

Implementa `specs/memora-app/spec07-compartir-nfc-qr.md`: que el owner
genere/obtenga y comparta el enlace de compartición del álbum (M7) y pueda
revocarlo; y que cree etiquetas NFC o QR que apuntan al álbum (M8),
viendo el código QR renderizado o la URL para grabar en NFC, y pueda
bloquearlas. Extiende el mismo `AlbumDetailScreen` (spec04/05) con una
nueva sección "Compartir", owner-only — sin pantalla nueva, la spec lo
recomendaba así salvo que el QR lo ameritara y no fue el caso.

- **`lib/albums/sharing_models.dart`** — `ShareLink` (`token`/`url`),
  `NfcQrTagType` (`nfc`/`qr`), `NfcQrTagStatus` (`enabled`/`disabled`),
  `NfcQrTag` (con `isDisabled` y un `copyWith` usado para reflejar
  localmente el resultado de `disable`, que responde 204 sin cuerpo).
- **`lib/albums/sharing_api.dart`** — `SharingApi` (patrón `*Api`):
  `createOrGetShareLink`/`revokeShareLink` (`POST`/`DELETE
  /albums/:albumId/share-link`, owner-only, ambos idempotentes en el
  backend), `createNfcQrTag` (`POST /albums/:albumId/nfc-qr-tags`, body
  `{type}`, SIEMPRE crea uno nuevo, sin dedup), `getNfcQrTag`/
  `disableNfcQrTag` (`GET`/`PATCH /nfc-qr-tags/:id/disable` — **sin**
  `albumId` en la ruta, a propósito: son un controller distinto en el
  backend, direccionado solo por el id propio de la etiqueta). Un 404 en
  cualquiera de los cinco métodos se mapea a la misma
  `AlbumNotAvailableException` de `albums_api.dart` (reusada).
- **`lib/albums/albums_controller.dart`** — extendido (no un tercer
  `ChangeNotifier`) con `shareLink`/`isLoadingShareLink`/
  `shareLinkErrorMessage` (cargado bajo demanda con
  `loadOrCreateShareLink`, nunca automáticamente al abrir el álbum) y
  `nfcQrTags` (ver la limitación de abajo), más
  `revokeShareLink`/`createNfcQrTag`/`disableNfcQrTag`. `loadAlbumDetail`
  resetea `shareLink`/`nfcQrTags` solo cuando el álbum abierto cambia
  (nunca en un refresco del mismo álbum, p. ej. tras subir fotos).
- **`lib/albums/screens/album_detail_screen.dart`** — nueva sección
  "Compartir" (owner-only, entre la grilla de fotos y la sección de
  colaboradores): muestra la visibilidad actual con un enlace a la misma
  acción "Cambiar visibilidad" del AppBar (no la duplica); botón "Obtener
  enlace para compartir" → botones "Compartir" (`SharePlus`, reusando el
  mismo patrón que la invitación de spec05) y "Revocar" (confirmación);
  botones "Crear etiqueta QR"/"Crear etiqueta NFC"; por cada etiqueta
  creada en esta sesión, una tarjeta con el QR renderizado (`qr_flutter`,
  solo para `type == QR`) o la URL seleccionable (solo para `type ==
  NFC`), el estado (`Activa`/`Bloqueada`) y un botón "Bloquear"
  (confirmación, deshabilitado si ya está bloqueada).
- **`pubspec.yaml`** — se agregó `qr_flutter: ^4.1.0` (render de QR en el
  cliente, decisión de la spec — offline, a partir de la `url` del
  backend, sin pedir una imagen al backend).

### Limitación real marcada para Kiro: no hay listado de etiquetas por álbum

El backend (`memora-backend/spec10-nfc-qr.md`) no expone
`GET /albums/:albumId/nfc-qr-tags` — solo permite **crear** una etiqueta
bajo un álbum y **consultar/deshabilitar** una etiqueta ya conocida por su
propio id (fuera de `/albums`). Como consecuencia, `nfcQrTags` en
`AlbumsController` es una lista **en memoria, no persistida**, poblada
únicamente por cada `createNfcQrTag` exitoso durante la sesión actual de
la pantalla — se resetea a vacío cada vez que se abre un álbum distinto (o
se cierra y reabre el mismo). Las etiquetas creadas antes **siguen
funcionando** (su `url` sigue resolviendo al álbum), pero esta pantalla no
tiene forma de volver a listarlas una vez que la app las "olvida". No se
resolvió inventando un endpoint del lado del cliente ni mostrando datos
falsos — queda marcado para una posible spec futura de backend que agregue
ese GET.

### Reglas duras verificadas

- Toda llamada nueva pasa por `ApiClient` (`SharingApi`) — cero llamadas
  `http` directas en este flujo.
- Ningún token (Bearer de sesión, `token` de share-link o de etiqueta
  NFC/QR) se loguea; ninguno de los dos últimos se persiste tampoco — solo
  la `url` completa se comparte/renderiza, nunca el `token` ni otro dato
  interno.
- Todas las acciones de esta sección son 100% owner-only, ocultas (no
  deshabilitadas) para `collaborator` — mismo criterio que el resto de
  acciones de administración del álbum.
- Ningún endpoint nuevo en el backend ni SDK de Google Drive agregado. No
  se implementó escritura NFC nativa (`nfc_manager`) — diferida por la
  spec misma; la app solo muestra la URL para que el usuario la grabe con
  su herramienta de preferencia.

## Visor de foto a pantalla completa (spec08-visor-foto-inapp.md)

Implementa `specs/memora-app/spec08-visor-foto-inapp.md`: tocar una
miniatura del detalle de álbum abre la foto a pantalla completa con
zoom/pan (pellizco, doble toque) y navegación por swipe entre las fotos del
álbum, en el mismo orden que la grilla.

- **Sin pipeline de descarga nuevo (decisión clave de la spec).**
  `DriveThumbnailService.getThumbnail(fileId)` (spec04) ya descarga el
  archivo **completo** de Drive (`alt=media`) — la foto optimizada a
  ≤2048px de lado mayor (spec03) es exactamente lo que Drive guarda y lo
  que ese método devuelve. "Resolución completa" para este visor es
  literalmente la misma llamada, mismo método, misma caché en memoria que
  ya usa la grilla de miniaturas: el visor recibe la **misma instancia** de
  `DriveThumbnailService` que ya vive en `main.dart`, así que una foto ya
  vista como miniatura abre instantánea en el visor.
- **`lib/albums/screens/photo_viewer_screen.dart`** (nueva) —
  `PhotoViewerScreen`: recibe `photos` (la lista completa del álbum),
  `initialIndex`, y las mismas `thumbnailService`/`authController` que la
  pantalla de detalle. Usa `PhotoViewGallery.builder` (paquete
  `photo_view`) con `PhotoViewGalleryPageOptions.customChild` por página
  (no `imageProvider:` directo, para poder manejar carga/error/reintento
  async con estado propio). Cada página es su propio `_PhotoViewerPage`
  (`StatefulWidget`) con un `Future<Uint8List>?` **mutable** (no `late
  final` — necesario para que "Reintentar" pueda pedir la imagen de nuevo)
  y tres estados: cargando (indicador), `unavailable` (M6: placeholder
  "Foto no disponible", **sin** intentar descargar nada), y error — genérico
  (botón "Reintentar") o `DriveReauthorizationRequiredException` (botón
  "Reconectar Google Drive", que reusa `promptDriveReconnect` de spec06 y,
  si tiene éxito, `thumbnailService.clearCache()` + pide la imagen de
  nuevo). AppBar mínima (solo volver); sin geolocalización ni ningún otro
  metadato (D8).
- **`lib/albums/screens/album_detail_screen.dart`** — `_PhotoTile` ganó un
  parámetro `onTap` (nunca sobre el botón "×" de quitar, que conserva su
  propio `InkWell`); `_AlbumDetailScreenState._openPhotoViewer(index)` hace
  `Navigator.push` a `PhotoViewerScreen` con la lista/índice tocados y las
  mismas `driveThumbnailService`/`authController` que ya usa esta pantalla.
- **`pubspec.yaml`** — se agregó `photo_view: ^0.15.0` (zoom/pan/swipe,
  decisión de la spec — resuelto con `flutter pub add`, no fijado a mano).

### Gotcha real descubierto (no solo de test) — ver detalle en CLAUDE.md

Un botón dentro de `PhotoViewGalleryPageOptions.customChild` SÍ recibe el
tap, pero con un retraso real de hasta 300ms: `photo_view` registra siempre
un `DoubleTapGestureRecognizer` (para su zoom por doble-toque) que compite
en la misma gesture arena que cualquier botón anidado, y no cede hasta que
expira el timeout de doble-toque de Flutter. Es el comportamiento esperado
de cualquier control dentro de una zona con zoom/pan (no un bug de esta
implementación), documentado en detalle en `CLAUDE.md` junto con el ajuste
necesario para testearlo (`tester.pump(kDoubleTapTimeout + margen)` antes
de `pumpAndSettle`).

### Reglas duras verificadas

- El `driveAccessToken` sigue yendo solo a la Drive API, vía la MISMA
  `DriveThumbnailService` que spec04 — ningún archivo nuevo hace `http`
  directo contra `googleapis.com`.
- Ningún token se loguea en ningún punto nuevo de este flujo.
- No se muestra geolocalización (D8) ni ningún otro metadato de ubicación.
- `DRIVE_REAUTHORIZATION_REQUIRED` nunca cierra la sesión de la app (D10) —
  delega en el mismo `promptDriveReconnect`/`AuthController.reconnectDrive`
  de spec06.
- No se agregó el SDK de Google Drive.

### Qué no es testeable sin dispositivo

El gesto real de pinch-zoom/pan/doble-toque y el render real de
`PhotoViewGallery` (`photo_view`) — mismo criterio que el resto de
gestos/plugins nativos de esta app (ver "Desarrollo" más abajo). Sí se
cubrieron con widget tests: el índice/lista inicial correctos, que
`unavailable` nunca dispara una descarga, que un error de reauth ofrece
"Reconectar Google Drive", y que "Reintentar" efectivamente vuelve a pedir
la foto (`test/photo_viewer_screen_test.dart`).

## Desarrollo

```bash
flutter analyze
flutter test
flutter run \
  --dart-define=API_BASE_URL=http://localhost:3000/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<ios client id>
# Android emulator (además cambia la base URL):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1

# Probar el login real requiere dispositivo/emulador con Google Play
# (Android) o un simulador/dispositivo iOS con la app firmada — ver la
# "Nota de verificación" al final de spec02-login-google.md.
```

`flutter test` cubre con mocks (sin dispositivo): el cálculo puro de
redimensionado (`computeTargetDimensions`), `DriveTokenApi` (incluyendo el
mapeo a `DriveReauthorizationRequiredException`), `DriveUploadService`
(búsqueda/creación/caché de la carpeta "Memora" y subida), `PhotosApi`
(`storageRef.fileId`, nunca `driveFileId`), y la orquestación completa del
lote en `PhotoUploadController` (éxito, error parcial y
`DRIVE_REAUTHORIZATION_REQUIRED`) con un `PhotoOptimizer` fake. También
(spec04-ui-albumes): `ApiClient.patchJson`/`.delete`/`.getJsonList`
(`test/api_client_test.dart`), `AlbumsApi` — contratos y mapeo de errores
incluido 404→`AlbumNotAvailableException` y 400→`AlbumValidationException`
(`test/albums_api_test.dart`), `AlbumsController` — estados, refrescos tras
cada mutación, y que el rol se conserva desde `loadAlbumDetail` en vez de
inventarse (`test/albums_controller_test.dart`), y `DriveThumbnailService`
— descarga con `alt=media`, caché en memoria, reutilización de un token no
expirado entre archivos, y propagación sin envolver de
`DriveReauthorizationRequiredException` (`test/drive_thumbnail_service_test.dart`),
todo con un `http.Client` fake (`MockClient`), sin bytes reales de Drive.
También (spec06-sesion-y-reauth-drive): el interceptor de refresh de
`ApiClient` — 401 genérico → refresca y reintenta con éxito, refresh que
también falla → invalida sesión y propaga el 401 original,
`DRIVE_REAUTHORIZATION_REQUIRED` → nunca dispara refresh, refreshes
concurrentes → un solo `POST /auth/refresh` real (`test/api_client_test.dart`);
`AuthController.reconnectDrive()` — éxito, cancelación y error del picker de
Google, y que los hooks `onSessionRefreshed`/`onSessionInvalidated` de
`ApiClient` hacen lo esperado sin nunca llamar `authApi.logout()`
(`test/auth_controller_test.dart`, con fakes de `GoogleAuthService`/`AuthApi`/
`SessionStorage` que extienden las clases reales para no tocar
`GoogleSignIn.instance` ni la red); y
`PhotoUploadController.retryAfterDriveReconnect` — reintenta solo los ítems
marcados `failedDueToDriveReauth`, dejando intactos los `done` y los que
fallaron por otra razón (`test/photo_upload_controller_test.dart`).
También (spec05-ui-colaboradores): los 7 métodos de `CollaboratorsApi`
(crear/listar/revocar invitación, aceptar, listar/quitar colaborador,
abandonar) incluyendo `extractToken` y el mapeo
410→`InvitationNotUsableException`/400→`CollaboratorActionNotAllowedException`
(`test/collaborators_api_test.dart`), y la extensión de `AlbumsController`
— refresco de `collaborators`/`invitations` tras cada mutación,
`acceptInvitation` funcionando sin `currentAlbumId` abierto, mensajes claros
para 404/410/400 (`test/albums_controller_collaborators_test.dart`).
También (spec07-compartir-nfc-qr.md): los 5 métodos de `SharingApi`
(contratos de ruta exactos — en particular que `getNfcQrTag`/
`disableNfcQrTag` van a `/nfc-qr-tags/:id` sin `albumId`, a diferencia de
crear y del share-link — y el mapeo de 404) (`test/sharing_api_test.dart`),
y la extensión de `AlbumsController` — `loadOrCreateShareLink`/
`revokeShareLink`, `createNfcQrTag` (agrega, no reemplaza),
`disableNfcQrTag` (actualiza el tag correcto in-place), y que
`shareLink`/`nfcQrTags` se resetean solo al abrir un álbum distinto, nunca
en un refresco del mismo (`test/albums_controller_sharing_test.dart`).
También (spec08-visor-foto-inapp.md): `PhotoViewerScreen` con widget tests
reales (`testWidgets`) y un `DriveThumbnailService` fake — arranca en el
`initialIndex` correcto pidiendo el `fileId` de esa foto y no el de las
demás, una foto `unavailable` nunca dispara `getThumbnail`, un fallo
`DRIVE_REAUTHORIZATION_REQUIRED` ofrece "Reconectar Google Drive", y un
error genérico ofrece "Reintentar" que efectivamente vuelve a pedir la foto
(`test/photo_viewer_screen_test.dart`).
**No** son testeables sin dispositivo: la compresión real
(`flutter_image_compress`, plugin nativo vía MethodChannel), el selector de
galería (`image_picker`), la subida real a Google Drive, la navegación real
entre pantallas de álbumes, el render real de las miniaturas, los diálogos
reales de `promptDriveReconnect`/el picker real de reconexión de Google, el
share sheet real de `share_plus`, el render real del QR (`qr_flutter`), el
gesto real de pinch-zoom/pan/doble-toque y el render real de
`PhotoViewGallery` (`photo_view`), y que la `url` compartida efectivamente
resuelva en un navegador o que una etiqueta bloqueada deje de resolver, y
el flujo completo de aceptar una invitación con una cuenta de Google real
distinta a la del owner — se verifican en dispositivo/emulador con una
sesión con Drive autorizado (ver la nota de verificación de
`spec03-fotografias.md`). En particular, forzar una expiración real del JWT
de sesión o revocar el permiso de Drive en una cuenta de Google real para
validar el refresh/reconexión de punta a punta requiere dispositivo — lo
hace el PO.

---

Getting Started (plantilla original de Flutter):

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
