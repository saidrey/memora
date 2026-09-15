# memora-app — convenciones y gotchas

Flutter. Único punto de captura/subida de contenido. Toda comunicación con
el backend pasa por `lib/api/` (`ApiClient` — ningún otro archivo usa
`http.get`/`http.post` directo contra `memora-backend`).

Para el estado de lo implementado spec por spec, ver `README.md` de esta
carpeta (ahí se documenta el avance porque `specs/` no se edita).

## Reglas de entorno

- No cambiar configuración global de Flutter/Dart (`flutter config`, etc.).
- **`google_sign_in` v7+ únicamente** — API separada de
  autenticación/autorización. Nunca usar `signIn()` ni leer `serverAuthCode`
  del resultado de autenticación (API pre-v7, prohibida): el flujo correcto
  es `GoogleSignIn.instance.authenticate()` (identidad) seguido de
  `account.authorizationClient.authorizeServer(scopes)` (autorización de
  servidor / `serverAuthCode`).
- Identidad del usuario viene del endpoint `userinfo` de Google (vía access
  token), no de verificar el `id_token` — por eso la app debe pedir los
  scopes `openid`, `email`, `profile` además de los de Drive.
- Sesión (JWT propio) se persiste **solo** con `flutter_secure_storage`
  (Keychain/Keystore). Nunca `SharedPreferences` ni almacenamiento en claro.
- Configuración vía `--dart-define` (`API_BASE_URL`,
  `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`), con defaults de la spec.
  Excepción: `ios/Runner/Info.plist` (`GIDClientID`,
  `CFBundleURLTypes`/esquema invertido) es plist nativo que el SDK lee antes
  de que Dart arranque — no puede venir de `--dart-define`, va hardcodeado
  (son valores públicos, no secretos).
- Emulador de Android: `localhost` es el propio emulador, no el host — usar
  `http://10.0.2.2:3000/api/v1` como `API_BASE_URL` ahí.
- **Excepción explícita a "todo pasa por `ApiClient`" (spec03-fotografias):**
  la subida de bytes a Google Drive (`lib/photos/drive_upload_service.dart`)
  usa `package:http` directo contra `googleapis.com`, NO `ApiClient`. Es
  intencional: Drive es otro host con su propio token de vida corta
  (`driveAccessToken`, scope `drive.file`) que nunca debe llegar al backend
  de Memora — `ApiClient` es solo para `memora-backend`. No confundir esto
  con una violación de la regla; es la única excepción y está acotada a ese
  archivo.
- **`flutter_image_compress`'s `minWidth`/`minHeight` NO son "cap del lado
  mayor"** (gotcha real, ver `lib/photos/photo_optimizer.dart`): internamente
  calculan `scale = max(1, min(srcW/minWidth, srcH/minHeight))`. Pasar el
  mismo valor (p. ej. 2048) en ambos hace que el plugin **no redimensione**
  si CUALQUIERA de las dos dimensiones crudas ya es ≤ 2048, aunque la otra
  sea mucho mayor (una foto 4000x1200 quedaría intacta). Por eso la app
  decodifica el tamaño real de la fuente (`dart:ui.instantiateImageCodec`) y
  calcula ella misma el `minWidth`/`minHeight` exactos con
  `computeTargetDimensions` (función pura, testeada sin dispositivo) antes
  de llamar a `compressWithList`. `keepExif` por defecto es `false` (así se
  cumple D8 sin pasar nada extra); `autoCorrectionAngle` por defecto es
  `true` (hornea la orientación EXIF, cumpliendo D15) — no pasar `keepExif:
  true` nunca.
- **`image_picker` en Android no requiere permisos ni cambios de
  manifest** para seleccionar de galería (usa el Photo Picker del sistema /
  `ACTION_GET_CONTENT`; verificado en `image_picker_android` 0.8.13+23, sin
  declaraciones de `READ_MEDIA_IMAGES`/`READ_EXTERNAL_STORAGE` en su propio
  manifest). El `minSdkVersion` por defecto de Flutter (24, ver
  `FlutterExtension.kt`) ya cubre el mínimo del plugin (SDK 24+). En iOS sí
  hace falta `NSPhotoLibraryUsageDescription` en `Info.plist` (por política
  de App Store), aunque llamando `pickMultiImage(requestFullMetadata:
  false)` el `PHPicker` de iOS 14+ no llega a pedir el permiso en runtime.
- **`GET /api/v1/albums` responde un array JSON suelto** (`AlbumListItem[]`),
  no un objeto — a diferencia de todos los demás endpoints que esta app
  consumía hasta spec04 (siempre `Map<String, dynamic>`). `ApiClient` tenía
  solo `getJson`/`postJson`, que asumían un objeto; se agregó
  `getJsonList(path)` para este caso, y `_send` se generalizó para devolver
  `dynamic` (el llamador castea a `Map` o `List` según corresponda) en vez
  de forzar siempre `Map<String, dynamic>`. Si aparece otro endpoint de
  lista en el futuro, usar `getJsonList`, no intentar decodificarlo con
  `getJson` (silenciosamente devolvería `{}`).
- **`AlbumDetail` (`GET /api/v1/albums/:id`) NO incluye `role`** — verificado
  contra `memora-backend/src/albums/albums.service.ts`: solo
  `AlbumListItem` (la lista combinada `GET /albums`) lo tiene; `AlbumDetail`
  es literalmente `AlbumSummary & { photos }`. Por eso
  `AlbumsController.loadAlbumDetail(albumId, {required role})` recibe el
  rol como parámetro en vez de leerlo de la respuesta — la pantalla de
  lista se lo pasa a la de detalle al navegar (ver
  `lib/albums/screens/albums_list_screen.dart`). Si una futura spec permite
  abrir un álbum sin pasar por la lista (deep link, notificación, etc.), va
  a hacer falta o bien un nuevo endpoint que sí incluya el rol, o resolverlo
  de otra forma — no asumir que `AlbumDetail` algún día lo tendrá sin
  volver a verificar el backend.
- **Miniaturas de Drive: sin SDK, `alt=media`, caché en memoria únicamente**
  (`lib/albums/drive_thumbnail_service.dart`, spec04-ui-albumes decisión A):
  `GET https://www.googleapis.com/drive/v3/files/{fileId}?alt=media` con el
  `driveAccessToken` en `Authorization` devuelve los bytes crudos del
  archivo — nunca `thumbnailLink`/`webContentLink` (piden auth de Google
  aparte del token de la app y caducan). La caché es un
  `Map<fileId, Uint8List>` sin expiración ni límite de tamaño (alcanza para
  una sesión con un álbum abierto a la vez); no hay caché en disco. **El
  token de Drive NO se comparte entre `PhotoUploadController` y
  `DriveThumbnailService`**: ambos reciben la misma instancia (sin estado)
  de `DriveTokenApi` desde `main.dart`, pero cada uno mantiene su propio
  `DriveToken` cacheado — decisión deliberada, no un descuido: sus ciclos
  de vida son distintos (un lote de subida es corto y descarta su caché al
  terminar; la pantalla de detalle de álbum sigue pidiendo miniaturas
  mientras esté abierta) y `POST /auth/drive-token` es barato/idempotente,
  así que la rara coincidencia de pedir token dos veces a la vez es un
  costo aceptable frente a acoplar dos controllers independientes con
  estado mutable compartido. Si en el futuro esto causa problemas reales
  (rate limiting del endpoint, por ejemplo), la solución sería extraer un
  `CachedDriveTokenProvider` compartido — no se hizo preventivamente para
  no añadir acoplamiento sin evidencia de que hace falta.
- **`flutter test` (sin flags) puede mostrar la asociación
  archivo↔test de forma engañosa bajo concurrencia por defecto**: con 10+
  archivos de test, el reporter (`compact`/`expanded`) intercala la salida
  de varios archivos ejecutándose en paralelo, y el nombre de archivo
  impreso junto a cada línea `+N:` puede no corresponder de forma fiable al
  archivo real de ESA línea — un `grep` sobre la salida puede parecer
  indicar que un archivo completo "no corrió". El conteo total de tests y
  el resultado final (`All tests passed!`/exit code) SÍ son fiables —
  verificado corriendo `flutter test --concurrency=1` (serial), que
  siempre imprime la asociación correcta y confirma el mismo total exacto
  de tests. Si algún día hace falta depurar qué archivo/test específico
  falló, usar `--concurrency=1` en vez de confiar en la salida por
  defecto con muchos archivos.
- **Nunca `autofocus: true` en un `TextField` dentro de `showDialog`**:
  descubierto en validación real de spec04 — cerrar el diálogo de
  renombrar álbum (tocando fuera del modal, o "Cancelar") crasheaba con
  pantalla roja: `Failed assertion: '_dependents.isEmpty': is not true`
  (`framework.dart`). Es un problema conocido del framework: una petición
  de foco automático pendiente que sobrevive al `Element` del diálogo
  cuando este se descarta rápido (barrier dismiss o pop inmediato). Se
  quitó `autofocus: true` del `TextField` de
  `AlbumDetailScreen._renameAlbum` — si se agrega otro diálogo con
  `TextField` en el futuro, NO ponerle `autofocus: true`.
- **Ítems de una lista/grid con estado async propio (`FutureBuilder` +
  `late final`) necesitan `key` estable por id, no solo por posición**:
  descubierto en validación real de spec04 — quitar una foto del álbum
  hacía que la miniatura equivocada desapareciera de la grilla. Causa:
  `GridView.builder` sin `key` reconcilia por posición; al reducir la
  lista, Flutter reutilizaba el `State` de `_PhotoTile` (con su
  `_thumbnailFuture` ya cacheado en un campo `late final`, calculado una
  sola vez) para la foto que quedó en esa misma posición, mostrando la
  miniatura de la foto vieja pegada a los datos de otra. El "×" de borrar sí
  actuaba sobre la foto correcta (el callback se recalcula en cada build),
  pero el usuario terminaba clickeando la foto equivocada porque veía la
  miniatura de otra. Arreglado con `key: ValueKey(photo.id)` en cada
  `_PhotoTile` (`lib/albums/screens/album_detail_screen.dart`). Cualquier
  `ListView.builder`/`GridView.builder` futuro cuyos items mantengan estado
  propio (imagen cacheada, animación, etc.) necesita el mismo patrón —
  nunca asumir que la posición identifica al item.
- **Un 401 genérico (JWT de sesión expirado) SHALL mostrarse como "Tu
  sesión expiró. Vuelve a iniciar sesión."**, no como el mensaje genérico
  de error — se descubrió en validación real de spec04 (listar/crear
  álbumes fallaba con "Ocurrió un error" tras dejar la sesión abierta un
  rato; el backend respondía 401 `UNAUTHORIZED` porque `spec02`/`A1.5`
  (refresco automático de sesión) todavía no existe). Este 401 de sesión es
  DISTINTO del 401 `DRIVE_REAUTHORIZATION_REQUIRED` (ese es específico de
  Drive y ya tenía su propio manejo desde spec03 —
  `DriveReauthorizationRequiredException`). El patrón: cada controller que
  llama al backend revisa `error is ApiException && error.statusCode ==
  401` en su mapeo de errores y antepone este mensaje al genérico de
  contexto (ver `AlbumsController._messageFor` y
  `PhotoUploadController._processItem`'s catch) — repetido en cada
  controller a propósito (dos líneas, no una abstracción nueva) en vez de
  centralizarlo en `ApiClient`, que deliberadamente solo conoce
  `ApiException`, no mensajes de UI. **Actualización (spec06-sesion-y-reauth-drive):**
  A1.5 (refresco automático) ya está implementado en `ApiClient` — la
  mayoría de estos 401 ahora se resuelven de forma transparente antes de
  llegar a estos controllers; este mensaje sigue existiendo como red de
  seguridad (el refresh también puede fallar, o el 401 puede repetirse en el
  reintento post-refresh) pero ya no es el camino principal. Ver la sección
  "ApiClient: interceptor de refresh de sesión" más abajo.
- `flutter build apk` imprime una advertencia de que
  `flutter_image_compress_common` aplica su propio Kotlin Gradle Plugin y
  que versiones futuras de Flutter podrían dejar de compilar plugins así
  ("Built-in Kotlin" migration) — no falla el build hoy (verificado con
  `flutter build apk --debug`), pero si una futura actualización de Flutter
  rompe el build por esto, es un problema conocido del plugin, no del
  código de esta app.
- **`ApiClient`: interceptor de refresh de sesión (spec06-sesion-y-reauth-drive,
  A1.5)** — `_send` detecta un 401 de sesión (`statusCode == 401 && code !=
  'DRIVE_REAUTHORIZATION_REQUIRED'`), intenta `POST /auth/refresh` una vez
  (nunca vía `_send`, para no recursar ni mandar un Bearer irrelevante) y
  reintenta la request original una sola vez si funciona (`isRetry: true`
  evita una segunda vuelta). Refreshes concurrentes coalescen en
  `_refreshInFlight` (un solo `POST /auth/refresh` real aunque varias
  requests reciban 401 "al mismo tiempo" — determinístico en Dart pese a ser
  single-threaded: cualquier request que ve `_refreshInFlight` ya asignado
  simplemente espera esa misma `Future`, sin condición de carrera real,
  porque la asignación ocurre de forma síncrona antes del primer `await`
  dentro de `_performRefresh`). `ApiClient` NUNCA persiste nada — expone
  `onSessionRefreshed`/`onSessionInvalidated` (campos públicos mutables,
  mismo patrón que `setAccessToken`) para que `AuthController` decida qué
  hacer. Si se agrega un endpoint nuevo con guard propio en el futuro y ese
  guard alguna vez responde 401 con OTRO código además de `UNAUTHORIZED`
  (que ya cae en "sesión" porque no es el código específico de Drive), hay
  que revisar si debe seguir cayendo en el refresh automático o si necesita
  su propia exclusión como Drive.
- **Reconectar Google Drive reutiliza el login, no hay endpoint dedicado**
  (spec06, A1.6) — confirmado leyendo `memora-backend`: no existe (ni se
  creó) un endpoint de "reconectar"; `POST /auth/google` hace upsert del
  usuario y sobrescribe el refresh token de Google que el backend tiene
  guardado, así que `AuthController.reconnectDrive()` simplemente vuelve a
  correr `GoogleAuthService.signInAndAuthorizeServer()` +
  `AuthApi.loginWithGoogle()` — el mismo canal que `signIn()`. Si el
  backend alguna vez agrega un endpoint dedicado para esto, hay que migrar
  `reconnectDrive()` a usarlo (hoy depende de un detalle de implementación
  del backend, no de un contrato explícito para "reconectar").
- **Forzar `GridView.builder` a re-crear tiles con el MISMO id (no solo
  distinguir por id)**: extensión del gotcha de key-por-id de spec04. Vaciar
  la caché de datos (`DriveThumbnailService.clearCache()`) NO alcanza para
  que una miniatura que falló se vuelva a pedir, porque `_PhotoTileState`
  guarda su `Future` en un campo `late final` calculado una sola vez al
  crear el `State` — y como la key sigue siendo `photo.id` (sin cambios),
  Flutter reutiliza el mismo `State` (con el mismo `Future` ya resuelto en
  error) en vez de crear uno nuevo. La solución (spec06,
  `AlbumDetailScreen`) es sumar un "epoch" que cambie tras la acción que
  invalida el estado cacheado, y meterlo en la key junto al id:
  `ValueKey('${photo.id}#$_epoch')` — mismo id para identidad correcta al
  reordenar/quitar, pero un id de key distinto tras el epoch para forzar un
  `State` nuevo. Cualquier widget futuro con un `late final Future`/estado
  cacheado por id que alguna vez necesite "refrescar todos" (no solo
  "identificar cada uno") necesita este mismo patrón de dos partes.
- **spec05-ui-colaboradores.md dice que `GET /albums/:albumId/collaborators`
  es "owner o miembro" — es falso, verificado contra el código real**: tanto
  ese endpoint como `GET .../invitations` llaman
  `AlbumAccessService.requireOwner` en el backend
  (`memora-backend/src/albums/collaborators/collaborators.service.ts` /
  `invitations.service.ts`), no `requireMembership`. La sección completa de
  colaboradores/invitaciones en el detalle del álbum es **100% owner-only**
  — no confiar en la prosa de una spec "APROBADA" sobre esto sin releer el
  controller/servicio real; ya pasó antes con otras imprecisiones de specs
  de `memora-backend` (ver su propio CLAUDE.md, sección NFC/QR).
- **`GET /albums/:albumId/collaborators` no expone PII: solo `userId`**
  (`CollaboratorsService.list`, `memora-backend`) — nunca email ni nombre.
  `CollaboratorListItem.userId` en `lib/albums/collaborator_models.dart` es
  literalmente ese id interno; no hay forma de mostrar "quién" es un
  colaborador por nombre/email desde esta pantalla hoy. No inventar un
  endpoint nuevo ni un campo que el backend no manda — es una limitación de
  producto real, marcada para una futura spec de backend.
- **Combinar un grid lazy con contenido variable debajo, en un solo
  scroll**: `AlbumDetailScreen` (spec05) necesitaba agregar una sección de
  colaboradores/invitaciones (alto variable, puede crecer) debajo de la
  grilla de fotos (potencialmente larga) sin que ambas compitan por un
  `Expanded` de altura fija dentro de un `Column`. Se migró el body de
  `Column` + `GridView.builder` en un `Expanded` a un único
  `CustomScrollView` con `SliverPadding(sliver: SliverGrid.builder(...))`
  para las fotos (conserva la construcción lazy, mismo `gridDelegate`) más
  un `SliverToBoxAdapter` para la sección de abajo (construida eagerly —
  aceptable porque la cantidad de colaboradores/invitaciones de un álbum es
  chica en el MVP). Si una futura pantalla necesita agregar OTRA sección
  larga/lazy debajo de una lista existente, este es el patrón: slivers en
  un `CustomScrollView`, no `Column` con múltiples `Expanded`.
- **`share_plus` 13.x: la API vigente es `SharePlus.instance.share(ShareParams(...))`,
  no `Share.share(text)`** — la clase `Share` con métodos estáticos sigue
  existiendo pero está `@Deprecated`. `ShareParams` es exportada por el
  paquete raíz (`package:share_plus/share_plus.dart`), no hace falta
  importar el paquete de plataforma. No requiere ningún permiso/entrada de
  `Info.plist`/`AndroidManifest.xml` nuevo para compartir solo texto
  (`ShareParams(text: ...)`, el caso de esta app — un enlace de invitación).
- **Reportar un error de un `Future` cacheado (`late final`) a un ancestro
  sin tragárselo**: para que `AlbumDetailScreen` supiera que una miniatura
  falló por `DriveReauthorizationRequiredException` (para mostrar un banner
  a nivel de pantalla, no solo el ícono por-tile que ya existía),
  `_PhotoTileState._thumbnailFuture` se envolvió con
  `.catchError((error) { ...notificar al padre...; throw error; })` —
  clave: **volver a lanzar (`throw error`) dentro del `catchError`**, porque
  si no, `Future.catchError` consume el error y `FutureBuilder` vería la
  future como resuelta sin error (perdiendo el ícono `link_off` por-tile).
  La notificación al padre se agenda con
  `WidgetsBinding.instance.addPostFrameCallback` porque llamar `setState`
  del ancestro sincrónicamente desde dentro de la construcción del árbol de
  un descendiente (el `late final` se evalúa durante `initState`/build del
  tile) puede pisar un frame en construcción.
- **No existe `GET /albums/:albumId/nfc-qr-tags` (listar etiquetas de un
  álbum) — verificado contra el backend real (spec07-compartir-nfc-qr.md)**:
  `memora-backend` solo expone crear (`POST /albums/:albumId/nfc-qr-tags`,
  bajo el álbum) y consultar/deshabilitar por id propio de la etiqueta
  (`GET`/`PATCH .../disable` en `/nfc-qr-tags/:id`, **sin** `albumId` en la
  ruta — son dos controllers distintos en el backend, no un descuido de esta
  app). Sin un endpoint de listado, `AlbumsController.nfcQrTags` es una
  lista **en memoria, no persistida**, poblada únicamente por cada
  `createNfcQrTag` exitoso durante la sesión actual de la pantalla de
  detalle — se resetea a `[]` cada vez que se abre un álbum *distinto* (ver
  `loadAlbumDetail`), pero sobrevive a un refresco del mismo álbum (p. ej.
  tras agregar fotos). Cerrar y reabrir el detalle de un álbum hace que las
  etiquetas creadas antes "desaparezcan" de esta lista — sus `url` siguen
  resolviendo igual, la app simplemente no puede volver a listarlas. Esto es
  una limitación real marcada para Kiro (posible spec futura de backend:
  `GET /albums/:albumId/nfc-qr-tags`), no algo que se deba resolver
  inventando un endpoint del lado del cliente. Si un futuro cambio agrega
  ese endpoint, `AlbumsController.loadAlbumDetail` (o un método nuevo) debe
  cargar la lista real en vez de mantenerla como estado de sesión.
- **`ApiClient.patchJson` requiere un `body` (no es opcional) incluso para un
  endpoint que no necesita ninguno**: `SharingApi.disableNfcQrTag` llama
  `patchJson('/nfc-qr-tags/$tagId/disable', const {})` — un objeto vacío,
  no `null` — porque la firma de `patchJson` exige `Map<String, dynamic>`
  como segundo argumento posicional (a diferencia de `postJson`, que sí
  tiene default `const {}`). Enviar `{}` es inofensivo para un endpoint que
  no lee el body.
- **`qr_flutter` (`^4.1.0`, agregado en spec07-compartir-nfc-qr.md)**:
  `QrImageView(data: url, size: ...)` renderiza el código QR en el cliente a
  partir de la `url` que devuelve el backend — offline, sin pedir una
  imagen al backend (decisión de la spec). No requiere ningún permiso
  nativo nuevo.
- **`photo_view` (`^0.15.0`, agregado en spec08-visor-foto-inapp.md,
  resuelto vía `flutter pub add` — no fijado a mano)**: usar
  `PhotoViewGalleryPageOptions.customChild(child: ...)` por página, nunca
  `imageProvider:` directo, cuando la imagen se carga de forma asíncrona con
  estados propios de carga/error/reintento — `.customChild` envuelve
  cualquier widget con el mismo comportamiento de zoom/pan/pinch/doble-toque
  sin exigir un `ImageProvider` síncrono. Ver
  `lib/albums/screens/photo_viewer_screen.dart`.
- **Un widget interactivo (botón) dentro de un `customChild` de `photo_view`
  SÍ recibe el tap, pero con un retraso real de hasta `kDoubleTapTimeout`
  (300 ms)** — descubierto testeando `photo_viewer_screen_test.dart`, no es
  un artefacto del entorno de test: `PhotoViewGestureDetector`
  (`photo_view`'s `photo_view_gesture_detector.dart`) registra SIEMPRE un
  `DoubleTapGestureRecognizer` (para el doble-toque que hace zoom), exista o
  no un callback `onDoubleTap` propio. Ese recognizer entra en la misma
  gesture arena que el `TapGestureRecognizer` de cualquier botón anidado
  dentro del `customChild`, y no se resuelve (rechaza el doble-toque) hasta
  que expira el timeout de doble-toque de Flutter — recién ahí el tap del
  botón se declara ganador y dispara `onPressed`. Es un comportamiento
  esperado de cualquier gesto dentro de una zona con zoom/pan (no un bug),
  pero hay que tenerlo en cuenta: (1) en tests con `tester.tap`, hace falta
  `await tester.pump(kDoubleTapTimeout + margen)` **antes** de
  `pumpAndSettle` — `pumpAndSettle` sola no alcanza a destrabar el temporizador
  pendiente de forma confiable; (2) en producción, esperar un ~300ms de
  latencia perceptible antes de que "Reintentar"/"Reconectar Google Drive"
  reaccionen dentro del visor — aceptable para este alcance (UI mínima
  funcional), pero si una futura spec pide una respuesta instantánea para
  controles dentro del visor, la solución es sacarlos del `customChild` (un
  overlay `Stack` por encima de `PhotoViewGallery`, fuera de la zona de
  zoom/pan) en vez de intentar "ganarle" la gesture arena a `photo_view`.
- **Un `Future` reasignado desde un callback que NO es `initState` necesita
  `Future.ignore()` antes de guardarlo en el campo mutable, o puede crashear
  con "Unhandled exception" en vez de mostrar el estado de error**
  (descubierto implementando `_PhotoViewerPage._load()` en
  `photo_viewer_screen.dart`, spec08). El patrón de `_PhotoTile`
  (`late final _thumbnailFuture` en `album_detail_screen.dart`) funciona
  porque se crea en `initState`, inmediatamente seguido de un `build()`
  síncrono en el mismo frame que suscribe el `FutureBuilder` — no hay
  ventana de tiempo sin oyente. Pero un método como `_load()` que también se
  invoca desde un botón "Reintentar" (o tras una reconexión de Drive)
  reasigna el campo dentro de un `setState`, y `setState` **no** reconstruye
  de forma síncrona — solo agenda un rebuild para el próximo frame. Si el
  `Future` se resuelve con error ANTES de ese próximo `build()` (algo que un
  mock/fake en tests puede hacer en un microtask, y que en producción una
  respuesta de red muy rápida también podría lograr), Dart detecta que nadie
  lo está escuchando todavía y lo reporta como error no manejado a nivel de
  zona — un crash real, no solo un fallo de test. La solución NO es
  encadenar `.catchError(...)` y relanzar (ese patrón solo traslada el mismo
  problema al `Future` derivado que devuelve `.catchError`, que tampoco
  tiene oyente todavía): hay que llamar `future.ignore()` sobre el `Future`
  ORIGINAL inmediatamente al crearlo (silencia la detección de "unhandled"
  sin consumirlo — los `Future` sí admiten múltiples oyentes, a diferencia
  de los `Stream`) y guardar ESE MISMO `future` en el campo, para que el
  `FutureBuilder` posterior siga viendo el error real. Reproducido de forma
  determinística en `test/photo_viewer_screen_test.dart` con un
  `DriveThumbnailService` fake que resuelve en un microtask; cualquier
  futuro widget con un `Future` mutable reasignado fuera de `initState`
  (reintentos, refrescos manuales) necesita este mismo patrón.

## Seguridad

- Nunca loguear (`print`/log) el `serverAuthCode` ni los JWT de sesión.
  Errores capturados se traducen a mensajes fijos, sin incluir el error
  original.
- Nunca loguear el `driveAccessToken` (spec03-fotografias): vive solo en
  memoria durante un lote de subida (`PhotoUploadController`/
  `DriveTokenApi`/`DriveUploadService`), nunca en
  `flutter_secure_storage` ni en ningún otro almacenamiento, y se envía
  únicamente en el header `Authorization` de las llamadas a
  `googleapis.com` — nunca al backend de Memora.
- Nunca loguear el refresh token de sesión (spec06-sesion-y-reauth-drive):
  vive en memoria en `ApiClient` (`_refreshToken`, solo usado internamente
  por `_performRefresh`) y persistido en `flutter_secure_storage` vía
  `SessionStorage`/`AuthController`, igual que el access token — nunca se
  adjunta a un header de request (solo va en el body de `POST
  /auth/refresh`).
- Nunca loguear el `token` de un `ShareLink` ni de un `NfcQrTag`
  (spec07-compartir-nfc-qr.md): ninguno de los dos se persiste tampoco (ni
  `flutter_secure_storage` ni ningún otro almacenamiento) — solo viven en el
  estado en memoria de `AlbumsController` mientras la pantalla de detalle
  está abierta. Lo único que la app comparte (share sheet, `SelectableText`,
  o el QR renderizado) es la `url` completa que ya devuelve el backend
  (`/s/{token}` o `/n/{token}`), nunca el `token` ni ningún otro dato
  interno — cumple "no exponer PII al compartir" porque la `url` no
  contiene más que el token opaco que el backend ya considera público una
  vez compartido.

## Tests

- `flutter analyze` sin warnings antes de reportar terminado.
- `flutter test` para lógica (servicios, controllers) — no depende de
  dispositivo/emulador.
- El login real con Google Sign-In solo se puede probar en
  dispositivo/emulador con Google Play (Android) o simulador/dispositivo iOS
  firmado — no es cubrible por `flutter test`; documentarlo como paso manual
  de verificación en el reporte final.
- `flutter build ios --simulator --no-codesign` resuelve dependencias de
  Swift Package Manager (p. ej. `SDWebImage`/`SDWebImageWebPCoder`, que
  arrastra `flutter_image_compress`'s implementación iOS) clonando desde
  GitHub — en este entorno la primera corrida puede fallar con `RPC failed;
  curl 56 Recv failure` por flakiness de red; reintentar suele bastar (una
  vez cacheado en `build/ios/SourcePackages`, corridas siguientes no vuelven
  a clonar). No es un problema del código de esta app.
- **Fakear `AuthApi`/`GoogleAuthService`/`SessionStorage` para testear
  `AuthController` sin plugins/red** (spec06): ninguna de las tres es
  abstracta ni tiene una interfaz separada, pero ninguno de sus métodos es
  `final` — el patrón ya usado para `PhotoOptimizer`
  (`_FakePhotoOptimizer extends PhotoOptimizer`) se extiende igual acá:
  subclasear y sobreescribir el método relevante evita tocar
  `GoogleSignIn.instance` (plugin nativo) o hacer una request real, sin
  necesidad de introducir interfaces/abstracciones nuevas solo para
  testeabilidad. Para `AuthApi`, el constructor todavía pide un `ApiClient`
  — pasarle uno con un `MockClient` que lanza si se lo llama, así cualquier
  fallback accidental al método real falla ruidosamente en vez de pegarle a
  la red en silencio. Ver `test/auth_controller_test.dart`.
- **spec08-visor-foto-inapp.md**: `test/photo_viewer_screen_test.dart`
  cubre, con widget tests reales (`testWidgets` + `MaterialApp` +
  `PhotoViewerScreen`, patrón de `widget_test.dart`) y un
  `DriveThumbnailService` fake (subclase que sobreescribe `getThumbnail`,
  nunca toca la red): que la galería arranca en el `initialIndex` correcto y
  pide el `fileId` de esa foto (no el de las demás); que una foto
  `unavailable` muestra "Foto no disponible" y **nunca** llama a
  `getThumbnail`; que `DRIVE_REAUTHORIZATION_REQUIRED` ofrece "Reconectar
  Google Drive" en vez del "Reintentar" genérico; y que un error genérico
  ofrece "Reintentar" y, al tocarlo, vuelve a pedir la foto (ver el gotcha
  de `Future.ignore()` arriba — sin él este último test crashea, no solo
  falla). **No** son testeables sin dispositivo: el gesto real de
  pinch-zoom/pan/doble-toque y el render real de `PhotoViewGallery`
  (`photo_view`) en sí — mismo criterio que el resto de gestos/plugins
  nativos documentado más abajo.
- **spec07-compartir-nfc-qr.md**: `test/sharing_api_test.dart` cubre los 5
  métodos de `SharingApi` (contratos de ruta exactos, en particular que
  `getNfcQrTag`/`disableNfcQrTag` van a `/nfc-qr-tags/:id` SIN `albumId`, a
  diferencia de crear y del share-link, que sí cuelgan del álbum) y el
  mapeo de 404 a `AlbumNotAvailableException`. `test/albums_controller_sharing_test.dart`
  cubre la extensión de `AlbumsController`: `loadOrCreateShareLink`/
  `revokeShareLink` (incluyendo que revocar limpia `shareLink`),
  `createNfcQrTag` (que agrega a `nfcQrTags` en vez de reemplazar),
  `disableNfcQrTag` (que actualiza el estado del tag correcto in-place), y
  que `nfcQrTags`/`shareLink` se resetean al abrir un álbum *distinto* pero
  sobreviven a un refresco del mismo álbum. **No** son testeables sin
  dispositivo: el render real del QR (`qr_flutter`, sin lógica propia que
  testear más allá de pasarle la `url`) y el share sheet real de
  `share_plus` (ya sin cobertura de widget test desde spec05, mismo
  criterio aquí).
