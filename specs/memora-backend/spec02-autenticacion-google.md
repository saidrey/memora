# spec02 — Autenticación con Google (backend)

**Ámbito:** memora-backend
**Estado de validación:** PASS (validado por Kiro: 12 unit + 14 e2e, sin fugas de tokens; ver notas al final)

## Objetivo

Implementar en `memora-backend` la autenticación de usuarios mediante Google (flujo híbrido con acceso offline), la emisión de una sesión propia basada en JWT, y el rol del backend como **broker de tokens** de Google Drive: guarda el refresh token del usuario (cifrado, solo en backend) y entrega al cliente access tokens efímeros de Drive bajo demanda.

## Contexto y decisiones ya fijadas

- **Google Login es obligatorio** (decisión de producto). No hay email/password ni registro tradicional.
- **Sesión: JWT propio** emitido por el backend (sin proveedor de identidad gestionado).
- **Scope de Drive: `drive.file`** (acceso solo a los archivos que Memora crea). Aprobado por el Product Owner.
- **Subida de fotos: directa cliente → Drive** (Opción A). El backend no recibe los bytes; sí orquesta y autoriza.
- **Persistencia: mocks en memoria** detrás de interfaces para el MVP (migrable a Postgres/Neon sin tocar la lógica).

## Alcance

- Endpoints de autenticación en `/api/v1/auth`.
- Canje del `serverAuthCode` de Google por access + refresh token (flujo offline).
- Almacenamiento del refresh token detrás de una interfaz (implementación mock en memoria; cifrado como frontera documentada).
- Emisión y validación de JWT de sesión propios (access token de sesión + refresh de sesión).
- Endpoint que entrega al cliente un **access token efímero de Drive** (scope `drive.file`).
- Guard de autenticación reutilizable para proteger endpoints futuros.
- Interfaces de integración (identidad Google, persistencia de usuarios/tokens) con implementaciones mock en memoria.

## Fuera de alcance

- Gestión de álbumes, carpetas en Drive, subida de fotos (specs posteriores).
- Colaboradores, permisos, NFC/QR.
- UI de login en `memora-app` / `memora-web` (specs propias de cada cliente; esta spec expone el contrato de backend que consumirán).
- Mecanismo concreto de cifrado en reposo en producción (KMS vs. clave de app): se decide con la infraestructura.

## Flujo de autenticación (híbrido, offline access)

```
1. Cliente hace Google Sign-In solicitando acceso offline + scope drive.file
      -> obtiene un serverAuthCode (código de un solo uso) e identidad básica
2. Cliente -> POST /api/v1/auth/google  { serverAuthCode }
3. Backend canjea el serverAuthCode con Google por:
      - access_token de Google (corta duración)
      - refresh_token de Google (larga duración)
      - identidad verificada del usuario (id de Google, email)
4. Backend:
      - crea o recupera el usuario (por id de Google)
      - GUARDA el refresh_token CIFRADO, asociado al usuario (nunca sale del backend)
      - emite JWT de sesión propios (access + refresh de sesión)
      -> responde { sessionAccessToken, sessionRefreshToken, user }
5. Para operar sobre Drive, el cliente pide un token efímero:
      Cliente -> POST /api/v1/auth/drive-token   (autenticado con JWT de sesión)
6. Backend usa el refresh_token guardado para obtener de Google un
   access_token de Drive de corta duración (scope drive.file)
      -> responde { driveAccessToken, expiresIn }
7. Cliente sube los bytes DIRECTO a Drive con ese driveAccessToken (Opción A)
```

## Comportamiento esperado

### Login con Google
- El backend SHALL exponer `POST /api/v1/auth/google` que reciba un `serverAuthCode` y lo canjee con Google por access token, refresh token e identidad del usuario.
- El backend SHALL crear el usuario si no existe (identificado por el id de Google) o recuperarlo si ya existe.
- El backend SHALL almacenar el refresh token de Google **cifrado en reposo** y asociado al usuario, y este refresh token NO SHALL exponerse nunca a los clientes.
- El backend SHALL emitir un JWT de sesión propio (access de sesión de corta duración + refresh de sesión) y devolverlo junto con datos básicos del usuario.
- Si el `serverAuthCode` es inválido o el canje con Google falla, el backend SHALL responder con el formato de error uniforme y un código HTTP apropiado (400/401), sin filtrar detalles internos.

### Sesión propia (JWT)
- El backend SHALL validar el JWT de sesión en los endpoints protegidos mediante un guard reutilizable.
- El backend SHALL exponer `POST /api/v1/auth/refresh` que, dado un refresh de sesión válido, emita un nuevo access de sesión.
- El backend SHALL exponer `POST /api/v1/auth/logout` que invalide la sesión del usuario (revocación del refresh de sesión).
- Un access de sesión expirado o inválido SHALL producir HTTP 401 con el formato de error uniforme.

### Token de Drive (broker)
- El backend SHALL exponer `POST /api/v1/auth/drive-token`, protegido por sesión, que devuelva un access token de Drive de corta duración con scope `drive.file` y su tiempo de expiración.
- El backend SHALL obtener ese access token usando el refresh token guardado del usuario; el cliente NO SHALL recibir nunca el refresh token.
- Si el usuario no tiene autorización de Drive válida (p. ej. refresh token revocado por el usuario en su cuenta Google), el backend SHALL responder con un error que indique la necesidad de re-autorizar, sin filtrar detalles internos.

### Seguridad
- El backend NO SHALL registrar en logs tokens (de Google o de sesión) ni el `serverAuthCode`.
- Los secretos de OAuth (client id/secret) SHALL leerse de variables de entorno, nunca hardcodearse.
- El almacenamiento del refresh token SHALL pasar por una interfaz que represente el cifrado en reposo; en el MVP la implementación es un mock en memoria que documenta esa frontera (sin cifrado real todavía).

## Interfaces (aislamiento de proveedores)

Se introducen ahora porque **esta spec sí las consume** (a diferencia de spec01):

- `GoogleAuthClient` (frontera con Google OAuth): canjear `serverAuthCode`, refrescar access token de Drive. Implementación real detrás de la librería oficial de Google; en tests, mockeable.
- `UserRepository` (persistencia de usuarios): crear/recuperar usuario por id de Google. Implementación **mock en memoria**.
- `TokenStore` (persistencia cifrada de refresh tokens): guardar/leer el refresh token del usuario. Implementación **mock en memoria** que documenta la frontera de cifrado.
- La lógica de negocio SHALL depender solo de estas interfaces, no de implementaciones concretas.

## Checklist de implementación

- [x] Definir el módulo `auth` en `memora-backend`.
- [x] Definir las interfaces `GoogleAuthClient`, `UserRepository`, `TokenStore` (sin acoplarse a proveedores concretos).
- [x] Implementar mocks en memoria de `UserRepository` y `TokenStore`, registrados por inyección de dependencias.
- [x] Implementar `GoogleAuthClient` usando la librería oficial de Google OAuth (`google-auth-library`), con client id/secret leídos de variables de entorno (documentado en `.env.example`).
- [x] Implementar `POST /api/v1/auth/google`: canje del `serverAuthCode`, alta/recuperación de usuario, guardado del refresh token vía `TokenStore`, emisión de JWT de sesión.
- [x] Implementar la emisión y validación de JWT de sesión (access + refresh de sesión) con secreto de firma desde entorno (con `type` claim que impide reutilizar un access como refresh).
- [x] Implementar un guard de autenticación reutilizable que valide el JWT de sesión y exponga el usuario autenticado.
- [x] Implementar `POST /api/v1/auth/refresh` y `POST /api/v1/auth/logout`.
- [x] Implementar `POST /api/v1/auth/drive-token`: usa `GoogleAuthClient` + `TokenStore` para emitir un access token de Drive efímero (scope `drive.file`).
- [x] Garantizar que ningún token ni el `serverAuthCode` se escriben en logs (verificado con test e2e dedicado).
- [x] Añadir pruebas: unitarias del servicio de auth y e2e de los endpoints (éxito y errores 400/401 con formato uniforme). 12 unit + 14 e2e pasando.
- [x] Documentar el flujo y los endpoints en el README del backend.
- [x] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- `POST /api/v1/auth/google` canjea el code, crea/recupera usuario, guarda el refresh token vía `TokenStore` y devuelve JWT de sesión + usuario.
- El refresh token de Google nunca aparece en respuestas ni en logs.
- El guard rechaza peticiones sin JWT válido con 401 en formato uniforme.
- `POST /api/v1/auth/refresh` renueva el access de sesión; `logout` invalida la sesión.
- `POST /api/v1/auth/drive-token` devuelve un access token de Drive efímero con scope `drive.file`, sin exponer el refresh token; ante refresh inválido, responde con error de re-autorización.
- La lógica depende de las interfaces; las únicas implementaciones son la real de Google (mockeable) y los mocks en memoria de repositorio/almacén.
- client id/secret y secreto de firma del JWT se leen de variables de entorno (documentadas en `.env.example`), no hardcodeados.
- `npm run build`, `npm run test`, `npm run test:e2e` pasan; el flujo y endpoints están documentados.

## Correcciones tras prueba en dispositivo real (Android físico)

Durante la prueba end-to-end en un Android físico surgieron dos bugs reales del flujo nativo (la spec original asumió el flujo web). Corregidos y validados con login real exitoso:

1. **`redirect_uri_mismatch` al canjear el `serverAuthCode`.** El backend usaba `redirect_uri: 'postmessage'` (valor del flujo **web**). Un `serverAuthCode` de app **nativa** no tiene `redirect_uri`, y `postmessage` causaba el error. **Fix:** canjear el code SIN `redirect_uri` (`getToken({ code })`).

2. **Identidad del usuario vía `userinfo`, no vía `id_token`.** La app solo autoriza scopes de negocio; Google no siempre devuelve `id_token` en el canje. Además, para leer `userinfo` el access token necesita los scopes de identidad. **Fix (dos partes):**
   - Backend: obtiene la identidad (sub/email/name) llamando a `https://www.googleapis.com/oauth2/v3/userinfo` con el access token, en vez de exigir `id_token`.
   - App: la autorización de servidor solicita `openid`, `email`, `profile` **además** de `drive.file` (sin esos scopes, `userinfo` responde 401 "Invalid Credentials").

**Estado: login end-to-end verificado en Android físico** (inicio y cierre de sesión correctos).

## Notas de validación (Kiro) — PASS

- **Resultado: PASS.** 12 unit + 14 e2e pasando; código revisado línea a línea. Sin fugas de tokens (test dedicado lo confirma). Logout revoca de verdad (el refresh falla tras logout). NestJS 10 y `.npmrc` intactos; secretos solo desde entorno.
- **Duración de tokens de sesión**: el implementador eligió access `15m` y refresh `30d` (configurables por entorno). Kiro los aprueba como valores por defecto razonables para el MVP.
- **Bug corregido**: un error del `GoogleAuthClient` se colaba como 500 en vez de 401; corregido con normalización defensiva en `AuthService` y cubierto por e2e.

## Ajustes pendientes (no bloqueantes, para antes de desplegar)

- **`SessionRegistry` → interfaz con mock en memoria**: actualmente es un provider en memoria (4ª pieza de estado no prevista en la spec). Debe elevarse a interfaz formal (patrón mock ahora → datastore real después, p. ej. Redis/Postgres), porque el logout es seguridad y hoy las sesiones activas se pierden si el backend reinicia. No urgente para desarrollo local.
- **Mecanismo real de cifrado en reposo** del refresh token: pendiente junto con la infraestructura; en el MVP es una frontera documentada en `TokenStore`.

## Dependencias

- `memora-backend/spec01-fundacion-backend.md` (contrato base, ya PASS).
- `global/spec02-contrato-api.md` (formato de error, correlación).
