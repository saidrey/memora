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
- **`nfc_manager` 4.x tiene una API completamente distinta a versiones
  anteriores — verificar SIEMPRE contra el código fuente resuelto, no
  contra lo que se recuerde de versiones viejas** (spec09-programar-nfc.md,
  resuelto vía `flutter pub add nfc_manager` → **`nfc_manager: ^4.2.1`**,
  que a su vez trae `ndef_record: ^1.4.2`). Desde `nfc_manager` 4.0.0 (ver su
  `CHANGELOG.md`), la clase `Ndef` (el helper unificado
  `Ndef.from(tag)`/lectura/escritura que existía en versiones pre-4.0) **fue
  eliminada del paquete core** — el changelog remite explícitamente a
  "usar el paquete `nfc_manager_ndef` o `NdefAndroid`/`NdefIos`" (las clases
  de bajo nivel específicas de cada plataforma, con métodos distintos:
  Android expone `writeNdefMessage`/`makeReadOnly`, iOS expone
  `writeNdef`/`writeLock`). Esta app agregó **`nfc_manager_ndef: ^1.1.0`**
  como dependencia adicional (no solo `nfc_manager`) específicamente para
  recuperar esa abstracción unificada (`Ndef.from(tag)` con
  `isWritable`/`cachedMessage`/`read()`/`write()`/`writeLock()` iguales en
  ambas plataformas) — sin ella, `nfc_programming_service.dart` habría
  tenido que ramificar por plataforma a mano. **Nota real de esa
  abstracción:** `Ndef.writeLock()` de `nfc_manager_ndef` reenvía a
  `NdefIos.writeLock()` en iOS también (Core NFC sí lo expone
  técnicamente) — pero la propia spec09 (P2 + su análisis de compatibilidad)
  es explícita en que ese lock de iOS no es fiable en todo el hardware de
  chips, así que `NfcProgrammingService.supportsReadOnlyLock` devuelve
  `false` en iOS y la UI nunca ofrece el botón ahí, aunque el plugin
  *podría* intentarlo. Tampoco existe (en `ndef_record` 1.4.x ni en
  `nfc_manager`/`nfc_manager_ndef`) un helper para construir/leer un
  registro NDEF de tipo URI (el viejo `NdefRecord.createUri(Uri)` de
  versiones pre-4.0 no tiene equivalente) — `buildUriRecord`/
  `decodeUriRecord`/`messageHasVerifiedUri` en
  `lib/albums/nfc_programming_service.dart` implementan a mano el NFC Forum
  URI Record Type Definition (byte de código de abreviación + resto en
  UTF-8), y son funciones puras 100% testeables sin hardware (ver
  `test/nfc_programming_service_test.dart`) — si una futura versión de
  cualquiera de estos paquetes agrega un helper equivalente, no hace falta
  seguir manteniendo el propio, pero verificar el código fuente resuelto
  antes de asumirlo.
- **Cancelar una sesión NFC en Android no genera ningún callback de "el
  usuario canceló"** (spec09-programar-nfc.md) — a diferencia de iOS, donde
  `onSessionErrorIos` sí reporta
  `NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled` cuando
  se descarta la hoja nativa. En Android, este botón "Cancelar" de la app es
  la ÚNICA señal de cancelación que existe, y llamar
  `NfcManager.instance.stopSession()` no resuelve ni rechaza el `Future` que
  `NfcProgrammingService.writeUrl` le devolvió a quien esperaba el tag — ese
  `Future` puede quedar pendiente para siempre. `NfcProgrammingController.start()`
  resuelve esto con `Future.any([writeUrl(...), cancelSignal.future.then((_) =>
  throw NfcCancelledException())])`: en vez de depender de que el plugin
  confirme el cancel, el controller compite la llamada real contra su propia
  señal de cancelación y usa la que resuelva primero. `Future.any` adjunta un
  listener a AMBOS futures internamente, así que el perdedor (casi siempre la
  sesión NFC real, abandonada a mitad de camino) nunca queda como un `Future`
  sin oyente — no hace falta `Future.ignore()` acá, a diferencia del gotcha
  de `late final`/campo reasignado documentado más arriba para
  `photo_viewer_screen.dart`. Un contador `_generation` (mismo patrón que
  otros controllers de esta app para descartar resultados obsoletos) evita
  que un intento abandonado (por cancelar o por un `retry()` posterior)
  pise el estado de uno más nuevo si de todos modos llega a resolver más
  tarde.

## Sistema de diseño visual — "Aurora" (Fase 1 del rediseño, sin spec de Kiro)

> **OBSOLETO tras el pivot a light-first (60-30-10)** — ver la sección
> "Rediseño visual 'Aurora' — pivot a light-first (60-30-10)" más abajo
> (al final de todas las secciones de diseño, justo antes de "Seguridad").
> Todo lo de acá para abajo describe el sistema **dark-first** original
> (Deep Ink como lienzo dominante). Sigue siendo útil como historia de las
> decisiones de layout/estructura/gotchas que **no cambiaron** con el
> pivot (siguen aplicando tal cual: `MemoraCurvedHero`, el patrón de
> `Hero`+`ClipPath`, el bottom sheet de compartir, `flutter_animate`, etc.)
> — pero cualquier mención concreta de un color/token/nombre (p. ej.
> `MemoraTheme.dark`, `surface1 #0F1428`, `MemoraCardElevation.light`,
> "la app es dark-first") quedó reemplazada por lo que dice la sección del
> pivot. No lo vuelvas a implementar así.

Rediseño visual completo de la app pedido directamente por el usuario (no
una spec de Kiro), dirección "Aurora / cielo nocturno" aprobada antes de
implementar. **Fase 1** (esta): `lib/design/` (sistema reutilizable) +
`HomeScreen` + `AlbumsListScreen`. El resto de pantallas
(`album_detail_screen`, `photo_viewer_screen`, `create_album_screen`,
`accept_invitation_screen`, `nfc_programming_screen`,
`drive_reconnect_prompt`) queda pendiente de Fase 2 — no las toques dando
por hecho que ya tienen el sistema nuevo.

- **`lib/design/memora_colors.dart`** — los 5 colores exactos de la paleta
  (`deepInk`/`glassBlue`/`auraViolet`/`mist`/`paper`) más los derivados de
  superficie (`surface1` `#0F1428`, `surface2` `#171D3A`, `border` = mist al
  8%) y `signatureGradient` (135°, Glass Blue -> Aura Violet). **Nunca**
  usar un color fuera de esta paleta en pantallas nuevas — si hace falta un
  matiz distinto, derivarlo de estos 5 con `Color.lerp`/`alphaBlend`, no
  inventar un hex nuevo.
- **`lib/design/memora_typography.dart`** — un solo `TextTheme` completo vía
  `google_fonts` (Manrope, pesos 400/600/700/800): `displayLarge`/`Medium`
  para hero, `headlineMedium`/`Small` para títulos, `titleMedium`/`Small`
  para subtítulos, `bodyLarge`/`Medium`/`Small` para body/caption,
  `labelLarge` para texto de botón (color `deepInk`, pensado para texto
  sobre el CTA primario con el gradiente claro), `labelMedium`/`Small` para
  metadata. Pantallas nuevas deben usar `Theme.of(context).textTheme.*`, no
  `TextStyle` sueltos.
- **`lib/design/memora_spacing.dart`** — `MemoraSpacing` (4/8/16/24/32/48) y
  `MemoraRadius` (`hero` 32 para cards grandes/protagonistas, `card` 20 para
  cards estándar, `pill` 999 para chips/botones). Usar estas constantes en
  vez de números mágicos de padding/radio en pantallas nuevas.
- **`lib/design/memora_theme.dart`** — el único `ThemeData` de la app
  (`MemoraTheme.dark`), aplicado en `MaterialApp(theme: ...)` en
  `main.dart`. Configura `ColorScheme.dark`, el `textTheme`,
  `appBarTheme`/`cardTheme`/`dialogTheme`/`inputDecorationTheme`/
  `chipTheme` sobre los tokens de arriba. La app es dark-first: no hay tema
  claro, `ThemeMode` no se toca.
- **`lib/design/widgets/`** — componentes reutilizables, pensados para que
  Fase 2 los reuse tal cual: `MemoraPrimaryButton` (pill con
  `signatureGradient`, reservado para el único CTA principal de la
  pantalla — implementado con `Material`+`Ink`+`InkWell` porque
  `ElevatedButton`/`ButtonStyle` de Flutter no soportan un `gradient` de
  fondo directamente), `MemoraSecondaryButton` (pill outlined, con
  `destructive: true` para acciones como "Eliminar álbum"),
  `MemoraBadge` (chip/pill; `MemoraBadgeVariant.gradient` reservado para un
  badge que deba destacar — p. ej. el rol que se desborda de una card de
  álbum —, `.neutral` para el resto; `dotColor` opcional dibuja un puntito
  de estado antes del label, usado por el chip de conectividad del
  backend), `MemoraCard` (superficie base con las capas `surface1`/
  `surface2`, borde `border`, opcionalmente con `gradient:` en vez de color
  plano — así es como se construyen las cards abstractas de álbum; ver
  `MemoraCardElevation.light` más abajo para la variante clara agregada en
  el ajuste post-feedback), `MemoraEmptyState` y `MemoraLoadingState`
  (reemplazan cualquier `CircularProgressIndicator`/`Text` suelto de "no
  hay nada"/"cargando"), y `MemoraFadeSlideIn` (entrada fade+slide de
  250ms/12px, respeta `MediaQuery.of(context).disableAnimations` — si está
  activo, el widget aparece instantáneo sin animar; ver más abajo).
  Importar todo desde el barrel `lib/design/design.dart` en vez de los
  archivos individuales.
- **`google_fonts: ^8.2.1`** (agregado vía `flutter pub add google_fonts`,
  no fijado a mano). **Gotcha real de esta dependencia**: por defecto
  descarga los archivos de fuente (Manrope) por HTTP en tiempo de
  ejecución la primera vez que se usa (`fonts.gstatic.com`, cacheado
  después) — no vienen embebidos en el bundle de la app. Verificado que
  `flutter test` (widget tests con `pumpAndSettle`, que sí renderizan
  texto con la fuente) pasa en este entorno porque hay red disponible; si
  algún día `flutter test` empieza a fallar o colgarse en un entorno sin
  red (CI aislado, por ejemplo), la causa más probable es esta — la
  solución documentada por el paquete es `GoogleFonts.config
  .allowRuntimeFetching = false` en un `setUp`/`flutter_test_config.dart`
  (cae a la fuente del sistema) o empaquetar el `.ttf` como asset local; no
  se hizo preventivamente porque hoy funciona y no agrega una dependencia
  nueva de assets sin evidencia de que haga falta. En producción no hace
  falta ningún permiso nuevo más allá del que ya necesitan las llamadas al
  backend/Drive (ver el hallazgo de `INTERNET` más abajo, que es anterior a
  esta dependencia y afecta a toda la app, no solo a las fuentes).
- **Cards abstractas de álbum (`AlbumsListScreen`) — sin foto de portada,
  por diseño**: `AlbumListItem` (`lib/albums/album_models.dart`) no trae
  ninguna imagen (ni la devuelve `GET /api/v1/albums`), así que cada card
  es una composición tipográfica: gradiente derivado de la paleta,
  `photoCount` como stat protagonista, y el rol desbordando el borde
  superior de la card (`Positioned` con `clipBehavior: Clip.none` fuera de
  los límites de la `MemoraCard`). El gradiente varía de forma
  determinística por álbum vía la función pura
  **`gradientForAlbumId(String albumId)`**
  (`lib/albums/screens/album_card_style.dart`, testeada sin dispositivo en
  `test/album_card_style_test.dart`, mismo patrón que
  `computeTargetDimensions`/`buildUriRecord`): hashea el `id` (hash
  djb2-like propio, no `Object.hashCode`, que no es estable entre
  ejecuciones) para elegir un ángulo entre 5 variantes y una mezcla
  azul/violeta entre 20%-80%, y mezcla (`Color.alphaBlend`, alpha 0.55) el
  color resultante sobre `surface1`/`surface2` — mantiene las cards
  moody/oscuras (coherente con "dark-first") en vez de pasteles brillantes.
  La versión image-led real (con foto de portada de `AlbumDetail.photos`)
  queda para la pantalla de **detalle** de álbum en Fase 2, no para esta
  lista.
- **Botón flotante con gradiente**: `FloatingActionButton` no soporta
  `gradient` directo tampoco — el patrón usado en `AlbumsListScreen` es
  `backgroundColor: Colors.transparent, elevation: 0, shape:
  CircleBorder()` con un `child` que es un `DecoratedBox` circular con
  `signatureGradient`. Mismo truco que `MemoraPrimaryButton` pero con la
  API de `FloatingActionButton` en vez de `Material`+`InkWell` a mano
  (aquí no hace falta el ripple custom, el FAB ya lo trae).

### Ajuste post-feedback de Fase 1 (sigue sin spec de Kiro): balance claro/oscuro + hero del Welcome

Después de que el usuario validara la Fase 1 corriendo la app en su celular,
dio dos piezas de feedback puntuales — resueltas en la misma Fase 1 (no es
Fase 2): "todo se ve muy oscuro, se usaron poco los tonos light" y un pedido
explícito de imagen hero de pantalla completa para el Welcome. Solo se
tocaron `lib/design/widgets/memora_card.dart`, `lib/screens/home_screen.dart`
y `pubspec.yaml` (asset) — ninguna otra pantalla.

- **`MemoraCardElevation.light`** (nuevo, en `memora_card.dart`) — variante
  de `MemoraCard` con fondo `MemoraColors.paper` (en vez de
  `surface1`/`surface2`) y borde derivado de Deep Ink a 8% de opacidad (el
  `border` token, Mist al 8%, es casi invisible sobre Paper — necesita su
  propio tono). Sigue siendo exactamente la misma paleta de 5 colores, solo
  se usa el extremo claro que hasta ahora casi no aparecía en pantalla.
  **Gotcha real de esta variante, no obvio**: el widget envuelve `child` en
  `DefaultTextStyle.merge`/`IconTheme.merge` con color Deep Ink como
  fallback, pero esto **NO** alcanza para un `Text(x, style:
  Theme.of(context).textTheme.algo)` — cada estilo de `MemoraTypography`
  ya trae su propio `color` explícito (calibrado para las superficies
  oscuras, que son la mayoría), y `TextStyle.merge`/`Text.style` hacen que
  ese color explícito le gane al default ambiente. El fallback solo cubre
  hijos sin `style`/sin `color` propio (p. ej. un `Icon(icon)` sin color).
  Cualquier `Text` que use un estilo de `textTheme.*` dentro de una
  `MemoraCardElevation.light` necesita `?.copyWith(color:
  MemoraColors.deepInk)` explícito en el call site — ver
  `_QuickAccessCard` en `home_screen.dart` para el patrón exacto. Si Fase 2
  usa esta variante en algún lado, no asumir que alcanza con envolver en la
  card sola.
- **Aplicada en `HomeScreen._QuickAccessCard`** (las dos cards de "Álbumes"/
  "Unirme a un álbum" del dashboard autenticado, spec04/05) — elegidas por
  ser lo primero que se ve al loguearse y tener alta visibilidad. El ícono
  de cada card va dentro de un chip circular de 40px con
  `signatureGradient` de fondo e ícono en Deep Ink (mismo motivo visual ya
  usado por `_InitialsAvatar` y el FAB de `AlbumsListScreen`: círculo con
  gradiente + contenido en Deep Ink encima), así la card clara sigue
  llevando los colores de acento de la paleta en vez de perderlos.
- **`AlbumsListScreen` — deliberadamente NO tocada** para este balance: la
  spec de ajuste pedía sumar presencia clara solo "si hay una forma natural
  de hacerlo sin forzarlo ni romper el patrón de gradiente de las cards de
  álbum" (ese patrón se queda igual, aprobado en la Fase 1). No se encontró
  un lugar natural (el fondo es oscuro por diseño dark-first, las cards de
  álbum son gradiente de la paleta, el FAB ya tiene el gradiente de firma) —
  si un futuro ajuste visual quiere sumar una superficie clara ahí, evaluarlo
  con cuidado para no romper la consistencia del grid de álbumes.
- **`assets/images/hero.png`** (nuevo, 853x1844px, provisto por el usuario
  tal cual — no editar/comprimir este archivo) — declarado en
  `pubspec.yaml` (`flutter: assets: - assets/images/hero.png`). Usado
  **únicamente** en `HomeScreen._WelcomeHeroBackdrop` (estado NO
  autenticado) como `Image.asset(fit: BoxFit.cover)` a pantalla completa,
  `Positioned.fill` **fuera** del `SafeArea` (a propósito: debe cubrir la
  statusbar; el `SafeArea` sigue envolviendo solo el contenido —
  wordmark/badge/headline/CTA). El estado autenticado
  (`_AuthenticatedDashboard`) sigue usando `_AuroraBackdrop` (el glow de
  blobs) tal cual — no se le puso la foto, no tiene sentido en un
  dashboard de datos; `_AuroraBackdrop` sigue viva y usada, no quedó
  huérfana.
- **Dos scrims sobre la foto** (`_WelcomeHeroBackdrop`), ambos derivados de
  `MemoraColors.deepInk` (nunca negro puro): uno arriba (`heightFactor:
  0.5`, opacidad 0.88 → 0 de arriba a abajo) para que el wordmark/badge/
  headline tengan contraste garantizado sobre el cielo de la foto, y uno
  abajo (`heightFactor: 0.38`, opacidad 0 → 0.92 de arriba a abajo) que se
  intensifica solo cerca del borde inferior para que el botón de login se
  lea bien sin tapar más composición de la foto de la necesaria (las fotos-
  recuerdo flotantes quedan visibles en la zona media, sin scrim).
- **Layout nuevo de `_WelcomeSection`**: ya no hay wordmark gigante
  centrado — ahora es "Memora" chico (`titleMedium`) arriba a la izquierda,
  en la misma fila que el chip de conectividad (que sigue arriba a la
  derecha, sin cambios de comportamiento). El headline/subtítulo/separador
  (`_HeroHeadline`) van en un `Column` con `Expanded` +
  `SingleChildScrollView` (nunca desborda en una pantalla baja: scrollea en
  vez de sangrar) alineado arriba a la izquierda, y el botón
  `MemoraPrimaryButton` (`expand: true`) queda anclado abajo, fuera del
  scroll — ya no centrado verticalmente (pedido explícito del usuario, y
  resuelve además el espacio muerto que yo mismo había notado en la Fase
  1). Mismo `auth.signIn`/`auth.errorMessage` que antes, sin tocar
  `AuthController`.
- **Copys del headline, transcriptos tal cual de la imagen de referencia
  del usuario (no en el repo)**: "Las historias\nque importan\nsiempre
  *contigo*" (la palabra "contigo" en `MemoraColors.auraViolet`, el resto
  en el color por defecto de `textTheme.displayMedium`, que ya es Paper) +
  subtítulo "Tus fotos, en su lugar, tus recuerdos, más cerca." + un
  separador corto (`Container` 40x1, Mist al 35% de opacidad — no un
  `Divider` de ancho completo).
- **Tamaño de imagen del bundle, no resuelto acá**: `hero.png` pesa
  ~1.8MB. No se comprimió ni se agregó ninguna herramienta de compresión de
  build (fuera de alcance explícito de esta tarea) — si el tamaño del APK/
  IPA final importa, es una decisión de build/release para el PO/Kiro, no
  algo para resolver dentro de un ajuste de capa visual.
- **`flutter test` decodifica la imagen real en los widget tests de
  `HomeScreen`** (no hay mock de `Image.asset`): `flutter_test` sirve los
  assets declarados en `pubspec.yaml` desde el propio filesystem del
  proyecto, así que el `Image.asset('assets/images/hero.png')` del estado
  no autenticado decodifica el PNG real (~1.8MB) durante
  `pumpAndSettle()`. Verificado que sigue pasando en este entorno (no
  necesita red, a diferencia del gotcha de `google_fonts` documentado más
  abajo) — si algún día un test de `HomeScreen` empieza a tardar
  notablemente más o a fallar por timeout, esta decodificación real es la
  primera sospechosa.

## Rediseño visual "Aurora" — Fase 2 (arranque): `album_detail_screen.dart`

Primera pantalla de Fase 2 (sigue sin spec de Kiro). Dos partes en la misma
tarea: un arreglo chico de Fase 1 (sombra de texto del headline del Welcome)
y el rediseño visual completo de `album_detail_screen.dart` — la pantalla
más compleja de la app y la primera con fotos reales, así que la primera
donde aplica de verdad el lenguaje "galería editorial" del brief original.
**Puramente visual**: ningún controller/`*Api`/modelo/contrato cambió; todos
los gotchas ya documentados arriba (key-por-id+epoch, owner-only,
`autofocus` prohibido en el diálogo de renombrar, distinción de errores de
Drive) se preservaron intactos.

- **Ajuste de Fase 1 (`lib/screens/home_screen.dart`, `_HeroHeadline`)**:
  feedback del usuario en dispositivo real — "el hero se ve bonito pero la
  letra se pierde" en zonas claras/texturadas de `hero.png`, donde el scrim
  solo no alcanza. Se agregó `TextStyle.shadows` (headline y subtítulo, este
  último con menor intensidad) derivado de `MemoraColors.deepInk` — una
  sombra suave (dos capas: una ajustada+oscura y una más amplia+difusa), NO
  un stroke/borde duro tipo cómic (se descartó explícitamente por verse
  genérico). El helper quedó además generalizado en
  **`MemoraTypography.legibilityShadows({double intensity = 1})`**
  (`lib/design/memora_typography.dart`) para que cualquier texto futuro
  compuesto sobre una foto (el hero de álbum de esta misma tarea, y
  cualquier pantalla de Fase 2 después) lo reuse en vez de reinventarlo —
  `home_screen.dart` mantiene su propia lista de shadows inline (no se
  refactorizó para llamar al helper nuevo, ya que estaba fuera del alcance
  tocar `HomeScreen` más allá de este único ajuste puntual); si se toca ese
  archivo en el futuro, es un candidato obvio para deduplicar.
- **`lib/design/widgets/memora_curved_hero.dart`** (nuevo, exportado desde
  `design.dart`) — `MemoraHeroCurve` (`CustomClipper<Path>`, un `ClipPath`
  con una curva asimétrica tipo ola, no un arco centrado/simétrico ni un
  corte recto) y `MemoraCurvedHero` (widget que aplica el clip a un
  `background` + `overlay` opcional, ambos dentro de un `Stack` de tamaño
  fijo). Es la transición "no 100% rectangular" pedida entre la foto hero y
  el contenido de abajo — genérico y reutilizable, no específico de álbum,
  para que cualquier futura pantalla con un hero de imagen (Fase 2) lo
  reuse. **Gotcha real**: el `overlay` comparte el mismo clip que el fondo
  (no hay forma de eximirlo), así que cualquier control interactivo dentro
  del `overlay` debe quedar en el ~85% superior "plano" de `height` — algo
  puesto muy cerca del borde inferior puede quedar recortado por la ola.
- **`MemoraRadius.thumbnail`** (nuevo, `lib/design/memora_spacing.dart`,
  14.0) — radio dedicado para tiles de grilla de fotos (ni `card` de 20 ni
  `hero` de 32 encajaban bien en una celda de grilla chica); pensado para
  reutilizarse en cualquier futura grilla de fotos (p. ej. si Fase 2 le da
  al visor de foto una tira de miniaturas).
- **El hero del álbum (`_AlbumHero`/`_HeroPhotoImage` en
  `album_detail_screen.dart`)**: usa la PRIMERA foto de `detail.photos`
  (`detail.photos.first`, sin filtrar por `availability` — mismo criterio
  que ya usaba la grilla: `_PhotoTile` siempre intenta `getThumbnail` sin
  importar `availability`, el ícono `cloud_off` es un overlay aparte tras el
  intento, no una skip-condition) como fondo a pantalla completa dentro de
  `MemoraCurvedHero`; si el álbum no tiene fotos, cae al gradiente
  determinístico **`gradientForAlbumId(detail.id)`** (`album_card_style.dart`,
  ya usado por `AlbumsListScreen`) — coherencia visual entre lista y detalle
  para el caso vacío, sin inventar un segundo generador de gradientes.
  `_HeroPhotoImage` es un widget aparte de `_PhotoTile` (no lo reutiliza)
  porque **replica a propósito su mismo patrón `late final`
  `Future`+`catchError`+re-throw+epoch-en-la-key** (ver el gotcha ya
  documentado arriba) pero con tamaño/ícono/ausencia-de-botón-quitar
  distintos — el padre (`_AlbumHero`, construido desde `_buildBody`) le pasa
  `key: ValueKey('hero-${heroPhoto.id}#$epoch')` usando el MISMO `_epoch` del
  grid, así un reconnect de Drive fuerza un `State` nuevo también para la
  miniatura del hero, no solo para las de la grilla. Tocar el hero (tap)
  abre `PhotoViewerScreen` en el índice 0, solo si el álbum tiene fotos.
- **AppBar transparente en vez de "quitarlo"**: `Scaffold.extendBodyBehindAppBar:
  true` + `AppBar(backgroundColor: Colors.transparent, elevation: 0)` sin
  `title` (el nombre del álbum se muestra ahora dentro del overlay del
  hero) — mantiene el botón de volver y los tres íconos owner-only
  (renombrar/visibilidad/eliminar) con su comportamiento/accesibilidad
  nativa de `AppBar`, en vez de reconstruirlos a mano sobre el hero. Dos
  scrims sobre la foto (derivados de Deep Ink, mismo patrón que
  `HomeScreen._WelcomeHeroBackdrop`): uno arriba para que esos íconos se
  lean, uno abajo para el nombre/badge de rol.
- **El elemento "desbordado" de esta pantalla es el pill de conteo de fotos
  (`_PhotoCountBadge`), NO el badge de rol repetido de `AlbumsListScreen`**
  (pedido explícito de la spec de esta tarea: "no lo repitas ahí de la
  misma forma"). Un `Stack(clipBehavior: Clip.none)` posiciona el pill a
  `bottom: -26` sobre la costura curva entre el hero y el contenido — mitad
  sobre la foto, mitad sobre el fondo oscuro de abajo. Usa
  **`MemoraCardElevation.light`** (fondo Paper) precisamente donde la propia
  documentación de esa variante dice que debe ir: "the one or two cards on
  a screen that should read as a real light/dark contrast moment" — el
  badge de rol se movió a estar simplemente inline en el overlay del hero
  (`MemoraBadge(variant: gradient)`, sin desbordar nada), evitando repetir
  el mismo truco visual dos veces en pantallas distintas.
- **El FAB "Agregar fotos" pasó a ser literalmente un `MemoraPrimaryButton`**
  en vez de `FloatingActionButton.extended` — mismo patrón ya usado por
  `AlbumsListScreen`'s FAB (un widget cualquiera puede ir en el slot
  `Scaffold.floatingActionButton`, no hace falta que sea una subclase de
  `FloatingActionButton`). Es el ÚNICO `MemoraPrimaryButton` de la pantalla
  (su propio doc comment dice "never used more than once per screen") — por
  eso la sección de compartir usa `MemoraSecondaryButton` para TODAS sus
  acciones, incluida "Obtener enlace para compartir" (antes tentador
  candidato a primary button, pero hubiera violado esa regla).
- **Grid de fotos: 2 columnas en vez de 3** (antes `crossAxisCount: 3`) —
  "fotos grandes protagonistas" del brief; sigue siendo
  `SliverGrid.builder` dentro del mismo `SliverPadding`, mismo
  `key: ValueKey('${photo.id}#$_epoch')` intacto. Cada `_PhotoTile` ahora
  envuelve su `Stack` en `ClipRRect(borderRadius:
  BorderRadius.circular(MemoraRadius.thumbnail))` y usa colores del sistema
  (`MemoraColors.surface1` en vez de `Colors.black12`, `MemoraLoadingState(compact:
  true)` en vez de un `CircularProgressIndicator` a mano, `MemoraColors.textTertiary`/
  `semanticError` para el ícono según el tipo de error — la distinción
  `link_off` (reauth) vs `broken_image_outlined` (genérico) se conserva
  exactamente igual, solo cambia el color).
- **Sección "Compartir" y "Colaboradores" envueltas en `MemoraCard`** (nivel
  2, sin `Divider` — el borde de la card ya separa visualmente) en vez de
  `Divider()` + `Text` sueltos; toda acción que era `TextButton`/
  `OutlinedButton` pasó a `MemoraSecondaryButton` (con `destructive: true`
  para "Revocar"/"Bloquear"/"Abandonar álbum"); el estado de una etiqueta
  NFC/QR (`Activa`/`Bloqueada`) pasó de `Text` coloreado a `MemoraBadge` con
  `dotColor`. El QR en sí (`QrImageView`) se mantiene sobre un fondo Paper
  explícito (necesario para que un QR sea escaneable — no es
  `MemoraCardElevation.light`, es un `DecoratedBox` manual, porque no hay
  texto/ícono ahí que necesite el ajuste de color de esa variante).
- **Filas de colaboradores/invitaciones (`_PersonRow`, nuevo widget privado
  de este archivo, no en `lib/design/` porque no se identificó otro caso de
  uso todavía)**: reemplazan `ListTile` por un chip circular
  (`MemoraColors.surface2` + ícono) + título/subtítulo con la tipografía del
  sistema + un borde inferior sutil (`MemoraColors.border`) en vez del
  divisor default de `ListTile`. Sigue mostrando exactamente la misma
  información que antes (incluida la limitación real de PII: solo
  `collaborator.userId`, nunca un nombre inventado — ver la sección de
  colaboradores más arriba, sin cambios).
- **No se tocó**: `photo_viewer_screen.dart`, `create_album_screen.dart`,
  `accept_invitation_screen.dart`, `nfc_programming_screen.dart`,
  `drive_reconnect_prompt.dart` (siguiente tanda de Fase 2, después de que
  el usuario revise esta pantalla en su celular), ni
  `AlbumsController`/`DriveThumbnailService`/ningún modelo o endpoint.

### Ajuste chico post-feedback (sigue sin spec de Kiro): jerarquía visual de "Cerrar sesión" en `HomeScreen`

Feedback del usuario en dispositivo real sobre `_AuthenticatedDashboard`:
"Cerrar sesión" era un `MemoraSecondaryButton` de ancho completo — mismo
peso visual que las acciones principales de la pantalla (las dos
`_QuickAccessCard`) — parado en medio del flujo de contenido. Se movió a un
`IconButton(Icons.logout, tooltip: 'Cerrar sesión')` dentro del Row superior
que ya existía para el chip de conectividad del backend (mismo `Row` que en
el estado Welcome muestra el wordmark "Memora" chico; acá se activa solo
cuando `auth.status == AuthStatus.authenticated`, no durante
`authenticating`/`unknown`). Mismo `auth.signOut`, sin tocar
`AuthController`. Único archivo tocado: `lib/screens/home_screen.dart` (+
`test/widget_test.dart`, que ahora busca `find.byTooltip('Cerrar sesión')`
en vez de `find.text(...)`, porque ya no es un botón de texto).

**Patrón a reutilizar en la "pasada final" de jerarquía visual (ya
anticipada como pendiente, ver README)**: cuando una pantalla sin `AppBar`
real necesita un lugar para una acción secundaria de cuenta/nivel-pantalla
(no la acción primaria del flujo), el Row superior con
wordmark/badge-de-conectividad de `HomeScreen` es el lugar natural — no
hace falta introducir un `AppBar` transparente ahí solo para esto (eso sí
se justificó en `album_detail_screen.dart` porque esa pantalla ya necesitaba
el botón de volver + tres acciones owner-only). El criterio general para
identificar estos casos: si un botón compite en ancho/estilo con el CTA
primario de la pantalla pero es conceptualmente una acción de "cuenta" o
"nivel superior" (no algo que el usuario vino a hacer en esa pantalla
específica), sacarlo del flujo principal a un ícono con `tooltip` — mismo
patrón `IconButton(icon, tooltip)` que ya usan las acciones owner-only del
`AppBar` de `album_detail_screen.dart`, no inventar un tercer patrón visual
para "acción secundaria".

### Hallazgo real, NO corregido por esta tarea: falta `INTERNET` en el manifest de release de Android

`android/app/src/main/AndroidManifest.xml` (el manifest base, el que se
mergea en un build de **release**) **no declara**
`<uses-permission android:name="android.permission.INTERNET" />` — solo
existe en `android/app/src/debug/AndroidManifest.xml` y
`.../profile/AndroidManifest.xml` (el comentario del propio archivo dice
que es "requerido para desarrollo", plantilla default de `flutter create`).
Esto significa que un **APK/AAB de release** de esta app, tal como está hoy,
no tendría permiso de red en absoluto — rompería TODAS las llamadas de red
(`ApiClient` contra `memora-backend`, Google Sign-In, subida/descarga de
Drive, y ahora también la descarga de fuentes de `google_fonts` si no se
desactiva el runtime fetching) en producción, no solo el sistema de diseño.
Es un hallazgo real (no introducido por esta tarea — ya afectaba a todas
las specs anteriores) descubierto al investigar si `google_fonts` iba a
necesitar algún permiso nuevo. **No se corrigió** porque toca la
configuración de build/release de la app (fuera del alcance "solo capa
visual" de esta tarea) — queda marcado explícitamente para que el PO/Kiro
lo confirme y decida dónde agregarlo (lo más simple sería sumar el mismo
`<uses-permission>` a `android/app/src/main/AndroidManifest.xml`, pero es
una decisión de release/build que no corresponde tomar unilateralmente
dentro de una tarea de rediseño visual).

## Rediseño visual "Aurora" — Fase 2 (completa): las 5 pantallas restantes

Última tanda de Fase 2 (sigue sin spec de Kiro): `photo_viewer_screen.dart`,
`create_album_screen.dart`, `accept_invitation_screen.dart`,
`nfc_programming_screen.dart`, `drive_reconnect_prompt.dart`. Con esto, las
7 pantallas del alcance original de Fase 2 (las 2 de arriba +
`album_detail_screen.dart`) tienen el sistema "Aurora" aplicado — **Fase 2
queda completa**. Puramente visual, mismo criterio que el resto del
rediseño: ningún controller (`NfcProgrammingController`, `AlbumsController`,
`AuthController`)/`*Api`/modelo cambió; todos los gotchas ya documentados
(el retraso de ~300ms de un botón dentro de `photo_view`, `autofocus`
prohibido en `showDialog`, la máquina de estados completa de NFC) se
preservaron intactos — ninguno de los 5 archivos tiene test dedicado salvo
`photo_viewer_screen.dart` (`test/photo_viewer_screen_test.dart`, sigue
pasando sin cambios de aserciones: sus `find.text('Reintentar')`/
`find.text('Reconectar Google Drive')`/`find.text('Foto no disponible')`
siguen encontrando esos textos porque siguen siendo literalmente esos
labels, ahora dentro de `MemoraSecondaryButton`/el nuevo `_StateOverlay` en
vez de un `OutlinedButton`/`Text` sueltos).

- **`photo_viewer_screen.dart`** — el reto real de esta pantalla era el
  chrome, no el contenido: es un visor full-bleed que envuelve
  `PhotoViewGallery.builder`/`.customChild` (paquete `photo_view`), y la
  tarea explícitamente prohibía tocar esa estructura. La solución fue
  exactamente el alcance pedido: reemplazar cada `Colors.black`/
  `Colors.white*` suelto por `MemoraColors` (`Scaffold`/`AppBar` a
  `MemoraColors.deepInk`, más un `backgroundDecoration` nuevo en
  `PhotoViewGallery.builder` — el paquete sí expone ese parámetro,
  verificado contra el código fuente resuelto en
  `~/.pub-cache/hosted/pub.dev/photo_view-0.15.0/lib/photo_view_gallery.dart`
  — para que el fondo detrás de cada página también sea Deep Ink en vez del
  negro por defecto del paquete) y unificar el placeholder "Foto no
  disponible" + los dos estados de error (genérico/reauth) en un solo
  widget privado nuevo, **`_StateOverlay`** (icon chip circular +
  mensaje + `MemoraSecondaryButton` opcional). Deliberadamente
  `MemoraSecondaryButton`, no `MemoraPrimaryButton`: "Reintentar"/
  "Reconectar Google Drive" son acciones de recuperación de UNA página de
  la galería, no el CTA principal de la pantalla — mismo criterio que ya
  usa `album_detail_screen.dart` para su propio banner de reauth de Drive.
  **Ningún momento de `MemoraCardElevation.light` en esta pantalla** — a
  diferencia de las otras 4, un visor full-bleed inmersivo es precisamente
  el caso donde una "isla clara" competiría con la foto en vez de sumar
  contraste con criterio; documentado explícitamente en el doc comment del
  archivo para que no se intente "corregir" en una futura pasada. El gotcha
  de los ~300ms de retraso de tap dentro de `customChild` sigue intacto y
  sigue cubierto por el mismo test con `tester.pump(kDoubleTapTimeout +
  margen)`.
- **`create_album_screen.dart`** — el momento `MemoraCardElevation.light`
  de esta pantalla (siguiendo el ejemplo textual del brief): la card
  entera del formulario. Gotcha nuevo descubierto acá, mismo espíritu que
  el ya documentado para `Text`/`textTheme.*` dentro de esa variante: el
  `InputDecorationTheme` global de la app (`MemoraTheme.dark`) rellena con
  `MemoraColors.surface1` y colorea label/hint/counter para texto-sobre-
  oscuro — dentro de una `MemoraCardElevation.light` (fondo Paper) ese
  decorado por defecto es ilegible. La solución para este campo puntual:
  **no** intentar re-derivar una caja rellena que combine con Paper, sino
  un campo sin relleno con borde inferior (`filled: false`,
  `UnderlineInputBorder`) con un puñado de colores explícitos basados en
  Deep Ink (`labelStyle`/`counterStyle`/`enabledBorder` a alpha reducido,
  `focusedBorder` en Glass Blue) — mismo patrón de "cada estilo necesita su
  color explícito dentro de una card clara" ya documentado para `Text`,
  extendido acá a `InputDecoration`. Si una futura pantalla necesita OTRO
  `TextField` dentro de una `MemoraCardElevation.light`, este es el
  precedente a seguir (no intentar reusar el `InputDecorationTheme` global
  tal cual).
- **`accept_invitation_screen.dart`** — sin momento `MemoraCardElevation
  .light` (decisión consciente, documentada en el doc comment del
  archivo): a diferencia de crear álbum, unirse a un álbum es una acción
  utilitaria de un solo paso sin un "premio" natural que justifique una
  isla clara — el brief pedía "con criterio", no en cada pantalla. Card
  `level2` + `InputDecorationTheme` global tal cual (sin el problema de
  `create_album_screen.dart`, porque acá el campo vive sobre una superficie
  oscura, para la que ese theme ya está calibrado). `autofocus: true` en el
  `TextField` se preservó tal cual estaba — sigue siendo seguro acá porque
  es un `Navigator.push` real, no un `showDialog` (ver el gotcha de
  `autofocus` más arriba).
- **`nfc_programming_screen.dart`** — el momento `MemoraCardElevation
  .light` de esta pantalla (el otro ejemplo textual del brief): el estado
  `success`, como "premio" por terminar la escritura física del tag —
  envuelve el ícono de check + mensaje (más el texto informativo de iOS
  cuando `supportsReadOnlyLock` es `false`) dentro de una `MemoraCard
  (elevation: light)`, con los mismos colores explícitos Deep-Ink-sobre-
  Paper que el resto de esa variante exige.
  **Gotcha nuevo descubierto acá (real, no solo de test) — extiende el ya
  documentado de `Text`/`textTheme.*` dentro de `MemoraCardElevation
  .light`**: `_buildLockSection` (el botón "Bloquear como solo lectura",
  sin cambios de comportamiento/gating por plataforma) usa
  `MemoraSecondaryButton`, cuyo foreground/borde por defecto es
  `MemoraColors.paper` — literalmente el mismo tono que el fondo Paper de
  esa card, así que anidarlo DENTRO de ella lo vuelve invisible (texto
  claro sobre fondo claro). A diferencia del gotcha de `Text` (que se
  arregla con `?.copyWith(color: deepInk)` en el call site),
  `MemoraSecondaryButton` no expone ningún parámetro de color para
  recalibrarlo widget por widget — la solución es sacar
  `_buildLockSection()` FUERA de la card (debajo, sobre el canvas oscuro
  normal de la pantalla, donde `MemoraSecondaryButton` ya es legible tal
  cual, como en cualquier otro lugar de la app), no intentar re-colorearlo
  por dentro. **Regla general para el resto de la app**: ningún
  `MemoraSecondaryButton` debería vivir anidado dentro de una
  `MemoraCardElevation.light` — a diferencia de `MemoraPrimaryButton`, que
  sí es seguro en cualquier fondo porque su gradiente es una decoración
  propia e independiente de la superficie que lo rodea (por eso
  `create_album_screen.dart` deja su único `MemoraPrimaryButton` fuera de
  la card de todos modos: no por este problema de contraste, sino por la
  jerarquía "un solo CTA principal por pantalla", pero el resultado
  práctico es el mismo patrón: acciones en pill viven sobre el canvas
  oscuro, la card clara es solo contenido). `MemoraBadge` (variante
  neutral, fondo `surface2` + texto `paper`) NO tiene este problema —un
  chip oscuro sí se lee con claridad sobre Paper— así que el badge de
  "Bloqueada a solo lectura" de este mismo `_buildLockSection` no necesitó
  moverse por esta razón, solo lo acompañó al salir de la card junto con el
  botón para no partir la sección en dos lugares distintos de la pantalla.
  **Ningún estado de `NfcProgrammingStatus` se perdió ni se
  fusionó**: `isRunning` (que cubre `checkingAvailability`/
  `waitingForTag`/`confirmingOverwrite`/`writing`/`verifying`) sigue siendo
  una sola rama visual (ahora `_StateIconChip` + `MemoraLoadingState(label:
  statusMessage)` en vez de `Icon`+`CircularProgressIndicator`+`Text`
  sueltos, mostrando el mismo `statusMessage` que ya distinguía cada
  sub-estado), `success` es la rama nueva con card clara, y todo lo demás
  (errores tipados + `cancelled`) sigue siendo la rama genérica final,
  ahora con dos botones de peso distinto: `MemoraPrimaryButton` para
  "Reintentar" (la recuperación es la acción más importante de un estado de
  error) y `MemoraSecondaryButton(destructive: true)` para "Deshabilitar
  etiqueta" (desistir, la opción menos deseable) — antes eran
  `ElevatedButton`/`OutlinedButton` con el mismo peso visual implícito.
  Nuevo widget privado **`_StateIconChip`** (círculo con tinte de color +
  ícono, 88px) reutiliza el mismo lenguaje de chip circular que
  `_QuickAccessCard`/`_InitialsAvatar`/el FAB, parametrizado por color
  (`glassBlue` para esperar/escribir, `semanticError` para error/cancelado)
  en vez de introducir un estilo de ícono nuevo. Los diálogos de
  confirmación (sobrescribir/bloquear/deshabilitar) se dejaron con
  `AlertDialog`+`TextButton` (ya heredan el `dialogTheme` de
  `MemoraTheme.dark` automáticamente); se agregó únicamente
  `foregroundColor: MemoraColors.semanticError` a la acción destructiva de
  cada uno, mismo criterio de jerarquía que el resto de la tarea.
- **`drive_reconnect_prompt.dart`** — el archivo que menos cambió en
  proporción, porque su `AlertDialog`/`SnackBar` ya heredaban la mayor
  parte de su estilo de `MemoraTheme.dark` (`dialogTheme`: fondo
  `surface2`, radio `card`, texto de título/contenido ya temado;
  `snackBarTheme`: mismo fondo/radio) simplemente por usar los widgets
  estándar de Flutter — a diferencia de las otras 4 pantallas, acá casi no
  hubo colores sueltos que reemplazar. Lo que sí se agregó: un ícono
  (`Icons.cloud_sync_outlined`, Glass Blue) en el título del diálogo de
  confirmación: color de las dos acciones diferenciado (`Cancelar` en
  `MemoraColors.textSecondary`, `Reconectar` en `MemoraColors.glassBlue`,
  nunca ambas con el mismo peso), y un ícono de resultado
  (`check_circle_outline`/`error_outline`) en el `SnackBar` final. El
  diálogo de "reconectando..." (no descartable) pasó su `SizedBox`+
  `CircularProgressIndicator` a `MemoraLoadingState(compact: true)`. Sigue
  sin `TextField` (el gotcha de `autofocus`/`showDialog` no aplica) y sigue
  sin tocar `AuthController.reconnectDrive`/D10.
- **Confirmado en esta tanda**: ningún `MemoraPrimaryButton` aparece más de
  una vez SIMULTÁNEAMENTE en el árbol de ningún build de estas 5 pantallas
  (aunque `nfc_programming_screen.dart` usa uno distinto en el estado
  `success` y otro en el estado de error — nunca ambos a la vez, son
  branches mutuamente excluyentes de la misma máquina de estados) —
  respeta el "nunca usado más de una vez por pantalla" del propio doc
  comment de `MemoraPrimaryButton`, interpretado como "por render", el
  mismo criterio implícito que ya usaban `HomeScreen`/`album_detail_screen.dart`
  antes de esta tarea.

## Post-feedback de Fase 2 (sin spec de Kiro): bug de borrado, bottom sheet, `flutter_animate`

> **El bottom sheet de esta sección quedó OBSOLETO** — ver la sección
> "Mockup redesign: tabs inline + menú overflow del owner (sin spec de
> Kiro)" al final del archivo. `_openSharingSheet`/`showModalBottomSheet`
> fueron eliminados por completo: Compartir/Colaboradores ahora son tabs
> inline debajo del hero, no un sheet modal. El resto de esta sección
> (bug de borrado, `flutter_animate`, el `Hero` compartido con
> `AlbumsListScreen`) sigue vigente tal cual — solo el mecanismo del sheet
> cambió.

Feedback concreto del usuario tras correr Fase 2 en su celular real, en tres
partes: un bug real (borrar una foto no pedía confirmación), una
reestructuración de información (`album_detail_screen.dart` tenía "mucha
información en una sola pantalla, mucho ruido visual") y un pedido explícito
de más dinamismo con animaciones reales (permiso explícito para agregar una
dependencia de animación). Alcance acotado a
`lib/albums/screens/album_detail_screen.dart`,
`lib/albums/screens/albums_list_screen.dart` y tres widgets de
`lib/design/widgets/` (`memora_card.dart`, `memora_primary_button.dart`,
`memora_secondary_button.dart`, `memora_curved_hero.dart`) — ningún
controller/`*Api`/modelo cambió, mismo criterio que toda la tarea de
rediseño visual hasta acá.

- **Bug real corregido: quitar una foto del álbum ahora pide confirmación**
  (`AlbumDetailScreen._confirmRemovePhoto`) — antes el "×" de cada
  `_PhotoTile` llamaba `_removePhoto`/`removePhotoFromCurrentAlbum`
  directo, así que un toque accidental borraba la foto del álbum sin
  ningún paso intermedio. Mismo patrón `AlertDialog` que el resto de
  confirmaciones destructivas de esta pantalla y de
  `nfc_programming_screen.dart` ("Sobrescribir"/"Bloquear
  definitivamente"/"Deshabilitar"): `TextButton.styleFrom(foregroundColor:
  MemoraColors.semanticError)` solo en la acción destructiva, nunca en
  "Cancelar". `AlbumsController.removePhotoFromCurrentAlbum` en sí no
  cambió — sigue siendo exactamente el mismo método, solo se agregó el paso
  de confirmación antes de llamarlo. Cubierto por
  `test/album_detail_screen_test.dart` (nuevo): tapear el "×" muestra el
  diálogo y NO llama al controller; "Cancelar" tampoco lo llama; solo
  "Eliminar" lo hace.
- **Compartir/Colaboradores se movieron a un `showModalBottomSheet`**
  (`AlbumDetailScreen._openSharingSheet`) — antes vivían inline, como dos
  `SliverToBoxAdapter` siempre expandidos debajo de la grilla de fotos
  dentro del mismo `CustomScrollView` (ver la sección de spec05/spec07 más
  arriba), compitiendo visualmente con las fotos. Ahora el
  `CustomScrollView` principal solo tiene: el hero, el título "Fotos", los
  banners de error/reauth (información crítica del estado de las fotos, no
  se movió) y la grilla. El trigger es un único ícono nuevo en el `AppBar`
  (`Icons.people_alt_outlined`, tooltip "Colaboradores y compartir"),
  **visible para ambos roles** (a diferencia de los tres íconos
  owner-only que ya existían ahí) porque la sección de colaborador
  ("Abandonar álbum") también vive ahora en el sheet. Dentro del sheet:
  exactamente el mismo `_buildSharingSection`/
  `_buildOwnerCollaboratorsSection`/`_buildCollaboratorSection` de antes
  (mismos controllers, misma gating owner-only, mismo
  `mutationErrorMessage`) — solo cambió dónde se renderiza.
  **Gotcha real de este bottom sheet**: su `builder` es una ruta/overlay
  separada del árbol de `AlbumDetailScreen` — el `setState`-driven
  `_onChanged` de la pantalla (via `widget.controller.addListener`) NO
  reconstruye el contenido del sheet. Sin más, una mutación disparada
  DESDE el sheet (revocar, quitar colaborador, deshabilitar una etiqueta)
  aplicaría bien en el controller pero el sheet seguiría mostrando
  contenido viejo hasta cerrarlo y reabrirlo. Solución: el `builder` del
  sheet envuelve su contenido en un `ListenableBuilder(listenable:
  widget.controller, ...)` propio, que lee `widget.controller.albumDetail`/
  `mutationErrorMessage` frescos en cada rebuild — independiente del
  `setState` de la pantalla. Cualquier futuro `showModalBottomSheet`/diálogo
  cuyo contenido dependa de un `ChangeNotifier` que ya escucha la pantalla
  padre necesita este mismo patrón (un `ListenableBuilder`/`AnimatedBuilder`
  propio dentro del `builder`), no asumir que el `setState` del padre
  alcanza.
- **`flutter_animate: ^4.5.2`** (agregado vía `flutter pub add
  flutter_animate`, sin fijar versión a mano — resolvió `4.5.2`, trae
  `flutter_shaders` como dependencia transitiva) — para animaciones
  declarativas más ricas que `MemoraFadeSlideIn` (que se dejó intacta,
  sigue en uso donde ya cumplía su rol simple, p. ej. el grid de
  `AlbumsListScreen`). Usada en dos lugares nuevos:
  - **Grid de fotos de `album_detail_screen.dart`**: cada `_PhotoTile`
    entra con `.animate(delay: ...).fadeIn().scale(begin: Offset(0.88,
    0.88))` en vez de aparecer instantáneo — un stagger real (45ms por
    índice, con el delay clamped a los primeros 12 tiles para que un álbum
    grande no obligue a esperar un stagger cada vez más largo para ver las
    últimas filas). El `key: ValueKey('${photo.id}#$_epoch')` (gotcha de
    spec04/spec06, ver arriba) se mantiene exactamente en `_PhotoTile`, NO
    se movió al wrapper de `.animate()` — la reconciliación de Flutter
    compara claves nodo por nodo en el árbol, no solo en el widget que
    `itemBuilder` devuelve en la raíz, así que envolver `_PhotoTile` (con
    su key) dentro de un `Animate` (sin key) no reintroduce el bug de
    key-por-posición ya documentado; verificado indirectamente porque
    `flutter analyze`/`flutter test` (incluida la key en sí, ejercitada por
    tests previos) siguen en verde.
  - **El bottom sheet nuevo**: sus secciones (grabber, título, banner de
    error si hay, Compartir, Colaboradores) entran con un stagger propio
    (`.fadeIn().slideY(begin: 0.06)`, 45ms de delay entre cada una) por
    encima del slide-up default de `showModalBottomSheet` (que se dejó
    como base, tal como permitía la spec de esta tarea) — un poco de
    personalidad en el CONTENIDO del sheet, sin tocar la mecánica de la
    ruta modal en sí (evita el riesgo de romper el swipe-to-dismiss/el
    `flightShuttleBuilder` implícito de `ModalBottomSheetRoute` con un
    `PageRouteBuilder` a medida).
  - Todo lo nuevo con `flutter_animate` respeta
    `MediaQuery.of(context).disableAnimations` explícitamente (se chequea
    antes de aplicar `.animate(...)` y, si está activo, se devuelve el
    widget sin envolver) — el paquete no lo respeta por sí solo.
- **Feedback de toque (escala al presionar) en `MemoraPrimaryButton`,
  `MemoraSecondaryButton` y `MemoraCard` (cuando tiene `onTap`)** —
  deliberadamente con `AnimatedScale` + `InkWell.onTapDown`/`onTapUp`/
  `onTapCancel` (Flutter core), NO con `flutter_animate`: los tres widgets
  ya usaban `InkWell`, que expone esos tres callbacks directo, así que no
  hacía falta un segundo `GestureDetector` compitiendo por el mismo puntero
  ni el paquete nuevo para algo tan simple (escala 0.96–0.97 en 120ms).
  Los tres pasaron de `StatelessWidget` a `StatefulWidget` únicamente para
  guardar el `bool _pressed` — su API pública (constructores, parámetros)
  no cambió, así que ningún call site en el resto de la app necesitó
  tocarse. También respeta `disableAnimations` (la escala nunca se aplica
  si está activo, aunque el `InkWell` sigue dando su ripple normal).
  **Alcance deliberadamente amplio**: al vivir en `lib/design/widgets/`,
  este cambio beneficia a TODAS las pantallas que ya usan estos tres
  componentes (o sea, prácticamente toda la app post-Fase-2), no solo
  `album_detail_screen.dart` — la spec de esta tarea permitía tocar estos
  archivos compartidos aunque restringía las pantallas completas a tocar.
- **`Hero` real entre `AlbumsListScreen._AlbumGridCard` y
  `AlbumDetailScreen._AlbumHero`** (tag compartido `'album-hero-${album.id}'`,
  `Hero` nativo de Flutter, sin paquete) — tapear una card de álbum ahora
  vuela hacia el hero del detalle en vez de solo cortar a la pantalla
  nueva.
  - **`_AlbumGridCard` (lista)**: el `Hero` envuelve el `MemoraCard`
    completo (gradiente + nombre + stat de fotos) tal cual ya existía —
    sin restructurar nada, porque `MemoraCard` no usa `ClipPath`/
    `CustomClipper` (solo `BoxDecoration.borderRadius` sobre un
    `Container`, que no clippea contenido), así que no aplica el gotcha de
    abajo en este lado del vuelo.
  - **`_AlbumHero` (detalle) — gotcha real de `Hero` + `ClipPath`,
    resuelto sin necesidad de sacar el `Hero` fuera de
    `MemoraCurvedHero`**: `MemoraCurvedHero` clippea su `background` con
    `MemoraHeroCurve` (`ClipPath`), y un vuelo de `Hero` interpola el
    tamaño de lo que envuelve en cada frame de animación — si el `ClipPath`
    estuviera DENTRO del `child` del `Hero`, necesitaría recalcular la
    curva en cada uno de esos tamaños intermedios. Investigando esto se
    encontró un bug real preexistente, no solo hipotético:
    **`MemoraHeroCurve.shouldReclip` devolvía `false` incondicionalmente**
    (parecía inofensivo porque una pantalla estática nunca cambia de
    tamaño después del primer layout, pero congelaba la curva calculada
    una sola vez — exactamente lo que un vuelo de `Hero`, que sí cambia de
    tamaño en cada frame, rompería). Se corrigió a `true` incondicional
    (el `getClip` es barato — un par de curvas Bézier cuadráticas — así
    que recalcular en cada layout no tiene costo medible). Con eso
    corregido, `_AlbumHero` de todos modos eligió la opción MÁS segura que
    la spec de esta tarea permitía en vez de confiar solo en el fix: el
    `Hero` envuelve únicamente el `background` crudo (la foto/gradiente sin
    clip) que se PASA COMO ARGUMENTO a `MemoraCurvedHero`, nunca el
    `MemoraCurvedHero` completo — así el `ClipPath` queda como ANCESTRO del
    `Hero`, nunca como descendiente, y un `Hero` solo captura/vuela su
    propio `child`, no sus ancestros. El `overlay` (nombre del álbum +
    badge de rol) se queda deliberadamente FUERA del `Hero` también (no
    tiene equivalente en la card de la lista) — aparece normal, ya
    asentada la pantalla de destino, una vez que el vuelo termina. Esta
    decisión (mantener el `Hero` dentro de `MemoraCurvedHero.background` en
    vez de envolver toda la pantalla) es la más conservadora de las dos que
    la spec de esta tarea permitía, elegida porque este entorno no tiene
    forma de confirmar visualmente en un dispositivo cómo se ve el vuelo —
    **queda marcado para que el usuario lo revise en su celular**; si se ve
    algo raro (flicker/tamaño extraño) durante el vuelo, el siguiente paso
    documentado en el propio doc comment de `_AlbumHero` es sacar el `Hero`
    fuera de `MemoraCurvedHero` por completo y aplicar la curva como una
    capa de máscara separada que no participe del `Hero`.
  - Cuando el álbum no tiene fotos, ambos lados usan el mismo
    `gradientForAlbumId(album.id)` (ya lo hacían) — el vuelo en ese caso es
    gradiente-a-gradiente, sin fetch de imagen de por medio.

## Rediseño visual "Aurora" — pivot a light-first (60-30-10, sin spec de Kiro)

Después de que el usuario validara Fase 1 y Fase 2 completas (todo lo de
arriba) en su celular real varias veces, siguió reportando la app "sin
vida" y "muy oscura" pese a los ajustes puntuales de balance claro/oscuro ya
hechos. Compartió dos referencias reales de apps de fotos/colecciones
compartidas (muy cercanas al dominio de Memora) y pidió aplicar la regla
**60-30-10** para resolver el contraste de una vez. Decisión de dirección
tomada directamente con el usuario (no una spec de Kiro, mismo canal que
todo el rediseño): **pivotar de dark-first a light-first**. Es un remapeo
puramente semántico de los mismos 5 colores exactos de siempre — ningún hex
de `deepInk`/`glassBlue`/`auraViolet`/`mist`/`paper` cambió — solo qué rol
cumple cada uno. Alcance: **todo `lib/design/` + las 7 pantallas** (todas
las tocadas en Fase 1/2), no una pantalla nueva.

### El mapeo 60-30-10

- **60% `MemoraColors.paper`** — el lienzo dominante ahora (antes era
  `deepInk`). `scaffoldBackgroundColor`, fondo de `Scaffold`, fondo de la
  mayoría de las pantallas.
- **30% `MemoraColors.mist`** — superficie secundaria: cards, secciones,
  divisores más marcados, fondos de sheets/dialogs.
- **10% dividido en dos roles para `MemoraColors.deepInk`**: ya no es el
  lienzo — es la "tinta" (texto principal, vía `MemoraTypography`, que
  ahora por defecto es Deep Ink en vez de Paper) y un acento oscuro fuerte
  deliberado en un puñado de elementos protagonistas (nunca como fondo de
  pantalla completo).
- **10% `signatureGradient`** — sin cambios como acento de color (CTAs,
  avatares, badges destacados), más un uso nuevo: borde de card en vez de
  relleno completo (ver `AlbumsListScreen` más abajo).

### `lib/design/` — la base (auditoría completa, no un find-replace)

- **`memora_colors.dart`**:
  - `surface1`/`surface2` pasaron de navy oscuro a tonos CLAROS derivados de
    Paper/Mist: `surface1 = #F0F2F5` (Paper/Mist mezclado 60/40,
    precalculado porque `Color.lerp` no es constante — la card por defecto,
    sutil, casi Paper) y `surface2 = mist` (mist completo — cards/secciones
    más "elevadas"/con más presencia, p. ej. las secciones grandes de
    Compartir/Colaboradores).
  - `border` pasó de Mist al 8% (pensado para fondo oscuro) a **Deep Ink al
    ~10%** (`0x1A080B18`) — visible sobre el lienzo claro.
  - `textSecondary`/`textTertiary` pasaron de Paper/Mist a opacidad
    reducida a **Deep Ink** a opacidad reducida (~70%/~50%).
  - **`semanticError`/`semanticSuccess` se oscurecieron** — los valores
    pastel originales (`#FCA5A5`/`#86EFAC`) daban solo ~2:1 de contraste
    sobre Paper (calibrados para fondo oscuro, donde sí funcionaban).
    Nuevos valores: `semanticError = #B91C1C` (rojo-700, ~6.6:1 sobre
    Paper) y `semanticSuccess = #15803D` (verde-700, ~4.8:1 sobre Paper) —
    ambos AA para texto normal, no solo para gráficos/UI. Los valores
    originales se conservan como `semanticErrorOnDark`/
    `semanticSuccessOnDark` para las excepciones oscuras deliberadas (ver
    abajo) — hoy solo `semanticErrorOnDark` tiene un call site real
    (`HomeScreen`'s mensaje de error sobre el hero), `semanticSuccessOnDark`
    queda documentado y disponible por simetría.
  - **Hallazgo real no anticipado por el brief**: `glassBlue`/`auraViolet`
    crudos (`#7DD3FC`/`#A78BFA`) son demasiado claros para servir de
    primer plano (ícono/texto/borde) directamente sobre Paper/Mist — Glass
    Blue crudo da ~1.6:1 de contraste sobre Paper, muy por debajo del piso
    ~3:1 de WCAG para componentes de UI/gráficos. Se agregaron
    **`glassBlueOnLight`** (`#487995`, glassBlue mezclado 45% hacia
    deepInk, ~4.5:1 sobre Paper) y **`auraVioletOnLight`** (`#5F5194`,
    mismo criterio) — usar estos, no los crudos, para cualquier
    ícono/texto/borde-de-foco directamente sobre el lienzo claro (ver la
    lista de call sites migrados más abajo). Los valores crudos siguen
    siendo correctos como componentes de gradiente o sobre una superficie
    oscura (las excepciones deliberadas).
- **`memora_typography.dart`**: el color explícito de cada estilo de
  `TextTheme` se invirtió de `MemoraColors.paper` (texto-sobre-oscuro) a
  `MemoraColors.deepInk` (texto-sobre-claro) — `labelLarge` (texto de
  botón) no cambió, ya era `deepInk` (pensado para el CTA con gradiente,
  sigue siendo correcto). **Esto invierte el gotcha ya documentado para la
  vieja `MemoraCardElevation.light`**: ahora es el resto de la app (light
  canvas) el que obtiene el color correcto "gratis" del `textTheme`
  ambiente, y son las excepciones oscuras deliberadas (ver abajo) las que
  necesitan `.copyWith(color: MemoraColors.paper, ...)` explícito — un
  estilo de `textTheme.*` con color explícito le sigue ganando a cualquier
  `DefaultTextStyle` ambiente, así que "la superficie ya lo arregla" nunca
  alcanza sin ese override puntual.
- **`memora_theme.dart`**: `ColorScheme.light()` en vez de `.dark()`,
  `Brightness.light`, `scaffoldBackgroundColor: paper`. **Renombrado**
  `MemoraTheme.dark` → **`MemoraTheme.theme`** (el nombre viejo mentía) —
  único call site actualizado en `lib/main.dart`
  (`MaterialApp(theme: MemoraTheme.theme)`). `appBarTheme`/`cardTheme`/
  `dialogTheme`/`chipTheme`/`inputDecorationTheme` recalculados para fondo
  claro (texto/íconos Deep Ink por defecto, superficies en Mist/`surface1`).
  `progressIndicatorTheme`/`inputDecorationTheme.focusedBorder` pasaron de
  `glassBlue` crudo a `glassBlueOnLight` (mismo motivo que arriba).
  `snackBarTheme` se dejó deliberadamente en el lienzo claro (Mist +
  texto Deep Ink) en vez de voltearlo a un toast "inverso" oscuro (patrón
  común de Material) — evita necesitar un segundo set de tokens
  "on-dark" solo para el snackbar.
- **`MemoraCardElevation`** (`memora_card.dart`) — **reestructurado, no
  solo recoloreado**: bajo dark-first, `level1`/`level2` eran superficies
  oscuras y `light` (Paper) era la excepción clara rara. Ahora el lienzo
  entero es claro, así que `level1` (`surface1`, la nueva card sutil por
  defecto) y `level2` (`surface2`/Mist, más "elevada"/con más presencia)
  YA SON las superficies claras — no hace falta una variante especial para
  eso. El rol invertido: la excepción rara y deliberada ahora es una card
  **oscura**, renombrada **`MemoraCardElevation.ink`** (fondo
  `MemoraColors.deepInk`, contenido Paper por defecto) — reservada para el
  puñado de "momentos protagonista" del 10% de acento oscuro (ver
  `nfc_programming_screen.dart` más abajo). El wrapper
  `DefaultTextStyle`/`IconTheme` que antes existía para `.light` ahora
  existe para `.ink` (mismo mecanismo, mismo gotcha, espejado): un
  `Text(x, style: textTheme.algo)` dentro de una card `.ink` sigue
  necesitando `.copyWith(color: MemoraColors.paper)` explícito, porque el
  color ya hardcodeado de cada `textTheme.*` le gana al fallback ambiente.
  El borde también se recalculó: `level1`/`level2` usan `MemoraColors.border`
  (ahora calibrado para claro) directo, sin la rama especial que existía
  antes; `.ink` usa un borde claro hardcodeado (`paper` al 14% de opacidad)
  porque `border` (Deep Ink al 10%) sería casi invisible sobre un fondo
  oscuro.
- **`MemoraSecondaryButton`**: el color por defecto (no-destructivo) pasó
  de `MemoraColors.paper` a `MemoraColors.deepInk` — bajo dark-first el
  lienzo universal era oscuro, así que texto/borde Paper funcionaba en
  todos lados; ahora el lienzo es claro casi en todos lados, así que Deep
  Ink es el default correcto. Se agregó un parámetro `color` opcional
  (ignorado si `destructive: true`) para la única excepción oscura que usa
  este widget (`photo_viewer_screen.dart`, pasa `color: MemoraColors.paper`
  explícito). **Regla invertida respecto al gotcha viejo**: nunca anides
  `MemoraSecondaryButton` dentro de una card `MemoraCardElevation.ink` sin
  pasar `color: MemoraColors.paper` — su default (`deepInk`) sería
  invisible sobre ese fondo oscuro (antes el gotcha era al revés, con
  `.light`).
- **`MemoraBadge`**: mismo default de texto para ambas variantes ahora
  (`MemoraColors.deepInk` — antes `neutral` usaba `paper`, `gradient` ya
  usaba `deepInk`). Se agregaron overrides opcionales
  `backgroundColor`/`textColor`/`borderColor` para la única excepción
  oscura de este widget: el badge de conectividad de `HomeScreen` cuando
  se muestra sobre el hero/Welcome (foto con scrim oscuro) — ver más abajo.
- **`MemoraLoadingState`**: el color del spinner pasó de `glassBlue` crudo
  a `glassBlueOnLight` por defecto; se agregó un parámetro `color`
  opcional para las excepciones oscuras (`photo_viewer_screen.dart` pasa
  `glassBlue` crudo; `HomeScreen` pasa `paper` para el spinner de
  conectividad mientras se ve el hero).
- **`MemoraEmptyState`**: el ícono pasó de `glassBlue` crudo a
  `glassBlueOnLight` (mismo motivo — este widget vive casi siempre sobre
  el lienzo claro ahora).
- **`memora_primary_button.dart`/`memora_curved_hero.dart`**: revisados,
  **sin cambios**. `MemoraPrimaryButton` ya usaba `deepInk` fijo sobre el
  gradiente (independiente del lienzo, sigue correcto). `MemoraCurvedHero`
  no tiene ningún color propio (recibe `background`/`overlay` del
  caller), nada que recalibrar.

### Las excepciones oscuras deliberadas (documentadas explícitamente, no accidentes)

Los tokens de `lib/design/` de arriba están calibrados para el **lienzo
claro** (la inmensa mayoría de la app ahora). Un puñado de contextos siguen
— a propósito — oscuros, y usan los tokens/valores ORIGINALES (crudos) en
vez de los recalibrados:

1. **`photo_viewer_screen.dart` — se queda OSCURO por completo,
   convención de plataforma.** Apple Fotos/Google Fotos mantienen el
   visor de fotos en negro incluso con la app en modo claro: un visor
   full-bleed necesita fondo oscuro para que el brillo/contraste de las
   fotos importe más que la consistencia con el tema global. Nada de su
   propio fondo (`MemoraColors.deepInk`) cambió — lo que sí cambió es que
   ya no puede reusar los tokens compartidos ahora recalibrados
   (`MemoraColors.border`/`.textSecondary`, el default de
   `MemoraSecondaryButton`, el default de `MemoraLoadingState`): pasa
   overrides explícitos (`color: MemoraColors.paper`/`glassBlue` crudo) o
   reconstruye su propio estilo self-contained (`_StateOverlay`'s círculo
   ahora usa `paper` a baja opacidad para fondo/borde en vez de
   `surface2`/`border`, que ahora son claros).
2. **El hero/Welcome de `HomeScreen`** (`_WelcomeHeroBackdrop` +
   `_HeroHeadline` + el wordmark "Memora" + el badge/spinner de
   conectividad mientras se muestra) — sigue siendo una foto con dos
   scrims de Deep Ink (composición sin cambios, pedido explícito del
   usuario de mantenerla). Todo el texto/badge/spinner ahí ahora necesita
   overrides explícitos a `paper`/`semanticErrorOnDark`/`glassBlue` crudo
   en vez de heredar el `textTheme`/tokens ambiente (que se volvieron
   claros). El `_buildConnectivityBadge` de `HomeScreen` recibe un
   parámetro `onDark` (true solo mientras se ve el hero) para elegir entre
   el estilo claro-por-defecto y el override oscuro.
3. **El overlay del hero de álbum** (`AlbumDetailScreen._AlbumHero`,
   nombre del álbum + badge de rol sobre la foto/gradiente con scrims) —
   mismo motivo que el punto 2: el `Text` del nombre del álbum necesita
   `color: MemoraColors.paper` explícito ahora (antes lo heredaba gratis).
4. **`MemoraCardElevation.ink`** — ver arriba.

**Regla general para cualquier código futuro**: si vas a tocar una de
estas cuatro zonas, no asumas que los tokens compartidos (`border`,
`textSecondary`, `semanticError`, el default de `MemoraSecondaryButton`/
`MemoraLoadingState`/`MemoraBadge`) te dan el resultado correcto — están
calibrados para el lienzo claro. Usa los overrides ya mencionados, o
hardcodea un valor derivado de `paper`/`deepInk` a la opacidad que
corresponda, igual que se hizo en estos cuatro lugares.

### Las 7 pantallas — qué cambió pantalla por pantalla

- **`HomeScreen`** — el usuario dio libertad explícita acá ("la pagina
  principal se puede cambiar mucho"):
  - `_AuroraBackdrop` (antes: fondo Deep Ink lleno + blobs difuminados al
    35% de opacidad — el propio fondo oscuro de todo el dashboard
    autenticado) pasó a **fondo Paper** + los mismos blobs al 12% de
    opacidad (textura de marca sutil en vez de un glow oscuro dominante).
    Es el cambio más grande de esta pantalla: antes el dashboard
    autenticado entero vivía sobre un fondo oscuro, ahora vive sobre Paper
    como el resto de la app.
  - `_QuickAccessCard` (antes `MemoraCardElevation.light`, la excepción
    clara rara) ahora es una `MemoraCard` sin elevación especial
    (`level1` por defecto) — ya no hace falta destacarla porque el lienzo
    entero es claro. Se eliminó el `.copyWith(color: MemoraColors.deepInk)`
    de su `Text`, que ahora es redundante (el `textTheme` ya da Deep Ink
    por defecto).
  - El wordmark "Memora"/headline/subtítulo del hero de Welcome y el badge
    de conectividad ganaron los overrides oscuros explícitos documentados
    arriba.
  - El error de login (`auth.errorMessage`) sobre el hero pasó a usar
    `semanticErrorOnDark` (el rojo pastel original) en vez del
    `semanticError` recién oscurecido, que sería casi invisible sobre el
    scrim oscuro.
  - `_PhotosSection`/`_PhotoItemRow`/el `IconButton` de "Cerrar sesión" —
    **sin cambios de código**: ya vivían sobre el lienzo claro efectivo
    (antes porque eran la superficie clara `.light`, ahora porque todo el
    dashboard es claro) y sus colores (`semanticSuccess`/`semanticError`
    ya recalibrados, `textTheme` ambiente) quedaron automáticamente
    correctos.
- **`AlbumsListScreen`**:
  - El FAB de "+" pasó de círculo con `signatureGradient` a **círculo
    sólido `MemoraColors.deepInk`** con ícono Paper — el ejemplo textual
    del brief ("el FAB circular negro de la Referencia B"). Los CTAs con
    texto (`MemoraPrimaryButton`, en cualquier pantalla) se quedan con el
    gradiente — son el otro rol del 10% ("el gradiente... CTAs"), un FAB
    circular sin texto es el rol del acento oscuro protagonista.
  - `_AlbumGridCard`: en vez de `gradientForAlbumId` rellenando toda la
    card, ahora es una card `MemoraCard` (level1, clara) enmarcada por un
    **borde grueso (3px) con el gradiente** — el patrón exacto de la
    Referencia B (cada colección con su propio marco de gradiente
    distintivo). Implementado con el truco clásico de "borde de
    gradiente vía padding": un `Container` exterior con el gradiente como
    `BoxDecoration` + `padding: 3px`, y adentro el `MemoraCard` con radio
    `hero - 3`. El `Hero` de la transición lista→detalle sigue envolviendo
    todo el conjunto (ni el `Container` exterior ni `MemoraCard` usan
    `ClipPath`, así que no aplica el gotcha de `Hero`+`ClipPath` que sí
    documenta `_AlbumHero` para su lado de la misma transición).
  - `gradientForAlbumId` (`album_card_style.dart`) se reescribió: antes
    mezclaba el acento con `surface1`/`surface2` (entonces navy oscuro) al
    55% de alpha, para un relleno "moody" oscuro de card completa. Ahora
    que se usa como BORDE (no relleno), necesita leerse vívido/saturado —
    se quitó la mezcla con superficie oscura y ahora interpola
    directamente entre `glassBlue` y `auraViolet`. Sigue siendo
    determinístico por `albumId` (mismo hash, mismos tests en
    `album_card_style_test.dart`, que no dependen de los valores exactos
    de color, solo de determinismo/variedad/2-colores — siguen pasando sin
    tocarlos). También sigue usándose como fondo completo (no borde) para
    el fallback de `_AlbumHero` cuando un álbum no tiene fotos — los
    scrims de Deep Ink de esa pantalla ya garantizan el contraste del
    texto encima sin importar cuán vívido sea el gradiente de base.
  - El badge de rol (`MemoraBadge` gradient, desbordando la esquina) se
    dejó tal cual — sigue funcionando igual (texto Deep Ink sobre
    gradiente, sin cambios).
- **`album_detail_screen.dart`**:
  - Iconos que eran `glassBlue`/`auraViolet` crudos (el ícono de
    "Compartir", el ícono por tipo de etiqueta NFC/QR, el ícono de
    "Colaboradores") pasaron a `glassBlueOnLight`/`auraVioletOnLight` —
    todos viven directo sobre una `MemoraCard` clara (`level1`/`level2`)
    ahora.
  - El nombre del álbum en el overlay del hero (`_AlbumHero`) ganó
    `color: MemoraColors.paper` explícito (antes lo heredaba gratis del
    `textTheme` oscuro-por-defecto) — es la excepción oscura #3 de arriba.
  - `_PhotoCountBadge` (antes `MemoraCardElevation.light`, la excepción
    clara rara que "flotaba" sobre la costura oscura/clara) ahora usa
    `level1` sin más — sigue siendo la card más clara del sistema (casi
    Paper), sigue funcionando igual como "pill brillante" sobre la costura
    curva, solo que ya no es una variante especial. Se eliminaron los dos
    `.copyWith(color: MemoraColors.deepInk)` de sus `Text` (redundantes
    ahora).
  - Todo lo demás (grid de fotos, `_PhotoTile`/`_HeroPhotoImage`, el
    bottom sheet de Compartir/Colaboradores, `_InlineBanner`, `_PersonRow`,
    los banners de error/reauth) **no necesitó cambios de código** — ya
    usaban `MemoraColors.surface1`/`surface2`/`border`/`textSecondary`/
    `textTertiary`/`semanticError`/`semanticSuccess` vía token (no
    hardcodeados), así que la nueva calibración de esos tokens los corrige
    automáticamente. Verificado explícitamente caso por caso (incluido el
    "×" de borrar foto y el overlay `cloud_off` sobre miniaturas, que
    siguen siendo overlays Deep Ink deliberados sobre una foto real —
    correctos sin cambios, independientes del tema global).
- **`create_album_screen.dart`** — simplificación real, no solo
  recoloreo: la card pasó de `MemoraCardElevation.light` (con un
  `InputDecoration` armado a mano porque el `InputDecorationTheme` global
  — entonces oscuro — era ilegible dentro de esa card clara) a
  `MemoraCardElevation.level2` usando el `InputDecorationTheme` GLOBAL sin
  modificar — porque ese theme global ahora es claro, ya no hace falta el
  campo especial. Se eliminaron los `.copyWith(color: MemoraColors.deepInk
  ...)` de sus `Text` (redundantes). El gotcha viejo ("cada `TextField`
  dentro de una card clara necesita su propio `InputDecoration`") queda
  obsoleto — ya no aplica a ninguna pantalla de esta app, porque ya no hay
  cards claras "excepcionales" en un mar oscuro.
- **`accept_invitation_screen.dart`** — **sin ningún cambio de código**.
  Ya usaba `MemoraCardElevation.level2` + el `InputDecorationTheme` global
  (sin campo especial) + `textTheme` ambiente sin overrides — la nueva
  calibración global (theme claro, `textTheme` Deep Ink por defecto,
  `semanticError` oscurecido) lo deja automáticamente correcto. Prueba de
  que el pivot es "puramente semántico" cuando una pantalla ya seguía las
  convenciones del sistema al pie de la letra.
- **`nfc_programming_screen.dart`**:
  - El estado `success` pasó de `MemoraCardElevation.light` (la excepción
    clara rara, "premio" por terminar la escritura física) a
    **`MemoraCardElevation.ink`** (la nueva excepción oscura rara) — un
    reflejo exacto de la misma idea: bajo dark-first, una card brillante
    en un mar oscuro se sentía como un premio; bajo light-first, una card
    negra en un mar claro cumple el mismo rol. Sus `Text` pasaron de
    `.copyWith(color: MemoraColors.deepInk...)` a
    `.copyWith(color: MemoraColors.paper...)` (mismo mecanismo de
    override, mismo gotcha, espejado).
  - `_buildLockSection` (el botón "Bloquear como solo lectura") se queda
    FUERA de la card `.ink`, sobre el lienzo normal de la pantalla (ahora
    claro) — mismo motivo que antes, invertido: `MemoraSecondaryButton`
    default ahora es `deepInk`, que sería invisible dentro de la card
    `.ink` (antes era al revés, con `paper` invisible dentro de `.light`).
  - `_StateIconChip` (el círculo de esperar/escribir/verificar) pasó de
    `glassBlue` crudo a `glassBlueOnLight` por defecto — vive sobre el
    lienzo claro ahora.
  - Los diálogos de confirmación (`AlertDialog`+`TextButton`) no
    necesitaron cambios de código — ya usaban `semanticError` vía token
    para la acción destructiva, que ahora es automáticamente legible sobre
    el `dialogTheme` claro.
- **`drive_reconnect_prompt.dart`** — el ícono del título del diálogo y el
  texto del botón "Reconectar" pasaron de `glassBlue` crudo a
  `glassBlueOnLight` (el diálogo ahora vive sobre un `dialogTheme` claro).
  Todo lo demás (colores de "Cancelar", íconos de resultado en el
  `SnackBar`) ya usaba tokens (`textSecondary`/`semanticSuccess`/
  `semanticError`) que se recalibraron solos.

### Verificación de contraste hecha explícitamente

- Deep Ink sobre Paper/Mist: ~19:1/~17:1 — sobra para cualquier texto.
- `semanticError`/`semanticSuccess` nuevos: ~6.6:1/~4.8:1 sobre Paper — AA
  para texto normal, no solo gráficos. Documentado el porqué del cambio de
  hex arriba.
- `glassBlueOnLight`/`auraVioletOnLight`: ~4.5:1 sobre Paper (justo en el
  piso AA, cómodo para el uso real: íconos/bordes de foco, nunca body text
  largo).
- Las 4 excepciones oscuras deliberadas se auditaron una por una (arriba)
  para asegurar que ninguna quedó "a medio pivotar" (mitad token claro,
  mitad valor oscuro sin querer) — en particular el nombre del álbum sobre
  el hero, que se detectó tarde en la auditoría (`textTheme.headlineMedium`
  sin override habría quedado Deep-Ink-sobre-scrim-oscuro, casi invisible)
  y se corrigió antes de reportar terminado.

### Qué NO cambió (confirmado explícitamente)

Ningún controller/`*Api`/modelo/lógica de negocio — 100% capa visual. Cero
dependencias nuevas. `memora-backend`/`memora-web`/`specs/` no se tocaron.
No se inventó ningún fetch de foto de portada nuevo para `AlbumsListScreen`
(sigue siendo la misma limitación de datos de siempre). Todos los gotchas
de interacción/estado documentados en las secciones de arriba (key-por-id
+epoch, owner-only, `autofocus` prohibido en diálogos, el retraso de
~300ms de `photo_view`, la máquina de estados de NFC, el `Future.ignore()`
de `photo_viewer_screen.dart`, el `ListenableBuilder` del bottom sheet)
siguen intactos — ninguno depende de color/tema.

## Pasada de motion design (sin spec de Kiro): sistema centralizado, loading states, microinteracciones

Última pasada visual pedida directamente por el usuario (no una spec de
Kiro): "más motion design" — un sistema de animación centralizado, loading
states reales para toda operación async, y microinteracciones consistentes,
por encima del trabajo de rediseño "Aurora"/light-first ya documentado
arriba. **Un intento anterior de esta misma tarea se cortó a mitad de
camino por un error de sesión** (no de código) mientras trabajaba en
`_HeroPhotoImage`, dejando progreso real parcial (el sistema base y la
mayoría de las pantallas ya tenían el motion aplicado, con **un bug real
sin corregir** — ver el gotcha de `initState`+`MediaQuery` más abajo) y
parte del checklist original sin verificar/completar. Esta sección
documenta el estado final tras retomarla, no solo lo agregado en esta
pasada.

### Gotcha real corregido: nunca leer `MediaQuery`/`MemoraMotion.reduceMotion` en `initState()`

**El bug que dejó `flutter test` roto** (1 test fallando en
`album_detail_screen_test.dart` con
`dependOnInheritedWidgetOfExactType<MediaQuery>() ... was called before
_MemoraSkeletonState.initState() completed`): `_MemoraSkeletonState.initState()`
(`lib/design/widgets/memora_skeleton.dart`) y
`_FloatingEmptyIllustrationState.initState()`
(`lib/albums/screens/albums_list_screen.dart`, el float loop del empty
state) llamaban `MemoraMotion.reduceMotion(context)` — que internamente usa
`MediaQuery.maybeOf(context)` — dentro de `initState()`. Es inválido en
Flutter: **cualquier** lookup de un `InheritedWidget` (`MediaQuery`
incluido) tiene que hacerse en `build()` o `didChangeDependencies()`, nunca
en `initState()` — en ese punto el `context` todavía no está completamente
asociado al árbol. Funciona "por accidente" en la app real corriendo en
dispositivo la mayoría de las veces (la inconsistencia solo se manifiesta
de forma confiable bajo el árbol de widgets más estricto de
`flutter_test`), así que no asumir que "anda en el celular" prueba que el
patrón es válido.

**Arreglo, mismo patrón en los dos sitios**: mover la lectura de
`MemoraMotion.reduceMotion(context)` a `didChangeDependencies()`, con un
flag `bool _startedRepeating = false` para no reiniciar el
`AnimationController.repeat()` en cada `didChangeDependencies()` posterior
(se llama más de una vez a lo largo de la vida del widget, no solo
al montar). Ver `_MemoraSkeletonState`/`_FloatingEmptyIllustrationState`
para el patrón exacto — **cualquier futuro `StatefulWidget` con un loop de
animación que dependa de `MemoraMotion.reduceMotion`/`MediaQuery` en su
arranque debe seguir este mismo patrón, nunca leerlo directo en
`initState()`**, aunque "funcione" corriendo la app a mano. Grepeado
`MemoraMotion.reduceMotion`/`MediaQuery` en todo `lib/` tras el arreglo:
todos los demás usos ya estaban en `build()` (via `final reduceMotion =
MemoraMotion.reduceMotion(context)` al principio del método), ninguno más
tenía este problema.

### El sistema centralizado (`lib/design/`)

- **`lib/design/memora_motion.dart`** — la única fuente de verdad para
  duraciones/curvas/stagger/reduced-motion de toda la app (ver su propio
  doc comment): `MemoraMotion.quick` (150ms, microinteracciones:
  press-scale, swaps de ícono/label dentro de un botón, crossfades
  chicos), `MemoraMotion.moderate` (300ms, transiciones de pantalla,
  entradas de lista/grid, stagger de sheet, swaps loading/error/contenido a
  nivel pantalla), `MemoraMotion.enterCurve`
  (`Curves.easeOutCubic`)/`MemoraMotion.exitCurve` (`Curves.easeInCubic`,
  el espejo de `enterCurve` para que un push/pop se sienta como una sola
  animación continua), `MemoraMotion.stagger(index, {step, maxIndex})`
  (45ms por defecto, clamped a los primeros 12 índices para que una lista
  larga no obligue a esperar un stagger cada vez más largo) y
  `MemoraMotion.reduceMotion(context)` (el único resolver de la
  accesibilidad "reducir movimiento" — **nunca** llamarlo desde
  `initState()`, ver el gotcha de arriba). Ningún literal de milisegundos
  ni chequeo de `MediaQuery...disableAnimations` suelto en ningún otro
  archivo de `lib/` — siempre pasar por acá.
- **`lib/design/memora_page_route.dart`** (`MemoraPageRoute<T>`) —
  reemplazo drop-in de `MaterialPageRoute` (mismo shape de constructor:
  `builder`, `settings`, `fullscreenDialog`) con la transición estándar de
  la app: slide-up sutil (4% de la altura) + fade en el push, con la
  pantalla saliente desvaneciéndose apenas (opacity 1→0.92) — Flutter
  espeja automáticamente la transición en el pop (mismo
  `transitionsBuilder` corriendo en reversa), así que no hace falta
  ninguna transición de "vuelta" separada. Colapsa a un corte instantáneo
  (cero duración, sin slide/fade) si `MemoraMotion.reduceMotion` está
  activo. **Usado en TODOS los `Navigator.push`/`pushReplacement` de la
  app** (`HomeScreen`, `AlbumsListScreen`, `AlbumDetailScreen`,
  `AcceptInvitationScreen`'s `pushReplacement` hacia `AlbumsListScreen`) —
  cualquier nuevo push debe usar `MemoraPageRoute`, nunca
  `MaterialPageRoute` directo. La app sigue sin `go_router` ni ningún
  paquete de routing — navegación 100% `Navigator.push` explícito.
- **`lib/design/widgets/memora_skeleton.dart`** (`MemoraSkeleton`,
  `MemoraAlbumCardSkeleton`, `MemoraPhotoTileSkeleton`) — bloque de loading
  con una "respiración" de opacidad lenta y sutil (900ms, NO un
  shimmer/barrido de luz — rechazado explícitamente por el usuario), en
  vez de un spinner centrado, para el loading inicial de listas/grids: el
  shape de cada skeleton coincide aproximadamente con el contenido real
  para que el layout no salte cuando llegan los datos. Respeta
  `reduceMotion` (opacidad fija en vez del loop) vía
  `didChangeDependencies`, ver el gotcha arriba.
- **`MemoraPrimaryButton`/`MemoraSecondaryButton` — nuevo parámetro
  `loading`** (agregado en esta pasada): cuando `true`, el `icon` (si lo
  hay) se reemplaza por un spinner chico (16px, `strokeWidth: 2`, mismo
  color que el resto del contenido del botón) — el `label` se mantiene
  visible, así el botón sigue leyéndose "haciendo X" en vez de un estado
  "ocupado" genérico — y los taps se bloquean (`tapEnabled = onPressed !=
  null && !loading`; a diferencia del estado disabled normal, un botón
  `loading` NO se atenúa a 0.45 de opacidad, para que se distinga de "esta
  acción no está disponible"). Es el mecanismo central del punto 5 del
  checklist ("spinner+label dentro de cada botón de mutación con bloqueo
  de doble-submit") — preferir SIEMPRE `loading:` sobre solo deshabilitar
  el botón (`onPressed: isMutating ? null : ...`) para cualquier botón que
  dispare una mutación async, salvo que la pantalla ya tenga su propio
  mecanismo equivalente (ver el patrón `_pendingAction`/`_isPending`
  abajo, o el caso de "Obtener enlace para compartir" en
  `album_detail_screen.dart`, que reemplaza el botón entero por
  `MemoraLoadingState` mientras `controller.isLoadingShareLink` — igual de
  válido, es la misma intención visual con otro mecanismo).

### Patrón: distinguir QUÉ botón está cargando cuando el controller solo expone un flag compartido

`AlbumsController.isMutating` es un único flag compartido entre TODAS las
mutaciones que puede disparar `AlbumDetailScreen` (rename/visibility/
delete/invite/revoke-invitation/remove-collaborator/leave/create-tag/
disable-tag/revoke-share-link) — por sí solo no alcanza para que un botón
sepa "soy yo el que está corriendo" en vez de simplemente deshabilitarse
igual que todos los demás a la vez. Patrón usado en
`_AlbumDetailScreenState` (campo `String? _pendingAction` + helper `bool
_isPending(String action) => _pendingAction == action &&
widget.controller.isMutating`): cada método de mutación hace
`setState(() => _pendingAction = 'tag-de-la-acción')` (con datos variables
del ítem cuando aplica, p. ej. `'revoke-invitation:${invitation.id}'`,
`'create-tag:${type.name}'`, `'disable-tag:${tag.id}'`,
`'remove-collaborator:${collaborator.userId}'`) justo antes de `await
widget.controller.elMétodoQueSea(...)`, y lo limpia a `null` después
(`setState(() => _pendingAction = null)`, con el chequeo de `mounted` de
siempre). Cada botón pasa `loading: _isPending('su-propio-tag')`.

**Por qué esto también funciona dentro del bottom sheet de
Compartir/Colaboradores** (`_openSharingSheet`, que — gotcha ya documentado
arriba — es una ruta/overlay separada cuyo contenido NO se reconstruye con
el `setState` de la pantalla, solo con `ListenableBuilder(listenable:
widget.controller)`): el `setState(() => _pendingAction = 'x')` corre
ANTES del `await widget.controller.mutación()`, así que cuando esa
mutación internamente pone `isMutating = true` y notifica a sus listeners
(disparando el rebuild del `ListenableBuilder` del sheet), `_pendingAction`
ya tiene el valor correcto — el sheet lee un campo plano de la clase State
que lo contiene (closure sobre `this`), no necesita su propio mecanismo de
notificación. Mismo razonamiento al limpiarlo: el `notifyListeners()` que
acompaña `isMutating = false` al terminar la mutación es el que dispara el
rebuild que ve `_pendingAction` ya en `null`. **No hace falta un
`ValueNotifier` separado para esto** — confiar en que el propio
`controller.notifyListeners()` (al iniciar Y al terminar cada mutación) ya
cubre ambas transiciones para cualquier consumidor que lea un campo plano
seteado justo antes del `await`.

**Para un `IconButton` suelto que no usa `MemoraSecondaryButton`** (p. ej.
el ícono "Revocar enlace" `link_off`, o `_PersonRow`'s ícono de acción por
invitación pendiente): mismo patrón, pero el spinner se arma a mano (un
`SizedBox(20x20, child: CircularProgressIndicator(strokeWidth: 2))`)
alternando con el `IconButton` real vía un `if`/`else` simple en vez de
`AnimatedSwitcher` (una sola transición de estado por acción, no vale la
pena la complejidad extra ahí). `_PersonRow` ganó un parámetro `isLoading`
para esto (ver `lib/albums/screens/album_detail_screen.dart`).

**Para una pantalla que NO escucha su propio controller (`addListener`)**:
`CreateAlbumScreen` y `NfcProgrammingScreen._giveUpAndDisable` no se
suscriben al `ChangeNotifier` relevante (`AlbumsController`), así que leer
`controller.isMutating` directo en el label/loading de un botón NO
funciona — nada dispara un rebuild cuando ese flag cambia a mitad de un
`await`. La solución en ambos: un flag local (`bool _submitting`/`bool
_disabling`) seteado con `setState` antes del `await` y limpiado después
— el mismo mecanismo que `_pendingAction`, pero sin depender de que algún
`ListenableBuilder`/listener externo dispare el rebuild, porque acá no
existe ninguno. **Regla general**: antes de usar `controller.isMutating`
(o cualquier flag de un `ChangeNotifier`) directo en un `build()`, verificar
que esa pantalla realmente escuche ese controller (`addListener` en
`initState`, o esté dentro de un `ListenableBuilder`/`AnimatedBuilder` que
lo haga) — si no, un flag de estado local del propio `State` es la opción
correcta, no un bug a "arreglar" agregando un listener nuevo sin motivo
(en el caso de `CreateAlbumScreen`, agregar un listener solo para esto
hubiera sido más acoplamiento del necesario para un solo botón).

### Estados de fotografías (`_PhotoTile`/`_HeroPhotoImage`/`_PolaroidPhoto`/`photo_viewer_screen.dart`)

Las cuatro implementaciones ya seguían (o ahora siguen, tras esta pasada)
el mismo patrón placeholder → fade-in → imagen/error, todas con
`AnimatedSwitcher(duration: MemoraMotion.moderate, switchInCurve:
MemoraMotion.enterCurve, switchOutCurve: MemoraMotion.exitCurve)` sobre un
`FutureBuilder` de tres estados (loading/error/imagen), cada rama con su
propia `ValueKey` para que `AnimatedSwitcher` detecte el cambio de estado:

- `_PhotoTile`/`_HeroPhotoImage` (`album_detail_screen.dart`): ya lo tenían
  desde antes de que se cortara la sesión previa — confirmado íntegro y
  correcto al retomar la tarea, no hizo falta tocar ninguno de los dos.
- **`photo_viewer_screen.dart`'s `_PhotoViewerPage.build`**: agregado en
  esta pasada — antes hacía un swap abrupto (sin `AnimatedSwitcher`) entre
  spinner/error/imagen dentro del `FutureBuilder`. Envolver esto en
  `AnimatedSwitcher` es seguro pese a vivir dentro del `customChild` de
  `photo_view` (ver el gotcha de los ~300ms de doble-tap ya documentado
  arriba): `AnimatedSwitcher` es puramente visual, no registra ningún
  gesture recognizer propio, así que no interactúa con la gesture arena de
  `photo_view` en absoluto. `_StateOverlay` ganó un parámetro `loading`
  (forwardeado a su `MemoraSecondaryButton` interno) para el botón
  "Reconectar Google Drive" mientras `_isReconnectingDrive` es `true`.
  `test/photo_viewer_screen_test.dart` sigue pasando sin tocar ninguna
  aserción — sus `find.text(...)` siguen encontrando los mismos labels,
  ahora dentro de una transición en vez de un swap instantáneo.
- `_PolaroidPhoto` (`albums_list_screen.dart`, las miniaturas del montaje
  de fotos en cada card de álbum): confirmado ya con el mismo patrón desde
  el trabajo de covers reales (ver la sección de arriba) — no forma parte
  del checklist de motion en sí (nunca fue parte de esta pasada), pero
  usa `FutureBuilder` + fallback de ícono en error, coherente con el resto.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → **166/166**
pasando (mismo total reportado en la pasada anterior de covers/empty-state/
FAB — ningún test se perdió, se agregaron cero tests nuevos en esta pasada
porque el cambio es capa de motion/loading sobre widgets ya cubiertos
indirectamente por los tests existentes, salvo el fix del bug de
`initState`, que SÍ estaba haciendo fallar un test real). El aspecto real
de las transiciones/loading states/microinteracciones en un dispositivo
físico **no** está verificado en este entorno (sin dispositivo/emulador) —
el usuario debe confirmarlo corriendo la app.

## Ajuste visual post-mockup: hero "Álbumes", nota caligráfica y bottom nav (sin spec de Kiro)

Tarea puntual pedida directamente con un mockup exacto (`principal.png`, no
está en el repo — descrito por el usuario) más dos assets provistos
(`assets/images/principal_asset.png`, `assets/images/principal_fondo.png`).
Alcance acotado a `lib/screens/home_screen.dart` (+ `pubspec.yaml` para el
asset nuevo) — ningún controller/`*Api`/modelo tocado, y el sistema de
motion/`MemoraCardElevation`/resto de `lib/design/` sin cambios (solo se
consumió lo que ya existía: `MemoraTypography.legibilityShadows`,
`MemoraRadius.hero/.pill`, el patrón de blur `ImageFiltered` de
`_AuroraBackdrop`/`_WelcomeHeroBackdrop`).

### 1. `_AlbumsActionBlock` — hero oscuro con gradiente radial (reemplaza la card clara anterior)

> **Parcialmente OBSOLETO** — ver la sección "4. Corrección post-feedback en
> dispositivo real..." más abajo (al final de este bloque, antes de
> "Verificación"). El widget se renombró a `_AlbumsHeroContent` y perdió su
> propio fondo/`ClipRRect`/altura fija (280px) — el `RadialGradient` +
> `_AlbumsHeroGlow` ahora pintan TODA la zona oscura superior del dashboard
> (`_DashboardDarkZone`), no solo esta card. Lo que sigue describe la
> primera versión (útil como historia de la composición visual del
> contenido del hero en sí — eyebrow/headline/flecha/dots — que no cambió),
> pero cualquier mención a "card"/`ClipRRect(MemoraRadius.hero)`/`height:
> 280` quedó reemplazada por la sección 4.

Ya no es una `MemoraCard`/`MemoraCardElevation` (ninguna variante ofrece un
fondo de gradiente radial) — se compone a mano: `ClipRRect(MemoraRadius
.hero)` > `Material`/`InkWell` (toda la card es UN solo tap target, el
círculo con flecha decorativo de abajo-derecha NO tiene su propio
`onTap` — evita que dos regiones de gesto superpuestas disparen la
navegación dos veces) > `Stack` con: el `RadialGradient` exacto que pidió
el usuario (`Alignment(0.9, -0.1)`, `auraViolet` → `deepInk`), una capa
extra de esferas borrosas (`_AlbumsHeroGlow`, mismo patrón
`ImageFiltered(blur)` + círculos que ya usan `_AuroraBackdrop`/
`_WelcomeHeroBackdrop`, no un patrón nuevo) posicionadas según
`principal_fondo.png` (concentradas arriba-derecha, un resto sutil
abajo-izquierda), el asset `principal_asset.png` superpuesto/desbordando
la esquina superior derecha (`Positioned` con `Stack(clipBehavior:
Clip.none)`, `opacity: 0.92` para integrarlo un poco con el fondo en vez de
verse pegado encima), el eyebrow "TUS ÁLBUMES" + headline
(`_AlbumsHeadline`), el círculo con flecha (`_CircularArrowGlyph`,
decorativo) y los 3 puntos de paginación (`_PaginationDots`).

- **Este es el 10% de acento oscuro "protagonista"** del pivot light-first
  (mismo rol que `MemoraCardElevation.ink`, aplicado aquí a mano por el
  gradiente radial que esa variante no soporta) — uno de los pocos momentos
  deliberadamente oscuros de toda la app light-first.
- **`_AlbumsHeadline` — el texto con gradiente ("compartes.")**: el brief
  pedía "mismo patrón que 'contigo' en el headline del Welcome —
  `ShaderMask` o el approach que ya se usó ahí, reusalo". Verificado
  releyendo `_HeroHeadline`: "contigo" en realidad usa un **color plano**
  (`auraViolet`), no un `ShaderMask`/gradiente — no había ningún call site
  de `ShaderMask` que copiar literalmente. Se implementó `ShaderMask`
  (`MemoraColors.signatureGradient.createShader`) envolviendo un `Text`
  dentro de un `WidgetSpan` (`PlaceholderAlignment.baseline`) dentro del
  `RichText`/`TextSpan` del resto del headline — nuevo en el archivo, en el
  mismo espíritu que pedía el brief (destacar la última palabra con el
  gradiente de firma), documentado en el propio doc comment del widget para
  que quede claro que no es un patrón preexistente copiado 1:1.
- **`principal_fondo.png` — NO se usó como imagen real**: el efecto se
  replicó con `RadialGradient` + `ImageFiltered(blur)` + círculos de Flutter
  puro (igual que pidió el usuario intentar primero) y quedó
  suficientemente parecido — no hizo falta el fallback de imagen real.
  **Por eso `principal_fondo.png` NO se declaró en `pubspec.yaml`** (el
  brief lo pedía "si termina haciendo falta como fallback" — no hizo
  falta); el archivo queda en `assets/images/` sin usar, disponible si un
  futuro ajuste visual decide sí necesitarlo como imagen real.
- **`_PaginationDots` es 100% decorativo** — documentado explícitamente en
  su doc comment: no hay un `PageView` real ni contenido para una
  "página 2/3", son solo 3 puntos estáticos (el primero más ancho/sólido)
  copiando el lenguaje visual del mockup. Si algún día se necesita un
  carrusel real ahí, este widget debe reemplazarse, no extenderse in situ.
- **Decisión no trivial, marcada para que el usuario la revise en su
  celular**: el tamaño/posición exactos del asset decorativo (168x168,
  `top: 4, right: -18` sobre una card de `height: 280`) y el punto de corte
  del texto (`padding` derecho de 100px para dejarle aire al asset) se
  ajustaron a ojo sin poder verlos renderizados en un dispositivo real —
  si el asset queda muy grande/pequeño o el texto se ve apretado contra él,
  es la primera zona a retocar.

### 2. Nota caligráfica + glow — `_ConnectingMemoriesFooter`

Nuevo widget al final de `_AuthenticatedDashboard` (después de
`_PhotosSection`): "Recuerdos que nos conectan" + un ícono de corazón chico,
en `GoogleFonts.caveat` — **usada solo en este `Text` puntual**, no es un
cambio de `MemoraTypography`/`Theme.of(context).textTheme` (que siguen
siendo Manrope en todos lados). Color: `MemoraColors.auraVioletOnLight`, NO
`auraViolet` crudo — este footer vive sobre el lienzo claro (Paper) del
resto del dashboard, no es una excepción oscura, así que aplica la regla ya
documentada del pivot light-first (el violeta crudo da solo ~1.6:1 de
contraste sobre Paper). El glow detrás es el mismo patrón
`ImageFiltered(blur)` + círculo ya usado en el resto del archivo, un único
blob violeta grande (240px, alpha 0.3) sangrando fuera del borde
inferior-derecho del widget (`Positioned` con `Stack(clipBehavior:
Clip.none)`).

### 3. Bottom navigation bar — `_AuroraBottomNav` (adición nueva a la app, decidida con el usuario)

`Scaffold.bottomNavigationBar` en `_HomeScreenState.build`, **solo cuando
`auth.status == AuthStatus.authenticated`** (`showBottomNav`) — nunca en el
Welcome sin sesión. `Scaffold.extendBody: showBottomNav` porque la barra es
flotante (con margen/sombra, no pegada al borde) — el contenido scrolleable
puede dibujarse detrás de ella; para que nada quede tapado de verdad,
`_AuthenticatedDashboard` suma `_bottomNavClearance` (104px) a su padding
inferior existente (antes `MemoraSpacing.xxl` solo, ahora `+
_bottomNavClearance`) — el único cambio al padding de ese widget, su
contenido interno (los 3 bloques + el footer nuevo) no se tocó.

- **4 items + "+" central flotante**, mismo mecanismo que el FAB de
  `AlbumsListScreen` (`Material`/`InkWell` a mano con `CircleBorder`,
  porque `FloatingActionButton` no soporta `gradient` directo — no un
  widget nuevo, el mismo truco ya documentado arriba).
  - **Inicio**: activo por defecto (`active: true`, color
    `auraVioletOnLight`), sin `onTap` — ya es esta pantalla.
  - **Álbumes**: `onTap: onOpenAlbums`, que en `_AuroraBottomNav` es
    literalmente `_HomeScreenState._openAlbums` (el mismo método que ya
    usa `_AlbumsActionBlock`/el resto de la app) — cero navegación nueva.
  - **"+" central**: `onTap: onAddPhotos`, pasado desde
    `_HomeScreenState.build` como `() =>
    widget.photoUploadController.pickAndUploadPhotos()` — la MISMA llamada
    que ya dispara `_PhotosSection`'s botón "Agregar fotos"
    (`PhotoUploadController.pickAndUploadPhotos`). No hay flujo nuevo, ni
    estado nuevo: si el picker/optimizador/subida fallan, el usuario ve el
    resultado donde siempre lo vio (la lista de `_PhotoItemRow` dentro de
    `_PhotosSection`, que sigue en el dashboard debajo) — el botón "+" es
    solo un segundo punto de entrada a la misma acción, no una UI
    duplicada.
  - **Compartidos/Ajustes**: sin pantalla — **decisión de producto ya
    tomada con el usuario, no una ambigüedad para resolver**. `onTap`
    dispara `ScaffoldMessenger.of(context).showSnackBar(...)` con
    "Compartidos: muy pronto."/"Ajustes: muy pronto." (usa el
    `snackBarTheme` ya configurado globalmente, no un estilo ad hoc) — el
    ítem sigue visible en la barra (ícono + label), nunca navega a nada ni
    crashea. **Marcado para una futura spec de Kiro**: cuándo/si estas dos
    secciones existen de verdad.
- **Glass descartado de entrada para el "+" central** — se aplicó
  directamente la lección ya documentada arriba ("FAB de 'crear álbum':
  de glassmorphism a relleno sólido con gradiente"): un efecto glass sobre
  el lienzo Paper liso es casi invisible; el "+" usa
  `signatureGradient` sólido + `BoxShadow` desde el primer intento, sin
  repetir el experimento fallido.
- **Decisión no trivial, marcada para revisión en dispositivo**: la
  geometría exacta del solape del botón central sobre la barra
  (`SizedBox(height: 78)` conteniendo un `Container` de 64px alineado abajo
  + el botón de 56px en `Positioned(top: 0)`, dando ~42px de superposición
  visual) se ajustó a ojo sin poder verla en un dispositivo real — mismo
  caveat que el asset decorativo del hero de arriba.

### 4. Corrección post-feedback en dispositivo real: fondo oscuro continuo, no card encajonada

El usuario probó la sección 1 en su celular contra el mockup original y dio
2 correcciones puntuales (sin spec de Kiro, mismo canal directo que el resto
de este bloque). Alcance: **solo `lib/screens/home_screen.dart`** — ningún
controller/`*Api`/modelo tocado, ninguna otra pantalla.

1. **El gradiente oscuro no puede ser una card "encajonada" sobre fondo
   blanco — tiene que ser el fondo de TODA la zona superior** (header con
   logout + badge "Backend: ok", fila de avatar+nombre+email, Y el contenido
   del hero de "Álbumes", sin ningún blanco entre ellos; recién donde
   empieza "Unirme a un álbum" pasa a `Paper`). Antes, `_AlbumsActionBlock`
   era una card oscura AISLADA (`ClipRRect(MemoraRadius.hero)`, altura fija
   280) flotando dentro del `SingleChildScrollView` de fondo `Paper` de
   `_AuthenticatedDashboard`, con el header (logout/badge) renderizado por
   separado en `_HomeScreenState.build` sobre un fondo Paper distinto —
   exactamente el "encajonado" que el usuario señaló.
   - **Fix**: `_HomeScreenState.build` ya no renderiza el header/Expanded
     compartido para el estado `authenticated` — le delega el `Scaffold
     .body` COMPLETO a `_AuthenticatedDashboard` (antes solo recibía el
     `Expanded` del medio). `_AuthenticatedDashboard` es ahora un `Column`
     de dos piezas: `_DashboardDarkZone` (nuevo widget — header + avatar +
     `_AlbumsHeroContent`, envueltos en un `Container` con el mismo
     `RadialGradient`/`_AlbumsHeroGlow` que antes tenía solo la card, más
     `SafeArea(bottom: false)` para que el fondo se extienda detrás de la
     statusbar sin que el contenido quede pegado ahí — mismo truco que
     `_WelcomeHeroBackdrop`) seguido de un `Expanded` con fondo `Paper`
     (`ColoredBox`) para Unirme/Fotos/nota manuscrita.
   - **`_AlbumsActionBlock` → `_AlbumsHeroContent`**: perdió el `ClipRRect`,
     el `DecoratedBox` de gradiente, `_AlbumsHeroGlow` (ambos se movieron a
     `_DashboardDarkZone`, pintados UNA vez para toda la zona) y el
     `SizedBox(height: 280)` fijo — ahora es puramente el contenido
     (eyebrow+headline+asset+flecha+dots) sobre el fondo compartido,
     dimensionado por su propio contenido (`mainAxisSize.min`).
   - **Altura de la zona oscura: calculada por contenido, no fija/pixel
     math** — deliberado, siguiendo el brief ("un `Container` que crezca con
     su contenido" en vez de `Positioned` con matemática de altura). El
     `Container` de `_DashboardDarkZone` no tiene `height` ni vive dentro de
     un `Stack`/`Positioned` — es simplemente el primer hijo de un `Column`
     normal, así que su fondo se estira exactamente lo que ocupe su propio
     `Padding`+`Column` (header + avatar + hero). Esto también evita el
     riesgo de que un nombre largo (avatar+email en 2 líneas) o una
     resolución de pantalla distinta desalineen un alto fijo calculado a
     mano.
   - **Header/avatar recalibrados para fondo oscuro** (antes vivían sobre el
     `Paper` del dashboard, con el tema ambient/Deep Ink ya correcto por
     defecto): el `IconButton` de logout ahora pasa `color: MemoraColors
     .paper` explícito al ícono; `textTheme.headlineSmall`/`.bodySmall` del
     nombre/email de `_InitialsAvatar`'s fila reciben `?.copyWith(color:
     MemoraColors.paper)`/`MemoraColors.paper.withValues(alpha: 0.75)` —
     mismo criterio de opacidad reducida para el texto secundario que ya usa
     `_HeroHeadline`'s subtítulo sobre el hero photo del Welcome. El badge de
     conectividad se sigue construyendo con `_buildConnectivityBadge(onDark:
     ...)` (ya existía, sin cambios de firma) — ahora se le pasa `true`
     siempre que el estado es `authenticated` (antes solo era `true` para
     `showHero`/Welcome).
   - **Transición dark→light: corte simple, sin curva** — pedido explícito
     del usuario ("no hace falta transición sofisticada"). Es literalmente
     el borde entre dos hijos de un `Column` (`_DashboardDarkZone` seguido
     del `Expanded`/`Paper`), sin `ClipPath`/gradiente de mezcla entre
     ambos.
2. **"TUS ÁLBUMES" muy pegado al borde superior — más aire.** Se sumó
   `MemoraSpacing.xxl` (48, antes el hueco entre la fila de avatar y el
   hero dependía indirectamente del padding interno de la card vieja) entre
   la fila de avatar y `_AlbumsHeroContent`, y `MemoraSpacing.md` como
   separación entre el header (logout/badge) y la fila de avatar — ambos
   con tokens de `MemoraSpacing`, ningún número suelto nuevo.

**Nota real para quien toque este archivo después**: el `RadialGradient` de
`_DashboardDarkZone` reusa el mismo `center`/`radius`/colores que tenía la
card vieja (`Alignment(0.9, -0.1)` → se ajustó levemente a `Alignment(0.9,
-0.5)`/`radius: 1.3` porque la zona ahora es bastante más alta que los 280px
originales — sin este ajuste el gradiente se veía casi plano/uniforme en la
mitad superior, con toda la transición violeta→deepInk comprimida en la
franja del hero). Si un futuro cambio hace la zona todavía más alta
(p. ej. agregando más contenido al header), revisar visualmente si estos
valores siguen dando la sensación de "glow concentrado arriba-derecha" o si
hace falta re-ajustarlos — no hay forma de derivarlos algebraicamente del
alto del contenido, se recalibran a ojo.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → **166/166**
pasando sin tocar ningún test existente (el test de `widget_test.dart` para
el estado autenticado no busca el texto exacto del hero de Álbumes, así que
seguir pasando confirma que nada rompió esa pantalla, pero no es una
aserción nueva sobre el hero/footer/bottom nav en sí — ningún test nuevo se
agregó para estos tres widgets, ya que son 100% composición visual sobre
callbacks/controllers ya cubiertos indirectamente). **El aspecto real del
hero (gradiente radial, asset decorativo, glow), la nota caligráfica y la
barra de navegación inferior en un dispositivo físico no están verificados
en este entorno** (sin dispositivo/emulador) — el usuario debe confirmarlos
corriendo la app. La sección 4 (fondo oscuro continuo sin card encajonada)
tiene la misma limitación: `flutter analyze` sin warnings y `flutter test`
**166/166** siguen pasando tal cual (mismo total, ningún test nuevo — el
cambio es 100% de layout/color sobre widgets/callbacks ya cubiertos), pero
el resultado visual real (que el corte se vea continuo, sin caja blanca, y
que el gradiente se vea bien proporcionado en una pantalla real) no está
verificado sin dispositivo.

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
- El registro NDEF escrito en un chip físico (spec09-programar-nfc.md,
  `NfcProgrammingService`/`buildUriRecord`) contiene **únicamente** la
  `url` del `NfcQrTag` (`https://memora.app/n/{token}`) — nunca fotos,
  nombre del álbum, ids internos ni ningún otro dato. Los mensajes de error
  de `NfcWriteFailedException`/`NfcVerificationFailedException` llevan un
  `detail` opcional pensado solo para depuración local (nunca se muestra
  tal cual en la UI, que usa los mensajes fijos de
  `NfcProgrammingController.statusMessage`) y ese `detail` en sí nunca
  incluye la `url`/`token` — es el `toString()` del error nativo
  subyacente (p. ej. un mensaje de I/O), no datos del tag.

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
- **spec09-programar-nfc.md**: `test/nfc_programming_service_test.dart`
  cubre, sin ningún plugin/canal de plataforma (`NdefMessage`/`NdefRecord`/
  `TypeNameFormat` de `ndef_record` son clases Dart puras), las funciones
  puras de codificación NDEF: `buildUriRecord` (código de abreviación
  correcto por prefijo — prioriza `https://www.` sobre `https://`, cae a
  "sin abreviación" si no reconoce el esquema, nunca escribe nada fuera de
  `type`/`payload`) y `decodeUriRecord`/`messageHasVerifiedUri` (round-trip
  exacto, comparación estricta string-a-string, ignora otros registros no-URI
  del mismo mensaje). `test/nfc_programming_controller_test.dart` cubre
  `NfcProgrammingController` completo contra un `NfcProgrammingService` fake
  (subclase que sobreescribe `checkAvailability`/`writeUrl`/`cancel`/
  `lockReadOnly`, mismo patrón de `AuthController`/`PhotoOptimizer`): el
  camino feliz completo (`waitingForTag` → `writing` → `verifying` →
  `success`), que un tag con contenido previo entra en
  `confirmingOverwrite` y espera a `resolveOverwriteConfirmation` antes de
  escribir, que declinar sobrescribir termina en `cancelled` sin llegar a
  escribir, que `cancel()` mientras se espera un tag refleja `cancelled` de
  inmediato aunque la sesión real nunca confirme que se detuvo (el caso real
  de Android, simulado con un fake cuyo `Future` jamás se resuelve por sí
  solo), que `NfcAvailability.disabled/unsupported` nunca llega a abrir una
  sesión, los 5 casos de error (incompatible/bloqueado/fallo de
  escritura/fallo de verificación/desconocido) cada uno con su propio
  `NfcProgrammingStatus` y mensaje — con un test que verifica que **todos**
  los mensajes de `statusMessage` son distintos entre sí (nunca dos estados
  comparten texto), que `retry()` reutiliza el mismo `NfcQrTag`/`url` (P3),
  y `lockReadOnly` (P2): no-op donde `supportsReadOnlyLock` es `false`
  (simula iOS), éxito donde es `true` (simula Android), y sus dos mensajes
  de error distintos (tag incompatible vs. cualquier otra falla). **No** son
  testeables sin dispositivo: una sesión NFC real (`NfcManager.instance.
  startSession`), acercar un tag físico, la hoja nativa de iOS, y el
  bloqueo físico real a solo lectura (`makeReadOnly`/`writeLock`) —
  documentado igual que el resto de plugins/gestos nativos de esta app; lo
  valida el PO en dispositivo.

### Capability NFC de iOS: verificado por edición de texto, no por Xcode

`ios/Runner/Runner.entitlements` (nuevo) declara
`com.apple.developer.nfc.readersession.formats = [NDEF, TAG]`, y las tres
configuraciones del target `Runner` en `project.pbxproj` (Debug/Release/
Profile) ahora tienen `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;`
— editado a mano (no hay Xcode disponible en este entorno para usar la UI de
"Signing & Capabilities"), verificado por inspección del propio
`project.pbxproj` (no había ningún `CODE_SIGN_ENTITLEMENTS` previo en el
proyecto, así que no se pisó nada existente) y confirmado indirectamente por
`flutter build ios --simulator --no-codesign` (compila y linkea sin errores
de resource/codesign relacionados a NFC). **Lo que este entorno NO puede
verificar**: que Xcode reconozca la capability como "añadida correctamente"
en su UI (el checkbox de "Near Field Communication Tag Reading" bajo
Signing & Capabilities), y sobre todo que el **App ID en el Apple Developer
Portal** tenga habilitado el NFC Tag Reading entitlement para el
`PRODUCT_BUNDLE_IDENTIFIER` real (`app.memora.memoraApp`) — sin eso, un
build firmado para dispositivo real (no simulador) puede fallar el
code-signing o instalar pero con la sesión NFC rechazada en runtime aunque
el entitlements file esté bien formado. Un simulador iOS tampoco tiene
hardware NFC (Core NFC no funciona en absoluto ahí), así que ni siquiera
`flutter run` en simulador puede validar el flujo real — hace falta un
iPhone 7+ físico con un Apple Developer Team que tenga el entitlement
habilitado. Esto queda marcado explícitamente para que el PO lo confirme/
resuelva desde Xcode + el Developer Portal antes de probar en dispositivo
real; no se puede dar por buena esta parte solo por haber editado el XML a
mano.

## Ajuste visual post-feedback: cards con fotos reales, empty state ilustrado, FAB glass, dashboard reestructurado (sin spec de Kiro)

Cuatro pedidos puntuales del usuario tras validar el pivot light-first
(60-30-10) corriendo en su celular. Alcance acotado: `AlbumsController`
(solo el mecanismo de covers, sin tocar nada de spec04-09),
`albums_list_screen.dart`, `home_screen.dart`, `memora_empty_state.dart`,
`pubspec.yaml`. Nada de `AuthController`/`PhotoUploadController`/
`memora-backend`/`memora-web`/`specs/` se tocó.

### 1. Cards de álbum con fotos reales tipo "montaje" — DECISIÓN DE ARQUITECTURA: N+1 aceptado explícitamente

**Marcado para que Kiro lo tenga en cuenta a futuro.** El usuario pidió DOS
VECES ver fotos reales "montadas entre sí" en cada card de álbum de
`AlbumsListScreen`, en vez del stat abstracto (`gradientForAlbumId` +
`photoCount`) que existía desde spec04 porque `AlbumListItem`
(`GET /api/v1/albums`) no trae ninguna foto de portada. Se decidió
resolverlo del lado del cliente, **aceptando explícitamente el costo de una
llamada extra por álbum** (N+1 desde la lista) en vez de esperar a que el
backend agregue un campo de portada al endpoint de lista — si
`memora-backend` alguna vez agrega ese campo (p. ej. `coverPhoto` en
`AlbumListItem`), este mecanismo entero se puede simplificar/eliminar a
favor de leerlo directo de la respuesta de `GET /albums`.

- **`AlbumsController`** (`lib/albums/albums_controller.dart`) gana:
  - `Map<String, List<Photo>> _albumCoverPhotos` — caché en memoria por
    `albumId`, sin expiración ni persistencia a disco (mismo criterio de
    sesión que `DriveThumbnailService`). Expuesto solo por lectura vía
    `List<Photo>? coverPhotosFor(String albumId)`.
  - `loadAlbums()` ahora dispara `unawaited(_loadMissingCovers())` justo
    después de poblar `albums` — **deliberadamente sin esperarlo**: la
    lista debe renderizar de inmediato con el fallback abstracto, y cada
    card se actualiza sola (vía `notifyListeners()`) cuando su cover
    llega. `isLoadingList`/`listErrorMessage` (el camino de carga
    primario) son completamente independientes de esto.
  - `_loadMissingCovers()` calcula qué álbumes necesitan cover
    (`photoCount > 0`, sin cover cacheado, sin fetch ya en vuelo — un
    `Set<String> _coverFetchesInFlight` evita pedir dos veces el mismo
    álbum si `loadAlbums()` se llama de nuevo, p. ej. pull-to-refresh,
    antes de que termine el primer fetch) y los procesa en chunks de
    `_coverFetchConcurrency = 4` con `Future.wait` — **no es un pool/cola
    de concurrencia real**, es deliberadamente simple para el volumen
    típico de álbumes de esta app (un puñado a unas pocas decenas). Si
    algún día el conteo de álbumes crece mucho y esto se vuelve
    problemático (ráfagas de 4 requests simultáneas muy seguidas), la
    solución es un limitador real (p. ej. `package:pool`), no subir este
    número a mano.
  - Cada álbum objetivo llama a **`AlbumsApi.getAlbumDetail`** (el mismo
    método ya usado por `loadAlbumDetail`, nada nuevo en la capa de red) y
    cachea `detail.photos.take(3)`. Un fallo silencioso (`catch (_) {}`)
    deja ese álbum sin cover — la card sigue mostrando el fallback
    abstracto, nunca un estado roto; este fetch es un nice-to-have visual,
    no el camino de carga principal con su propio manejo de error/retry.
  - **Bug real atrapado en tests antes de reportar terminado**: la primera
    versión de `_loadMissingCovers` construía la lista de álbumes-objetivo
    como un `Iterable` perezoso (`albums.where(...)`) y lo iteraba DOS
    veces — una para juntar los ids y agregarlos a
    `_coverFetchesInFlight`, otra (`.toList()`) para construir la cola a
    procesar. Como el predicado de `where` lee `_coverFetchesInFlight`, la
    segunda iteración volvía a evaluar la condición **después** de haber
    agregado esos mismos ids al set — filtrando todo de vuelta a una lista
    vacía y dejando la cola siempre en `[]` (cero requests, sin error
    visible). Se descubrió porque el test nuevo
    (`test/albums_controller_covers_test.dart`) fallaba con "0 llamadas
    esperadas". Arreglado materializando la lista con `.toList()` **antes**
    de mutar `_coverFetchesInFlight`. Cualquier código futuro que combine
    un `Iterable` perezoso con un predicado que lee un `Set`/`Map` que ese
    mismo código va a mutar debe materializar (`.toList()`) antes de mutar,
    no asumir que "ya lo recorrí una vez" alcanza.
- **`AlbumsListScreen`** (`lib/albums/screens/albums_list_screen.dart`):
  `_AlbumGridCard` recibe `coverPhotos`/`thumbnailService` nuevos. Cuando
  `coverPhotos` no es null/vacío, el área inferior de la card (antes el
  número grande + "fotos") se reemplaza por `_PhotoMontage`: hasta 3
  miniaturas reales en abanico (`Transform.translate` + `Transform.rotate`,
  offsets/ángulos fijos por posición — nunca aleatorios en cada rebuild,
  para que no "tiemble" al refrescar), cada una envuelta en un marco blanco
  redondeado tipo Polaroid (`_PolaroidPhoto`) con sombra suave. Si no hay
  cover (todavía no llegó, o el álbum no tiene fotos), se mantiene el
  fallback abstracto exacto de antes (`_AbstractStat`, extraído sin cambios
  de comportamiento) — nunca un estado roto/vacío.
  - `_PolaroidPhoto` reutiliza la **misma instancia** de
    `DriveThumbnailService` (y su caché de bytes en memoria) que ya usa
    `album_detail_screen.dart`'s `_PhotoTile`/`_HeroPhotoImage` — cero
    pipeline de descarga nuevo, cero caché nueva. Sigue el mismo patrón
    `late final Future` creado en `initState` + `FutureBuilder` (seguro sin
    `Future.ignore()` porque se observa sincrónicamente en el mismo frame,
    ver el gotcha ya documentado de `photo_viewer_screen.dart`). `key:
    ValueKey(photo.id)` en el call site (`_PhotoMontage`) — mismo patrón
    "key por id" que el resto de la app para widgets con estado async
    propio en una lista.
  - Un fallo de un tile individual (`snapshot.hasError`) muestra un ícono
    neutro (`image_not_supported_outlined`) dentro del marco Polaroid, no
    un hueco vacío ni un crash — el fallback de la card completa
    (abstracto) es independiente de esto y solo aplica cuando NO hay
    ningún cover cacheado.
- **Test nuevo**: `test/albums_controller_covers_test.dart` (mismo patrón
  `_routedClient`/`MockClient` que `albums_controller_test.dart`/
  `albums_controller_sharing_test.dart`) cubre: solo se pide detalle para
  álbumes con `photoCount > 0`; se cachea como máximo 3 fotos aunque el
  álbum tenga más; un fallo del fetch de cover deja `coverPhotosFor` en
  `null` sin tocar `listErrorMessage` ni el resto de la lista; y una
  segunda llamada a `loadAlbums()` no vuelve a pedir un cover ya cacheado.
  **No cubierto con widget test** (ni antes ni ahora existía
  `albums_list_screen_test.dart`): el render real del abanico/Polaroid y
  el fetch de miniaturas vía `DriveThumbnailService` en un `StatefulWidget`
  — se consideró que el controller test cubre la lógica nueva real
  (dónde/cuándo se pide/cachea un cover) con menor costo que levantar
  infraestructura de widget test nueva para una pantalla que nunca la tuvo.

### 2. `MemoraEmptyState` — nuevo parámetro `imageAsset`

`lib/design/widgets/memora_empty_state.dart`: `icon` pasó de requerido a
opcional, y se agregó `imageAsset` (opcional, `String?`) — cuando está
presente, reemplaza el círculo-con-ícono por un `Image.asset` (`width: 220`,
`BoxFit.contain`, con aire alrededor, no full-bleed). Un `assert` exige que
al menos uno de los dos esté presente. Los otros dos call sites existentes
(`album_detail_screen.dart`, sin tocar) siguen pasando `icon:` como antes,
sin cambios de comportamiento. `AlbumsListScreen` es el único call site
nuevo que usa `imageAsset: 'assets/images/empty.png'` para su estado vacío
(cuando `controller.albums.isEmpty`), con copy nueva ("Todo empieza con un
álbum" / "Creá el primero para guardar tus recuerdos.") + el mismo CTA
"Crear álbum" de siempre.

- **`assets/images/empty.png`** (nuevo, 1230x1278px, provisto por el
  usuario tal cual — no editado/comprimido) — declarado en `pubspec.yaml`
  junto a `hero.png`. Ilustración 3D (caja/cesta translúcida + 3 fotos en
  abanico + anillo de luz), usada únicamente en este empty state.

### 3. FAB de "crear álbum" — glassmorphism real

> **REVERTIDO en un ajuste posterior** — ver "Ajuste visual post-feedback en
> dispositivo real: FAB glass ilegible + panel de colaboradores rediseñado"
> al final del archivo. El glass descrito acá resultó casi invisible sobre
> el lienzo Paper en un dispositivo real; se reemplazó por un relleno
> sólido con `signatureGradient`. Se deja esta sección como historia de por
> qué se intentó (y por qué no funcionó) en vez de borrarla.

`AlbumsListScreen`'s FAB pasó del círculo sólido Deep Ink (agregado en el
pivot light-first) a un efecto glass real:
`ClipOval` > `BackdropFilter(ImageFilter.blur(sigmaX: 12, sigmaY: 12))` >
`DecoratedBox` (relleno `MemoraColors.paper` al 28% de opacidad, borde 1px
`paper` al 55%) > `Material`/`InkWell` (para el ripple + `onTap`) > el ícono
"+" en Deep Ink. `FloatingActionButton` no soporta `BackdropFilter` directo
(mismo motivo por el que ya no soporta `gradient` directo, ver el hallazgo
ya documentado de Fase 1), así que el círculo se arma a mano — mismo
espíritu que el truco del FAB con gradiente, pero con blur real en vez de
color. Es una de las pocas excepciones deliberadas a "sin glassmorphism"
del brief original: este FAB flota sobre contenido variable (fotos/cards de
la grilla) y necesita distinguirse sin ser un bloque sólido pesado.

### 4. `HomeScreen._AuthenticatedDashboard` — de "mal dashboard" a 3 bloques apilados y diferenciados

Reestructuración pedida con las palabras exactas del usuario: "tienes
álbumes, Unirme y Fotos ahí como sin un orden lógico, solo puestos ahí como
un mal dashboard [...] las 3 opciones pueden estar una debajo de la otra,
que ocupen cada una el ancho de la pantalla y que se diferencien no que
parezcan 3 tarjetas iguales. Puedes jugar con tonos para diferenciarlas.
Una oscura, una clara y la otra el tono contraste." Antes: "Álbumes"/
"Unirme" eran dos `_QuickAccessCard` idénticas en un `Row` (mitad de ancho
cada una) y "Fotos" era una tercera card, del mismo template, debajo — tres
tarjetas iguales sin jerarquía. `_QuickAccessCard` se eliminó por completo
(sin call sites restantes). Ahora, tres bloques FULL-WIDTH apilados
verticalmente, cada uno una composición distinta (no la misma card
recoloreada):

- **"Álbumes" → `_AlbumsActionBlock`, tono OSCURO** (histórico — esta
  descripción es de la primera iteración con `MemoraCardElevation.ink`;
  reemplazada primero por el hero de gradiente radial ("Ajuste visual
  post-mockup" más abajo) y luego, tras feedback en dispositivo real, por
  `_AlbumsHeroContent` dentro de `_DashboardDarkZone` — ver la sección "4.
  Corrección post-feedback en dispositivo real" bajo ese mismo bloque para
  la versión vigente) —
  `MemoraCardElevation.ink` (fondo Deep Ink, contenido Paper). Es el 10%
  de acento oscuro "protagonista" que el pivot light-first reserva para un
  puñado de momentos (antes solo usado en el estado de éxito de
  `nfc_programming_screen.dart`) — usarlo acá es deliberado: entre las tres
  acciones, "ver tus álbumes" es la que más se toca, así que se lleva la
  superficie de mayor contraste y el ícono/tipografía más grandes de los
  tres bloques (chip de ícono 56px, `headlineSmall`, subtítulo, flecha).
- **"Unirme a un álbum" → `_JoinAlbumActionBlock`, tono CLARO** —
  `MemoraCard` sin elevación especial (`level1`, el tono claro por
  defecto), fila compacta de una sola línea (chip de ícono 36px, sin
  subtítulo) — una acción secundaria/ocasional junto al peso de "Álbumes",
  deliberadamente más chica y silenciosa, no solo "la misma card en otro
  color".
- **"Fotos" → `_PhotosSection`, tono CONTRASTE (gradiente)** — el
  `signatureGradient` como acento fuerte, pero como MARCO/borde grueso (3px,
  mismo truco "borde de gradiente vía padding" que ya usan las cards de
  álbum de `AlbumsListScreen`, porque `MemoraCard`/`BoxDecoration` no
  soportan un borde multicolor directo), no como relleno completo. Decisión
  deliberada: el contenido de este bloque es el más impredecible de los
  tres (lista de items subiendo de largo variable, banners de error,
  botón condicional de reconectar Drive) — un relleno de gradiente
  completo habría obligado a re-verificar el contraste de cada uno de esos
  estados contra un fondo celeste/violeta claro, para el bloque cuyo
  contenido más cambia. El marco da la misma lectura "este es el bloque de
  acento" sin tocar un solo color interno — **el contenido interno (botón
  "Agregar fotos", progreso por foto, errores, prompt de reconectar) queda
  100% intacto**, solo cambió el contenedor/tono alrededor, tal como pedía
  el brief. Se agregó únicamente un chip de ícono con gradiente + el label
  "Fotos" arriba, para que el bloque tenga la misma "personalidad
  compuesta" (ícono + título) que los otros dos sin duplicar su estructura
  exacta.
- Mismos controllers/callbacks exactos (`onOpenAlbums`,
  `onOpenAcceptInvitation`, `photoUploadController`,
  `onReconnectDriveForPhotos`) — cero cambios de lógica, cero cambios en
  `AuthController`/`PhotoUploadController`.

### Verificación

`flutter analyze` sin warnings y `flutter test` (166/166) en verde tras este
ajuste — ver el reporte de la tarea para la salida completa. El login real
con Google, el render real del FAB con blur, y el aspecto real de las cards
con fotos/el dashboard reestructurado en un dispositivo físico **no** están
verificados en este entorno (sin dispositivo/emulador) — el usuario debe
confirmarlos corriendo la app.

## Ajuste visual post-feedback en dispositivo real: FAB glass ilegible + panel de colaboradores rediseñado (sin spec de Kiro)

Dos piezas de feedback puntuales tras probar la versión anterior en un
celular real. Alcance acotado a `lib/albums/screens/albums_list_screen.dart`
(solo `_GlassCreateAlbumFab`) y `lib/albums/screens/album_detail_screen.dart`
(solo la sección de compartir/colaboradores del bottom sheet abierto por
`_openSharingSheet`) — ninguna otra pantalla, ningún controller/`*Api`/modelo
tocado.

### 1. FAB "crear álbum": de glassmorphism a relleno sólido con gradiente

El glass (`BackdropFilter` blur + relleno Paper al 28% + borde Paper al 55%,
documentado arriba en "FAB de 'crear álbum' — glassmorphism real") resultó
**casi invisible en un dispositivo real**: sobre el lienzo Paper (60% del
pivot light-first), el usuario literalmente no distinguía ningún círculo —
solo veía el ícono "+" flotando sin nada alrededor ("fondo claro sobre fondo
claro"). Glass necesita un fondo con contraste real detrás (una foto, una
superficie oscura) para leerse; el lienzo Paper dominante de esta pantalla
no lo tiene. Se sacó el `BackdropFilter`/toda transparencia por completo:
ahora es un círculo con `MemoraColors.signatureGradient` como relleno SÓLIDO,
ícono "+" en `MemoraColors.paper` (blanco) encima, y un `BoxShadow` derivado
de `MemoraColors.deepInk` (alpha 0.28, blur 16, offset (0,6)) para que siga
flotando visualmente sobre el contenido de la grilla debajo. Mismo mecanismo
de construcción a mano (`DecoratedBox` + `Material`/`InkWell` +
`CircleBorder`, `FloatingActionButton` no soporta `gradient` directo) — solo
cambió qué hay dentro del `DecoratedBox`. **Lección para cualquier futuro
efecto glass en esta app**: solo tiene sentido sobre un fondo con contraste
propio (foto, superficie oscura) — nunca sobre el lienzo Paper liso del
pivot light-first, sea cual sea la superficie que quede debajo.

### 2. Panel "Colaboradores y compartir": de filas de texto sueltas a secciones con identidad

Feedback textual del usuario sobre el bottom sheet: **"todo sin vida, sin
orden, puros botones ahi puestos, sin secciones definidas y todo color
claro, parece una hoja de un articulo de oficina."** Antes, `Compartir` y
`Colaboradores` eran dos `MemoraCard(elevation: level2)` con un ícono
monocromo de 18px suelto junto al título, varios `MemoraSecondaryButton` en
un `Wrap` compitiendo entre sí, y una lista de `_PersonRow` (fila de texto +
ícono) por colaborador — sin jerarquía real ni identidad de color entre
secciones. Cambios, mismos controllers/`AlbumsController`/gating
owner-only/`_confirmRevokeShareLink`/etc. exactos, 100% capa visual:

- **`_SectionHeader`** (nuevo, privado a `album_detail_screen.dart`): chip
  circular de 36px con `MemoraColors.signatureGradient` + ícono en
  `MemoraColors.paper` + título con `textTheme.headlineSmall` — el mismo
  lenguaje ya usado por `_QuickAccessCard`/`_InitialsAvatar` de
  `HomeScreen` y el badge de rol de esta misma pantalla, reusado tal cual
  en vez de inventar un lenguaje nuevo. Reemplaza el ícono de 18px suelto
  en las tres sub-secciones (Compartir, Colaboradores, y la vista de
  colaborador "Este álbum").
- **`_sectionTint(Color accent)`** (nueva función top-level): un
  `LinearGradient` diagonal que mezcla `accent` sobre `MemoraColors.paper`
  vía `Color.alphaBlend` (~8% en la esquina superior-izquierda, ~3% en la
  inferior-derecha) — pasado como `MemoraCard.gradient` (el parámetro ya
  existía, pensado justo para esto). "Compartir" usa
  `_sectionTint(MemoraColors.glassBlue)`, "Colaboradores" usa
  `_sectionTint(MemoraColors.auraViolet)` — cada sección del panel ahora
  tiene una identidad de color propia y sutil en vez de que las tres cards
  sean el mismo tono parejo. Deliberadamente NO se usó en la sección de
  colaborador simple ("Este álbum", solo "Abandonar álbum") — es la única
  sub-sección de esta pantalla, no compite por identidad de color con
  ninguna otra, y sumarle un tinte hubiera sido color sin motivo (criterio
  explícito del brief: "con criterio, no sobrecargues").
- **Separación real entre sub-bloques dentro de "Compartir"**: se
  agregaron `Divider(height: 1, color: MemoraColors.border)` entre
  visibilidad / enlace de compartición / etiquetas NFC-QR, en vez de solo
  `SizedBox`. "Compartir" y "Colaboradores" ya eran cada una su propia
  `MemoraCard` con borde (`MemoraColors.border`) — eso no cambió, la queja
  de "sin secciones definidas" apuntaba sobre todo a la falta de jerarquía
  tipográfica/color dentro de cada card, no a que compartieran una sola
  card grande.
- **`_CollaboratorAvatarStack`** (nuevo, privado): reemplaza la lista de
  `_PersonRow` por colaborador (una fila de texto plana con el `userId`
  crudo) por un stack de avatares circulares superpuestos —
  `signatureGradient` de fondo, borde `MemoraColors.paper` de 2.5px para
  distinguir el overlap, iniciales derivadas de las primeras 1-2 letras del
  propio `userId` en mayúsculas (mismo patrón visual que
  `HomeScreen._InitialsAvatar`, pero sin nombre real para derivar
  iniciales — ver la limitación de PII de `CollaboratorListItem`, ya
  documentada arriba y en `README.md`: el backend solo expone `userId`, sin
  nombre ni email). Muestra hasta 6 avatares (`_maxShown`); el resto
  colapsa en un chip "+N" con `MemoraColors.surface2` (neutro, no
  gradiente, porque no representa una persona). **La acción de "quitar" se
  movió de un `IconButton` por fila a tocar el avatar mismo**
  (`onTapCollaborator`, gated por `controller.isMutating` igual que
  antes) — dispara exactamente el mismo diálogo de confirmación
  (`_confirmRemoveCollaborator`) y la misma llamada al controller que ya
  existía, solo cambió dónde vive el gesto. Un texto pequeño debajo del
  stack ("Toca a un colaborador para quitarlo del álbum.") cubre la
  pérdida de affordance del `IconButton` explícito. Las invitaciones
  pendientes (`_PersonRow`, sin cambios en ese widget salvo quitarle el
  parámetro `subtitle` — quedó sin ningún call site tras este cambio y
  `flutter analyze` lo marca como `unused_element_parameter`) siguen como
  lista compacta debajo, separadas del stack de avatares por un `Divider`
  real.
- **Menos botones sueltos en "Compartir"**: el bloque de enlace de
  compartición pasó de dos `MemoraSecondaryButton` (Compartir/Revocar)
  compitiendo en un `Wrap` a una única acción primaria ("Compartir", pill,
  ahora con `Expanded` para ocupar el ancho disponible) + "Revocar" como
  `IconButton` (ícono `link_off`, color `MemoraColors.semanticError`,
  tooltip "Revocar enlace") — mismo `_confirmRevokeShareLink` de siempre.
  El bloque de "Cambiar visibilidad" quedó igual (ya era una sola acción
  secundaria junto al badge, no hacía falta bajarle peso). El `Wrap` de
  "Crear etiqueta QR/NFC/Programar etiqueta NFC" **no se tocó** — no era
  uno de los pares explícitamente señalados en el feedback (Compartir/
  Revocar, Cambiar visibilidad) y las tres acciones ahí son igual de
  válidas como alternativas entre sí (crear tag manual vs. programar
  físicamente), no una primaria+secundarias claras — se dejó como
  candidato para un futuro ajuste si el usuario lo señala explícitamente.
- **`MemoraCard.gradient` ya soportaba un `Gradient` arbitrario** (no solo
  el uso previo de bordes-de-gradiente-vía-padding de
  `album_card_style.dart`/`home_screen.dart`) — `_sectionTint` es el primer
  call site que lo usa como relleno completo de fondo en vez de como marco;
  no hizo falta tocar `memora_card.dart`.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → 166/166 tests
pasando (mismo total que antes de este ajuste; ningún test existente
ejercita el contenido interno del bottom sheet de compartir, así que no
hubo regresiones ni necesidad de tests nuevos — el cambio es 100% capa
visual sobre widgets ya cubiertos indirectamente por
`album_detail_screen_test.dart`, que sigue en verde). El aspecto real del
FAB sólido y del panel rediseñado en un dispositivo físico **no** están
verificados en este entorno (sin dispositivo/emulador) — el usuario debe
confirmarlos corriendo la app.

## Ajuste visual post-feedback en dispositivo real: revert del hero de Home + rediseño completo de `AlbumsListScreen` (sin spec de Kiro)

Dos piezas de feedback tras probar la versión anterior en el celular. Alcance
acotado a `lib/screens/home_screen.dart`, `lib/albums/screens/albums_list_screen.dart`
(reescritura completa) y una extracción nueva,
`lib/design/widgets/aurora_bottom_nav.dart` — ningún controller/`*Api`/modelo
tocado, y **ninguna otra pantalla** (`album_detail_screen.dart`,
`photo_viewer_screen.dart`, `create_album_screen.dart`,
`accept_invitation_screen.dart`, `nfc_programming_screen.dart`,
`drive_reconnect_prompt.dart`, `memora_motion.dart`/`MemoraPageRoute`/
`MemoraSkeleton` quedaron intactos).

### 1. Revert del hero "Álbumes" de `HomeScreen`: de fondo continuo a card contenida

La tarea inmediatamente anterior había extendido el gradiente radial oscuro
para que fuera el fondo de TODA la zona superior (header+avatar+hero, ver "4.
Corrección post-feedback en dispositivo real: fondo oscuro continuo, no card
encajonada" más arriba). El usuario la probó en su celular contra el mockup
original y prefirió la versión anterior: **"TUS ALBUMES se veia mejor como
una tarjeta."** Revertido:

- `_DashboardDarkZone` (el `Container` de fondo oscuro que envolvía header +
  avatar + hero juntos) se eliminó. `_AuthenticatedDashboard` volvió a ser un
  único `ColoredBox(color: paper)` + `SafeArea` + `SingleChildScrollView`
  con TODO su contenido en un solo `Column` sobre el lienzo claro: header
  (logout + badge, colores por defecto del tema — ya no `color: paper`
  forzado) → fila de avatar+nombre (también colores por defecto) →
  `_AlbumsHeroCard` (antes `_AlbumsHeroContent`, sin fondo propio) → Unirme →
  Fotos → nota manuscrita.
- **`_AlbumsHeroCard`** (renombrado desde `_AlbumsHeroContent`) recuperó su
  propio `ClipRRect(MemoraRadius.hero)` + `Container` con el
  `RadialGradient` (`Alignment(0.9, -0.1)`, radius 1.1 — geometría re-ajustada
  para el tamaño de card más chico, ya no la geometría de la zona
  extendida) + `_AlbumsHeroGlow` (ahora clippeada por el `ClipRRect` de la
  card, no por los bordes edge-to-edge de una zona completa) — todo
  contenido dentro de sus propios límites, flotando sobre `Paper` como
  cualquier otro bloque del dashboard. El contenido interno (eyebrow +
  headline con gradiente + flecha + dots) no cambió.
- **Lo que NO se revirtió** (pedido explícito: solo el fondo continuo vuelve
  atrás): el aire extra arriba de "TUS ÁLBUMES" (`MemoraSpacing.xxl` entre
  la fila de avatar y la hero card, `MemoraSpacing.md` entre el header y esa
  fila) — sigue usando tokens de `MemoraSpacing`, ningún número suelto
  reintroducido.
- `_buildConnectivityBadge(onDark: ...)` pasó de `true` a `false` para el
  estado autenticado (el header ya no está sobre fondo oscuro) — sigue
  `true` solo para el Welcome/hero photo sin sesión, que no se tocó.
- **Lección para quien vuelva a tocar este hero**: dos ajustes consecutivos
  de producto ya fueron en direcciones opuestas sobre el mismo elemento
  (card contenida → fondo continuo → card contenida de nuevo). Si un futuro
  pedido vuelve a pedir "que sea todo un fondo continuo", confirmar
  explícitamente con el usuario que es un cambio deliberado y no una
  repetición del experimento ya descartado, antes de reimplementarlo.

### 2. `AlbumsListScreen` — rediseño completo según una referencia visual exacta del usuario (no en el repo)

Reescritura completa del archivo (no un ajuste incremental) para igualar una
referencia visual que el usuario describió en detalle: header con título +
contador, dos círculos de acción arriba a la derecha (búsqueda placeholder +
crear álbum), grid de 2 columnas con foto de portada real full-bleed por
card (ya no el "montaje" de 2-3 fotos en abanico), card promocional al final
de la grilla, y el mismo `AuroraBottomNav` de `HomeScreen` abajo.
`AlbumsController`/`*Api`/modelos: sin cambios — solo se leen métodos que ya
existían.

- **Header (`_AlbumsListHeader`)**: "Mis álbumes" (`headlineMedium`, bold) +
  subtítulo "`{N} álbumes · {M} recuerdos`" — `N = controller.albums.length`,
  `M = controller.albums.fold(0, (sum, a) => sum + a.photoCount)`, calculado
  en cada build (no cacheado, es una suma trivial sobre una lista chica).
  **Sin variante singular** ("1 álbum"/"1 recuerdo") — la referencia del
  usuario mostraba un único formato fijo, no se inventó pluralización
  condicional no pedida.
- **Búsqueda: NO es una feature real de la app** (pedido explícito de no
  implementarla). El ícono de lupa (`_HeaderCircleButton`, círculo neutro
  `surface1`+borde) dispara el mismo patrón `SnackBar` "`$label: muy
  pronto.`" que ya usaban Compartidos/Ajustes del bottom nav — mismo texto
  exacto, mismo mecanismo (`ScaffoldMessenger`), para consistencia. El
  círculo de "+" (`_HeaderCircleButton(gradient: true)`, `signatureGradient`
  + ícono Paper) hace exactamente lo mismo que el FAB de crear álbum hacía
  antes (`Navigator.push` a `CreateAlbumScreen`) — **el FAB flotante se
  eliminó, esta acción se mudó arriba, sin duplicarla**. `_GlassCreateAlbumFab`
  (el FAB de la tarea anterior, ver la sección de arriba sobre su fix de
  glass→sólido) quedó completamente eliminado de este archivo — la lección
  documentada sobre glass-sobre-Paper sigue siendo válida para cualquier
  futuro uso, solo que este call site concreto ya no existe.
- **Cards de álbum (`_AlbumGridCard`) — una sola foto real, full-bleed, sin
  montaje**: usa `AlbumsController.coverPhotosFor(albumId).first` (nunca las
  hasta-3 fotos que ya cacheaba el mecanismo de covers de la tarea
  anterior — el N+1/caché en memoria/chunks de 4 sigue exactamente igual,
  esta tarea solo cambió CUÁNTAS de esas fotos ya cacheadas se pintan: 1 en
  vez de hasta 3). `_PhotoMontage`/`_PolaroidPhoto` (el abanico rotado tipo
  Polaroid) se **eliminaron por completo** del archivo — no se dejaron sin
  usar (hubieran quedado marcados `unused_element` por el analyzer); si algún
  futuro diseño quiere ese efecto en otro lado, hay que reimplementarlo, el
  código de referencia está en el historial de git de este archivo antes de
  este commit. `_AlbumCoverImage` (nuevo, reemplaza `_PolaroidPhoto`) sigue
  el mismo patrón `late final Future` + `FutureBuilder` +
  `key: ValueKey(photo.id)` en el call site — misma
  `DriveThumbnailService`/caché en memoria que el resto de la app, cero
  pipeline nuevo.
- **Tres estados de portada distintos, NO dos** — gotcha real a preservar:
  - `item.photoCount == 0` (el álbum genuinamente no tiene fotos):
    `_NoPhotosCoverArea` — card oscura (`MemoraColors.deepInk` como fondo del
    área de portada, no toda la card completa: el nombre/badge/contador
    siguen debajo en la zona clara habitual) con un chip circular de
    gradiente + ícono `Icons.photo_library_outlined` + "Aún no hay fotos" +
    "Agrega recuerdos para que este álbum cobre vida." — reemplaza el
    fallback abstracto `_AlbumCoverPlaceholder`/`gradientForAlbumId` que
    existía antes para TODO álbum sin cover resuelto (loading incluido).
    **Decisión de interpretación, no 100% literal del brief** (documentada
    acá por si Kiro quiere ajustarla): "la card es oscura" se interpretó
    como "el área de portada es oscura", no "toda la card pasa a ser un
    bloque oscuro sin nombre/badge/contador visibles" — se mantuvo la
    estructura de card uniforme (portada + metadata debajo) para los tres
    estados, en vez de una card con layout completamente distinto solo para
    este caso.
  - `item.photoCount > 0` y `coverPhotosFor(id)` ya resolvió (cover
    cacheado): `_AlbumCoverImage` con la primera foto.
  - `item.photoCount > 0` pero el cover todavía no llegó (fetch en curso,
    mismo mecanismo async de `_loadMissingCovers`): `MemoraSkeleton` liso —
    **nunca** el estado "Aún no hay fotos", que sería engañoso para un álbum
    que sí tiene fotos. Confundir estos dos casos fue explícitamente
    señalado como error a evitar en el brief de esta tarea.
  - `gradientForAlbumId`/`album_card_style.dart` **no se tocaron** — siguen
    existiendo y siguen usados por `album_detail_screen.dart` (su propio
    fallback de hero sin fotos) y su test dedicado; simplemente
    `albums_list_screen.dart` dejó de importarlos.
- **Menú "···" (`_openAlbumOptions`) — Renombrar y Eliminar SÍ quedaron
  wireados, no solo "Abrir álbum"**: el mecanismo de
  `AlbumsController.renameCurrentAlbum`/`deleteCurrentAlbum` opera sobre un
  "álbum actual" que hoy solo se puebla vía `loadAlbumDetail(albumId, role:
  role)` (el mismo que usa `album_detail_screen.dart` al entrar). Se
  reutilizó tal cual, sin inventar ningún método de controller nuevo:
  - `_loadAsCurrentAlbum(item)` (nuevo, privado a esta pantalla): muestra un
    diálogo de carga no descartable (mismo patrón que
    `promptDriveReconnect`), llama `controller.loadAlbumDetail(item.id,
    role: item.role)`, lo cierra, y devuelve `true`/`false` según
    `detailErrorMessage`. Se llama ANTES de mostrar el diálogo de
    renombrar/confirmar-eliminar.
  - El diálogo de renombrar replica exactamente el de
    `AlbumDetailScreen._renameAlbum` (mismo copy, **sin** `autofocus: true`
    — el gotcha de `showDialog`+`TextField` ya documentado arriba sigue
    aplicando literalmente al mismo tipo de diálogo). El de eliminar replica
    el de `AlbumDetailScreen._deleteAlbum` (mismo copy D16: las fotos NO se
    borran).
  - **Gotcha real encontrado**: `renameCurrentAlbum` (vía
    `AlbumsController._updateCurrentAlbum`) solo refresca
    `loadAlbumDetail`, **no** la lista (`albums`) — a diferencia de
    `deleteCurrentAlbum`, que sí llama `loadAlbums()` internamente en éxito.
    Sin un refresco explícito, esta pantalla habría seguido mostrando el
    nombre viejo en la card hasta el próximo pull-to-refresh casual. Se
    agregó `await widget.controller.loadAlbums()` explícito tras un rename
    exitoso desde esta pantalla — `_deleteAlbumFromList` NO lo necesita (el
    controller ya lo hace).
  - Owner-only: "Renombrar"/"Eliminar" solo aparecen en el bottom sheet si
    `item.role == AlbumRole.owner` — mismo criterio (oculto, no
    deshabilitado) que el resto de acciones de administración de la app.
- **`AuroraBottomNav`** (extraído a `lib/design/widgets/aurora_bottom_nav.dart`,
  exportado desde `design.dart`): antes vivía como `_AuroraBottomNav`/
  `_NavBarItem`/`_CentralAddButton`, privados a `home_screen.dart`. Ahora es
  público, parametrizado por `activeTab` (`AuroraNavTab.home`/`.albums`) y
  callbacks `onTapHome`/`onTapAlbums`/`onAddPhotos` — el ítem que coincide
  con `activeTab` se renderiza activo sin `onTap` (ya está en esa pantalla);
  el otro recibe su callback. `HomeScreen` pasa `activeTab: home,
  onTapAlbums: _openAlbums` (`onTapHome` queda null). `AlbumsListScreen`
  pasa `activeTab: albums, onTapHome: () => Navigator.of(context).maybePop()`
  (`onTapAlbums` queda null) — **decisión de navegación no trivial**: esta
  pantalla ya no tiene `AppBar`/botón de volver propio (ver el punto
  siguiente), así que "Inicio" en su bottom nav hace de botón de volver
  implícito, haciendo pop hacia el `HomeScreen` que siempre está debajo en
  el stack (`AlbumsListScreen` solo se abre vía `Navigator.push` desde ahí).
  El "+" central sigue llamando exactamente
  `photoUploadController.pickAndUploadPhotos()` en ambas pantallas — mismo
  método, cero flujo nuevo.
- **Sin `AppBar`** (antes esta pantalla tenía una oscura con el título "Tus
  álbumes"): el nuevo header vive dentro del body, como en la referencia. La
  navegación hacia atrás depende del gesto/botón de sistema (`Navigator.pop`
  sigue funcionando sin `AppBar`) y del ítem "Inicio" del bottom nav
  (arriba). **No se marcó esto como ambigüedad de producto** porque es un
  detalle de implementación de bajo riesgo (no cambia ningún contrato ni
  comportamiento de datos), pero si en algún dispositivo/gesto de Android
  específico la ausencia de un botón de volver visible resulta confusa,
  es el primer lugar a revisar.
- **Limitación de datos conocida, NO inventada**: la referencia visual del
  usuario mostraba una descripción/caption corta por álbum (algo como
  "Pequeños grandes momentos ♡" superpuesto a la foto). Ni `AlbumListItem`
  ni `AlbumDetail` (`lib/albums/album_models.dart`) tienen ningún campo de
  texto libre más allá de `name` — **no se agregó ese texto decorativo ni se
  inventó un campo nuevo**. Si el backend agrega algo así en el futuro
  (spec de Kiro), esta card es donde iría, debajo/superpuesto a la foto de
  portada.
- **Test widget**: sigue sin existir `albums_list_screen_test.dart` (ya era
  así antes de esta tarea — ver la nota de la sección de "cards con fotos
  reales" más arriba sobre por qué no se levantó infraestructura de widget
  test nueva para esta pantalla). El comportamiento de
  `AlbumsController.renameCurrentAlbum`/`deleteCurrentAlbum`/
  `loadAlbumDetail` que el nuevo menú "···" reutiliza ya está cubierto por
  `albums_controller_test.dart`/`album_detail_screen_test.dart` (que ejercen
  los mismos métodos desde el otro lado). `flutter test` completo (166/166,
  mismo total que antes) confirma que nada del resto de la app se rompió.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → **166/166** pasando
(mismo total exacto que antes de esta tarea — ningún test nuevo, ninguna
regresión). El aspecto real del hero contenido de Home, del nuevo diseño
completo de `AlbumsListScreen` (header, grid de covers reales, card
promocional, bottom nav compartido) y el comportamiento táctil del menú
"···"/diálogos en un dispositivo físico **no** están verificados en este
entorno (sin dispositivo/emulador) — el usuario debe confirmarlos corriendo
la app.

## Mockup redesign: tabs inline + menú overflow del owner (sin spec de Kiro)

Rediseño estructural de `album_detail_screen.dart` a partir de una referencia
visual nueva del usuario (mockup, no en el repo — descrita en detalle en el
prompt de la tarea, no es el estado real previo de la app). Cambio de
estructura, no solo de color: el `showModalBottomSheet` de
Compartir/Colaboradores (ver la sección de arriba, ahora OBSOLETA en esa
parte) se eliminó por completo a favor de 3 tabs (pills) inline debajo del
hero, el AppBar pasó de "1 ícono de personas + 3 íconos owner-only sueltos" a
"3 círculos" (2 triggers + 1 menú overflow owner-only), y el hero ganó una
fila de metadata (conteo de fotos + fecha de creación). Alcance: solo
`lib/albums/screens/album_detail_screen.dart` +
`lib/design/widgets/memora_segmented_tabs.dart` (nuevo, ver abajo) +
`lib/design/design.dart` (export). Ningún controller/`*Api`/modelo cambió —
todos los gotchas ya documentados (key-por-id+epoch, owner-only, `autofocus`
prohibido, distinción de errores de Drive) se preservaron intactos.

- **AppBar: de 4 íconos sueltos a 3 círculos** (`_HeroAppBarCircleIcon`,
  privado a este archivo): un círculo translúcido Deep Ink (alpha ~0.38)
  detrás de cada ícono Paper — mismo lenguaje "chip sobre foto" que
  `_PhotoCountBadge`, solo circular en vez de pill. Dos triggers simples
  (constructor default) — "Colaboradores" (`person_add_alt`, ambos roles) y
  "Compartir" (`ios_share_outlined`, **solo owner**) — que únicamente hacen
  `setState(() => _activeTab = ...)`, más un `PopupMenuButton` owner-only
  (constructor nombrado `.menu`) con 3 `PopupMenuItem` (Renombrar/Cambiar
  visibilidad/Eliminar álbum) que llaman los mismos
  `_renameAlbum`/`_changeVisibility`/`_deleteAlbum` de siempre — la clase
  `_AppBarActionIcon` (los 3 íconos sueltos con spinner individual) se borró
  por completo, ya no queda ningún call site. **Decisión no trivial, no
  pedida explícitamente por el brief pero necesaria dada una regla dura ya
  documentada**: el trigger "Compartir" del AppBar, y por lo tanto también el
  tab "Compartir" en sí, **solo existen para el owner** — la sección
  Compartir (M7/M8) es 100% owner-only desde spec07 (regla dura, ver la
  sección de spec07 más arriba), así que mostrarle ese tab a un
  `collaborator` abriría contenido vacío. El tab "Colaboradores" sí existe
  para ambos roles (igual que el trigger de personas ya existía para ambos
  antes de esta tarea) — un `collaborator` ve ahí su única acción
  ("Abandonar álbum", `_buildCollaboratorSection`, sin cambios).
- **3 tabs pill (`MemoraSegmentedTabs`, nuevo,
  `lib/design/widgets/memora_segmented_tabs.dart`, exportado desde
  `design.dart`)**: fila de píldoras de igual ancho, la activa con
  `MemoraColors.signatureGradient` de fondo + texto/ícono Paper, las
  inactivas con `surface1` + borde `border` + texto/ícono `textSecondary`.
  **Se agregó a `lib/design/widgets/` (no privado a este archivo)** porque un
  segmented control de 3(+) píldoras con ícono+label es un patrón
  genéricamente reutilizable, no algo específico de esta pantalla — a
  diferencia de `_HeroAppBarCircleIcon`/`_HeroMetadataRow`, que sí quedaron
  privados a `album_detail_screen.dart` por ser demasiado específicos del
  hero de esta pantalla (el círculo translúcido sobre foto, la fila
  ícono+"N fotos"+ícono+fecha). `MemoraSegmentedTabs` NO es un
  `TabBar`/`TabController` — no hay `PageView`/swipe detrás; es solo la fila
  de píldoras, la pantalla que la usa sigue siendo dueña de qué significa
  "activo" y de swapear su propio contenido (mismo patrón que
  `AuroraBottomNav`, que tampoco es un `BottomNavigationBar` real).
  `AlbumDetailScreen` arma la lista de tabs dinámicamente
  (`[photos, collaborators, if (_isOwner) sharing]`) — nunca hardcodea 3 tabs
  fijos, por la razón de arriba (owner-only).
- **El contenido de cada tab vive inline en el body, no en un sheet**: el
  `CustomScrollView` ahora tiene el hero, la fila de tabs, los banners de
  error/reauth (comunes a cualquier tab, ya que una mutación puede disparar
  desde cualquiera), y luego un `switch (activeTab)` que renderiza
  `_buildPhotosTabSliver`/`_buildOwnerCollaboratorsSection` o
  `_buildCollaboratorSection`/`_buildSharingSection` — **los 3 últimos son
  exactamente los mismos métodos/widgets que ya existían para el sheet
  (`_buildOwnerCollaboratorsSection`, `_buildCollaboratorSection`,
  `_buildSharingSection`), sin cambios de comportamiento, solo reubicados**.
  **El gotcha del `ListenableBuilder` del sheet (documentado arriba, "el
  `setState` del padre no reconstruye el contenido del sheet") YA NO
  APLICA**: al vivir inline en el mismo árbol de `AlbumDetailScreen`, una
  mutación disparada desde cualquier tab (revocar, quitar colaborador,
  deshabilitar etiqueta) refresca el controller, que ya dispara
  `widget.controller.addListener(_onChanged)` → `setState(() {})` de la
  pantalla completa — el `CustomScrollView` entero se reconstruye con datos
  frescos sin necesidad de ningún `ListenableBuilder` adicional. La
  `CustomScrollView` está keyed por `'content-${activeTab.name}'` (dentro del
  `AnimatedSwitcher` de `build`, que ya existía para loading/error/content):
  cambiar de tab resetea el scroll a 0 (no arrastra un offset de otro tab) y
  de paso hace un crossfade de 300ms entre tabs — gratis, reusando el mismo
  `AnimatedSwitcher`, sin animación nueva a mano.
- **Header de "Fotos" con orden funcional
  (`_buildPhotosTabSliver`/`_PhotoSortOrder`)**: "Fotos" (bold,
  `titleMedium` + `FontWeight.w800`) a la izquierda, un `PopupMenuButton` a
  la derecha ("Más recientes"/"Más antiguas" + `keyboard_arrow_down`).
  **`_sortedPhotos(photos)`** (método de `_AlbumDetailScreenState`) es
  **puramente de presentación — nunca toca `AlbumsController`/
  `detail.photos`**: ordena por `Photo.capturedAt` (descendente por defecto =
  "Más recientes"; el control alterna a ascendente), con las fotos de
  `capturedAt == null` siempre al final, EN CUALQUIER dirección de orden.
  **Detalle no trivial**: `List.sort` de Dart no garantiza estabilidad, así
  que en vez de confiar en eso, se ordenan pares `(índiceOriginal, photo)` y
  se usa `índiceOriginal` como desempate explícito cuando dos fotos empatan
  (ambas `null`, o el mismo `capturedAt` exacto) — así dos fotos sin fecha
  nunca se reordenan entre sí solo porque cambió la dirección del sort, ni
  dependen de qué tan estable resulte ser el algoritmo de sort subyacente.
  El grid, `_openPhotoViewer` (ahora recibe la lista+índice explícitos en vez
  de leer `widget.controller.albumDetail!.photos` internamente) y el
  `key: ValueKey('${photo.id}#$_epoch')` de cada tile usan `sortedPhotos` —
  el visor de foto a pantalla completa (spec08) navega en el MISMO orden que
  el grid está mostrando. El hero (`_AlbumHero`) sigue usando
  `detail.photos.first` SIN ordenar (la primera foto registrada, criterio
  preexistente sin cambios) — el sort es solo para la presentación del grid
  del tab "Fotos", no para qué foto protagoniza el hero.
- **Metadata del hero (`_HeroMetadataRow`, nuevo widget privado)**: debajo
  del badge de rol, una fila con ícono + "`N` foto(s)" e ícono + "Creado el
  `fecha`" — mismo `MemoraTypography.legibilityShadows` que el título del
  hero, a menor `intensity` (0.7) por ser texto más chico. **Fecha
  formateada a mano en español** (`_formatDateEs`, top-level, privada a este
  archivo — ej. "12 sep. 2026"): array fijo de 12 abreviaturas de mes en
  español (`ene.`...`dic.`), sin agregar ningún paquete de formato de
  fechas, tal como pedía el brief. Distinta de
  `_AlbumDetailScreenState._formatDate` (que sigue siendo `dd/mm/yyyy`, usada
  para expiración de invitaciones/etiquetas en otras partes de esta misma
  pantalla — no se tocó, ni se intentó unificar los dos formatos). Nótese que
  el `_PhotoCountBadge` que ya existía (el pill que desborda la costura del
  hero) **no se tocó ni se quitó** — sigue mostrando el mismo conteo en un
  lugar distinto (la costura, no el overlay de texto); hay redundancia visual
  deliberada entre ambos, tal como lo pedía la referencia.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → **168/168**
pasando (166 previos + 2 nuevos: orden de `_sortedPhotos`
descendente/ascendente con `capturedAt == null` al final en ambas
direcciones, y que tocar el trigger "Colaboradores" del AppBar cambia el tab
activo y muestra "Abandonar álbum" para un `collaborator`). El test
preexistente de confirmación de borrado de foto
(`album_detail_screen_test.dart`) siguió pasando sin cambios de aserciones —
localiza el botón "×" por ícono, no por la estructura del AppBar/sheet que
cambió. **Gotcha de test descubierto acá**: `SliverGrid.builder` es lazy —
con el viewport por defecto de `flutter_test` (mucho más bajo que un celular
real, y esta pantalla ya ocupa buena parte con hero+tabs+header antes de
llegar a la grilla), una fila de la grilla puede quedar fuera del área
construida y `find.byKey`/`tester.getTopLeft` no la encuentran (no es que el
widget esté oculto: directamente no fue instanciado por el builder). El test
de orden de fotos fija un viewport alto
(`tester.view.physicalSize = const Size(800, 2400)`, con
`addTearDown(tester.view.resetPhysicalSize)`/`resetDevicePixelRatio`) para
que las 2 filas de 3 fotos queden construidas sin necesidad de scrollear —
cualquier test futuro que necesite verificar posición/orden de ítems en una
grilla lazy con pocos ítems debería considerar el mismo ajuste en vez de
asumir que el viewport por defecto alcanza. El armado visual real (los 3
círculos del AppBar, el segmented control, la fila de metadata del hero) y
el toque en dispositivo físico **no** están verificados en este entorno (sin
dispositivo/emulador) — el usuario debe confirmarlos corriendo la app.

## Restyle de "Compartir"/"Colaboradores" según referencia `colaboradores.png` (sin spec de Kiro)

Tarea explícitamente de RESTYLE, no de re-arquitectura: el usuario fue
explícito ("las referencias visuales son para que tomes y modifiques la ui
no la logica") — los 3 tabs inline (`MemoraSegmentedTabs`) de la sección
anterior **se quedan tal cual**; solo cambió el contenido visual de los tabs
"Compartir" y "Colaboradores" (`lib/albums/screens/album_detail_screen.dart`)
más un asset nuevo. Ningún controller/`*Api`/modelo cambió — cada acción
sigue llamando exactamente el mismo método de `AlbumsController` que antes,
solo cambió cómo se ve.

- **Tab "Compartir" (`_buildSharingSection`)**: el header ganó `subtitle`
  ("Controla quién puede ver y agregar fotos.") + una **`_VisibilityPill`**
  tappable a la derecha (🔒/🌐 + "Álbum privado"/"Álbum público" + chevron)
  que llama `_changeVisibility` — la MISMA acción que ya vivía en el menú
  "···" del AppBar, ahora alcanzable también desde acá (sin acción nueva). El
  bloque del enlace se separó en su propio método
  **`_buildShareLinkCard`**: ícono en chip circular con
  `signatureGradient` + "Enlace de compartición" + descripción, y — cuando
  no existe enlace — una **`_GradientPillButton`** ("Obtener enlace") nueva
  (ver nota de diseño abajo); cuando ya existe, el mismo `SelectableText` +
  "Compartir"/revocar de siempre, solo dentro de esta card en vez de sueltos.
  Los 3 `MemoraSecondaryButton` en `Wrap` (Crear QR/Crear NFC/Programar NFC)
  se reemplazaron por **`_buildQuickShareRow`**: una fila de 4
  `_QuickShareItem` (ícono en chip circular `surface2` + label, separados por
  una línea vertical `MemoraColors.border` de 1px) — los primeros 3 llaman
  exactamente los mismos handlers de antes (`_createTag`/`_programNfcTag`);
  el cuarto, **"Compartir en otras apps", es la única wiring nueva**
  (`_shareInOtherApps`): si no hay `shareLink` todavía lo obtiene/crea
  (`loadOrCreateShareLink`, la misma llamada que "Obtener enlace") y después
  dispara el mismo `SharePlus.instance.share(ShareParams(text: link.url))`
  ya usado en 2 lugares de esta pantalla — ninguna API/mecanismo de compartir
  nuevo. Las tarjetas de etiquetas creadas en la sesión (`_buildTagCard`) NO
  se tocaron.
- **Tab "Colaboradores" (`_buildOwnerCollaboratorsSection`)**: **el
  `_CollaboratorAvatarStack` (círculos superpuestos) se ELIMINÓ por completo**
  y se reemplazó por una lista de **`_EntityRow`** (una fila completa por
  entidad: avatar + título + subtítulo + badge + menú "···") — pedido
  explícito del usuario al ver esta nueva referencia, revirtiendo el
  avatar-stack introducido en el ajuste post-feedback anterior. Tres usos de
  `_EntityRow` en esta pantalla:
  1. **La fila del usuario actual** (fija, siempre primera, sin menú "···" —
     no puede quitarse a sí mismo): título = `widget.authController.user`'s
     `name` (si no está vacío) o si no `email` — dato YA disponible en esta
     pantalla, sin llamada nueva — con una etiqueta "Tú" al lado del título
     y badge "Owner". **Esta sección solo se construye para `_isOwner`
     (gating preexistente, sin cambios)**, así que esta fila fija siempre
     representa al owner — nunca hace falta resolver el caso "colaborador
     viendo su propia fila" acá.
  2. **Una fila por cada `controller.collaborators`** (verificado contra
     `CollaboratorsService.list`/`listCollaborators` en `memora-backend`:
     este endpoint nunca incluye al owner, solo memberships con
     `role: 'collaborator'` — la fila fija de arriba y este loop nunca se
     solapan). Como `CollaboratorListItem` solo trae `userId` (limitación de
     backend ya documentada varias veces en este archivo), el título es el
     label genérico **"Colaborador"** (nunca un nombre inventado), badge
     "Colaborador", subtítulo "Puede ver y agregar fotos", avatar con
     iniciales derivadas del `userId` (**`_initialsFromId`**, función libre
     — misma lógica que tenía `_CollaboratorAvatarStack._initialsFor` antes
     de borrarse esa clase) y menú "···" con "Quitar" →
     `_confirmRemoveCollaborator` (mismo diálogo de confirmación de siempre).
  3. **Una fila por cada invitación pendiente** (`pendingInvitations`, sin
     cambios en el filtro): avatar = ícono de sobre (`avatarIcon`, no
     iniciales), título **"Invitación pendiente"**, subtítulo "Expira el
     `fecha`" (mismo `_formatDate`), badge "Pendiente", menú "···" con
     "Revocar" → `_confirmRevokeInvitation`. El título del bloque ganó un
     `MemoraBadge` con el conteo (`'${pendingInvitations.length}'`) al lado,
     per la referencia.
  - **`_personInitials`/`_initialsFromId`** (top-level, privadas a este
    archivo): la primera deriva iniciales de un nombre real (o su fallback
    de email) — solo usada para la fila del usuario actual; la segunda es la
    función que ya existía para derivar iniciales de un `userId` opaco. Se
    mantienen separadas a propósito — nunca usar `_initialsFromId` sobre un
    nombre real ni viceversa, cada una asume una fuente de datos distinta.

### Dato de la spec de esta tarea que resultó ser incorrecto (marcado para Kiro)

El brief de esta tarea decía mostrar, en cada invitación pendiente, "email
real (`Invitation.email`, esto SÍ es un dato real que ya tenemos)". **Es
falso, verificado contra el modelo real**: ni
`lib/albums/collaborator_models.dart`'s `InvitationListItem` ni el backend
(`memora-backend/src/albums/collaborators/invitations.service.ts`'s
`InvitationListItem`/`InvitationCreated`) tienen NUNCA un campo `email` — el
flujo de invitación de esta app es por enlace/token (D12), no por dirección
de correo, y el backend nunca pide ni guarda un email al crear una
invitación. Siguiendo la regla dura de este archivo ("no inventar datos que
el backend no da"), la fila de invitación pendiente NO muestra ningún email
— usa el título genérico "Invitación pendiente" en su lugar (ver arriba).
**Marcado para revisión de Kiro**: si se quiere mostrar el email real del
invitado en el futuro, hace falta una spec de backend que agregue captura de
email al crear la invitación (cambiaría el flujo de "por enlace" a "por
enlace + email", una decisión de producto, no solo de UI).

### Nota de diseño no trivial: `_GradientPillButton` es una segunda CTA con gradiente (marcado para Kiro)

`MemoraPrimaryButton`'s propio doc comment (y la convención seguida en toda
la Fase 2) dice que debe usarse **una sola vez por pantalla** — en
`AlbumDetailScreen` ese único uso es el FAB "Agregar fotos". La referencia
visual de esta tarea muestra explícitamente un botón pill con relleno
degradado para "Obtener enlace" dentro del tab "Compartir". Para no violar
la regla de "una sola vez" de `MemoraPrimaryButton` (that specific widget)
pero sin ignorar tampoco el pedido explícito de estilo del usuario, se creó
**`_GradientPillButton`** — un widget nuevo y separado, privado a este
archivo, que reutiliza el mismo `signatureGradient` pero NO es una instancia
de `MemoraPrimaryButton`. El resultado real: esta pantalla ahora tiene DOS
elementos con relleno degradado visibles potencialmente al mismo tiempo (el
FAB, siempre presente, y este botón, solo dentro del tab "Compartir" y solo
mientras no exista un `shareLink` todavía) — una excepción deliberada a la
convención de "un solo gradiente por pantalla", documentada acá en vez de
silenciada. **Marcado para revisión de Kiro**: si en una futura revisión de
diseño se decide que esto compite visualmente con el FAB, la corrección más
simple es que `_GradientPillButton` pase a un estilo outline (como
`MemoraSecondaryButton`) en vez de gradiente — no se hizo unilateralmente acá
porque el pedido explícito de la referencia visual era justamente un botón
con gradiente en ese lugar.

### Decisión no trivial: dónde va el banner "Más formas de compartir"

La referencia visual coloca este banner al final del panel, después de la
sección "Colaboradores" (en el mockup, ambas secciones comparten un solo
scroll largo). En esta app, "Compartir" y "Colaboradores" son dos TABS
separados (decisión ya cerrada de la tarea anterior, que esta tarea no debía
tocar) — **se decidió colocar el banner al final del tab "Compartir"**
(`_MoreWaysToShareBanner`, dentro de `_buildSharingSection`) en vez de al
final de "Colaboradores", por dos razones: (1) el contenido del banner habla
exclusivamente de NFC/QR, que es contenido de "Compartir", no de
"Colaboradores"; (2) el tab "Compartir" no existe para un `collaborator` (es
100% owner-only desde spec07), así que si el banner viviera en
"Colaboradores" un `collaborator` lo vería sin poder usarlo (NFC/QR es
owner-only). Documentado acá como decisión de criterio, no un descuido de la
referencia.

### Copy del banner y acción wireada

El usuario pidió explícitamente NO traducir/copiar literalmente el texto de
la referencia, sino redactar un copy propio, corto y cálido, en español,
sobre compartir el álbum físicamente (NFC/QR) sin apps ni conexión. Texto
final: título **"Comparte con solo un toque"**, cuerpo **"Programa una
etiqueta NFC o crea un QR para este álbum: se abre acercando el teléfono o
escaneando, sin apps ni conexión."**, con un link visual "Programar ahora →".
**Acción wireada al tap del banner completo: `_programNfcTag`** — la MISMA
acción que ya dispara el ítem "Programar etiqueta NFC" de la fila de accesos
rápidos (crea el tag vía `AlbumsController.createNfcQrTag` y navega a
`NfcProgrammingScreen`) — decisión tomada porque el copy del banner enfatiza
específicamente NFC ("acercando el teléfono") como el caso principal, y
reutilizar un handler existente evita una segunda ruta de creación de tags.
El banner reutiliza el mismo lenguaje visual "Aurora" oscuro que
`HomeScreen._AlbumsHeroCard` (`RadialGradient` `auraViolet`→`deepInk`, un
asset decorativo rotado/desbordando una esquina) — no un patrón nuevo.

### Asset nuevo: `assets/images/nfc_icon.png`

Provisto por el usuario, ya copiado a `assets/images/` antes de esta tarea
(no se generó/editó acá) — declarado en `pubspec.yaml`'s `flutter: assets:`.
Usado únicamente por `_MoreWaysToShareBanner`, `Image.asset` con
`Transform.rotate`+`Opacity`, mismo patrón que `principal_asset.png` en
`HomeScreen._AlbumsHeroCard`.

### Verificación

`flutter analyze` → `No issues found!`. `flutter test` → **169/169** pasando
(168 previos + 1 nuevo: `album_detail_screen_test.dart`'s test de vista
owner, que pumpea con `role: AlbumRole.owner` y un `AuthController.user` real
seteado a mano, verifica la fila propia con "Tú"/"Owner", la fila del
colaborador genérico, y que el tab "Compartir" muestra el pill de
visibilidad + los items de la fila rápida + el banner). Ningún test
preexistente dependía de `_CollaboratorAvatarStack`/el `Wrap` de 3 botones
viejo (ninguno de los 2 tests previos de este archivo tocaba el rol owner),
así que no hizo falta migrar ninguna aserción rota — solo se sumó cobertura
nueva. **No verificado en este entorno (sin dispositivo/emulador)**: el
armado visual real (chips circulares, la fila de accesos con las líneas
verticales, el banner oscuro con el ícono NFC rotado) y el toque real de los
menús "···"/pills en un dispositivo físico — el usuario debe confirmarlos
corriendo la app.
