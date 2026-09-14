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

---

Getting Started (plantilla original de Flutter):

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
