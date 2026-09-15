# spec03 — Fotografías: seleccionar, optimizar y subir a Drive (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** ✅ VALIDADO EN DISPOSITIVO por el PO (2026-09-14): la app sube la foto optimizada a la carpeta "Memora" en el Drive del usuario y la registra en el backend. (Metodología vigente: valida el PO en dispositivo, no Kiro — ver `COMO-TRABAJAR.md`.)
**Backlog:** M3 (Fotografías) — parte **app**. El backend de M3 (`memora-backend/spec04`) y la abstracción de almacenamiento (`memora-backend/spec08`) ya están **PASS**.

## Objetivo
Implementar en `memora-app` el flujo por el que el usuario **selecciona una o varias fotos de su dispositivo**, la app las **optimiza automáticamente** (D15) **sin filtrar geolocalización** (D8), pide un **token de Drive** al backend, **sube los bytes directo a Google Drive del usuario** (Opción A: el backend nunca ve los bytes) y **registra cada foto en el backend** con su `storageRef`. Debe además **detectar** el caso en que el backend exige re-autorizar Drive (`DRIVE_REAUTHORIZATION_REQUIRED`) y avisar al usuario (el flujo completo de re-autorización se especifica aparte, ver E/A1.6 del ROADMAP).

## Contexto y decisiones que aplican
Fuente de verdad de producto: `specs/producto-mvp.md`. Aplican:
- **Opción A (subida directa).** La app sube los bytes cliente→Drive; el backend orquesta y guarda referencias, **nunca** maneja bytes (`producto-mvp.md` §Decisiones técnicas; `spec04`/`spec08` backend). Única excepción al límite "los clientes solo hablan con la API": la transferencia de bytes app→Drive.
- **D15 — Optimización automática.** Optimización con buenos defaults; **el usuario NO elige** calidad ni resolución. Los parámetros técnicos los define el Tech Lead (ver *Decisiones abiertas*, decisión 3).
- **D8 — Metadatos mínimos, sin GPS.** No se almacena geolocalización. La optimización SHALL además **garantizar que no se filtren metadatos GPS/EXIF** al archivo que se sube a Drive.
- **Scope `drive.file`.** El `driveAccessToken` que entrega el backend tiene scope `drive.file`: solo puede tocar archivos que la propia app crea. Esto condiciona la subida (solo `create`) y la estructura en Drive.
- **Estructura de Drive organizativa (Precisión aprobada).** NO hay carpeta por álbum; los álbumes son entidades lógicas de Memora. La estructura en Drive es organizativa (p. ej. una carpeta única de Memora por usuario). Esto abre la decisión de *dónde* crear el archivo (ver *Decisiones abiertas*, decisión 1).
- **D11 — Biblioteca.** Al registrar una foto, entra en la biblioteca del usuario (`GET /api/v1/library`), independientemente de que se asocie o no a un álbum.

## Contrato real del backend (ya verificado — usar tal cual)
- **Token de Drive:** `POST /api/v1/auth/drive-token` (autenticado, Bearer de sesión) → `{ driveAccessToken, expiresIn }`, scope `drive.file`. Sin refresh de Google válido → **401 con `code: "DRIVE_REAUTHORIZATION_REQUIRED"`**.
- **Subida de bytes:** la app sube directo a Google Drive con ese `driveAccessToken` (Drive API, `files.create` multipart) y obtiene un **`fileId`** de Drive. El backend NO participa en esta transferencia.
- **Registro:** `POST /api/v1/photos` (autenticado) con body: `{ storageRef: { fileId, provider? }, capturedAt?, width?, height?, mimeType?, sizeBytes?, albumId? }`. **OJO — el contrato es `storageRef { fileId, provider? }`, NO `driveFileId`** (lo cambió `spec08`). `provider` es **opcional** y por defecto `'google-drive'`. **Solo `storageRef.fileId` es obligatorio.** Respuesta: la `Photo` registrada.
- **Asociar a álbum existente:** `POST /api/v1/albums/:albumId/photos`. (También se puede asociar en un paso enviando `albumId` en `POST /photos`.)
- **Biblioteca:** `GET /api/v1/library`.

## Alcance (app)
- **Selección** de una o varias fotos de la galería/almacenamiento del dispositivo, **sin modificar ni eliminar los originales**.
- **Optimización automática** de cada foto antes de subir (D15), **removiendo GPS/EXIF** (D8), con defaults fijos (decisión 3).
- **Obtención del `driveAccessToken`** vía `POST /auth/drive-token` a través de la capa API existente.
- **Subida directa de bytes** a Google Drive del usuario (Drive API `files.create` multipart con el `driveAccessToken`), obteniendo el `fileId`.
- **Registro** de cada foto en el backend con `POST /api/v1/photos` usando `storageRef: { fileId }` + metadatos mínimos disponibles.
- **Detección** del error `DRIVE_REAUTHORIZATION_REQUIRED` (401) al pedir el token y **aviso claro** al usuario (sin resolver la re-autorización aquí).
- **Estado y UI mínima funcional** (sin diseño final): disparar la selección, mostrar progreso por foto (subiendo/registrando/ok/error) y resultado agregado. Consistente con el estilo de `home_screen` (pantalla funcional, no diseñada).

## Fuera de alcance
- **Re-autorización de Drive** (recuperar el flujo tras `DRIVE_REAUTHORIZATION_REQUIRED`): se especifica en la spec de A1.6 (ROADMAP FASE 2, ítem E). Aquí solo se **detecta y avisa**.
- **Refresco automático del JWT de sesión** (pendiente conocido de `spec02`): si el access de sesión caduca, se maneja en la spec de A1.5. Aquí se asume sesión válida.
- **UI de álbumes** (crear/ver/abrir/renombrar/eliminar): es el ítem B del ROADMAP. Esta spec puede asociar a un `albumId` si se le pasa uno, pero **no** construye la pantalla de gestión de álbumes.
- **Captura con cámara en vivo** (tomar la foto dentro de la app): esta spec cubre **selección** desde el dispositivo. La cámara, si se decide, es incremento posterior (ver decisión 2).
- **Colaboradores** (M4), **compartir/visor** (M7), **NFC/QR** (M8), **disponibilidad** (M6 en app).
- **Verificación/visualización de miniaturas** desde Drive (se aborda con M6/M7 en app).
- **Diseño visual final.** Identidad visual es decisión aparte.

## Flujo esperado (por foto seleccionada)
```
Usuario: toca "Agregar fotos" -> selector del sistema (una o varias fotos)
App: por cada foto seleccionada, en la capa de subida:
  1. Optimiza los bytes (redimensiona + recomprime + ELIMINA GPS/EXIF)  [D15, D8]
  2. Pide POST /api/v1/auth/drive-token  -> { driveAccessToken, expiresIn }
       (si 401 DRIVE_REAUTHORIZATION_REQUIRED -> aborta y avisa "reconectar Drive")
  3. Sube los bytes optimizados directo a Drive (files.create multipart, drive.file)
       -> obtiene fileId
  4. Registra en backend: POST /api/v1/photos { storageRef: { fileId }, width?, height?,
       mimeType?, sizeBytes?, capturedAt?, albumId? } -> Photo registrada
App: refleja progreso/resultado por foto (ok / error) y un resumen al terminar
```
Notas del flujo:
- El **backend nunca recibe los bytes**; solo el paso 2 (token) y 4 (registro) lo tocan, vía `ApiClient`.
- El `driveAccessToken` puede **reutilizarse** para varias subidas mientras no expire (`expiresIn`); la app debería pedirlo una vez por lote y renovarlo si expira (ver decisión 4 sobre selección múltiple).
- Los **originales del dispositivo no se tocan**: la optimización trabaja sobre una copia en memoria/temporal.

## Comportamiento esperado (normativo)
### Selección
- La app SHALL permitir seleccionar **una o varias** fotos del dispositivo mediante el selector del sistema, sin modificar ni eliminar los archivos originales.
- La app SHALL solicitar los permisos de acceso a fotos que la plataforma requiera y, si se deniegan, SHALL mostrar un mensaje claro sin bloquear el resto de la app.
### Optimización (D15 + D8)
- La app SHALL optimizar automáticamente cada foto antes de subirla, con **parámetros fijos definidos por el Tech Lead** (decisión 3); el usuario NO SHALL elegir calidad ni resolución.
- La optimización SHALL producir un archivo **sin metadatos de geolocalización GPS/EXIF**. La app NO SHALL subir la geolocalización a Drive ni enviarla al backend.
- La optimización NO SHALL alterar los archivos originales del dispositivo.
### Token de Drive
- La app SHALL obtener el `driveAccessToken` mediante `POST /api/v1/auth/drive-token` a través del `ApiClient` (con el Bearer de sesión ya adjunto).
- Si esa llamada responde **401 con `code == "DRIVE_REAUTHORIZATION_REQUIRED"`**, la app SHALL detenerse para esa(s) foto(s) y mostrar un mensaje claro de que hace falta **reconectar Google Drive**, sin cerrar la sesión de la app (D10) y sin filtrar detalles internos. La resolución del flujo de re-autorización queda fuera de alcance (spec A1.6).
### Subida a Drive
- La app SHALL subir los **bytes optimizados** directamente a Google Drive del usuario usando el `driveAccessToken` (Drive API `files.create`, subida multipart), y SHALL obtener el `fileId` resultante.
- La app SHALL enviar el `driveAccessToken` **solo** a la API de Google Drive (nunca al backend de Memora ni a terceros) y NO SHALL registrarlo en logs.
- Ante fallo de subida (red, token expirado, cuota, etc.), la app SHALL marcar esa foto como fallida y continuar con las demás, sin dejar el lote en estado inconsistente.
### Registro en backend
- Tras obtener el `fileId`, la app SHALL registrar la foto con `POST /api/v1/photos` enviando **`storageRef: { fileId }`** (sin enviar `driveFileId`; `provider` se omite y el backend asume `'google-drive'`) más los metadatos mínimos disponibles (`width`, `height`, `mimeType`, `sizeBytes`, `capturedAt` si se conoce; **nunca** geolocalización).
- Si la app recibió un `albumId` de contexto, SHALL asociar la foto (vía `albumId` en `POST /photos`, o `POST /albums/:albumId/photos`). Sin `albumId`, la foto queda solo en la biblioteca (D11).
- El registro SHALL pasar por el `ApiClient` (nunca `http` directo).
### Estado / UI
- La app SHALL exponer el progreso del lote (por foto: optimizando/subiendo/registrando/ok/error) y un resumen al finalizar, con una UI mínima funcional consistente con `home_screen`.
- Errores SHALL mostrarse con mensajes claros y sin filtrar detalles internos ni tokens.
### Reglas transversales
- La app NO SHALL enviar los bytes de la foto al backend en ningún momento.
- La app NO SHALL persistir el `driveAccessToken` en almacenamiento; se usa en memoria durante el lote y se descarta.
- Ningún token (`driveAccessToken`, Bearer de sesión) ni ruta de archivo sensible SHALL escribirse en logs.

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **Decisión 1 — Ubicación en Drive: carpeta única "Memora" en "Mi unidad".** La app crea (una vez) una carpeta "Memora" y sube todos los archivos ahí; cachea su `fileId` para el lote. Fotos visibles y ordenadas para el dueño; una sola carpeta organizativa por usuario, **NO** por álbum (coherente con la estructura aprobada y D14). El backend no conoce la carpeta (guarda solo `storageRef.fileId`).
- **Decisión 2 — Solo selección de galería en esta spec.** La captura con cámara en vivo queda como incremento posterior (reutilizará el mismo pipeline). Este corte cubre subir fotos existentes del dispositivo.
- **Decisión 3 — Defaults de optimización (D15, el usuario NO elige):** lado mayor ≤ **2048 px** (solo reduce si excede, nunca amplía); **JPEG ~85%**; aplicar orientación EXIF y luego **eliminar EXIF/GPS**. Ajustables por el Tech Lead si las pruebas reales lo requieren, sin exponer la elección al usuario.
- **Decisión 4 — Selección múltiple: lote real, procesado en secuencia.** N fotos en secuencia (no paralelo masivo) con progreso y errores parciales por foto, reutilizando el `driveAccessToken` mientras no expire.
- **Decisión 5 (técnica) — Paquetes:** `image_picker` (selección) + `flutter_image_compress` (redimensiona, recomprime y descarta EXIF/GPS). Subida a Drive con `http` multipart contra la Drive API v3, reutilizando el patrón de la capa API; **no** se añade el SDK de Google Drive (respeta el aislamiento de proveedores de spec01), tratando Drive como endpoint HTTP con el `driveAccessToken`.

## Checklist de implementación
- [ ] Añadir dependencias en `pubspec.yaml`: selector (`image_picker`) y compresión con borrado de EXIF/GPS (`flutter_image_compress` o equivalente aprobado). Configurar permisos por plataforma (iOS `Info.plist` `NSPhotoLibraryUsageDescription`; Android correspondientes).
- [ ] Implementar `DriveTokenApi` (o método en la capa auth) que llame `POST /api/v1/auth/drive-token` vía `ApiClient` y devuelva `{ driveAccessToken, expiresIn }`; mapear el 401 `DRIVE_REAUTHORIZATION_REQUIRED` a un error tipado propio.
- [ ] Implementar la **optimización** con los defaults aprobados (decisión 3): redimensionar (≤ 2048 px), recomprimir (JPEG ~85%), aplicar orientación EXIF y **eliminar GPS/EXIF**. Trabajar sobre copia; no tocar el original.
- [ ] Implementar la **subida directa a Drive** (`files.create` multipart de la Drive API v3) usando el `driveAccessToken`; según decisión 1, crear/resolver la carpeta "Memora" y cachear su `fileId` para el lote; devolver el `fileId`. Nunca enviar el token al backend ni loguearlo.
- [ ] Implementar un `PhotosApi` con `registerPhoto(...)` → `POST /api/v1/photos` con **`storageRef: { fileId }`** + metadatos mínimos (`width/height/mimeType/sizeBytes/capturedAt` cuando se conozcan; **sin** geolocalización) y `albumId?` opcional. Modelar la `Photo`/`StorageRef` de respuesta (`storageRef { provider, fileId }`).
- [ ] Orquestar el flujo por lote (decisión 4): optimizar → token (una vez, renovar si expira) → subir → registrar, por cada foto en secuencia, con estado/progreso por foto y errores parciales. Controlador de estado tipo `ChangeNotifier` (patrón de `AuthController`).
- [ ] UI mínima funcional: acción "Agregar fotos", lista de progreso por foto, resumen final y aviso específico para `DRIVE_REAUTHORIZATION_REQUIRED`. Consistente con `home_screen`.
- [ ] Garantizar que ningún token ni ruta sensible se escribe en logs, y que los bytes nunca van al backend.
- [ ] Verificar que `flutter analyze` pasa y el proyecto compila (build iOS y/o Android según disponibilidad).

## Criterios de validación (los revisa Kiro)
- El usuario puede seleccionar una o varias fotos del dispositivo; los originales no se modifican ni eliminan.
- Cada foto se optimiza con los defaults aprobados y **sin GPS/EXIF** en el archivo subido (verificable: el archivo resultante no contiene metadatos de ubicación).
- La app pide `drive-token` vía `ApiClient` y sube los **bytes** directo a Drive (`files.create`), obteniendo un `fileId`; el backend **no** recibe bytes en ningún punto.
- El registro usa `POST /api/v1/photos` con **`storageRef: { fileId }`** (no `driveFileId`); `provider` omitido; metadatos mínimos sin geolocalización; `albumId` opcional respetado.
- Un 401 `DRIVE_REAUTHORIZATION_REQUIRED` al pedir el token se detecta y se avisa claramente, sin cerrar sesión (D10) y sin resolver la re-autorización (fuera de alcance).
- El `driveAccessToken` solo se envía a la Drive API, no se persiste y no aparece en logs; los errores no filtran detalles internos.
- La selección múltiple procesa el lote con progreso y errores parciales por foto (según decisión 4 aprobada).
- La estructura en Drive respeta la decisión 1 aprobada (p. ej. carpeta "Memora").
- `flutter analyze` pasa y el proyecto compila.

> Nota de verificación (para Kiro): la subida real a Drive requiere un dispositivo/cuenta con Google Play y una sesión válida con Drive autorizado. Kiro valida en revisión: (1) `flutter analyze`/compilación, (2) que el flujo llama a los endpoints correctos (`drive-token`, `files.create` de Drive, `POST /photos` con `storageRef`), (3) que los bytes no pasan por el backend, (4) que la optimización elimina EXIF/GPS y (5) ausencia de tokens en logs. La prueba manual de subida en dispositivo la realiza el PO si Kiro no puede ejecutarla (igual que en `spec02`).

## Dependencias
- `memora-app/spec01-fundacion-app.md` (capa `ApiClient`) — PASS.
- `memora-app/spec02-login-google.md` (sesión JWT + Bearer adjunto; scope `drive.file` ya solicitado en el login) — PASS.
- `memora-backend/spec04-fotografias.md` (registro `POST /photos`, biblioteca, asociación a álbum) — PASS.
- `memora-backend/spec08-abstraccion-almacenamiento.md` (contrato `storageRef { provider, fileId }` en `POST /photos`) — PASS.
- `memora-backend/spec02-autenticacion-google.md` (broker `POST /auth/drive-token`, error `DRIVE_REAUTHORIZATION_REQUIRED`) — PASS.
- **Se relaciona con** (fuera de alcance aquí): spec de A1.6 (re-autorización de Drive) y A1.5 (refresh de sesión) — ROADMAP FASE 2 ítem E; UI de álbumes — ítem B.
