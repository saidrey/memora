# spec08 — Abstracción de almacenamiento de fotografías (`PhotoStorage`) (backend)

**Ámbito:** memora-backend
**Estado de validación:** ✅ PASS (validado por Kiro el 2026-09-14: build OK; 89 unit + 77 e2e; neutralidad de dominio verificada por test dedicado + grep). Ver "Notas de validación (Kiro)" al final.
**Backlog:** decisión arquitectónica transversal (habilitador de M5 futuro y de un storage propio de Memora). Se implementa **antes de M7**.

## Objetivo

Desacoplar el dominio de Memora del proveedor de almacenamiento concreto (hoy Google Drive) introduciendo una abstracción **`PhotoStorage`** y una **referencia física neutral** en la `Photo`. **No** se migra nada, **no** se añade B2, **no** se cambian scopes ni se convierte a Memora en custodio. Es un cambio de forma/encapsulación que protege la evolución futura sin ser un proyecto de infraestructura.

## Contexto y decisiones que aplican

- Google Drive sigue siendo el **único** almacenamiento del MVP (decisión técnica de `specs/README.md`). Esta spec no lo cambia; solo lo pone **detrás de una interfaz**.
- El backend **no maneja bytes** (Opción A): la app sube directo a Drive; el backend coordina y guarda referencias. Por eso la mayoría de operaciones de `PhotoStorage` son de **coordinación/autorización**, no de transferencia de bytes.
- Estado actual verificado: la `Photo` ya está poco acoplada — el único acoplamiento real es el **nombre del campo** `driveFileId: string` y el broker `drive-token` en auth. `Photo.id` (identidad lógica) y `Photo.ownerId` (propietario lógico) ya son neutrales.
- **M5 sigue diferido** (`spec06-adoptar.md`). Esta abstracción es su habilitador natural cuando se retome, pero aquí NO se implementa la copia.

## Separación conceptual que fija esta spec

| Concepto | Dónde vive | Cambia? |
|---|---|---|
| Identidad lógica de la foto | `Photo.id` (UUID de Memora) | No |
| Propietario lógico | `Photo.ownerId` | No |
| Proveedor de almacenamiento | `StorageRef.provider` (nuevo) | Nuevo |
| Referencia/identificador físico | `StorageRef.fileId` (antes `driveFileId`) | Renombrado/encapsulado |
| Operaciones sobre el archivo | interfaz `PhotoStorage` (nueva) | Nuevo |

## Alcance (backend)

- **Referencia física neutral** en `Photo`: reemplazar `driveFileId: string` por **`storageRef: StorageRef`**, con `StorageRef = { provider: StorageProvider; fileId: string }` y `type StorageProvider = 'google-drive'` (único valor en el MVP; el tipo deja lugar a futuros como `'b2'`).
- **Interfaz `PhotoStorage`** (token `Symbol`, patrón de repos), con **solo las operaciones que el MVP usa hoy** implementadas, y las demás **declaradas pero marcadas "no soportadas aún"** (lanzan un error controlado / `NOT_IMPLEMENTED`) para fijar la intención sin sobre-ingeniería.
- **Una implementación viva: `GoogleDrivePhotoStorage`**, que envuelve lo que ya existe (el broker `drive-token` de auth) y produce/lee `StorageRef` con `provider: 'google-drive'`.
- Ajustar el **registro de foto** (spec04) y las **respuestas de API** que exponían `driveFileId` para usar `storageRef` (cambio de contrato, aditivo — aún no hay clientes que lo consuman).
- El **provider por defecto** en el MVP es `'google-drive'`; el cliente no lo elige (se asume) — se documenta como default configurable a futuro, sin implementar selección ahora.

## Operaciones de `PhotoStorage` (definición del Tech Lead)

Se parte de la lista sugerida por el PO y se ajusta al dominio real del MVP (backend no maneja bytes):

**Implementadas en el MVP (Google Drive):**
- `getUploadAuthorization(userId): UploadAuthorization` — lo que hoy da `drive-token` (token efímero + parámetros para que el **cliente** suba directo). Ubica la subida sin que el backend toque bytes.
- `getReadReference(photo): ReadReference` — datos neutrales que el cliente/visor necesita para pedir los bytes al proveedor (p. ej. provider + fileId; el modo de lectura concreto lo resuelve el cliente con su token). Habilita M7 (visor) con referencias neutrales.
- `describe(photo)` / `exists(photo)` — **declaradas**; en el MVP la verificación real la hace el cliente y la reporta (M6, spec07). El backend no consulta Drive; estas quedan como contrato para cuando exista un proveedor consultable server-side. Marcar "no soportado server-side en el MVP" o delegar al modelo de reporte de M6.

**Declaradas pero NO implementadas en el MVP (fijan intención):**
- `download` / `stream` — el backend no maneja bytes; `NOT_IMPLEMENTED`.
- `copy` — es justo M5 (diferido); `NOT_IMPLEMENTED`.
- `delete` — Memora **nunca** borra del Drive del usuario por principio; `NOT_IMPLEMENTED` (y se documenta que un futuro storage propio podría soportarlo bajo decisión de producto).

> La interfaz exacta se cierra en implementación; lo vinculante es: (1) provider reemplazable, (2) referencia neutral, (3) solo lo del MVP se implementa, (4) el resto declarado como no soportado.

## Fuera de alcance (explícito, por instrucción del PO)

- Migrar fotos existentes de Google Drive.
- Añadir Backblaze B2 (solo se documenta como **dirección futura**, candidato serio, sin implementar).
- Cambiar scopes OAuth de Google.
- Convertir a Memora en custodio de bytes.
- Implementar M5 (copia) ni la copia cross-Drive.
- Cambiar decisiones de producto sobre propiedad de las fotos.
- Selección de proveedor por el cliente / multi-provider activo.

## Comportamiento esperado (normativo)

- El dominio (álbumes, colaboradores, disponibilidad, biblioteca) NO SHALL referirse a "Drive" ni a `driveFileId`; SHALL usar `Photo.storageRef` y, cuando necesite operar sobre el archivo, la interfaz `PhotoStorage`.
- `Photo` SHALL exponer `storageRef: { provider, fileId }` en lugar de `driveFileId`. El registro SHALL seguir aceptando el identificador físico que hoy envía el cliente, mapeándolo a `storageRef` con `provider: 'google-drive'` (ver P/nota de contrato abajo).
- `PhotoStorage` SHALL ser inyectable por token `Symbol`, con `GoogleDrivePhotoStorage` como implementación registrada.
- Las operaciones no soportadas en el MVP SHALL fallar de forma **controlada y uniforme** (código `NOT_IMPLEMENTED` / `STORAGE_OPERATION_UNSUPPORTED`), nunca con un error crudo.
- El backend SHALL seguir sin manejar bytes.
- M3 (registro), M4 (colaboradores) y M6 (disponibilidad) SHALL seguir funcionando **sin depender del proveedor**: operan sobre `Photo.id`/`ownerId` y, donde tocaban `driveFileId`, sobre `storageRef.fileId`.

## Nota de contrato de API (aprobada por el PO — decisión 1)

El campo de referencia pasa de `driveFileId: "xxx"` a **`storageRef: { "provider": "google-drive", "fileId": "xxx" }`** en:
- **Entrada** de `POST /api/v1/photos` (registro): el cliente envía `storageRef` (o `fileId` + provider por defecto — a resolver en implementación, manteniéndolo simple).
- **Salida** en `GET /albums/:id` (fotos) y `GET /library`.

Es un cambio aditivo y seguro **ahora** porque aún no hay clientes en producción consumiéndolo (la app aún no implementó M3 app). Se documenta en el README del backend.

## Checklist de implementación

- [ ] Definir `StorageProvider` (`'google-drive'`) y `StorageRef { provider, fileId }`.
- [ ] Reemplazar `Photo.driveFileId` por `Photo.storageRef`; actualizar `PhotoRepository`, mocks y usos internos (`storageRef.fileId` donde antes iba `driveFileId`).
- [ ] Definir interfaz `PhotoStorage` (token `Symbol`) con operaciones del MVP implementadas y el resto declaradas como no soportadas (`NOT_IMPLEMENTED`/`STORAGE_OPERATION_UNSUPPORTED`).
- [ ] Implementar `GoogleDrivePhotoStorage` envolviendo el broker `drive-token` existente (sin duplicar lógica de auth).
- [ ] Ajustar `POST /photos` (entrada) y las respuestas de `GET /albums/:id` y `GET /library` (salida) a `storageRef`.
- [ ] Errores uniformes para operaciones no soportadas; validación manual de entrada.
- [ ] Actualizar tests existentes (spec03/04/06/07) al nuevo campo `storageRef`; añadir tests de la abstracción (provider correcto en registro; operación no soportada → error uniforme; el dominio no referencia "drive").
- [ ] Documentar en el README del backend el nuevo contrato y la abstracción.
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- `Photo` expone `storageRef { provider: 'google-drive', fileId }`; no queda `driveFileId` en el dominio ni en el contrato.
- Existe `PhotoStorage` (token + `GoogleDrivePhotoStorage`); las operaciones del MVP funcionan y las no soportadas fallan con código uniforme.
- El registro de foto y las lecturas exponen `storageRef`; el backend no maneja bytes.
- M3/M4/M6 siguen pasando con el nuevo campo (regresión verde).
- No se añadió B2, ni se cambiaron scopes, ni hay copia (M5) ni borrado en Drive.
- `build`, `test`, `test:e2e` pasan; contrato documentado.

## Dirección futura (informativo, NO implementar)

- Candidato serio para storage principal futuro: **Backblaze B2** (`ObjectStorage`), con Google Drive pasando a respaldo/exportación. La abstracción de esta spec es lo que permitirá añadir `B2PhotoStorage` sin tocar el dominio.
- **M5 (adoptar/copiar)** se retomará evaluando: (1) ampliar scopes de Google, (2) transferencia por descarga/subida, (3) storage propio de Memora, (4) otras. Criterios: privacidad, seguridad, costos, UX, requisitos OAuth, escalabilidad. Esta abstracción es su prerrequisito.

## Dependencias

- `memora-backend/spec04-fotografias.md` (Photo, registro) — PASS.
- `memora-backend/spec02-autenticacion-google.md` (broker `drive-token` que envuelve `GoogleDrivePhotoStorage`) — PASS.
- `memora-backend/spec07-disponibilidad.md` (disponibilidad; `describe/exists` se relacionan con el modelo de reporte) — PASS.
- `producto-mvp.md` (principio "no custodio"; propiedad de fotos sin cambios).
- Habilita: M7 (visor con referencias neutrales), M5 futuro, y un eventual storage propio.

## Notas de validación (Kiro) — PASS

**Veredicto: PASS** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK.
- `npm test` → **89 unit** pasan (8 suites; +11 respecto a M6, incluidos `google-drive-photo-storage.spec.ts` y el test de neutralidad de dominio).
- `npm run test:e2e` → **77/77** pasan a la primera. El cambio de contrato `driveFileId` → `storageRef` no rompió M2/M3/M4/M6.
- Grep: "b2"/"scope"/"drive" solo aparecen en **comentarios** (el tipo deja lugar a un futuro `'b2'`; scopes `drive.file` sin cambios). No se añadió B2 real ni se tocaron scopes.

**Criterios de la spec (todos cumplidos):**
- `Photo.storageRef { provider: 'google-drive', fileId }` reemplaza `driveFileId`; `StorageProvider` es unión de un solo miembro (deja lugar a futuros sin ensanchar a `string`).
- Existe `PhotoStorage` (token `PHOTO_STORAGE` + `GoogleDrivePhotoStorage` registrado en `AlbumsModule`). `GoogleDrivePhotoStorage` **reutiliza `AuthService.getDriveAccessToken`** (no duplica la lógica de auth; `AuthModule` ahora exporta `AuthService`).
- Operaciones del MVP implementadas: `getUploadAuthorization` (envuelve el drive-token), `getReadReference` (referencia neutral). Operaciones no soportadas (`describe`, `exists`, `download`, `stream`, `copy`, `delete`) lanzan **501 `STORAGE_OPERATION_UNSUPPORTED`** (uniforme), con doc que explica el porqué (bytes/Opción A, M5 diferido, "no custodio").
- `POST /photos` acepta `storageRef` (con default de provider `'google-drive'` si se omite) y las lecturas exponen `storageRef`.
- **Neutralidad de dominio verificada mecánicamente:** `domain-storage-neutrality.spec.ts` escanea `src/albums` (fuera de `photos/storage/` y specs) y falla si aparece `driveFileId`/`Drive` literal. Excelente decisión de calidad.
- Sin B2, sin cambio de scopes, sin copia (M5), sin borrado en Drive, backend sin bytes.

**Detalles de calidad:** el test de neutralidad de dominio hace cumplir la regla normativa de la spec por construcción, no por convención. La interfaz documenta operación por operación qué está implementado y qué no y por qué. Sin deuda nueva.
