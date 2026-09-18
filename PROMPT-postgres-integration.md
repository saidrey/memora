# Prompt para agente de IA — Integración PostgreSQL en memora-backend

Copiá todo lo que sigue (dentro del bloque) y pásalo al otro agente. Es autosuficiente: incluye las firmas reales de las interfaces y las decisiones ya cerradas por el PO.

---

## Tarea

Sos un ingeniero senior de NestJS. Trabajás en `memora-backend`, un backend **NestJS 10 + TypeScript**. Hoy TODA la persistencia es in-memory. Tu trabajo es **reemplazar las 9 implementaciones in-memory por implementaciones PostgreSQL**, respetando EXACTAMENTE las interfaces existentes. Es una **migración de capa, no de funcionalidad**: no cambies servicios, controllers, ni el contrato de la API HTTP. No agregues endpoints. No cambies reglas de negocio.

La spec completa y vinculante está en `specs/memora-backend/spec12-persistencia-postgres.md` — **léela primero y seguila al pie de la letra.** Este prompt es el resumen operativo.

## Contexto del proyecto (verificado)

- Framework: NestJS `^10`, TypeScript `^5`, `@nestjs/config` `^4` (ya registrado global desde `AuthModule`), `@nestjs/jwt`, `google-auth-library`. Sin ORM instalado.
- Patrón de persistencia: cada store está detrás de una **interfaz + token `Symbol`**, con una implementación `InMemory*` registrada por `useClass` en su módulo. Vos vas a AGREGAR una clase `Postgres*` por cada una y cambiar el `useClass`, **sin tocar las interfaces** (única excepción: `SessionRegistry`, ver abajo).
- El storage de fotos (`GoogleDrivePhotoStorage`, token `PHOTO_STORAGE`) **NO se toca**: el backend no maneja bytes, solo metadatos. Solo persistís entidades/metadatos.
- Comandos: `npm run build`, `npm test` (unit, Jest), `npm run test:e2e`.

## Decisiones ya cerradas por el PO (no las re-abras)

1. **ORM/driver: Kysely + `pg`.** Query builder tipado sobre SQL explícito. NADA de TypeORM ni Prisma. Cada `Postgres*Repository` es una clase `@Injectable()` que compone SQL con Kysely y cumple la interfaz. El dominio no debe acoplarse al ORM (sin decoradores de entidad).
2. **Hosting: Neon (Postgres gestionado), usado SOLO como Postgres.** La app se conecta por connection string estándar (`DATABASE_URL`), así que una Postgres local es intercambiable. No uses features propietarias de Neon.
3. **Migraciones versionadas.** SQL/Kysely versionado, aplicado explícitamente por un script. NUNCA `synchronize`/auto-DDL contra una base real.
4. **`storageRef` → dos columnas planas** en la tabla `photos`: `storage_provider` (text, hoy siempre `'google-drive'`) y `storage_file_id` (text). El repo recompone `storageRef = { provider, fileId }` al leer. Nada de jsonb.
5. **Se migran los 9 stores** (lista abajo).
6. **Refresh token de Google cifrado at-rest con AES-256-GCM**, clave desde env `TOKEN_ENCRYPTION_KEY` (32 bytes). Nunca en claro en la columna. Descifrar solo en memoria al usar. Usá nonce/IV por registro.
7. **Tests:** conservá las clases `InMemory*` como fakes. Los **unit** siguen usando `new InMemory*()` (no los cambies). Los **e2e** siguen corriendo contra `InMemory*` por override (deben quedar simples y NO bloqueantes — no requieren Postgres). La cobertura SQL va en tests de integración por repositorio contra Postgres real, **opcionales y no bloqueantes** (fuera del `npm test` normal).

## Los 9 stores a migrar (con sus firmas reales)

Todas las interfaces de repos YA son async (`Promise`). La ÚNICA síncrona es `SessionRegistry`.

### Dominio de álbumes — registrados en `src/albums/albums.module.ts`

1. **`ALBUM_REPOSITORY`** (`src/albums/album-repository.interface.ts`) → `PostgresAlbumRepository`. Incluye la relación N:M foto↔álbum (hoy `Map<albumId, Set<photoId>>`) → tabla join **`album_photos`**. Métodos: `create({ownerId,name,visibility?})`, `findById`, `findByOwner`, `rename`, `updateVisibility`, `delete` (borra álbum + relaciones, NUNCA la Photo), `addPhoto` (idempotente), `removePhoto`, `listPhotoIds`, `countPhotos`, `removePhotoFromAllAlbums`. `visibility` default `'PRIVATE'`. Debe preservar aislación de borrado (D16): borrar álbum no borra la foto ni la saca de otros álbumes.
2. **`PHOTO_REPOSITORY`** (`src/albums/photos/photo-repository.interface.ts`) → `PostgresPhotoRepository`. Persiste `storageRef` como dos columnas planas.
3. **`MEMBERSHIP_REPOSITORY`** (`src/albums/collaborators/membership-repository.interface.ts`) → `PostgresMembershipRepository`.
4. **`INVITATION_REPOSITORY`** (`src/albums/collaborators/invitation-repository.interface.ts`) → `PostgresInvitationRepository`.
5. **`SHARE_LINK_REPOSITORY`** (`src/albums/shared/share-link-repository.interface.ts`) → `PostgresShareLinkRepository`.
6. **`NFC_QR_TAG_REPOSITORY`** (`src/albums/nfc-qr/nfc-qr-tag-repository.interface.ts`) → `PostgresNfcQrTagRepository`.

> Para 2–6, LEÉ la interfaz correspondiente y su modelo (`*.model.ts`) para replicar firmas y campos exactos. No inventes campos.

### Auth — registrados en `src/auth/auth.module.ts`

7. **`USER_REPOSITORY`** (`src/auth/users/user-repository.interface.ts`) → `PostgresUserRepository`. Firma:
   ```ts
   interface User { id: string; googleId: string; email: string; name?: string; }
   interface UserRepository {
     findByGoogleId(googleId: string): Promise<User | null>;
     create(user: Omit<User, 'id'>): Promise<User>;
   }
   ```
   **Crítico:** es el ancla de integridad — `albums.owner_id` referencia `users.id`.
8. **`TOKEN_STORE`** (`src/auth/tokens/token-store.interface.ts`) → `PostgresTokenStore`. Firma:
   ```ts
   interface TokenStore {
     saveGoogleRefreshToken(userId: string, refreshToken: string): Promise<void>;
     getGoogleRefreshToken(userId: string): Promise<string | null>;
   }
   ```
   Cifrá el refresh token con AES-256-GCM antes de escribir; descifrá al leer. La columna guarda ciphertext.
9. **`SESSION_REGISTRY`** (`src/auth/session/session-registry.interface.ts`) → `PostgresSessionRegistry`. Firma actual (SÍNCRONA):
   ```ts
   interface SessionRegistry {
     register(userId: string, jti: string): void;
     isActive(userId: string, jti: string): boolean;
     revokeAll(userId: string): void;
   }
   ```
   **Debés volver la interfaz async** (`Promise<void>` / `Promise<boolean>` / `Promise<void>`) porque va a SQL, y ajustar sus consumidores en `src/auth/auth.service.ts` (login registra jti, refresh valida `isActive`, logout `revokeAll`) más `auth.service.spec.ts`. Misma semántica; solo cambia la asincronía. Actualizá también `InMemorySessionRegistry` para cumplir la interfaz async. Este es el ÚNICO cambio de firma permitido.

## Configuración (patrón `@nestjs/config`, sin hardcodear)

Agregá a `memora-backend/.env.example` (solo placeholders/comentarios, nunca valores reales) y documentá en el README:
- `DATABASE_URL` — connection string Postgres. En Neon usar la variante **pooled** (host con `-pooler`), con `sslmode=require`.
- `DATABASE_DIRECT_URL` (opcional) — variante **direct** (sin pooler) para correr migraciones. Si falta, migraciones usan `DATABASE_URL`.
- `TOKEN_ENCRYPTION_KEY` — clave 32 bytes (base64/hex) para AES-256-GCM del refresh token. Obligatoria si se persiste `TOKEN_STORE`.

Configurá un provider inyectable para la instancia de Kysely (pool `pg` desde `DATABASE_URL`, SSL habilitado).

## Esquema (migraciones versionadas)

Definí tablas: `users`, `albums`, `photos` (con `storage_provider`, `storage_file_id`), `album_photos` (join N:M), `memberships`, `invitations`, `share_links`, `nfc_qr_tags`, `refresh_tokens` (token cifrado), y la tabla del session registry (p. ej. `session_jtis`). Declará las FKs de integridad (`albums.owner_id`→`users.id`, `album_photos`→`albums`/`photos`, etc.) con el comportamiento de borrado que respete las reglas de dominio ya especificadas (borrar álbum limpia `album_photos` pero no `photos`). Índices donde haga falta (lookups por `owner_id`, `google_id`, tokens, etc.).

## Reglas de comportamiento (normativas)

- Cada `Postgres*` implementa su interfaz SIN cambiar firma (salvo `SessionRegistry` → async).
- La generación de `id` y `timestamps` debe replicar el contrato actual de cada repo (hoy los generan los repos; mirá cada `in-memory-*` para el formato exacto — p. ej. UUID, ISO string — y reproducilo; no delegues a defaults de columna que cambien el formato observable).
- El contrato HTTP no cambia: mismos endpoints, códigos, formas y errores.
- Recomponé `storageRef` al leer `photos` (respeta spec08).
- Backend sigue sin manejar bytes.

## Pasos sugeridos

1. Leé `specs/memora-backend/spec12-persistencia-postgres.md` y las 9 interfaces + sus `*.model.ts` e `in-memory-*` (para copiar semántica y formatos).
2. Instalá `kysely` y `pg` (+ `@types/pg`). Creá el provider de Kysely + config.
3. Escribí las migraciones versionadas y el script para aplicarlas (usando `DATABASE_DIRECT_URL` si está).
4. Implementá los 9 `Postgres*` respetando cada interfaz; recomponé entidades de dominio al leer.
5. Volvé `SessionRegistry` async; ajustá `AuthService`, `InMemorySessionRegistry` y `auth.service.spec.ts`.
6. Implementá el cifrado AES-256-GCM en `PostgresTokenStore` (helper reutilizable, nonce por registro).
7. Cambiá los `useClass: InMemory*` a `useClass: Postgres*` en `albums.module.ts` y `auth.module.ts`. Conservá las clases `InMemory*` (las usan los tests).
8. Mantené los e2e contra `InMemory*` por override (no bloqueantes). Agregá tests de integración por repo opcionales.
9. Actualizá `.env.example` + README del backend.
10. Verificá: `npm run build` OK; `npm test` (unit contra InMemory) con los mismos conteos; e2e verdes contra InMemory.

## Criterios de aceptación

- 9 clases `Postgres*` cumplen sus interfaces (SessionRegistry async con consumidores ajustados).
- Esquema versionado con FKs correctas; `album_photos` modela la N:M y preserva aislación de borrado (D16).
- `photos` con columnas planas `storage_provider`/`storage_file_id`; `storageRef` recompuesto al leer.
- `refresh_tokens` guarda el token CIFRADO (AES-256-GCM); nunca en claro.
- Módulos registran los providers Postgres; `InMemory*` conservados y usados por los unit.
- Contrato HTTP intacto: e2e verdes sin cambios de aserción.
- `DATABASE_URL`/`TOKEN_ENCRYPTION_KEY` vía `@nestjs/config`, sin hardcodear; `.env.example` documentado.
- `npm run build` y `npm test` pasan.

## Restricciones (no hacer)

- No migrar datos (no hay datos en prod).
- No cambiar decisiones de producto D1–D17, endpoints ni contrato de API.
- No usar servicios de Neon distintos de Postgres.
- No Redis, no Testcontainers en el flujo por defecto, no KMS (queda para infra; `TOKEN_ENCRYPTION_KEY` por env es el mínimo).
- No Dockerfile ni pipeline de despliegue (spec de infra aparte).
- No cambiar `GoogleDrivePhotoStorage` ni la lógica de auth de Google.

---
