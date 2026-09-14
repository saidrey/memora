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

## Seguridad

- Nunca loguear (`print`/log) el `serverAuthCode` ni los JWT de sesión.
  Errores capturados se traducen a mensajes fijos, sin incluir el error
  original.

## Tests

- `flutter analyze` sin warnings antes de reportar terminado.
- `flutter test` para lógica (servicios, controllers) — no depende de
  dispositivo/emulador.
- El login real con Google Sign-In solo se puede probar en
  dispositivo/emulador con Google Play (Android) o simulador/dispositivo iOS
  firmado — no es cubrible por `flutter test`; documentarlo como paso manual
  de verificación en el reporte final.
