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

## Programar etiqueta NFC nativa (spec09-programar-nfc.md)

Implementa `specs/memora-app/spec09-programar-nfc.md` (decisiones P1–P3
cerradas por el PO, 2026-09-14): continúa lo que spec07 dejó diferido
("la app muestra la URL para que el usuario la grabe con su herramienta de
NFC de preferencia; escritura NFC nativa después"). El owner ahora puede,
desde el mismo detalle de álbum, **escribir físicamente** un chip NFC con
la `url` del álbum usando `nfc_manager`, con verificación post-escritura y
bloqueo opcional a solo lectura — sin reemplazar el flujo manual de spec07,
que sigue existiendo tal cual (ambos botones coexisten en la sección
"Etiquetas NFC/QR").

- **`lib/albums/nfc_programming_service.dart`** (nuevo) — envoltorio fino
  sobre `nfc_manager` (4.x) + `nfc_manager_ndef` (ver CLAUDE.md sobre por
  qué hace falta este segundo paquete: `nfc_manager` 4.0 eliminó su clase
  `Ndef` unificada del core). `writeUrl(url, confirmOverwrite, onPhase)`
  hace, dentro de UNA sola sesión NFC: detectar el tag → leer su NDEF
  actual → si ya tiene contenido, pedir confirmación vía el callback
  `confirmOverwrite` antes de seguir → escribir un único registro NDEF URI
  con la `url` (nunca fotos/nombre de álbum/ids — `buildUriRecord`) →
  releer y verificar byte-a-byte/string-a-string que coincide
  (`messageHasVerifiedUri`). Lanza una excepción tipada distinta por caso
  (`NfcCancelledException`, `NfcIncompatibleTagException`,
  `NfcTagLockedException`, `NfcWriteFailedException`,
  `NfcVerificationFailedException`) — nunca un error genérico. `lockReadOnly()`
  es una sesión NFC SEPARADA (P2) que solo hace algo si
  `supportsReadOnlyLock` (`true` solo en Android — ver CLAUDE.md sobre por
  qué iOS se excluye deliberadamente aunque el plugin lo permitiría).
  `buildUriRecord`/`decodeUriRecord`/`messageHasVerifiedUri` son funciones
  puras (implementan el NFC Forum URI Record Type Definition a mano, sin
  helper del paquete) testeadas sin hardware.
- **`lib/albums/nfc_programming_controller.dart`** (nuevo) — `ChangeNotifier`
  con un estado por cada paso del checklist de la spec: `waitingForTag`,
  `confirmingOverwrite`, `writing`, `verifying`, `success`, `cancelled`, y
  un valor de error DISTINTO por caso (`errorIncompatibleTag`,
  `errorTagLocked`, `errorWriteFailed`, `errorVerificationFailed`,
  `errorNfcUnavailable`, `errorUnknown`) — `statusMessage` da un texto fijo
  y distinto para cada uno (nunca el genérico de la app para estos casos).
  `retry()` reintenta con el MISMO `NfcQrTag`/token/url (P3), nunca crea uno
  nuevo. `cancel()` resuelve de forma fiable incluso en Android, donde la
  sesión real no avisa que se detuvo — ver el gotcha de `Future.any` en
  CLAUDE.md. `lockReadOnly()` es un método totalmente separado del flujo de
  escritura (P2), con su propio estado (`isLockingReadOnly`/
  `lockedReadOnly`/`lockReadOnlyErrorMessage`). No depende de
  `AlbumsController` — la creación del tag (P1) y su `disable` (P3, si el
  usuario desiste) siguen siendo responsabilidad de `AlbumsController`,
  reutilizadas tal cual desde la pantalla.
- **`lib/albums/screens/nfc_programming_screen.dart`** (nueva pantalla) —
  recibe el `NfcQrTag` YA CREADO (la pantalla nunca llama a la API: eso lo
  hace `AlbumDetailScreen._programNfcTag` antes de navegar, reutilizando
  `AlbumsController.createNfcQrTag(NfcQrTagType.nfc)` — sin una segunda
  llamada `POST`). Muestra el estado actual con un mensaje claro; mientras
  espera el tag ofrece "Cancelar"; si el tag ya tenía datos, muestra un
  diálogo de confirmación explícita antes de sobrescribir; en éxito, ofrece
  "Bloquear como solo lectura" (con diálogo de advertencia de
  irreversibilidad) SOLO si `supportsReadOnlyLock` — en iOS se muestra en
  su lugar un texto explicando que Core NFC no lo soporta de forma fiable;
  en cualquier error/cancelación ofrece "Reintentar" (mismo tag/token/url)
  y "Deshabilitar etiqueta" (P3: si el usuario desiste, reutiliza
  `AlbumsController.disableNfcQrTag` — el mismo soft-delete lógico que ya
  usaba el botón "Bloquear" de spec07, nunca automático).
- **`lib/albums/screens/album_detail_screen.dart`** — nuevo botón
  "Programar etiqueta NFC" (`_programNfcTag`), owner-only, en el mismo
  `Wrap` que "Crear etiqueta QR"/"Crear etiqueta NFC" de spec07 — coexiste
  con ambos, no los reemplaza ("Crear etiqueta NFC" sigue siendo el flujo
  manual de spec07: crea el tag y muestra la URL como texto seleccionable
  para que el usuario la grabe con su propia herramienta).
- **`pubspec.yaml`** — se agregaron `nfc_manager` y `nfc_manager_ndef`
  (ambos resueltos con `flutter pub add`, no fijados a mano — ver CLAUDE.md
  para las versiones exactas resueltas y por qué hacen falta los dos
  paquetes).
- **Android** (`android/app/src/main/AndroidManifest.xml`) — se agregó
  `<uses-permission android:name="android.permission.NFC" />`.
- **iOS** (`ios/Runner/Info.plist` + `ios/Runner/Runner.entitlements`,
  nuevo, + `project.pbxproj`) — se agregó `NFCReaderUsageDescription` al
  plist, y el entitlement `com.apple.developer.nfc.readersession.formats =
  [NDEF, TAG]` referenciado desde las tres configuraciones del target
  Runner (`CODE_SIGN_ENTITLEMENTS`). Ver CLAUDE.md: esto se editó a mano
  (sin Xcode disponible en este entorno) y compila para simulador, pero la
  capability en el Developer Portal del bundle id real y el comportamiento
  en un iPhone físico quedan sin verificar aquí — marcado para el PO.

### Decisiones de producto ya cerradas por el PO, aplicadas tal cual (P1–P3)

- **P1** — el tag se crea en el backend al INICIAR la programación
  (reutilizando `AlbumsController.createNfcQrTag`, sin una llamada nueva);
  si la escritura física falla, el token puede quedar huérfano (inocuo) y
  se limpia con `disable`, nunca automáticamente.
- **P2** — "bloquear a solo lectura" (físico, solo Android, con
  advertencia de irreversibilidad) y `disableNfcQrTag` (lógico, backend,
  ya existente desde spec07) son acciones completamente separadas: no
  comparten botón, diálogo ni lógica.
- **P3** — un fallo de escritura/verificación ofrece explícitamente
  "Reintentar" (mismo token/url) y, si el usuario desiste, "Deshabilitar
  etiqueta" — el usuario decide en cada paso, nunca automático.

### Qué no es testeable sin dispositivo

Una sesión NFC real (`NfcManager.instance.startSession`), acercar un tag
físico (NDEF/Type 2 real, uno ya bloqueado, uno incompatible), la hoja de
sistema real de iOS, y el bloqueo físico real a solo lectura
(`makeReadOnly`/Core NFC `writeLock`) — igual criterio que el resto de
plugins/gestos nativos de esta app (Google Sign-In, `image_picker`,
`photo_view`, `share_plus`). Sí están cubiertas con `flutter test`, sin
hardware: toda la codificación/decodificación/verificación NDEF (funciones
puras) y el controller completo (todas las transiciones de estado, los 5
casos de error, retry, cancel en el escenario real de Android donde la
sesión nunca confirma que se detuvo, y el gating de plataforma de
`lockReadOnly`) — ver `test/nfc_programming_service_test.dart` y
`test/nfc_programming_controller_test.dart`, y el detalle en CLAUDE.md.

## Rediseño visual — Fase 1: sistema "Aurora" (sin spec de Kiro)

> **OBSOLETO tras el pivot a light-first (60-30-10)** — ver "Rediseño
> visual 'Aurora' — pivot a light-first (60-30-10)" más abajo (justo antes
> de "Desarrollo"). Esta sección y las siguientes ("Fase 2", los ajustes
> post-feedback) describen el sistema **dark-first** original; el layout/
> las decisiones de estructura ahí siguen vigentes, pero cualquier mención
> de colores/tokens (`MemoraTheme.dark`, `MemoraCardElevation.light`, "la
> app es dark-first") quedó reemplazada por el pivot.

Rediseño visual completo de la app pedido directamente por el usuario
(dirección "Aurora / cielo nocturno" ya aprobada), en dos fases. **Fase 1
(completa)**: el sistema de diseño reutilizable y su aplicación a
`HomeScreen` y `AlbumsListScreen`, con un ajuste post-feedback ya aplicado
(ver más abajo). **Fase 2 (en curso — primera pantalla lista, ver más
abajo)**: aplicar el mismo sistema al resto de pantallas —
`album_detail_screen.dart` (hecha), `photo_viewer_screen.dart`,
`create_album_screen.dart`, `accept_invitation_screen.dart`,
`nfc_programming_screen.dart` y `drive_reconnect_prompt.dart` (pendientes,
a la espera de que el usuario revise `album_detail_screen.dart` en su
celular) — estas últimas cinco siguen con su UI mínima funcional previa.

### Ajuste post-feedback (sigue en Fase 1): balance claro/oscuro + hero del Welcome

El usuario validó la Fase 1 corriendo la app en su celular y dio dos
piezas de feedback puntuales, resueltas sin tocar la paleta ni ninguna
pantalla fuera de `HomeScreen`:

- **"Todo se ve muy oscuro, se usaron poco los tonos light"**: se agregó
  `MemoraCardElevation.light` a `MemoraCard` (fondo Paper, contenido en
  Deep Ink por defecto — mismos 5 colores de siempre, solo el extremo claro
  que casi no se usaba) y se aplicó a las cards de acceso rápido
  "Álbumes"/"Unirme a un álbum" del dashboard autenticado (las primeras que
  se ven al loguearse), con el ícono de cada una en un chip circular con el
  gradiente de firma. `AlbumsListScreen` se dejó sin cambios — no se
  encontró un lugar para sumar presencia clara ahí sin romper el patrón de
  gradiente de las cards de álbum ya aprobado (ver detalle en `CLAUDE.md`).
- **Imagen hero para el Welcome + botón de login abajo (pedido explícito,
  no una referencia de estilo)**: `assets/images/hero.png` (provista por
  el usuario, usada tal cual, sin editar/comprimir) ahora es el fondo a
  pantalla completa del estado no autenticado (`Image.asset(fit:
  BoxFit.cover)`, fuera del `SafeArea` para cubrir la statusbar), con dos
  scrims derivados de Deep Ink (arriba y abajo, nunca negro puro) para
  garantizar contraste. El wordmark "Memora" pasó a ser chico y discreto
  arriba a la izquierda; el headline ("Las historias / que importan /
  siempre *contigo*", con "contigo" en Aura Violet) y el subtítulo van en
  el tercio superior sobre el cielo de la foto; el botón de login quedó
  anclado abajo (ya no centrado — resuelve también el espacio muerto que
  se había notado en la Fase 1 original). El dashboard autenticado sigue
  con el fondo oscuro liso/glow de siempre (`_AuroraBackdrop`), no la foto
  — no tiene sentido en una pantalla de datos.

Detalle técnico completo (el gotcha de `DefaultTextStyle`/estilos del
`textTheme` con color explícito, los valores exactos de los scrims, y el
detalle del texto transcripto de la referencia del usuario) en la sección
"Ajuste post-feedback de Fase 1" de `CLAUDE.md`.

Puramente visual: ningún controller, `*Api`, modelo, ni contrato de datos
cambió. Ver la sección "Sistema de diseño visual — 'Aurora'" de
`CLAUDE.md` para el detalle técnico completo (tokens, componentes,
gotchas). Resumen:

- **`lib/design/`** (nuevo) — tokens (`memora_colors.dart`,
  `memora_typography.dart`, `memora_spacing.dart`), el `ThemeData` único de
  la app (`memora_theme.dart`, aplicado en `main.dart` vía
  `MaterialApp(theme: ...)`), y componentes reutilizables en
  `widgets/`: `MemoraPrimaryButton`, `MemoraSecondaryButton`, `MemoraBadge`,
  `MemoraCard`, `MemoraEmptyState`, `MemoraLoadingState`,
  `MemoraFadeSlideIn` (entrada fade+slide, respeta "reduce motion"). Barrel
  export: `lib/design/design.dart`.
- **`pubspec.yaml`** — se agregó `google_fonts: ^8.2.1` (única dependencia
  nueva de esta fase, resuelta vía `flutter pub add`; fuente Manrope,
  pesos 400/600/700/800).
- **`lib/screens/home_screen.dart`** — mismos controllers/callbacks
  (`auth.signIn`/`signOut`, `_openAlbums`, `_openAcceptInvitation`, todo el
  flujo de `PhotoUploadController` incluida la reconexión de Drive), capa
  visual nueva: composición "Welcome" inmersiva (wordmark + glow de la
  paleta, sin imagen stock) cuando no hay sesión, dashboard con avatar de
  iniciales + cards de acceso rápido cuando sí la hay, chip de
  conectividad del backend discreto (mismo texto "Backend: ok"/"Backend:
  no disponible" que antes, para no romper los widget tests existentes).
- **`lib/albums/screens/albums_list_screen.dart`** — mismo
  `AlbumsController`/navegación (`_openAlbum`, `_openCreateAlbum`,
  `RefreshIndicator`), reemplaza el `ListView`/`ListTile` por un grid de
  cards abstractas (sin foto de portada — `AlbumListItem` no trae una, ver
  CLAUDE.md): gradiente determinístico por álbum
  (`lib/albums/screens/album_card_style.dart`, función pura
  `gradientForAlbumId`, testeada en `test/album_card_style_test.dart`),
  `photoCount` como stat protagonista, badge de rol desbordando el borde
  superior de la card. El botón "crear álbum" pasó del ícono del `AppBar` a
  un `FloatingActionButton` con el gradiente de firma. Estados de
  carga/error/vacío con `MemoraLoadingState`/`MemoraEmptyState` (el vacío
  con CTA "Crear álbum").
- **Animaciones**: solo entrada fade+slide de las cards del grid
  (`MemoraFadeSlideIn`, 250ms, escalonada por índice) y el feedback táctil
  nativo (`InkWell`) de los botones — nada más. Respeta
  `MediaQuery.of(context).disableAnimations`.

### Fase 2 (en curso): `album_detail_screen.dart`

Primera pantalla de Fase 2 — la más compleja de la app (grilla de fotos
reales, secciones de compartir/colaboradores) y la primera donde el
lenguaje "galería editorial" del brief aplica de verdad (fotos grandes
protagonistas, transición curva imagen→contenido, un elemento desbordado
con su propio criterio). Puramente visual: ningún controller/`*Api`/modelo
cambió; todos los gotchas ya documentados (key-por-id+epoch, owner-only,
`autofocus` prohibido, distinción de errores de Drive) se preservaron
intactos. Detalle técnico completo (por qué el hero usa `_HeroPhotoImage` en
vez de reutilizar `_PhotoTile`, el gotcha del `overlay` compartiendo el clip
de `MemoraCurvedHero`, por qué el FAB pasó a ser un `MemoraPrimaryButton`)
en la sección "Fase 2 (arranque)" de `CLAUDE.md`. Resumen:

- **`lib/design/widgets/memora_curved_hero.dart`** (nuevo, exportado desde
  `design.dart`) — `MemoraHeroCurve` (un `CustomClipper<Path>` con una
  curva asimétrica tipo ola) + `MemoraCurvedHero` (imagen/gradiente
  full-bleed con esa costura + un `overlay` opcional encima). Genérico y
  reutilizable, no específico de álbum.
- **`MemoraRadius.thumbnail`** (nuevo, 14.0, `lib/design/memora_spacing.dart`)
  — radio dedicado para tiles de grilla de fotos.
- **`MemoraTypography.legibilityShadows()`** (nuevo, `lib/design/memora_typography.dart`)
  — el helper de sombra de texto sobre foto (ver el ajuste de Fase 1 más
  abajo) generalizado para reuso en cualquier pantalla con texto compuesto
  sobre una imagen; usado por el nombre del álbum en el hero de esta
  pantalla.
- **El hero**: la primera foto del álbum (`detail.photos.first`, vía
  `DriveThumbnailService`, misma caché que la grilla) a pantalla completa
  dentro de `MemoraCurvedHero`, con dos scrims (derivados de Deep Ink) y el
  nombre del álbum + badge de rol superpuestos; si el álbum no tiene fotos,
  cae al gradiente determinístico `gradientForAlbumId` que ya usa
  `AlbumsListScreen` (mismo generador, sin duplicar). El `AppBar` se volvió
  transparente (`extendBodyBehindAppBar: true`) en vez de eliminarse — sigue
  dando el botón de volver y los íconos owner-only (renombrar/visibilidad/
  eliminar) nativos, ahora flotando sobre la foto.
- **El elemento desbordado de esta pantalla** es un pill de conteo de fotos
  que straddlea la costura curva del hero (`_PhotoCountBadge`, usando
  `MemoraCardElevation.light` — el "light island" que la propia
  documentación de esa variante pedía para "uno o dos momentos de contraste
  real" por pantalla) — deliberadamente DISTINTO del badge de rol
  desbordando una card que ya usa `AlbumsListScreen` (ese patrón no se
  repitió acá; el rol quedó simplemente inline en el overlay del hero).
- **Grid de fotos**: 2 columnas (antes 3) para fotos más grandes/protagonistas,
  mismo `SliverGrid.builder`/mismo `ValueKey('${photo.id}#$_epoch')`
  intacto, tiles con `ClipRRect(MemoraRadius.thumbnail)` y colores del
  sistema — la distinción visual `link_off` (reauth) vs `broken_image`
  (genérico) se conserva.
- **Compartir/Colaboradores**: ambas secciones ahora son un `MemoraCard`
  (nivel 2) con `MemoraSecondaryButton` (destructivo para
  revocar/bloquear/abandonar) en vez de `TextButton`/`OutlinedButton`
  sueltos, `MemoraBadge` para el estado de una etiqueta NFC/QR, y filas de
  colaborador/invitación con un chip circular en vez de `ListTile`. El FAB
  "Agregar fotos" pasó a ser un `MemoraPrimaryButton` (el único de la
  pantalla — por eso la sección de compartir usa siempre
  `MemoraSecondaryButton`, incluida "Obtener enlace para compartir").
- **Tocadas en la siguiente tanda** (ver más abajo, "Fase 2 (completa)"):
  `photo_viewer_screen.dart`, `create_album_screen.dart`,
  `accept_invitation_screen.dart`, `nfc_programming_screen.dart`,
  `drive_reconnect_prompt.dart`.

### Fase 2 (completa): las 5 pantallas restantes

Última tanda de Fase 2 (sigue sin spec de Kiro): `photo_viewer_screen.dart`,
`create_album_screen.dart`, `accept_invitation_screen.dart`,
`nfc_programming_screen.dart`, `drive_reconnect_prompt.dart`. Con esto, las
7 pantallas del alcance original de Fase 2 tienen el sistema "Aurora"
aplicado — **Fase 2 queda completa**. Puramente visual: ningún controller
(`NfcProgrammingController`, `AlbumsController`, `AuthController`)/`*Api`/
modelo cambió; todos los gotchas documentados (el retraso de ~300ms de un
botón dentro de `photo_view`, `autofocus` prohibido en `showDialog`, la
máquina de estados completa de NFC) se preservaron intactos. Detalle técnico
completo (por qué `photo_viewer_screen.dart` no tiene ningún momento
`MemoraCardElevation.light`, el gotcha nuevo de `InputDecorationTheme`
dentro de esa variante para `create_album_screen.dart`, y por qué el estado
`success` de NFC es el que se llevó la card clara) en la sección
"Rediseño visual 'Aurora' — Fase 2 (completa)" de `CLAUDE.md`. Resumen:

- **`photo_viewer_screen.dart`** — solo chrome: `Colors.black`/
  `Colors.white*` sueltos reemplazados por `MemoraColors` (incluido un
  `backgroundDecoration` nuevo en `PhotoViewGallery.builder`, que el
  paquete sí expone), y el placeholder "Foto no disponible" + los dos
  estados de error (genérico/reauth) unificados en un widget nuevo,
  `_StateOverlay` (icon chip + mensaje + `MemoraSecondaryButton` opcional
  — nunca `MemoraPrimaryButton`, son acciones de recuperación de una
  página de la galería, no el CTA de la pantalla). Ningún cambio a
  `PhotoViewGallery.builder`/`.customChild` ni al gotcha de retraso de tap
  de ~300ms — `test/photo_viewer_screen_test.dart` sigue pasando sin tocar
  sus aserciones.
- **`create_album_screen.dart`** — su momento `MemoraCardElevation.light`
  es la card entera del formulario (ejemplo textual del brief). El campo
  de nombre necesitó un `InputDecoration` a mano (borde inferior, sin
  relleno, colores explícitos derivados de Deep Ink) porque el
  `InputDecorationTheme` global de la app está calibrado para texto-sobre-
  oscuro y es ilegible sobre Paper — gotcha nuevo, documentado en
  `CLAUDE.md` como precedente para cualquier futuro `TextField` dentro de
  una card clara.
- **`accept_invitation_screen.dart`** — card `level2` (no `light`: unirse a
  un álbum es una acción utilitaria de un paso, sin un "premio" natural que
  justifique una isla clara), `InputDecorationTheme` global sin cambios (acá
  sí calza, porque el campo vive sobre una superficie oscura). `autofocus:
  true` preservado tal cual — sigue siendo seguro porque es
  `Navigator.push`, no `showDialog`.
- **`nfc_programming_screen.dart`** — su momento `MemoraCardElevation.light`
  es el estado `success` (el otro ejemplo textual del brief), como "premio"
  tras la escritura física. Ningún estado de `NfcProgrammingStatus` se
  perdió: esperar/escribir/verificar sigue siendo una sola rama visual
  (`_StateIconChip` + `MemoraLoadingState(label: statusMessage)`), y
  error/cancelado sigue siendo la rama final, ahora con
  `MemoraPrimaryButton` para "Reintentar" y
  `MemoraSecondaryButton(destructive: true)` para "Deshabilitar etiqueta"
  (antes ambos con el mismo peso visual). Nuevo widget `_StateIconChip`
  reutiliza el lenguaje de chip circular ya establecido
  (`_QuickAccessCard`/`_InitialsAvatar`/el FAB).
- **`drive_reconnect_prompt.dart`** — el que menos cambió: su
  `AlertDialog`/`SnackBar` ya heredaban la mayor parte de su estilo del
  `dialogTheme`/`snackBarTheme` de `MemoraTheme.dark` por ser widgets
  estándar de Flutter. Se agregó un ícono en el título del diálogo de
  confirmación, colores distintos para "Cancelar" (muted) vs "Reconectar"
  (acentuado), y un ícono de resultado en el `SnackBar` final.
- Confirmado: ningún `MemoraPrimaryButton` aparece más de una vez
  simultáneamente en el árbol de ningún build de estas 5 pantallas (aunque
  `nfc_programming_screen.dart` usa uno distinto en `success` y otro en el
  estado de error — nunca ambos a la vez, son branches mutuamente
  excluyentes).
- **Pendiente después de esto (ya lo pidió el usuario, todavía no
  iniciado)**: una pasada final de refinamiento sobre TODA la app — no es
  parte de esta tarea.

### Ajuste chico post-feedback (sigue sin spec de Kiro): jerarquía de "Cerrar sesión"

El usuario, viendo el dashboard autenticado en su celular, notó que el botón
"Cerrar sesión" (antes un `MemoraSecondaryButton` de ancho completo, con el
mismo peso visual que las acciones principales, parado en medio del flujo
entre las cards de acceso rápido y la sección de fotos) se veía "sin orden,
sin sentido ahí en medio". Solo se tocó `lib/screens/home_screen.dart` (y su
test en `test/widget_test.dart`) — ninguna otra pantalla, ningún controller.

- Se sacó el `MemoraSecondaryButton` del flujo principal de
  `_AuthenticatedDashboard` y se movió a un `IconButton` (`Icons.logout`,
  `tooltip: 'Cerrar sesión'`) en el Row superior que ya mostraba el chip de
  conectividad del backend — mismo `auth.signOut` de siempre. Se eligió esto
  (en vez de dejarlo al final del scroll como texto chico) porque
  `HomeScreen` no tiene `AppBar` real, pero ese Row cumple el mismo rol
  visual; y porque el `IconButton`+`tooltip` es exactamente el patrón que ya
  usa `album_detail_screen.dart` para sus acciones owner-only en el
  `AppBar`, así que no introduce un patrón nuevo a la app.
- El ícono solo aparece cuando `auth.status == AuthStatus.authenticated`
  (antes ese lado del Row alternaba entre el wordmark "Memora" del Welcome y
  un `SizedBox.shrink()` para cualquier otro estado); no aparece durante
  `authenticating`/`unknown`, donde cerrar sesión no tiene sentido.
- Orden resultante de `_AuthenticatedDashboard`: greeting → cards de acceso
  rápido (Álbumes/Unirme) → sección de Fotos — se revisó con el mismo
  criterio de jerarquía y no hizo falta reordenar nada más.
- `test/widget_test.dart` — el test "shows user info and a logout button
  when authenticated" ahora busca `find.byTooltip('Cerrar sesión')` en vez
  de `find.text('Cerrar sesión')` (ya no es un botón de texto).

### Pendiente para el usuario/Kiro (no resuelto en esta tarea)

- **Revisión de `album_detail_screen.dart` en dispositivo real** (Fase 2,
  ver arriba) — en particular cómo se ve el hero con una foto real de
  distinto aspect ratio/orientación, la legibilidad del nombre del álbum
  sobre la foto, y el posicionamiento del pill de conteo de fotos sobre la
  costura curva (los valores de offset/altura se ajustaron a ojo, sin poder
  verlos corriendo en un dispositivo real desde este entorno).
- **Revisión en dispositivo real de las 5 pantallas de la última tanda de
  Fase 2** (ver arriba) — en particular: el visor de foto (el retraso real
  de ~300ms al tocar "Reintentar"/"Reconectar Google Drive" dentro del
  zoom/pan de `photo_view`, ya documentado como esperado, pero vale
  sentirlo en mano; y cómo se ve `_StateOverlay` sobre una foto real detrás
  del `PhotoViewGallery`), la card clara del formulario de crear álbum
  (contraste del campo con borde inferior sobre Paper), y la card clara del
  estado de éxito de NFC (solo verificable con hardware NFC real, ver
  "Qué no es testeable sin dispositivo" en `CLAUDE.md`).
- **Fase 2 del rediseño visual queda completa con esta tarea.** El usuario
  ya pidió, como siguiente paso, una pasada final de refinamiento visual
  sobre TODA la app (no solo las pantallas tocadas en Fase 1/2) — todavía
  no iniciada, es la próxima tarea, no parte de esta.
- **Revisión de esta Fase 1 ajustada** (balance claro/oscuro + hero del
  Welcome, ver arriba) antes de aplicar el mismo sistema al resto de
  pantallas en Fase 2 — probar en dispositivo real, en particular cómo se
  ve `hero.png` a pantalla completa en distintos tamaños/aspect ratios de
  celular y el contraste real de los scrims sobre la foto.
- **Tamaño del bundle**: `assets/images/hero.png` pesa ~1.8MB, sin
  comprimir (pedido explícito del usuario de no tocar el archivo) — si el
  tamaño final del APK/IPA importa, es una decisión de build/release para
  el PO/Kiro.
- **Hallazgo real, no corregido**: `android/app/src/main/AndroidManifest.xml`
  no declara `android.permission.INTERNET` (solo existe en los manifests de
  `debug`/`profile`) — un build de **release** de esta app, tal como está,
  no tendría permiso de red y rompería todas las llamadas de red en
  producción (backend, Google Sign-In, Drive, y ahora también la descarga
  de fuentes de `google_fonts`). No es un problema introducido por esta
  tarea (ya afectaba a todas las specs anteriores) ni se corrigió acá por
  tocar configuración de release/build, fuera del alcance de un rediseño
  puramente visual — ver el detalle completo en `CLAUDE.md`.
- Ninguna dependencia nueva más allá de `google_fonts` durante Fase 1/2.
  **Actualizado**: la pasada de post-feedback de abajo sí agregó una
  (`flutter_animate`), pedida explícitamente por el usuario.

## Post-feedback de Fase 2 (sin spec de Kiro): bug de borrado, bottom sheet, dinamismo con `flutter_animate`

El usuario probó las 7 pantallas de Fase 2 en su celular real y dio
feedback concreto en tres partes, todas resueltas en esta pasada — detalle
técnico completo (el gotcha de `Hero`+`ClipPath`, el bug real encontrado en
`MemoraHeroCurve.shouldReclip`, el `ListenableBuilder` que necesita el
bottom sheet) en la sección correspondiente de `CLAUDE.md`:

- **Bug real corregido**: quitar una foto del álbum (el "×" de cada
  miniatura) ahora pide confirmación (`AlertDialog`, mismo patrón que el
  resto de acciones destructivas de la app) antes de llamar
  `AlbumsController.removePhotoFromCurrentAlbum` — antes lo llamaba
  directo, así que un toque accidental borraba la foto sin ningún paso
  intermedio. Nuevo test: `test/album_detail_screen_test.dart`.
- **Reestructuración de información**: las secciones "Compartir" y
  "Colaboradores" de `album_detail_screen.dart` (antes siempre expandidas
  debajo de la grilla de fotos, "mucha información en una sola pantalla,
  mucho ruido visual") se movieron a un `showModalBottomSheet`, disparado
  por un ícono nuevo en el `AppBar` (`Icons.people_alt_outlined`,
  "Colaboradores y compartir", visible para owner y colaborador). El
  `CustomScrollView` principal ahora solo tiene el hero, la grilla de
  fotos, y los banners de error/reauth (información crítica, no se movió).
  Mismos controllers/lógica/gating owner-only de siempre — solo cambió
  dónde se renderiza.
- **Más dinamismo (`flutter_animate: ^4.5.2`, agregado vía `flutter pub
  add`, permiso explícito del usuario)**: entrada escalonada real (fade +
  escala) del grid de fotos y de las secciones del bottom sheet nuevo;
  feedback de toque con una escala sutil al presionar en
  `MemoraPrimaryButton`/`MemoraSecondaryButton`/`MemoraCard` (con
  `AnimatedScale` + `InkWell`, no hizo falta el paquete nuevo para esto);
  y una transición `Hero` real (nativa de Flutter) entre la card de álbum
  de `AlbumsListScreen` y el hero de `album_detail_screen.dart`, con tag
  compartido `'album-hero-${album.id}'`. Todo respeta `MediaQuery.of(context)
  .disableAnimations` explícitamente.
- **Pendiente de revisión del usuario en su celular**: el vuelo del `Hero`
  entre la lista y el detalle de álbum — se tomó la opción más
  conservadora entre las dos que permitía la spec de esta tarea (mantener
  el `Hero` dentro de `MemoraCurvedHero.background`, con su `ClipPath`
  como ancestro, no como descendiente) porque este entorno no tiene forma
  de correr la app y ver el vuelo en un dispositivo real. Si se ve
  raro (flicker/tamaño extraño) durante la animación, `CLAUDE.md` documenta
  el siguiente paso (sacar el `Hero` fuera del `ClipPath` con una máscara
  separada).

## Rediseño visual "Aurora" — pivot a light-first (60-30-10, sin spec de Kiro)

Tras validar Fase 1/2 varias veces en dispositivo real, el usuario siguió
viendo la app "sin vida"/"muy oscura". Compartió dos referencias reales de
apps de fotos/colecciones compartidas y pidió aplicar 60-30-10. Decisión
tomada directamente con él: **pivotar de dark-first a light-first** — mismo
remapeo semántico de los 5 colores exactos de siempre (ningún hex cambió),
aplicado a `lib/design/` completo + las 7 pantallas de Fase 1/2. Detalle
técnico completo (gotchas, cada call site migrado, la verificación de
contraste) en la sección homónima de `CLAUDE.md`. Resumen:

- **Mapeo**: 60% `paper` (lienzo), 30% `mist` (superficie secundaria), 10%
  `deepInk` dividido en texto ("tinta") + acento oscuro protagonista puntual
  (nunca fondo de pantalla completo), 10% `signatureGradient` sin cambios
  (CTAs, avatares, badges, y ahora también bordes de card).
- **`memora_theme.dart`**: `MemoraTheme.dark` renombrado a
  `MemoraTheme.theme` (único call site: `main.dart`), `ColorScheme.light()`,
  `scaffoldBackgroundColor: paper`.
- **`MemoraCardElevation`**: `level1`/`level2` pasaron a ser las
  superficies claras por defecto (ya no una excepción); la vieja variante
  `.light` (Paper, la excepción clara rara) se reemplazó por
  **`.ink`** (Deep Ink, la nueva excepción oscura rara) — mismo rol de
  "momento protagonista", espejado.
- **`MemoraSecondaryButton`/`MemoraBadge`/`MemoraLoadingState`/
  `MemoraEmptyState`**: sus colores por defecto se recalibraron para el
  lienzo claro (antes calibrados para el lienzo oscuro universal); cada uno
  ganó un override explícito opcional para las excepciones oscuras
  deliberadas.
- **`semanticError`/`semanticSuccess` se oscurecieron** (rojo-700/verde-700,
  ~6.6:1/~4.8:1 sobre Paper — los pasteles originales daban solo ~2:1 sobre
  Paper). Los originales se conservan como `semanticErrorOnDark`/
  `semanticSuccessOnDark` para las excepciones oscuras.
- **Hallazgo no anticipado**: `glassBlue`/`auraViolet` crudos son
  demasiado claros (~1.6:1) para usarse como ícono/texto/borde directo
  sobre Paper/Mist — se agregaron `glassBlueOnLight`/`auraVioletOnLight`
  (mezclados hacia Deep Ink, ~4.5:1) para esos casos.
- **Las 4 excepciones oscuras deliberadas** (documentadas explícitamente,
  no descuidos): `photo_viewer_screen.dart` completo (convención de
  plataforma — Apple/Google Fotos mantienen el visor en negro incluso en
  modo claro), el hero/Welcome de `HomeScreen` (foto con scrim, sin
  cambios de composición), el overlay del hero de álbum en
  `album_detail_screen.dart`, y cualquier card `MemoraCardElevation.ink`.
- **`AlbumsListScreen`**: el FAB de "+" pasó a círculo sólido Deep Ink
  (el ejemplo textual de la referencia); las cards de álbum pasaron de
  gradiente de fondo completo a un **borde grueso con el gradiente**
  alrededor de una card clara (patrón "cada colección con su propio marco
  de color").
- **`create_album_screen.dart`/`accept_invitation_screen.dart`**: se
  simplificaron — el `InputDecoration` a mano que necesitaba
  `create_album_screen.dart` (porque el theme global de inputs era oscuro y
  su card era clara) ya no hace falta, porque el theme global ahora es
  claro; `accept_invitation_screen.dart` no necesitó ningún cambio de
  código.
- **`nfc_programming_screen.dart`**: el estado `success` pasó de la vieja
  card clara (`.light`) a la nueva card oscura (`.ink`) — mismo rol de
  "premio", espejado.
- Verificado: `flutter analyze` sin warnings, `flutter test` en verde
  (162 tests). Puramente visual — ningún controller/`*Api`/modelo cambió;
  todos los gotchas de interacción/estado documentados en las secciones de
  arriba siguen intactos.

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
También (spec09-programar-nfc.md): la codificación/decodificación/
verificación NDEF-URI pura, sin plugin ni hardware
(`test/nfc_programming_service_test.dart`), y `NfcProgrammingController`
completo contra un `NfcProgrammingService` fake — camino feliz, tag con
contenido previo (confirmación → escribir), declinar la sobrescritura
(cancelado), cancelar mientras se espera un tag (incluyendo el caso real de
Android donde la sesión nunca confirma que se detuvo), NFC apagado/no
soportado, los 5 casos de error cada uno con mensaje propio y distinto,
`retry()` reutilizando el mismo tag, y `lockReadOnly` respetando
`supportsReadOnlyLock` por plataforma
(`test/nfc_programming_controller_test.dart`).
**No** son testeables sin dispositivo: la compresión real
(`flutter_image_compress`, plugin nativo vía MethodChannel), el selector de
galería (`image_picker`), la subida real a Google Drive, la navegación real
entre pantallas de álbumes, el render real de las miniaturas, los diálogos
reales de `promptDriveReconnect`/el picker real de reconexión de Google, el
share sheet real de `share_plus`, el render real del QR (`qr_flutter`), el
gesto real de pinch-zoom/pan/doble-toque y el render real de
`PhotoViewGallery` (`photo_view`), una sesión NFC real y acercar un tag
físico (`nfc_manager`, spec09), y que la `url` compartida efectivamente
resuelva en un navegador o que una etiqueta bloqueada deje de resolver, y
el flujo completo de aceptar una invitación con una cuenta de Google real
distinta a la del owner — se verifican en dispositivo/emulador con una
sesión con Drive autorizado (ver la nota de verificación de
`spec03-fotografias.md`). En particular, forzar una expiración real del JWT
de sesión o revocar el permiso de Drive en una cuenta de Google real para
validar el refresh/reconexión de punta a punta requiere dispositivo — lo
hace el PO.

## Ajuste visual post-feedback: cards con fotos reales, empty state, FAB glass, dashboard (sin spec de Kiro)

Cuatro pedidos puntuales tras validar el pivot light-first en dispositivo
real (ver el detalle completo, decisiones y gotchas en `CLAUDE.md`, sección
"Ajuste visual post-feedback: cards con fotos reales, empty state
ilustrado, FAB glass, dashboard reestructurado"):

1. **`AlbumsListScreen`: cards de álbum con fotos reales tipo "montaje".**
   `AlbumsController` ahora, tras `loadAlbums()`, pide de forma perezosa y
   no bloqueante el `AlbumDetail` de cada álbum con `photoCount > 0` solo
   para cachear (en memoria, por sesión) sus primeras 3 fotos —
   `coverPhotosFor(albumId)`. Cada card muestra un abanico de hasta 3
   miniaturas reales (Polaroid, vía la misma `DriveThumbnailService` de
   siempre) en cuanto llegan; hasta entonces, o si el álbum no tiene fotos,
   se mantiene el fallback abstracto de siempre. **Decisión de arquitectura
   aceptada explícitamente por el usuario** (lo pidió dos veces): un N+1 de
   requests desde la lista — marcado para Kiro por si el backend algún día
   agrega una portada a `GET /albums`.
2. **Empty state ilustrado.** `MemoraEmptyState` ganó un parámetro opcional
   `imageAsset`; `AlbumsListScreen` lo usa con `assets/images/empty.png`
   (nuevo asset, provisto por el usuario) + copy nueva, en vez del ícono
   genérico anterior.
3. **FAB de "crear álbum" con glassmorphism real** (`BackdropFilter` +
   blur + relleno semi-transparente + borde sutil) en vez del círculo
   sólido Deep Ink. **Revertido en el ajuste siguiente** (ver más abajo): el
   glass resultó ilegible sobre el lienzo Paper en un dispositivo real.
4. **`HomeScreen._AuthenticatedDashboard` reestructurado**: las 3 acciones
   (Álbumes/Unirme a un álbum/Fotos) pasaron de "2 cards en fila + 1 card
   distinta debajo" a 3 bloques full-width apilados, cada uno con un tono
   deliberadamente distinto — Álbumes oscura (`MemoraCardElevation.ink`,
   la de mayor peso), Unirme clara (`level1`, compacta), Fotos con marco de
   gradiente (el "tono contraste"), con el mismo contenido/controllers
   exactos que antes en cada una.

`flutter analyze` sin warnings, `flutter test` en 166/166 (incluye
`test/albums_controller_covers_test.dart`, nuevo, para el mecanismo de
covers). No verificado en dispositivo real en este entorno: el render real
del blur/FAB, el aspecto real de las cards con fotos y el dashboard
reestructurado — el usuario debe confirmarlos corriendo la app.

## Ajuste visual post-feedback en dispositivo real: FAB glass ilegible + panel de colaboradores rediseñado

Dos piezas de feedback puntuales tras probar la versión anterior en un
celular real (sin spec de Kiro). Alcance acotado a
`_GlassCreateAlbumFab` (`albums_list_screen.dart`) y a la sección de
compartir/colaboradores del bottom sheet de `album_detail_screen.dart`
(`_openSharingSheet`) — ninguna otra pantalla, ningún controller/`*Api`/
modelo tocado. Detalle completo (incluyendo el porqué de cada decisión) en
`CLAUDE.md`, sección "Ajuste visual post-feedback en dispositivo real: FAB
glass ilegible + panel de colaboradores rediseñado".

1. **FAB "crear álbum"**: el glass del punto 3 de arriba resultó casi
   invisible sobre el lienzo Paper en un dispositivo real ("fondo claro
   sobre fondo claro" — el usuario solo veía el "+" flotando sin ningún
   círculo alrededor). Reemplazado por un relleno SÓLIDO con
   `MemoraColors.signatureGradient`, ícono "+" en `MemoraColors.paper`, y
   una sombra suave derivada de `MemoraColors.deepInk` para que siga
   flotando visualmente. Sin `BackdropFilter`, sin transparencia.
2. **Panel "Colaboradores y compartir"**: feedback textual — "todo sin
   vida, sin orden, puros botones ahi puestos, sin secciones definidas y
   todo color claro, parece una hoja de un articulo de oficina". Cada
   sección (Compartir / Colaboradores) ganó un header con chip circular de
   `signatureGradient` + título con jerarquía tipográfica real (mismo
   lenguaje que `_QuickAccessCard`/`_InitialsAvatar` de `HomeScreen`), un
   teñido sutil de fondo distinto por sección (Glass Blue para Compartir,
   Aura Violet para Colaboradores, vía la nueva `_sectionTint`) y
   `Divider`s reales entre sub-bloques en vez de solo espacio en blanco.
   Los colaboradores ahora se muestran como un **stack de avatares
   circulares superpuestos** con iniciales derivadas del `userId` (no hay
   nombre/email disponible — limitación de PII ya documentada más abajo);
   tocar un avatar dispara la misma confirmación de "quitar" de siempre. El
   bloque de enlace de compartición bajó de dos botones compitiendo
   (Compartir/Revocar) a una acción primaria ("Compartir") + un
   `IconButton` con tooltip para "Revocar". Mismos controllers/lógica/
   gating owner-only exactos — 100% capa visual.

`flutter analyze` → sin issues. `flutter test` → 166/166 (mismo total;
ningún test ejercita el contenido interno del sheet, así que no hubo
regresiones ni tests nuevos necesarios). No verificado en dispositivo real
en este entorno: el aspecto real del FAB sólido y del panel rediseñado — el
usuario debe confirmarlos corriendo la app.

## Pasada de motion design (sin spec de Kiro): sistema centralizado, loading states, microinteracciones

Pedido directo del usuario: motion design real por encima del sistema
visual "Aurora"/light-first (60-30-10) ya documentado arriba. Detalle
completo (incluyendo el gotcha de `initState`+`MediaQuery` y el patrón
`_pendingAction`/`loading:` para distinguir qué botón mutando está cargando)
en `CLAUDE.md`, sección "Pasada de motion design (sin spec de Kiro): sistema
centralizado, loading states, microinteracciones".

Retomó un intento anterior que se había cortado a mitad de camino por un
error de sesión (no de código), con progreso real parcial ya en el repo
(`lib/design/memora_motion.dart`, `memora_page_route.dart`,
`widgets/memora_skeleton.dart`) pero **un bug real que dejaba 1 test roto**.

1. **Bug corregido**: `_MemoraSkeletonState`/`_FloatingEmptyIllustrationState`
   (`albums_list_screen.dart`) llamaban `MemoraMotion.reduceMotion(context)`
   (que usa `MediaQuery` internamente) desde `initState()` — inválido en
   Flutter (cualquier lookup de `InheritedWidget` debe ir en `build()`/
   `didChangeDependencies()`). Movido a `didChangeDependencies()` con un
   flag `_startedRepeating` para no reiniciar el loop en cada llamada
   posterior. Grepeado el resto de `lib/design/` y las pantallas tocadas:
   ningún otro sitio tenía el mismo problema.
2. **Sistema centralizado confirmado completo**: `MemoraMotion` (duraciones
   `quick`/`moderate`, curvas `enterCurve`/`exitCurve`, `stagger()`,
   `reduceMotion()`), `MemoraPageRoute` (reemplaza `MaterialPageRoute` en
   TODOS los `Navigator.push`/`pushReplacement` de la app — se corrigió el
   único sitio que aún usaba `MaterialPageRoute` directo,
   `AcceptInvitationScreen`'s `pushReplacement`).
3. **Hero álbum→detalle**: confirmado funcionando (el fix de
   `MemoraHeroCurve.shouldReclip` ya documentado arriba sigue vigente).
4. **Entrada con stagger**: confirmado (`_animatedAlbumIds` en
   `AlbumsListScreen` ya evita re-animar toda la grilla al crear un álbum
   nuevo — trackea qué ids ya animaron, sin re-disparar `MemoraFadeSlideIn`
   para los que ya estaban en pantalla).
5. **Loading states de TODAS las mutaciones**: nuevo parámetro `loading` en
   `MemoraPrimaryButton`/`MemoraSecondaryButton` (spinner reemplaza el
   ícono, label se mantiene, taps bloqueados) — conectado a cada botón de
   mutación de `album_detail_screen.dart` (rename/visibility/delete ya lo
   tenían vía `_AppBarActionIcon`; se sumaron invite/revoke-invitation/
   remove-collaborator/leave/create-tag/program-nfc/disable-tag/
   revoke-share-link), `create_album_screen.dart`,
   `accept_invitation_screen.dart` y `nfc_programming_screen.dart`
   ("Bloquear como solo lectura"/"Deshabilitar etiqueta"). Dos pantallas
   (`CreateAlbumScreen`, y `_giveUpAndDisable` en
   `NfcProgrammingScreen`) no escuchaban su propio controller — se les
   agregó un flag de estado local (`_submitting`/`_disabling`) en vez de
   depender de `controller.isMutating`, que ahí no dispara rebuild.
6. **Estados de fotografías**: `_PhotoTile`/`_HeroPhotoImage`
   (`album_detail_screen.dart`) ya estaban completos desde antes del corte.
   `photo_viewer_screen.dart` ganó el mismo patrón placeholder→fade→imagen
   vía `AnimatedSwitcher` (antes era un swap abrupto) — seguro dentro del
   `customChild` de `photo_view` porque `AnimatedSwitcher` no registra
   gestos propios.
7-12. Microinteracciones (`AnimatedScale` en botones/cards), empty states
   ilustrados, `AnimatedSwitcher` para loading/error/contenido, toda
   animación gateada por `MemoraMotion.reduceMotion` (sin checks ad-hoc —
   verificado por grep), y `RepaintBoundary`/`dispose()` en los
   `AnimationController` existentes: todos confirmados ya cumplidos, sin
   cambios adicionales necesarios.

`flutter analyze` → `No issues found!`. `flutter test` → **166/166**
pasando (0 tests nuevos: el bug fix hizo pasar el test que ya existía para
la confirmación de borrado de foto; el resto de esta pasada es motion/
loading sobre widgets ya cubiertos indirectamente). No verificado en
dispositivo real en este entorno: el aspecto real de transiciones/loading
states/microinteracciones — el usuario debe confirmarlo corriendo la app.

## Ajuste visual post-mockup: hero "Álbumes", nota caligráfica y bottom nav (sin spec de Kiro)

Réplica de un mockup exacto compartido por el usuario (`principal.png`, no
está en el repo) para el bloque "Álbumes" del dashboard, más una nota
caligráfica de cierre y una barra de navegación inferior nueva. Detalle
completo (decisiones, gotchas, caveats de dispositivo) en `CLAUDE.md`,
sección "Ajuste visual post-mockup: hero 'Álbumes', nota caligráfica y
bottom nav". Alcance acotado a `lib/screens/home_screen.dart` +
`pubspec.yaml` (asset nuevo) — ningún controller/`*Api`/modelo tocado;
`AlbumsListScreen`/`album_detail_screen.dart`/el resto de pantallas y el
sistema de motion existente no se tocaron.

1. **`_AlbumsActionBlock` rediseñado**: de la card clara con franja de
   gradiente anterior a un hero oscuro con `RadialGradient` (Aura Violet →
   Deep Ink, el exacto que pidió el usuario), esferas de glow extra con el
   mismo patrón de blur ya usado en `_AuroraBackdrop`, el asset
   `assets/images/principal_asset.png` (nuevo, declarado en `pubspec.yaml`)
   desbordando la esquina superior derecha, un eyebrow "TUS ÁLBUMES", un
   headline de dos líneas con la última palabra ("compartes.") en el
   gradiente de firma vía `ShaderMask`, un círculo con flecha decorativo, y
   3 puntos de paginación **puramente decorativos** (no hay `PageView` real
   ni una "página 2" con contenido — documentado explícitamente en el
   código para que no se confunda con un carrusel funcional).
   `assets/images/principal_fondo.png` (el otro asset provisto) **no se
   usó**: el efecto de fondo se replicó con gradiente + blur de Flutter
   puro y quedó suficientemente parecido, así que no se declaró en
   `pubspec.yaml` (queda disponible si un futuro ajuste sí lo necesita como
   imagen real).
2. **Nota caligráfica de cierre**: "Recuerdos que nos conectan" + un
   corazón chico, en `GoogleFonts.caveat` (nueva, usada solo en este
   `Text` puntual — `MemoraTypography` sigue siendo Manrope en todo lo
   demás), con un glow violeta grande y borroso detrás, al final de
   `_AuthenticatedDashboard`.
3. **Bottom navigation bar nueva** (`_AuroraBottomNav`, adición real a la
   app — antes no existía): 4 ítems + un "+" central flotante con el
   mismo lenguaje sólido-con-gradiente que el FAB de `AlbumsListScreen`
   (sin repetir el experimento de glassmorphism ya descartado). Solo
   visible con sesión iniciada (`Scaffold.bottomNavigationBar`, nunca en el
   Welcome). **Inicio**: esta misma pantalla, activo por defecto, sin
   navegación. **Álbumes**: el mismo `Navigator.push` que ya usa el resto
   del dashboard. **"+"**: la misma
   `PhotoUploadController.pickAndUploadPhotos()` que ya dispara "Agregar
   fotos" en `_PhotosSection` — ningún flujo nuevo. **Compartidos/
   Ajustes**: sin pantalla (decisión de producto ya tomada con el usuario,
   marcada para una futura spec de Kiro) — tocarlos solo muestra un
   `SnackBar` "muy pronto", nunca navegan ni crashean.
4. **Corrección post-feedback en dispositivo real (mismo alcance acotado a
   `home_screen.dart`)**: el usuario probó lo anterior en su celular contra
   el mockup original y dio 2 ajustes puntuales. Detalle completo en
   `CLAUDE.md`, sección "4. Corrección post-feedback en dispositivo real:
   fondo oscuro continuo, no card encajonada" (dentro del mismo bloque de
   arriba). Resumen:
   - El gradiente oscuro dejó de ser una card aislada sobre fondo blanco:
     ahora es el fondo de TODA la zona superior del dashboard autenticado
     (header con logout+badge, fila de avatar+nombre+email, y el contenido
     del hero de "Álbumes", sin blanco entre medio) — recién donde empieza
     "Unirme a un álbum" el fondo pasa a `Paper`. `_AlbumsActionBlock` se
     renombró a `_AlbumsHeroContent` (perdió su propio fondo/altura fija) y
     un nuevo `_DashboardDarkZone` pinta el `RadialGradient`+glow una sola
     vez para header+avatar+hero juntos, dimensionado por su propio
     contenido (no un alto fijo calculado a mano). Header/avatar pasaron a
     colores explícitos Paper (antes vivían sobre el lienzo claro del
     dashboard, donde el tema ambient ya era correcto por defecto).
   - Más espacio (`MemoraSpacing.xxl`/`.md`, ningún número suelto) entre el
     header, la fila de avatar y el eyebrow "TUS ÁLBUMES", que antes quedaba
     apretado contra el borde superior.

`flutter analyze` → `No issues found!`. `flutter test` → **166/166**
pasando (sin tests nuevos en ninguna de las dos pasadas: el cambio es 100%
composición visual/layout sobre callbacks/controllers ya cubiertos
indirectamente, y ningún test existente busca el texto exacto del
hero/footer/bottom nav, así que seguir en verde confirma que nada rompió
pero no es una aserción dedicada). **No verificado en dispositivo real en
este entorno**: el aspecto real del gradiente radial/asset decorativo/glow
del hero (incluido el nuevo `Alignment`/`radius` reajustados para la zona
más alta), la nota caligráfica, la barra de navegación inferior, y que el
corte dark→light se vea continuo/sin caja blanca — el usuario debe
confirmarlos corriendo la app.

## Ajuste visual post-feedback en dispositivo real: revert del hero de Home + rediseño completo de `AlbumsListScreen` (sin spec de Kiro)

Dos piezas de feedback tras probar la app en el celular real (detalle
completo en `CLAUDE.md`):

1. **Revert puntual del hero "Álbumes" de `HomeScreen`**: la tarea anterior
   había hecho que el gradiente oscuro fuera el fondo de toda la zona
   superior (header+avatar+hero). El usuario prefería la versión anterior
   ("TUS ALBUMES se veia mejor como una tarjeta") — vuelto a una card
   contenida (`_AlbumsHeroCard`, `ClipRRect(MemoraRadius.hero)` con su
   propio gradiente/glow), flotando sobre el lienzo `Paper` normal; el
   header y la fila de avatar volvieron a colores por defecto del tema. El
   espaciado extra (`MemoraSpacing.xxl`/`.md`) sumado en la tarea anterior
   **se mantuvo**.
2. **Rediseño completo de `AlbumsListScreen`** según una referencia visual
   exacta del usuario (no en el repo): header "Mis álbumes" +
   "`{N} álbumes · {M} recuerdos`", dos círculos de acción (búsqueda —
   placeholder "muy pronto", no es una feature real — y crear álbum, que
   reemplaza al FAB eliminado), grid de 2 columnas con la foto de portada
   REAL de cada álbum a pantalla completa (una sola foto, ya no el montaje
   de 2-3 en abanico), menú "···" por card con Renombrar/Eliminar
   funcionales (reutiliza `AlbumsController.loadAlbumDetail` +
   `renameCurrentAlbum`/`deleteCurrentAlbum`, el mismo mecanismo que
   `AlbumDetailScreen`, sin inventar ningún método nuevo), una card
   promocional al final de la grilla, y el mismo `AuroraBottomNav` de
   `HomeScreen` abajo (extraído a `lib/design/widgets/aurora_bottom_nav.dart`
   para no duplicarlo entre las dos pantallas — parametrizado por
   `activeTab`).
   - Estado "sin fotos" de una card (`photoCount == 0`): área de portada
     oscura con ícono + "Aún no hay fotos" / "Agrega recuerdos para que
     este álbum cobre vida." — distinto del estado "cover todavía
     cargando" (skeleton), que sigue siendo un caso separado.
   - **Limitación de datos conocida, no inventada**: la referencia mostraba
     una descripción/caption corta por álbum que el backend no expone
     (`AlbumListItem`/`AlbumDetail` solo tienen `name`) — se omitió, sin
     inventar un campo nuevo.
   - `AlbumsController`/`*Api`/modelos: sin cambios, solo se leen métodos
     que ya existían.

`flutter analyze` → `No issues found!`. `flutter test` → **166/166**
pasando (mismo total exacto — sin tests nuevos: `albums_list_screen.dart`
seguía sin tener su propio archivo de widget tests antes de esta tarea
también, y el comportamiento del controller que el nuevo menú "···"
reutiliza ya está cubierto desde `albums_controller_test.dart`/
`album_detail_screen_test.dart`). **No verificado en dispositivo real en
este entorno**: el aspecto real de la card contenida del hero de Home, del
grid con fotos reales de `AlbumsListScreen`, y el comportamiento táctil del
menú "···"/diálogos — el usuario debe confirmarlos corriendo la app.

## Mockup redesign: tabs inline + menú overflow del owner (sin spec de Kiro)

Rediseño estructural de `album_detail_screen.dart` a partir de una nueva
referencia visual del usuario (mockup, no en el repo). Cambios principales
(detalle completo, incluidas decisiones no triviales, en `CLAUDE.md`):

- El hero ganó una fila de metadata (conteo de fotos + fecha de creación,
  formateada a mano en español — sin paquete nuevo) debajo del badge de rol.
- El AppBar pasó de "1 ícono de personas + 3 íconos owner-only sueltos" a 3
  círculos translúcidos: "Colaboradores" y "Compartir" (owner-only, este
  último) cambian el tab activo; un menú "···" (owner-only) agrupa
  Renombrar/Cambiar visibilidad/Eliminar álbum (mismos diálogos/lógica de
  siempre).
- El `showModalBottomSheet` de Compartir/Colaboradores se eliminó — ahora son
  2 de 3 tabs pill inline debajo del hero ("Fotos"/"Colaboradores"/
  "Compartir", nuevo componente reutilizable `MemoraSegmentedTabs` en
  `lib/design/widgets/`), con "Fotos" como contenido por defecto.
- El header de "Fotos" ahora tiene un control de orden funcional ("Más
  recientes"/"Más antiguas") sobre `Photo.capturedAt`, puramente client-side
  (nunca toca `AlbumsController`), con las fotos sin fecha siempre al final
  de forma estable.

Ningún controller/`*Api`/modelo cambió. `flutter analyze` → sin issues.
`flutter test` → **168/168** (166 previos + 2 nuevos: orden de fotos y
cambio de tab). No verificado en dispositivo real en este entorno.

## Restyle de "Compartir"/"Colaboradores" según referencia `colaboradores.png` (sin spec de Kiro)

Solo restyle visual del CONTENIDO de los tabs "Compartir"/"Colaboradores"
(los tabs en sí, de la tarea anterior, se quedan igual) — pedido explícito
del usuario ("las referencias visuales son para modificar la UI, no la
lógica"). Detalle completo, incluidas decisiones no triviales marcadas para
Kiro, en `CLAUDE.md`.

- **"Compartir"**: header con subtítulo + un pill tappable de visibilidad
  (🔒/🌐, misma acción `_changeVisibility` de siempre). El enlace de
  compartición pasó a su propia card destacada, con un botón pill degradado
  ("Obtener enlace") cuando no existe uno todavía. Los 3 botones sueltos
  (Crear QR/Crear NFC/Programar NFC) pasaron a ser una fila de 4 accesos con
  ícono circular + label separados por líneas verticales — el cuarto,
  "Compartir en otras apps", es la única acción nueva (comparte el enlace del
  álbum por el share sheet del sistema, obteniéndolo/creándolo primero si
  hace falta — reutiliza los mismos métodos de siempre). Al final, un banner
  oscuro "Comparte con solo un toque" (estilo Aurora, asset
  `assets/images/nfc_icon.png` nuevo) que abre la programación de NFC.
- **"Colaboradores"**: el avatar-stack superpuesto (círculos apilados) volvió
  a ser una lista de filas completas — una fija para el usuario actual (con
  su nombre/email real, ya disponible en la pantalla, y badge "Owner"), una
  por cada otro colaborador (label genérico "Colaborador", ya que el backend
  no expone su nombre/email — limitación real, documentada desde spec05) y
  una por cada invitación pendiente (con su fecha de expiración; sin email,
  porque a diferencia de lo que asumía el brief de esta tarea, el backend
  tampoco guarda un email al crear una invitación — invitación por enlace,
  no por correo).

`flutter analyze` → sin issues. `flutter test` → **169/169** (168 previos +
1 nuevo test de vista owner de ambos tabs). No verificado en dispositivo
real en este entorno.

---

Getting Started (plantilla original de Flutter):

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
