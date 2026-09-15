# spec04 — UI de álbumes (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones A–E cerradas por el PO, 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** M2/M3 en app — UI de álbumes. FASE 2 (app), ítem B del ROADMAP. Consume el backend de M2/M3 (ya PASS) y reutiliza el flujo de subida de `memora-app/spec03` (validado en dispositivo).

## Objetivo
Implementar en `memora-app` la interfaz de **álbumes**: ver la lista de álbumes (propios y donde el usuario colabora), crear un álbum, abrirlo y ver sus fotos, renombrarlo y cambiar su visibilidad (solo owner), eliminarlo (solo owner), y agregar/quitar fotos. Reutiliza el flujo de subida de fotos de spec03 pasando el `albumId` de contexto.

## Contexto y decisiones que aplican
Fuente de verdad de producto: `specs/producto-mvp.md`. Aplican:
- **D1 — Roles.** Dos roles por álbum: **Owner** (administra álbum + colaboradores) y **Collaborator** (ve todo y aporta lo suyo, **no** administra el álbum ni colaboradores). La UI SHALL distinguir el rol y **ocultar/deshabilitar** las acciones de administración (renombrar, cambiar visibility, eliminar) cuando el usuario es collaborator.
- **D11 — Biblioteca vs álbumes.** La biblioteca personal (fotos que Memora conoce del usuario) es distinta de los álbumes (agrupaciones). Una foto puede estar en varios álbumes sin duplicarse (N:M).
- **D16 — Eliminar álbum.** Elimina la agrupación y sus relaciones, **no** las fotografías (ni de Drive ni de la biblioteca). La UI SHALL dejarlo explícito en la confirmación de borrado.
- **D17 — Visibilidad del álbum.** `PRIVATE`/`PUBLIC` (default `PRIVATE`), editable **solo por el owner**. Sin catálogo/descubrimiento público (KISS).

## Contrato real del backend (ya verificado — usar tal cual)
- `POST /api/v1/albums` body `{ name, visibility? }` (`visibility` = `'PRIVATE'|'PUBLIC'`, opcional, default `PRIVATE`) → `AlbumSummary` `{ id, name, visibility, photoCount, createdAt, updatedAt }`. Nombre máx **100** chars.
- `GET /api/v1/albums` → lista de `AlbumListItem` = `AlbumSummary` + `role` (`'owner'|'collaborator'`). Incluye álbumes propios **y** donde el usuario colabora.
- `GET /api/v1/albums/:id` → `AlbumDetail` = `AlbumSummary` + `photos: Photo[]`. Accesible por owner **y** colaboradores; sin membresía → **404 uniforme**.
- `PATCH /api/v1/albums/:id` body `{ name?, visibility? }` (al menos uno; si ninguno → **400 `INVALID_REQUEST`**). **Owner-only**; ajeno/inexistente → **404**.
- `DELETE /api/v1/albums/:id` → **204**. Owner-only. Elimina agrupación y relaciones, **no** las fotos ni archivos de Drive (D16).
- `POST /api/v1/albums/:albumId/photos` → **204** (asocia foto existente del usuario, N:M, idempotente). `DELETE /api/v1/albums/:albumId/photos/:photoId` → **204** (quita la relación; no borra archivo, D3/D4).
- `Photo` incluye `storageRef { provider, fileId }`, `availability` (`'available'|'unavailable'`) y metadatos (`width`, `height`, `mimeType`, `capturedAt`...). Las miniaturas se obtienen de Drive con el `fileId` + `drive-token` (la app ya lo tiene, spec03).

## Alcance (UI app)
- **Extender `ApiClient`** con métodos PATCH y DELETE (hoy solo tiene GET/POST), reutilizando el mapeo a `ApiException { statusCode, code, message, requestId }`.
- **Capa `AlbumsApi`** (patrón `*Api` sobre `ApiClient`) con crear/listar/detalle/actualizar/eliminar/asociar/quitar.
- **Controlador de estado** `AlbumsController` (`ChangeNotifier`, patrón de `AuthController`).
- **Modelos** `Album`/`AlbumListItem`/`AlbumDetail` y extensión del modelo `Photo` de la app para incluir `availability`.
- **Navegación:** introducir el primer stack de `Navigator` de la app (hoy todo vive en `home_screen`).
- **Pantalla lista de álbumes:** propios + colaborando, con indicador de **rol** y **photoCount**; acción "crear álbum".
- **Crear álbum:** nombre (validación ≤100 chars) y visibilidad (ver decisión D).
- **Pantalla detalle de álbum:** grid de miniaturas (ver decisión A), fotos `unavailable` marcadas (M6); acción "agregar fotos" (reusa el flujo de spec03 con `albumId`); quitar una foto del álbum; acciones de administración (renombrar, cambiar visibility, eliminar) **solo si owner**.
- **Eliminar álbum:** confirmación que aclara que **no** borra las fotos de Drive (D16).

## Fuera de alcance
- UI de colaboradores/invitaciones (ítem C del ROADMAP).
- Compartir/visor y NFC/QR en app (ítem F).
- Refresco de sesión / re-autorización de Drive (ítem E).
- Pantalla dedicada de "biblioteca personal" (ver decisión B).
- Diseño visual final.

## Comportamiento esperado (normativo)
### Lista de álbumes
- La app SHALL listar, vía `GET /api/v1/albums`, los álbumes propios y en los que colabora, mostrando por cada uno nombre, `photoCount` y un indicador de **rol** (owner/collaborator).
- La app SHALL ofrecer una acción para **crear álbum**.
### Crear álbum
- La app SHALL crear un álbum vía `POST /api/v1/albums` con `name` (obligatorio, ≤100 chars) y `visibility` según la decisión D.
- Nombre vacío o >100 chars SHALL mostrarse como error de validación **antes** o **según** la respuesta 400 del backend, sin filtrar detalles internos.
### Detalle y fotos
- Al abrir un álbum, la app SHALL cargar `GET /api/v1/albums/:id` y mostrar sus fotos en un grid de miniaturas.
- Las miniaturas SHALL obtenerse desde Drive usando el `fileId` + `drive-token` (según la decisión A). Si falta el drive-token (`DRIVE_REAUTHORIZATION_REQUIRED`), la app SHALL avisar sin romper la pantalla.
- Las fotos con `availability == 'unavailable'` SHALL mostrarse **marcadas** como no disponibles (M6), no ocultas (esto es vista autenticada).
- La app SHALL permitir **agregar fotos** al álbum reutilizando el flujo de subida de spec03 (pasando el `albumId`), y **quitar** una foto del álbum vía `DELETE /api/v1/albums/:albumId/photos/:photoId` (solo quita la relación).
### Administración (owner-only, D1)
- La app SHALL permitir **renombrar** y **cambiar visibility** vía `PATCH /api/v1/albums/:id`, y **eliminar** vía `DELETE`, **solo cuando el rol es owner**. Para collaborator, estas acciones SHALL estar ocultas o deshabilitadas.
- La eliminación SHALL pedir confirmación que aclare que **no se borran las fotografías** (D16).
- Un 404 al operar (álbum ajeno/inexistente) SHALL tratarse como "no disponible" sin revelar existencia.
### Transversales
- Toda llamada al backend SHALL pasar por `ApiClient` (Bearer de sesión adjunto); nunca `http` directo al backend.
- Ningún token SHALL escribirse en logs. Errores con mensajes claros, sin filtrar detalles internos.
- UI mínima funcional (sin diseño final), consistente con el estilo de `home_screen`.

## Decisiones (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **A — Miniaturas de Drive: descargar con el `drive-token` en el header `Authorization`** (patrón hermano del servicio de subida de spec03), con caché en memoria/disco. No se usan URLs crudas de Drive (`thumbnailLink`/`webContentLink`), que exigen auth de Google y caducan. Coherente con `drive.file`.
- **B — Sin pantalla de "biblioteca personal" en este corte.** Solo álbumes; la biblioteca (`GET /library`) se aborda en una spec posterior.
- **C — "Agregar fotos a un álbum" = solo subir fotos nuevas** (reutiliza el flujo de spec03 pasando el `albumId`) + quitar la relación del álbum. Asociar fotos **ya existentes** de la biblioteca queda para cuando exista esa pantalla (junto con B).
- **D — Visibility solo al editar.** La creación pide únicamente el nombre (el álbum nace `PRIVATE` por default, D17); cambiar a `PUBLIC` es una acción consciente posterior vía `PATCH`.
- **E — Navegación: `Navigator` nativo de Flutter** (push/pop lista → detalle → crear), sin paquete de routing pesado por ahora.

## Checklist de implementación
- [ ] Extender `ApiClient` con `patchJson` y `delete` (o equivalentes), reutilizando el mapeo a `ApiException`.
- [ ] Modelos `Album`, `AlbumListItem` (con `role`), `AlbumDetail` (con `photos`), y extender `Photo` con `availability`.
- [ ] `AlbumsApi` (patrón `*Api`): crear, listar, detalle, `PATCH` (name/visibility), `DELETE`, asociar/quitar foto.
- [ ] `AlbumsController` (`ChangeNotifier`): estado de lista y de detalle, carga, errores, refresco tras crear/editar/eliminar/asociar.
- [ ] Servicio de miniaturas de Drive según decisión A (probable A1: descarga con `drive-token`, con caché).
- [ ] Navegación con `Navigator`: lista → detalle → crear.
- [ ] Pantalla lista: álbumes propios + colaborando, rol, photoCount, acción crear.
- [ ] Pantalla crear: nombre (≤100) y visibility según decisión D.
- [ ] Pantalla detalle: grid de miniaturas; fotos `unavailable` marcadas; "agregar fotos" (reusa spec03 con `albumId`); quitar foto del álbum; acciones owner-only (renombrar, visibility, eliminar) ocultas/deshabilitadas para collaborator; confirmación de borrado que aclara D16.
- [ ] Manejo de errores (400 al crear/editar, 404 ajeno/inexistente, `DRIVE_REAUTHORIZATION_REQUIRED` al cargar miniaturas) con mensajes claros; sin tokens en logs.
- [ ] `flutter analyze` pasa y el proyecto compila.

## Criterios de validación (los valida el PO en el dispositivo)
> Metodología vigente (2026-09-14): la validación la hace el PO en el dispositivo real; Kiro no corre validación por defecto.
- El usuario ve sus álbumes (propios y donde colabora) con rol y cantidad de fotos.
- Puede crear un álbum; el nombre inválido se maneja con mensaje claro.
- Al abrir un álbum ve las miniaturas de sus fotos; las no disponibles aparecen marcadas.
- Puede agregar fotos al álbum (subida reutilizando el flujo ya validado) y quitar una foto del álbum sin que desaparezca de Drive.
- Siendo **owner**: puede renombrar, cambiar visibility y eliminar (con confirmación que aclara que no borra las fotos). Siendo **collaborator**: esas acciones no están disponibles.
- Ningún token aparece en logs; los errores no filtran detalles internos.
- `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec01-fundacion-app.md` (`ApiClient`) — PASS.
- `memora-app/spec02-login-google.md` (sesión + Bearer + `drive-token`) — PASS.
- `memora-app/spec03-fotografias.md` (flujo de subida reutilizable con `albumId`; servicio de Drive) — validado en dispositivo.
- `memora-backend/spec03-biblioteca-albumes.md` y `spec04-fotografias.md` (endpoints de álbumes y fotos) — PASS.
- **Se relaciona con** (fuera de alcance aquí): UI de colaboradores (ítem C), compartir/visor y NFC/QR (ítem F), refresh/re-auth (ítem E).
