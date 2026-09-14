# spec04 — Fotografías: registro y coordinación (backend)

**Ámbito:** memora-backend
**Estado de validación:** PASS (validado por Kiro: 31 unit + 38 e2e; backend no maneja bytes; N:M y borrado sin tocar Drive verificados)
**Backlog:** M3 (Fotografías) — parte backend

## Objetivo

Implementar en `memora-backend` el **registro de fotografías** (referencias + metadatos) y la **coordinación de su subida** a Google Drive, respetando la Opción A: el dispositivo optimiza y sube los bytes directamente a Drive; el backend NO recibe ni almacena los bytes, solo orquesta y guarda referencias/relaciones.

## Contexto y decisiones que aplican

- Ver `producto-mvp.md`. Relevantes: principio "Memora no es custodio"; subida directa cliente→Drive (Opción A); metadatos mínimos (D8, sin geolocalización); modelo N:M foto↔álbum; estructura de Drive organizativa (no carpeta por álbum); disponibilidad perezosa (D9).
- La entidad `Photo` y el `PhotoRepository` ya existen a nivel mínimo (creados en M2/spec03). Esta spec los completa.
- La **optimización de imágenes y la subida real de bytes son de la app** (M3 app), no del backend. Aquí NO se construye optimización ni transferencia de bytes.
- El token efímero de Drive para que el cliente suba lo provee `POST /api/v1/auth/drive-token` (ya existe, spec02).

## Alcance (backend)

- Completar la entidad `Photo` con los metadatos mínimos (D8).
- Registrar una foto en Memora tras subirla el cliente a Drive: el cliente informa `driveFileId` + metadatos; el backend crea la `Photo` (propiedad del usuario) y opcionalmente la asocia a un álbum.
- Asociar/quitar una foto de un álbum (relación N:M).
- Listar las fotos de la **biblioteca** del usuario (`GET /api/v1/library`) y confirmar el detalle de fotos de un álbum (ya expuesto en M2 vía `GET /albums/:id`).
- Quitar una foto de un álbum (solo relación, no borra archivo — D3) y quitar una foto de la biblioteca (elimina la referencia en Memora; NO borra de Drive).

## Fuera de alcance

- Optimización de imágenes y subida de bytes (M3 app).
- Colaboradores (M4): aquí las fotos son del owner que las registra.
- Adopción/copia cross-Drive (M5).
- Verificación de disponibilidad contra Drive (M6) — se define allí; aquí solo se guarda el campo de estado.
- Thumbnails (los provee Drive/ю cliente; el backend solo guarda referencia).

## Flujo de registro (coordinación, sin bytes)

```
App: optimiza la foto y pide POST /auth/drive-token (scope drive.file)
App: sube los BYTES directo a Drive del usuario -> obtiene driveFileId
App: POST /api/v1/photos { driveFileId, metadatos, albumId? }
Backend: crea Photo (owner = usuario), la asocia al álbum si albumId viene
Backend: responde la Photo registrada (referencia + metadatos)
```

## Comportamiento esperado

### Registro de fotos
- El backend SHALL exponer `POST /api/v1/photos` (autenticado) que reciba `driveFileId` y metadatos (D8) y cree una `Photo` cuyo **propietario es el usuario autenticado**. Opcionalmente acepta `albumId` para asociarla de una vez.
- La `Photo` SHALL guardar solo los metadatos mínimos (D8): id Memora, `driveFileId`, ownerId, fecha de incorporación, fecha de captura (si viene), dimensiones, tipo/formato, tamaño, estado de disponibilidad (por defecto "disponible"). NO SHALL guardar geolocalización.
- Si se envía `albumId`, el usuario SHALL ser owner de ese álbum (si no, 404 como en M2), y la foto se asocia.

### Asociación a álbumes (N:M)
- El backend SHALL exponer `POST /api/v1/albums/:albumId/photos` (autenticado, owner) para asociar una foto **ya existente** del usuario a un álbum.
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/photos/:photoId` (autenticado, owner) que **quita la relación** foto↔álbum, sin borrar la foto ni el archivo de Drive (D3/D4).
- Asociar la misma foto a un álbum dos veces NO SHALL duplicarla.

### Biblioteca
- El backend SHALL exponer `GET /api/v1/library` (autenticado) que devuelve las fotos propiedad del usuario conocidas por Memora (independiente de álbumes) (D11).
- El backend SHALL exponer `DELETE /api/v1/photos/:photoId` (autenticado, owner) que elimina la **referencia** de la foto en Memora y todas sus relaciones con álbumes, **sin borrar el archivo de Drive** (principio: Memora no borra de Drive).

### Reglas
- El backend NO SHALL recibir, almacenar ni proxear los bytes de las fotografías.
- Todas las operaciones requieren sesión válida (guard existente). Foto o álbum ajeno/inexistente → 404 uniforme.
- El backend SHALL usar el `driveFileId` como referencia estable (nunca nombre/ruta).

## Checklist de implementación

- [x] Completar el modelo `Photo` con los metadatos mínimos (D8) y validación de entrada.
- [x] Completar `PhotoRepository` (crear, findById, findByOwner, delete + limpiar relaciones) — mock en memoria.
- [x] Implementar `POST /api/v1/photos` (registro; owner = usuario; asociación opcional a álbum).
- [x] Implementar `POST /api/v1/albums/:albumId/photos` y `DELETE /api/v1/albums/:albumId/photos/:photoId` (asociar/quitar relación; owner-only, idempotente).
- [x] Implementar `GET /api/v1/library`.
- [x] Implementar `DELETE /api/v1/photos/:photoId` (elimina referencia + quita de TODOS los álbumes; nunca toca Drive).
- [x] Validaciones y autorización (owner-only; 404 uniforme para ajeno/inexistente; 400 para entrada inválida).
- [x] Pruebas unitarias (registro, N:M asociar/quitar sin duplicar, borrar foto quita de todos los álbumes, biblioteca) y e2e de los endpoints. 31 unit + 38 e2e.
- [x] Documentar endpoints en el README del backend.
- [x] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.

## Notas de validación (Kiro) — PASS

- 31 unit + 38 e2e pasan; build OK. "El backend no maneja bytes" es cierto por construcción (no hay cliente de Drive en el service).
- `DELETE /photos/:id` verificado: quita la foto de todos los álbumes y olvida la referencia, sin tocar Drive.
- **Deuda técnica documentada (no bloqueante):** flake residual de transporte en e2e (supertest + apps Nest efímeras), ~1 fallo aislado cada varias corridas, nunca de lógica. Decisión Tech Lead: no profundizar ahora (forzar `Connection: close` o unificar apps es infra de testing con poco retorno para el MVP). `auth.e2e` se deja sin migrar a `beforeAll` a propósito (muta sesión compartida).

## Criterios de validación (los revisa Kiro)

- Registrar una foto crea una `Photo` del usuario con metadatos mínimos y sin geolocalización.
- Asociar/quitar fotos de álbumes funciona (N:M, sin duplicar); quitar la relación no borra la foto ni el archivo.
- `GET /library` devuelve las fotos del usuario; `GET /albums/:id` muestra las asociadas.
- `DELETE /photos/:id` elimina la referencia en Memora y sus relaciones, y NO borra nada de Drive.
- El backend nunca maneja bytes de imágenes.
- Sesión requerida (401); ajeno/inexistente → 404 uniforme.
- build + test + e2e pasan; endpoints documentados.

## Nota de verificación (para Kiro)

- La prueba end-to-end real (subir una foto a Drive y registrarla) requiere la app (M3 app). En backend, Kiro valida con tests que el registro/coordinación funcionan usando `driveFileId` simulados. La subida real se prueba cuando llegue la app.

## Decisiones de producto (aprobadas por el PO)

- **`DELETE /photos/:id`**: si la foto está en varios álbumes, se quita de **todos** y se elimina su referencia en Memora (Memora la olvida). El archivo **permanece** en Drive.
- **Registro de fotos en un álbum**: en esta fase solo el **owner** del álbum registra/asocia fotos. El aporte de colaboradores llega en M4.

## Dependencias

- `memora-backend/spec03-biblioteca-albumes.md` (álbumes, `Photo` mínima, N:M) — PASS.
- `memora-backend/spec02-autenticacion-google.md` (`drive-token`, guard) — PASS.
- Habilita: M3 app (optimización + subida real) y M6 (disponibilidad).
