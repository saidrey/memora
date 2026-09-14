# spec03 — Biblioteca y álbumes (backend)

**Ámbito:** memora-backend
**Estado de validación:** PASS (validado por Kiro: 20 unit + 26 e2e; N:M y D16 verificados)
**Backlog:** M2 (Biblioteca personal y álbumes)

## Objetivo

Implementar en `memora-backend` el modelo y la API de **álbumes** y **biblioteca personal** del usuario autenticado: crear, listar, abrir, renombrar y eliminar álbumes, respetando el modelo lógico N:M (una foto puede estar en varios álbumes) y el principio de que Memora guarda referencias/relaciones, no fotos.

## Contexto y decisiones de producto que aplican

- Ver `specs/producto-mvp.md`. Relevantes aquí: D11 (biblioteca = solo fotos que Memora conoce), D16 (eliminar álbum = eliminar agrupación, no fotos), N:M foto↔álbum.
- Persistencia: **mocks en memoria** detrás de interfaces (patrón ya establecido; migrable a Postgres/Neon sin tocar lógica).
- Autenticación: los endpoints de gestión requieren sesión JWT (guard ya existente de spec02).
- Esta spec cubre **álbumes y biblioteca**; las **fotos** (subir/optimizar/asociar) son M3 (spec posterior). Aquí se define la entidad álbum y sus relaciones, dejando la incorporación de fotos para M3.

## Alcance

- Entidad **Album** (id, ownerId, nombre, fechas, orden/estado básico).
- Entidad **Photo** a nivel de modelo mínimo y la **relación N:M Photo↔Album** (la creación de fotos es M3; aquí se define el modelo y la relación para que M3 se apoye en él).
- Concepto de **Biblioteca personal**: el conjunto de fotos que pertenecen al usuario dentro de Memora (se materializa plenamente con M3; aquí se define su significado y el endpoint de consulta preparado).
- API de álbumes: crear, listar (propios), obtener uno (con sus fotos), renombrar, eliminar.
- Interfaces `AlbumRepository` (y la parte de relación que necesite), con implementación mock en memoria.

## Fuera de alcance

- Subida/optimización de fotos y su almacenamiento en Drive (M3).
- Colaboradores y compartición (M4/M7): en esta spec, un álbum solo lo maneja su owner.
- NFC/QR (M8).
- Adopción (M5) y disponibilidad de archivos (M6).

## Comportamiento esperado

### Álbumes
- El backend SHALL exponer `POST /api/v1/albums` (autenticado) para crear un álbum con un nombre; el usuario autenticado queda como **owner**.
- El backend SHALL exponer `GET /api/v1/albums` (autenticado) que devuelve los álbumes de los que el usuario es owner, con datos básicos (id, nombre, conteo de fotos, fechas).
- El backend SHALL exponer `GET /api/v1/albums/:id` (autenticado) que devuelve el álbum y la lista de sus fotos (referencias/metadatos), solo si el usuario es owner (colaboradores llegan en M4).
- El backend SHALL exponer `PATCH /api/v1/albums/:id` (autenticado) para renombrar el álbum, solo por su owner.
- El backend SHALL exponer `DELETE /api/v1/albums/:id` (autenticado) que elimina el álbum y **todas las relaciones foto↔álbum de ese álbum**, sin eliminar ninguna foto ni archivo de Drive (D16).
- El backend SHALL responder **404 (formato uniforme) tanto si el álbum no existe como si es de otro usuario** (aprobado por PO: no revelar la existencia de álbumes ajenos).
- Un álbum recién creado SHALL poder quedar **vacío** (sin fotos); las fotos se agregan después (M3). (Aprobado por PO.)

### Biblioteca personal y relación N:M
- El modelo SHALL representar que una **foto pertenece a un único propietario** y puede estar relacionada con **múltiples álbumes** (N:M), sin duplicar la foto.
- La **Biblioteca personal** SHALL definirse como el conjunto de fotos propiedad del usuario conocidas por Memora (independiente de a qué álbumes pertenezcan). El endpoint de consulta de biblioteca puede prepararse aquí y completarse con M3.
- Eliminar un álbum NO SHALL eliminar fotos de la biblioteca ni relaciones de esas fotos con **otros** álbumes.

### Reglas
- Toda operación de gestión SHALL requerir sesión válida (guard JWT existente).
- El backend NO SHALL crear carpetas por álbum en Drive; los álbumes son entidades lógicas (precisión de producto: estructura de Drive organizativa, no por álbum).

## Checklist de implementación

- [ ] Definir el módulo `albums` en `memora-backend`.
- [ ] Definir el modelo `Album` (id, ownerId, name, createdAt, updatedAt) y el modelo mínimo de `Photo` + relación N:M `Photo↔Album` (a nivel de tipos/repositorio; la creación real de fotos es M3).
- [ ] Definir la interfaz `AlbumRepository` (crear, listar por owner, obtener por id, renombrar, eliminar + limpiar relaciones del álbum) e implementación **mock en memoria**.
- [ ] Implementar los endpoints: `POST/GET/GET:id/PATCH:id/DELETE:id /api/v1/albums`, todos protegidos por el guard de sesión.
- [ ] Validación de entrada (nombre no vacío, longitud razonable) devolviendo error uniforme en 400.
- [ ] Autorización: solo el owner accede/gestiona su álbum; respuestas apropiadas si no.
- [ ] `DELETE` elimina álbum + relaciones foto↔álbum de ese álbum, sin tocar fotos ni Drive.
- [ ] Pruebas: unitarias del servicio (crear/listar/obtener/renombrar/eliminar; N:M; que eliminar álbum no borra fotos) y e2e de los endpoints (éxito + 400/401/404 con formato uniforme).
- [ ] Documentar los endpoints en el README del backend.
- [ ] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- Un usuario autenticado crea un álbum y queda como owner; aparece en su listado.
- `GET /albums` devuelve solo los álbumes del usuario; `GET /albums/:id` devuelve el álbum con sus fotos (vacío por ahora).
- Renombrar funciona solo para el owner; un tercero no puede.
- Eliminar un álbum quita el álbum y sus relaciones foto↔álbum, y NO elimina fotos ni sus relaciones con otros álbumes (verificado con una foto en 2 álbumes).
- El modelo soporta N:M foto↔álbum sin duplicar la foto.
- Sin sesión → 401 uniforme; álbum inexistente o ajeno → **404** uniforme en ambos casos.
- Se puede crear un álbum vacío y aparece en el listado con conteo de fotos 0.
- No se crean carpetas por álbum en Drive.
- `build`, `test`, `test:e2e` pasan; endpoints documentados.

## Decisiones de producto (aprobadas por el PO)

- Un álbum puede crearse **vacío**.
- Álbum inexistente o ajeno → **404** en ambos casos (no revelar existencia de álbumes ajenos).
- `GET /library` como endpoint HTTP queda para M3 (aquí solo se prepara `PhotoRepository.findByOwner`).

## Notas de validación (Kiro) — PASS

- 20 unit + 26 e2e pasan; build OK. Verificado el caso D16 (foto en 2 álbumes: borrar uno no afecta al otro ni a la foto) y el N:M sin duplicación.
- Fix de DI: `AuthModule` ahora exporta `SessionAuthGuard` + `SessionTokenService` (necesario para reusar el guard en `AlbumsModule`).
- Flake de test-infra (socket reciclado entre apps Nest efímeras) resuelto en `albums.e2e-spec.ts` con `beforeAll/afterAll`. Deuda menor: mismo patrón aplicaría a `auth.e2e`/`app.e2e` si crecen.

## Dependencias

- `memora-backend/spec02-autenticacion-google.md` (guard de sesión) — PASS.
- `producto-mvp.md` (D11, D16, modelo N:M).
- Habilita: M3 (fotos) que añadirá la creación de fotos y su asociación a álbumes.
