# spec02 — Login con Google (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** PASS — código validado por Kiro y **login real verificado en Android físico** (inicio y cierre de sesión). Incluye correcciones tras la prueba (ver al final).

## Objetivo

Implementar en `memora-app` el inicio de sesión con Google de forma nativa, obteniendo un `serverAuthCode` (acceso offline) que se envía al backend (`POST /api/v1/auth/google`). La app guarda la sesión JWT devuelta por el backend de forma segura, refleja el estado de autenticación y permite cerrar sesión.

## Contexto y decisiones ya fijadas

- **Google Login es obligatorio** (producto). No hay email/password.
- **Flujo híbrido offline**: la app obtiene un `serverAuthCode` y lo envía al backend; el backend lo canjea y guarda el refresh token de Google. La app **nunca** ve el refresh token de Google.
- **La sesión de la app es el JWT propio de Memora** (access + refresh), emitido por el backend en spec02 de backend (ya PASS).
- **Scope de Drive: `drive.file`** (aprobado).
- **El backend ya expone** `POST /api/v1/auth/google`, `/auth/refresh`, `/auth/logout`, `/auth/drive-token` (ver `specs/memora-backend/spec02-autenticacion-google.md`).

## Configuración de Google (setup ya realizado por el Product Owner)

Estos valores provienen del proyecto de Google Cloud ya configurado:

- **Web client ID** (se usa como `serverClientId` en Google Sign-In para que el `serverAuthCode` sea canjeable por el backend):
  `677454923415-sjt01rvlh4of49p1ufvgoh1vi3b1i70m.apps.googleusercontent.com`
- **iOS client ID**: `677454923415-b3q3s2ku6qrik4j6fpki1qp97151n0o7.apps.googleusercontent.com` (público).
- **Android**: registrado en la consola con package `app.memora.memora_app` + SHA-1 de debug. No requiere Client ID en código.
- **Bundle ID iOS**: `app.memora.memoraApp`.
- **Scope solicitado**: `https://www.googleapis.com/auth/drive.file` (además de los básicos de identidad).

Ninguno de estos valores es secreto. El `serverClientId` (Web client ID) debe ser configurable (p. ej. `--dart-define`), con el valor de arriba como defecto de desarrollo.

## Alcance

- Integración de Google Sign-In nativo (paquete `google_sign_in`).
- Obtención del `serverAuthCode` mediante la autorización de servidor.
- Intercambio con el backend (`POST /api/v1/auth/google`) y persistencia segura de los JWT de sesión.
- Estado de autenticación en la app (autenticado / no autenticado) y cierre de sesión.
- Adjuntar el JWT de sesión (Bearer) en las peticiones autenticadas a la API.

## Fuera de alcance

- Refresco automático del JWT de sesión y manejo avanzado de expiración (puede ser una spec posterior; para esta basta guardar y usar el access token).
- Obtención/uso del `drive-token` y subida a Drive (spec posterior de fotos).
- Álbumes, colaboradores, NFC/QR.
- Pantallas con diseño final (identidad visual es decisión aparte); basta una pantalla funcional.

## Notas técnicas obligatorias

- Usar `google_sign_in` **v7+**. En v7 la API separó autenticación de autorización: el `serverAuthCode` se obtiene mediante la **autorización de servidor** (método de servidor authorization / `authorizeServer`), NO desde el resultado de `signIn` como en versiones antiguas. No usar la API previa a v7.
- Pasar el **Web client ID** como `serverClientId` para que el `serverAuthCode` sea canjeable por el backend.
- Solicitar el scope `drive.file` junto con los básicos.
- Persistir los JWT de sesión con almacenamiento seguro del sistema (Keychain en iOS, Keystore en Android) mediante un paquete adecuado (p. ej. `flutter_secure_storage`). NO usar `SharedPreferences`/almacenamiento en claro para los tokens.
- Nunca registrar tokens ni el `serverAuthCode` en logs.
- Toda petición al backend sigue pasando por la capa de API de spec01 (`ApiClient`).

## Comportamiento esperado

- La app SHALL permitir iniciar sesión con Google mediante un botón/acción de "Iniciar sesión con Google".
- Al iniciar sesión, la app SHALL obtener un `serverAuthCode` (acceso offline, scope `drive.file`) y enviarlo a `POST /api/v1/auth/google`.
- La app SHALL guardar los JWT de sesión (access + refresh) devueltos por el backend en almacenamiento seguro del sistema.
- La app SHALL reflejar el estado autenticado (mostrar datos básicos del usuario: email/nombre) tras un login exitoso.
- La app SHALL adjuntar el access token de sesión como `Authorization: Bearer <token>` en las peticiones autenticadas.
- La app SHALL permitir cerrar sesión: llamar a `POST /api/v1/auth/logout`, cerrar la sesión de Google local y borrar los tokens del almacenamiento seguro.
- Si el login con Google falla o el usuario lo cancela, la app SHALL permanecer en estado no autenticado y mostrar un mensaje claro, sin filtrar detalles internos.
- Al reabrir la app, SHALL considerarse autenticado si hay una sesión válida almacenada.

## Checklist de implementación

- [x] Añadir dependencias: `google_sign_in` (^7.2.0) y `flutter_secure_storage` en `pubspec.yaml`.
- [x] Configurar el `serverClientId` (Web client ID) de forma configurable (`--dart-define`), con el valor de desarrollo por defecto.
- [x] Configurar iOS: iOS client ID + URL scheme (client ID invertido) en `Info.plist`.
- [x] Configurar Android: package `app.memora.memora_app` + SHA-1 coinciden con el cliente OAuth (verificado por Kiro); sin client secret.
- [x] Implementar un servicio de autenticación (`GoogleAuthService`) que inicie Google Sign-In (`authenticate`), obtenga el `serverAuthCode` (`authorizeServer`, scope `drive.file`) y lo envíe a `POST /api/v1/auth/google` vía `ApiClient`.
- [x] Persistir los JWT de sesión en almacenamiento seguro (`SessionStorage`); lectura/limpieza incluidas.
- [x] Exponer el estado de autenticación (autenticado/no autenticado + usuario) a la UI (`AuthController`).
- [x] Hacer que `ApiClient` adjunte `Authorization: Bearer <access token>` cuando haya sesión.
- [x] Implementar cierre de sesión (backend `logout` + signOut de Google + borrar tokens; best-effort si el backend falla).
- [x] Implementar una pantalla mínima (`home_screen`): botón de login, estado autenticado con datos del usuario, botón de logout, y manejo de error/cancelación (consolidó el indicador de salud de spec01).
- [x] Garantizar que ningún token ni el `serverAuthCode` se escriben en logs.
- [x] Verificar que `flutter analyze` pasa y el proyecto compila (build iOS OK).

## Criterios de validación (los revisa Kiro)

- El botón de login inicia Google Sign-In y obtiene un `serverAuthCode` con la API v7 (autorización de servidor), no la API antigua.
- Se usa el Web client ID como `serverClientId` y el scope `drive.file`.
- Tras login, la app envía el code a `POST /api/v1/auth/google` y guarda los JWT en almacenamiento seguro (no en claro).
- El estado autenticado se refleja en la UI con datos del usuario; al reabrir con sesión válida, sigue autenticado.
- Las peticiones autenticadas llevan `Authorization: Bearer`.
- El logout llama al backend, cierra Google y borra los tokens.
- Cancelación/fallo dejan la app no autenticada con mensaje claro, sin filtrar detalles.
- Ningún token ni `serverAuthCode` en logs.
- `flutter analyze` pasa y compila.

## Dependencias

- `memora-app/spec01-fundacion-app.md` (capa `ApiClient`, ya PASS).
- `memora-backend/spec02-autenticacion-google.md` (endpoints de auth, ya PASS).

## Nota de verificación (para Kiro)

- La verificación end-to-end del login real requiere un dispositivo/emulador con Google Play y la app iOS firmada. En validación, Kiro confirmará: (1) `flutter analyze`/compilación, (2) que el flujo llama a los endpoints correctos y usa la API v7, (3) almacenamiento seguro y ausencia de logs sensibles. La prueba manual del login en dispositivo la realiza el Product Owner si Kiro no puede ejecutarla.

## Notas de validación (Kiro) — PASS (código)

- **Código: PASS.** API v7 usada correctamente (`authenticate` + `authorizeServer(drive.file)`), `serverClientId` = Web client, tokens en `flutter_secure_storage`, `ApiClient` adjunta Bearer, logout completo best-effort, restauración de sesión en `bootstrap`, sin logs de tokens. `flutter analyze` limpio y `flutter build ios` OK.
- **SHA-1 de debug verificado por Kiro**: coincide con el registrado en el cliente OAuth Android.
- **Consolidación de pantallas** (salud de spec01 + login en `home_screen`): decisión de implementación aprobada.
- **Prueba de login real: HECHA y EXITOSA en Android físico** (inicio y cierre de sesión correctos).

## Correcciones tras prueba en dispositivo real

- **Scopes de identidad en la autorización de servidor.** La app solicita ahora `openid`, `email`, `profile` **además** de `drive.file`. Sin ellos, el access token que el backend obtiene del canje no puede leer `userinfo` (Google responde 401), y el login falla. (Ver también las correcciones en `memora-backend/spec02`.)
- **Entorno de prueba (aprendizajes):**
  - **Emulador Android sin cuenta de Google**: Credential Manager falla al instante (`GetCredentialResponse error`). Requiere una imagen con Google Play y una cuenta de Google agregada.
  - **Android físico por WiFi**: `adb reverse` no aplica; usar la IP de la Mac en la red: `--dart-define=API_BASE_URL=http://<IP-de-la-Mac>:3000/api/v1`. El backend debe ser accesible por esa IP.
  - **Emulador Android**: `--dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1` (localhost apunta al propio emulador).
  - Recordar: la app OAuth está en modo "Prueba" → solo funcionan los emails agregados como usuarios de prueba en Google Cloud.
