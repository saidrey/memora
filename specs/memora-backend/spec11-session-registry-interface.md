# Memora — spec11-session-registry-interface (A1.5 deuda backend)

**Estado de validación:** ✅ PASS (validado por Kiro el 2026-09-14: build OK; 124 unit + 116 e2e, mismos conteos, sin regresión; ver "Notas de validación" al final).
**Backlog:** A1.5 (parte backend) — deuda técnica de auth. **Cierra la FASE 1 (backend) del MVP.**

## Contexto y problema

El refresco del JWT de sesión ya está implementado y **PASS** en `spec02-autenticacion-google.md` (`POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout`). Esta spec **no** toca ese comportamiento.

La deuda que cierra esta spec es de **consistencia arquitectónica y seguridad**: `SessionRegistry` (`src/auth/session/session-registry.ts`) rastrea qué `jti` de refresh token están activos por usuario (para que `logout` pueda revocar sesiones aunque los JWT sean stateless). Hoy es una **clase concreta `@Injectable()` con un `Map` en memoria**, inyectada directamente por clase — **la única pieza de estado del backend que NO está detrás de una interfaz + token `Symbol`**, a diferencia de `UserRepository`, `TokenStore`, `AlbumRepository`, `PhotoRepository`, `ShareLinkRepository`, `NfcQrTagRepository`, etc.

Consecuencias:
- El backend queda inconsistente con su propio patrón (mock en memoria detrás de interfaz, migrable a datastore real sin tocar lógica).
- `logout` es **seguridad**: hoy las sesiones activas viven solo en memoria del proceso; migrar a un datastore real (Redis/Postgres) más adelante exige hoy refactorizar el punto de inyección. Con la interfaz, será solo añadir un adaptador.

El propio código ya lo dejó señalado (comentario en `session-registry.ts`: "flagged for Kiro in case it should become one for consistency").

## Alcance (backend)

- Definir la **interfaz** `SessionRegistry` (contrato de los métodos actuales) + token de inyección `export const SESSION_REGISTRY = Symbol('SESSION_REGISTRY')`.
- Renombrar la implementación concreta actual a `InMemorySessionRegistry` (`@Injectable()` que implementa la interfaz), siguiendo el patrón `in-memory-*.repository.ts` del resto del backend.
- Registrar el provider en `auth.module.ts` como `{ provide: SESSION_REGISTRY, useClass: InMemorySessionRegistry }`.
- Cambiar la inyección en `AuthService` a `@Inject(SESSION_REGISTRY) private readonly sessionRegistry: SessionRegistry`.
- Actualizar el mock/instanciación en los tests (`auth.service.spec.ts` usa `new SessionRegistry()` → `new InMemorySessionRegistry()`).

## Fuera de alcance

- **No** cambiar el comportamiento observable de auth: `/auth/refresh`, `/auth/logout`, el guard y la emisión/validación de JWT siguen idénticos. Sin cambios de contrato de API.
- **No** implementar un datastore real (Redis/Postgres): sigue siendo mock en memoria. Esta spec solo introduce la **frontera** (interfaz) para que el cambio futuro sea un adaptador.
- **No** cifrado, expiración server-side ni límites de sesiones concurrentes: fuera de alcance.
- **No** tocar la capa app (el refresco automático del JWT cuando expira es FASE 2).

## Comportamiento esperado

- La interfaz `SessionRegistry` SHALL declarar exactamente los métodos que hoy usa `AuthService`:
  - `register(userId: string, jti: string): void` — marca un `jti` de refresh como activo para el usuario.
  - `isActive(userId: string, jti: string): boolean` — indica si un `jti` sigue activo.
  - `revokeAll(userId: string): void` — logout: revoca todos los refresh activos del usuario.
- `InMemorySessionRegistry` SHALL implementar la interfaz con el `Map<string, Set<string>>` actual, preservando la semántica exacta (register idempotente por Set, `isActive` false si no existe, `revokeAll` borra la entrada del usuario).
- `AuthService` SHALL depender de la **interfaz** (vía `@Inject(SESSION_REGISTRY)`), nunca de la clase concreta.
- El comportamiento de `login` (registra jti), `refresh` (valida `isActive`) y `logout` (`revokeAll`) SHALL permanecer idéntico: mismos códigos de estado, mismos errores (`sessionRefreshInvalid` → 401), misma revocación efectiva tras logout.

> Si al implementar aparece cualquier otro consumidor de `SessionRegistry` además de `AuthService`, se migra igual (a la interfaz). No debería haber otros según el mapa actual.

## Checklist de implementación

- [ ] Crear `src/auth/session/session-registry.interface.ts`: interfaz `SessionRegistry` (los 3 métodos) + `export const SESSION_REGISTRY = Symbol('SESSION_REGISTRY')` + doc que explique que es la frontera para un datastore real futuro (Redis/Postgres) y que hoy la única impl es el mock en memoria.
- [ ] Crear `src/auth/session/in-memory-session-registry.ts`: `InMemorySessionRegistry` `@Injectable()` que implementa la interfaz (mueve la lógica del `Map` actual).
- [ ] Borrar/renombrar el `session-registry.ts` concreto anterior (que la clase pública pase a ser la interfaz; no dejar dos símbolos con el mismo nombre exportado).
- [ ] `auth.module.ts`: registrar `{ provide: SESSION_REGISTRY, useClass: InMemorySessionRegistry }` (quitar el provider de clase concreta).
- [ ] `auth.service.ts`: inyectar con `@Inject(SESSION_REGISTRY)` tipado como la interfaz.
- [ ] `auth.service.spec.ts`: instanciar `new InMemorySessionRegistry()` donde hoy usa `new SessionRegistry()`.
- [ ] Confirmar que no queda ninguna referencia a la clase concreta como token de inyección.
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan **con los mismos conteos** (no debe cambiar el número de tests; el comportamiento es idéntico).

## Criterios de validación (los revisa Kiro)

- Existe `session-registry.interface.ts` con la interfaz + token `Symbol`, siguiendo el patrón de los demás repos.
- `AuthService` inyecta la interfaz vía `@Inject(SESSION_REGISTRY)`, no la clase concreta.
- La implementación en memoria conserva la semántica exacta (register/isActive/revokeAll).
- **Sin regresión de comportamiento:** login → refresh funciona; logout revoca de verdad (el refresh falla tras logout con 401 uniforme). Los tests e2e de auth siguen pasando sin cambios de aserción.
- `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Dependencias

- `memora-backend/spec02-autenticacion-google.md` (PASS) — define `SessionRegistry`, `/auth/refresh`, `/auth/logout` y el guard. Esta spec solo lo refactoriza tras una interfaz.
- Patrón a replicar: cualquier `x-repository.interface.ts` + `in-memory-x.repository.ts` del backend (p. ej. `share-link-repository.interface.ts`).

## Nota

Con esta spec PASS, **FASE 1 (backend) del MVP queda cerrada** (M5 diferido a post-MVP). Sigue FASE 2 (app), que arranca cuando el PO lo indique.

## Notas de validación (Kiro) — PASS

**Veredicto: PASS** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK.
- `npm test` → **124 unit** (mismo conteo que M8: sin regresión, refactor sin cambio de comportamiento como exigía la spec).
- `npm run test:e2e` → **116/116** (incluye `auth.e2e-spec.ts`: login → refresh → logout revoca de verdad).

**Criterios de la spec (todos cumplidos):**
- `src/auth/session/session-registry.interface.ts`: interfaz `SessionRegistry` (`register`, `isActive`, `revokeAll`) + `export const SESSION_REGISTRY = Symbol('SESSION_REGISTRY')`, documentada como la frontera para un datastore real futuro (Redis/Postgres).
- `src/auth/session/in-memory-session-registry.ts`: `InMemorySessionRegistry` `@Injectable() implements SessionRegistry` con el `Map<string, Set<string>>` (semántica idéntica).
- El `session-registry.ts` concreto anterior fue **eliminado** (no quedan dos símbolos con el mismo nombre; el directorio solo tiene interfaz + mock).
- `auth.module.ts`: `{ provide: SESSION_REGISTRY, useClass: InMemorySessionRegistry }`.
- `auth.service.ts`: `@Inject(SESSION_REGISTRY) private readonly sessionRegistry: SessionRegistry` (depende de la interfaz, no de la clase concreta).
- `auth.service.spec.ts`: usa `new InMemorySessionRegistry()`.
- Sin cambio de contrato de API ni de comportamiento observable; conteos de tests idénticos a los previos.

**Cierre:** con esta spec PASS, **FASE 1 (backend) del MVP queda cerrada**. Todos los ítems no diferidos de backend están ✅ (M5 ⏸️ diferido a post-MVP). El PO decide el paso a FASE 2 (app).
