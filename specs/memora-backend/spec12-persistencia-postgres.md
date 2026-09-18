# spec12 — Persistencia PostgreSQL (backend)

**Ámbito:** memora-backend
**Estado de validación:** 📝 BORRADOR (aprobada por el PO; pendiente de implementación y validación por Kiro).
**Backlog:** ítem 12 de FASE 1 (backend). Completa el backend para el MVP: reemplaza la persistencia in-memory por PostgreSQL. Requisito previo real de cualquier despliegue.

## Objetivo

Reemplazar **todas** las implementaciones in-memory de persistencia por implementaciones **PostgreSQL**, respetando **exactamente** las interfaces existentes (contratos detrás de token `Symbol`). Es una **migración de capa, no de funcionalidad**: no cambia servicios, controllers ni el contrato de API, no toca decisiones de producto D1–D17, no añade endpoints. Al terminar, el estado del backend sobrevive a reinicios del proceso.

**No** cambia el almacenamiento de fotos (`GoogleDrivePhotoStorage`, spec08): solo se persisten los **metadatos y entidades de dominio**, no los bytes (el backend sigue sin manejar bytes).

## Contexto y decisiones que aplican

- Estado actual verificado: la persistencia es **100% in-memory**. Cada pieza de estado ya está detrás de una **interfaz + token `Symbol`** con una implementación `InMemory*` (patrón consolidado en spec01/spec08/spec11). Esta spec añade, junto a cada `InMemory*`, una implementación `Postgres*` **sin cambiar la interfaz**.
- **Hosting (decisión del PO):** la Postgres corre en **Neon** (Postgres gestionado), como ya fijaba `specs/README.md` — **sin cambios de documentación**. Neon se usa **solo como Postgres**; no se usan Auth/Storage/otros servicios de ningún proveedor. La app se conecta por **connection string** estándar, por lo que una Postgres local o cualquier otra Postgres es intercambiable sin lógica específica de proveedor.
- La autenticación (Google + JWT propios) y el storage de fotos (Google Drive) **no cambian**: siguen como en spec02 y spec08.
- `spec11` dejó `SessionRegistry` detrás de interfaz **precisamente** anticipando este momento ("frontera para un datastore real futuro Redis/Postgres"). Esta spec materializa ese adaptador.

## Alcance de la migración (inventario verificado)

Se migran **los 9 stores de persistencia in-memory** (decisión del PO, alcance completo). Para cada uno: nueva clase `Postgres*` que implementa la interfaz existente, registrada en su módulo reemplazando el `useClass` in-memory.

### Dominio de álbumes (`src/albums`)
1. `ALBUM_REPOSITORY` / `InMemoryAlbumRepository` → `PostgresAlbumRepository`. Incluye la **relación N:M foto↔álbum** que hoy vive embebida como `Map<albumId, Set<photoId>>` → pasa a **tabla join `album_photos`**. Debe preservar la aislación de borrado (D16).
2. `PHOTO_REPOSITORY` / `InMemoryPhotoRepository` (`src/albums/photos`) → `PostgresPhotoRepository`. Persiste `storageRef` (ver "Mapeo de `storageRef`").
3. `MEMBERSHIP_REPOSITORY` / `InMemoryMembershipRepository` (`src/albums/collaborators`) → `PostgresMembershipRepository`.
4. `INVITATION_REPOSITORY` / `InMemoryInvitationRepository` (`src/albums/collaborators`) → `PostgresInvitationRepository`.
5. `SHARE_LINK_REPOSITORY` / `InMemoryShareLinkRepository` (`src/albums/shared`) → `PostgresShareLinkRepository`.
6. `NFC_QR_TAG_REPOSITORY` / `InMemoryNfcQrTagRepository` (`src/albums/nfc-qr`) → `PostgresNfcQrTagRepository`.

### Auth (`src/auth`)
7. `USER_REPOSITORY` → `PostgresUserRepository`. **Crítico:** sin usuarios persistentes, los álbumes referencian un `ownerId` que desaparece al reiniciar (quedarían huérfanos). Es el ancla de integridad referencial.
8. `TOKEN_STORE` (refresh token de Google) → `PostgresTokenStore`. **Frontera de cifrado-at-rest** (ver "Cifrado del refresh token").
9. `SESSION_REGISTRY` (spec11) → `PostgresSessionRegistry`. **Atención:** la interfaz `SessionRegistry` es hoy **síncrona** (única excepción del backend). Migrarla a SQL obliga a volver la interfaz **async** (`Promise<...>`) y ajustar sus consumidores en `AuthService`. Este es el único cambio de firma de interfaz permitido por esta spec, y es puramente de asincronía (misma semántica).

## Decisiones técnicas cerradas (aprobadas por el PO)

- **B — ORM/driver:** **Kysely + `pg`** (query builder tipado sobre SQL explícito). Elegido porque respeta la arquitectura actual (repos detrás de interfaz, dominio sin acoplar a un ORM): cada `Postgres*Repository` es una clase que cumple la interfaz y compone SQL con Kysely, sin decoradores de entidad ni active-record que filtren al dominio. No se introduce TypeORM ni Prisma.
- **C — Migraciones:** **versionadas** (migraciones SQL/Kysely bajo control de versiones, aplicadas explícitamente). **Nunca** `synchronize`/auto-DDL contra una base real. Un script de migración corre antes de arrancar en prod y en el entorno de integración.
- **D — `storageRef`:** **dos columnas planas** en `photos`: `storage_provider` (texto, hoy siempre `'google-drive'`) y `storage_file_id` (texto). Nada de jsonb. El repositorio recompone `storageRef = { provider, fileId }` al leer, respetando spec08.
- **E — Tests:** los `InMemory*` **se conservan** como fakes. Los **unit** siguen instanciando los `InMemory*` con `new` (sin cambios). Los **e2e** siguen corriendo contra `InMemory*` vía override (decisión del PO: e2e lo más simples posible, **no bloqueantes**, sin requerir Postgres). La cobertura de la capa SQL se cubre con **tests de integración por repositorio** contra una Postgres real, **opcionales y no bloqueantes** (se corren a demanda, no en el flujo normal de `npm test`).
- **F — Alcance:** **los 9 stores** (ver inventario).
- **G — Cifrado del refresh token:** el refresh token de Google en `TOKEN_STORE` se **cifra at-rest con AES-256-GCM**, con clave desde env (`TOKEN_ENCRYPTION_KEY`). Nunca se persiste en claro. Descifrado solo en memoria al usarlo.

## Configuración (patrón `@nestjs/config`, sin hardcodear)

Añadir al `.env.example` (y documentar en README) siguiendo el patrón existente:

- `DATABASE_URL` — connection string Postgres estándar. En Neon usar la variante **pooled** (host con `-pooler`) para la app. Neon exige `sslmode=require` (viene en la string).
- `DATABASE_DIRECT_URL` (opcional) — connection string **direct** (sin pooler) para **correr migraciones**. Si se omite, migraciones usan `DATABASE_URL`.
- `TOKEN_ENCRYPTION_KEY` — clave (32 bytes, p. ej. base64/hex) para AES-256-GCM del refresh token (G). Obligatoria en cualquier entorno que persista `TOKEN_STORE`.

Ningún valor real se commitea; `.env.example` lleva solo placeholders/comentarios, igual que las demás variables.

## Comportamiento esperado (normativo)

- Cada `Postgres*Repository` SHALL implementar su interfaz existente **sin cambiar la firma** (única excepción: `SessionRegistry` pasa a async, ver alcance #9). Servicios y controllers NO SHALL cambiar.
- El contrato de API (endpoints, códigos de estado, formas de request/response, errores uniformes) SHALL permanecer **idéntico**. Esta spec no altera comportamiento observable salvo la durabilidad.
- La generación de `id` y `timestamps` SHALL replicar el contrato actual de cada repo (hoy los generan los repos internamente; la impl SQL debe producir los mismos valores/formatos, no delegar a defaults de columna que cambien el formato observable).
- La relación foto↔álbum SHALL persistirse en `album_photos` y SHALL preservar la aislación de borrado (D16): borrar un álbum no borra la foto ni afecta su presencia en otros álbumes.
- `photos.storage_provider` / `photos.storage_file_id` SHALL recomponerse como `storageRef` al leer (spec08 intacta).
- `TOKEN_STORE` SHALL cifrar el refresh token con AES-256-GCM antes de escribir y descifrar solo en memoria al leer; el valor en columna SHALL ser ciphertext (nunca el token en claro).
- Las migraciones SHALL ser versionadas y aplicarse explícitamente; NO SHALL usarse auto-DDL/synchronize contra una base real.
- El esquema SHALL declarar las claves foráneas de integridad (p. ej. `albums.owner_id` → `users.id`, `album_photos` → `albums`/`photos`) con el comportamiento de borrado que preserve las reglas de dominio ya especificadas.
- El backend SHALL seguir **sin manejar bytes** de fotos.

## Fuera de alcance (explícito)

- Migrar/portar datos existentes (no hay datos en prod; es la primera persistencia real).
- Cambiar cualquier decisión de producto D1–D17, endpoints o contrato de API.
- Servicios de Neon distintos de Postgres (Auth/Storage/etc.).
- Redis u otro datastore para sesiones (se usa Postgres; Redis queda como dirección futura si el volumen lo pidiera).
- Testcontainers / levantar Postgres automáticamente en el flujo de tests por defecto (los e2e siguen con InMemory; integración es opcional).
- KMS/gestión de claves gestionada (se resuelve con la infra de despliegue; aquí `TOKEN_ENCRYPTION_KEY` por env es el mínimo).
- Dockerfile / pipeline de despliegue (spec aparte de infraestructura).

## Checklist de implementación

- [ ] Añadir dependencias: `kysely`, `pg` (+ tipos). Configurar la instancia de Kysely como provider inyectable (pool `pg` desde `DATABASE_URL`, SSL).
- [ ] Definir el **esquema** (migraciones versionadas): `users`, `albums`, `photos` (con `storage_provider`, `storage_file_id`), `album_photos` (join N:M), `memberships`, `invitations`, `share_links`, `nfc_qr_tags`, `refresh_tokens` (token cifrado), `sessions`/`session_jti` (registry). Claves foráneas e índices según reglas de dominio.
- [ ] Script de migración (aplicar/rollback) usando `DATABASE_DIRECT_URL` si está presente.
- [ ] Implementar los 9 `Postgres*` respetando cada interfaz; recomponer entidades de dominio al leer (sin filtrar detalles SQL al dominio).
- [ ] Volver `SessionRegistry` async y ajustar `AuthService` (los 2 consumidores) + su spec.
- [ ] `TOKEN_STORE`: cifrado AES-256-GCM con `TOKEN_ENCRYPTION_KEY` (helper de cifrado reutilizable; nonce por registro).
- [ ] Registrar los providers Postgres en sus módulos (`AlbumsModule`, `AuthModule`) reemplazando `useClass: InMemory*`. Conservar las clases `InMemory*` para tests.
- [ ] `.env.example` + README del backend: `DATABASE_URL`, `DATABASE_DIRECT_URL`, `TOKEN_ENCRYPTION_KEY`, nota Neon (pooled vs direct, `sslmode=require`, auto-suspend) y cómo correr migraciones.
- [ ] e2e: mantener override a `InMemory*` (no requieren Postgres; no bloqueantes). Tests de integración por repo contra Postgres real: opcionales, documentados como no bloqueantes.
- [ ] `npm run build` y `npm test` (unit, contra InMemory) pasan con los mismos conteos. e2e siguen verdes contra InMemory.

## Criterios de validación (los revisa Kiro)

- Existen los 9 `Postgres*` implementando sus interfaces sin cambio de firma (salvo `SessionRegistry` async, con la misma semántica y sus consumidores ajustados).
- El esquema versionado incluye las 10–11 tablas con FKs correctas; `album_photos` modela la N:M y preserva la aislación de borrado (D16).
- `photos` usa columnas planas `storage_provider`/`storage_file_id` y el repo recompone `storageRef` (spec08 intacta).
- `refresh_tokens` guarda el token **cifrado** (AES-256-GCM); no aparece el token en claro en la columna.
- Los módulos registran los providers Postgres; los `InMemory*` siguen existiendo y los unit los usan con `new`.
- El contrato de API no cambió: e2e verdes sin cambios de aserción (contra InMemory).
- `DATABASE_URL`/`TOKEN_ENCRYPTION_KEY` se leen vía `@nestjs/config`, sin hardcodear; `.env.example` documentado.
- `npm run build` y `npm test` pasan.

## Dependencias

- `memora-backend/spec01-fundacion-backend.md` — patrón repos + token `Symbol` que se extiende aquí.
- `memora-backend/spec08-abstraccion-almacenamiento.md` (PASS) — `storageRef`; esta spec lo persiste como dos columnas planas.
- `memora-backend/spec11-session-registry-interface.md` (PASS) — dejó `SessionRegistry` detrás de interfaz para este momento; aquí se añade el adaptador Postgres (con paso a async).
- `memora-backend/spec02-autenticacion-google.md` (PASS) — `UserRepository`, `TokenStore` (refresh de Google) que aquí se persisten y cifran.
- `specs/README.md` — hosting Neon (Postgres) ya fijado; sin cambios.

## Nota de infraestructura (informativo)

- Neon escala el compute a cero tras inactividad y **auto-resume** en la siguiente request (latencia extra en la primera llamada tras suspensión). Aceptable para el MVP; sin acción de código.
- Usar la connection string **pooled** para la app y la **direct** para migraciones.
- El despliegue del proceso Node (Dockerfile/host) y la gestión de secretos en prod se tratan en una spec de infraestructura aparte; esta spec deja la app lista para conectarse a cualquier Postgres por `DATABASE_URL`.
