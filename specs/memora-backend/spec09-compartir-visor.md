# spec09 — Compartir y visor: enlace estable y resolución (backend)

**Ámbito:** memora-backend
**Estado de validación:** ✅ PASS (validado por Kiro el 2026-09-14: build OK; 107 unit + 99 e2e; neutralidad de dominio verificada). Ver "Notas de validación (Kiro)" al final.
**Backlog:** M7 (Compartir y visor) — parte backend

## Objetivo

Permitir que el owner de un álbum genere un **enlace estable de compartición** que da acceso de **solo lectura** al álbum a **cualquiera con el enlace, sin login** (D2), y exponer el endpoint público de **resolución** que el visor (web/app) usa para mostrar el álbum. La gestión/modificación sigue requiriendo autenticación. El visor de UI es de la capa web/app; aquí se construye el **contrato backend** (crear/gestionar el enlace + resolución pública).

## Contexto y decisiones de producto que aplican

Ver `specs/producto-mvp.md`. Relevantes:

- **D2 — Visibilidad del visor (opción A).** El visor es accesible por **cualquiera con el enlace** (aplica a enlace/QR/NFC). **No indexable ni descubrible** públicamente. La **gestión/modificación requiere autenticación**.
- **D17 — Visibilidad del álbum (`PRIVATE` | `PUBLIC`, KISS).** Cada álbum tiene `visibility` con default **`PRIVATE`**, fijable al crear y cambiable con `PATCH /albums/:id` (owner). En el MVP **ambos** tipos se visualizan por el **mismo enlace de compartición** (token opaco); `visibility` marca la intención de producto y prepara el futuro. **NO** se implementa catálogo/descubrimiento/SEO.
- **D9 / M6 — Disponibilidad.** El visor muestra solo fotos **disponibles**; las `unavailable` no se muestran como disponibles.
- **D16 / D5** — La compartición no cambia propiedad ni relaciones; eliminar el álbum invalida su enlace.
- **spec08 — `PhotoStorage` / `storageRef`.** El visor recibe **referencias neutrales** (`storageRef`), no conceptos de Drive. El backend no maneja bytes: el visor obtiene los bytes del proveedor por su cuenta con la referencia.

## Distinción importante (no confundir con M4)

- El enlace de **invitación** de M4 (spec05) sirve para **unirse como colaborador autenticado** (un solo uso, requiere login). 
- El enlace de **compartición** de esta spec es de **solo lectura, sin login**, para **ver** el álbum en el visor. Son cosas distintas y coexisten.

## Alcance (backend)

- **Visibilidad del álbum (D17):** añadir `Album.visibility` (`'PRIVATE' | 'PUBLIC'`, default `'PRIVATE'`); fijable opcionalmente en `POST /albums` y cambiable en `PATCH /albums/:id` (**owner-only**). Reflejar `visibility` en las respuestas de álbum. **Sin** catálogo/descubrimiento.
- Generar/gestionar un **enlace de compartición** de un álbum: entidad `ShareLink` (token opaco estable, álbum, estado), su repositorio en memoria y endpoints owner-only para crear, consultar y revocar. **Un enlace por álbum** (P5), válido para `PRIVATE` y `PUBLIC` por igual en el MVP.
- Endpoint **público** (sin guard) de **resolución**: dado el token del enlace, devuelve una **vista de solo lectura** del álbum (datos mínimos + fotos **disponibles**, con `storageRef` para que el visor pida los bytes).
- Garantizar que el endpoint público **no expone** datos sensibles (ver P4) y **no es descubrible** (token opaco, no enumerable; sin listados públicos).
- Integración con disponibilidad (M6): la vista pública lista solo fotos `available` (ver P3).
- Invalidación: revocar el enlace y eliminar el álbum dejan el enlace inutilizable.

## Fuera de alcance

- La **UI del visor** (web/app) — es M7 en esas capas / M9.
- NFC/QR (M8) — reutilizarán este enlace/resolución, pero se especifican aparte.
- Adopción (M5, diferido) y subida de bytes.
- Autenticación del visor (por definición es sin login).
- Servir/proxear bytes de imágenes (el backend nunca maneja bytes; el visor los pide al proveedor con `storageRef`).

## Comportamiento esperado (normativo)

### Crear/gestionar el enlace (owner, autenticado)
- El backend SHALL exponer `POST /api/v1/albums/:albumId/share-link` (autenticado, **owner-only**) que crea o **devuelve el existente** (P5, uno por álbum) y responde su **token** y **URL** (construida sobre `APP_SHARE_BASE_URL`, P2).
- El token SHALL ser **opaco, aleatorio y no adivinable** (no enumerable, no derivable del `albumId`).
- El backend SHALL exponer `DELETE /api/v1/albums/:albumId/share-link` (autenticado, owner-only) que **revoca** el enlace: tras revocar, resolverlo → **404** (P1).
- El backend SHALL permitir consultar el estado del enlace del álbum (en `GET /albums/:id` o endpoint dedicado).

### Resolución pública (sin login)
- El backend SHALL exponer `GET /api/v1/shared/:token` **sin autenticación** (público) que devuelve la vista de solo lectura del álbum si el token es válido y activo.
- La respuesta SHALL incluir **solo** datos de presentación (nombre del álbum; por foto `storageRef` + metadatos de presentación) y NO SHALL incluir identidad de personas, ids internos, tokens ni lista de colaboradores (P4).
- Un token inexistente/revocado/con álbum eliminado SHALL responder **404 uniforme** (P1) **sin revelar** si el álbum existe.
- La respuesta pública NO SHALL requerir ni aceptar sesión; NO SHALL exponer endpoints de gestión.
- La resolución pública SHALL listar **solo fotos disponibles** (M6); las `unavailable` se **omiten** (P3).

### Reglas transversales
- Este es el **primer endpoint público** del backend (todo lo demás usa `SessionAuthGuard`). SHALL documentarse explícitamente como público y quedar fuera del guard, pero seguir el contrato de errores uniforme y correlación (`x-request-id`).
- La compartición NO SHALL cambiar propiedad ni relaciones; eliminar el álbum (D16) SHALL invalidar el enlace.
- El backend NO SHALL servir bytes: expone `storageRef`; el visor obtiene los bytes del proveedor.

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **P1 — Token no válido → 404 uniforme.** Token inexistente, revocado o con álbum eliminado responden **404 `NOT_FOUND`**, sin distinguir el caso (no revela historia del álbum). El visor muestra un mensaje genérico "álbum no disponible".

- **P2 — URL del enlace:** URL completa desde **`APP_SHARE_BASE_URL`** (placeholder por defecto en dev: `https://memora.app/s/{token}`) + el `token` suelto.

- **P3 — Visor anónimo oculta las no disponibles:** `GET /api/v1/shared/:token` lista **solo fotos `available`** (las `unavailable` no aparecen). En las vistas **autenticadas** (`GET /albums/:id`, `GET /library`) se mantiene el estado `unavailable` marcado, como en M6.

- **P4 — Superficie pública mínima:** la resolución pública expone **solo lo necesario para ver**: nombre del álbum y, por foto, `storageRef` + metadatos de presentación (dimensiones, mimeType, capturedAt, orden). **NO** expone: identidad/email del owner ni de colaboradores, ids internos de usuario, tokens, ni la lista de colaboradores.

- **P5 — Un enlace de compartición por álbum:** `POST /api/v1/albums/:albumId/share-link` crea o devuelve el existente; revocar y volver a crear genera uno nuevo. Vale igual para `PRIVATE` y `PUBLIC` (D17): la visibilidad **no** multiplica enlaces en el MVP. Para un álbum `PRIVATE`, revocar el enlace corta el acceso anónimo; para `PUBLIC` es técnicamente el mismo mecanismo (la visibilidad solo marca intención de producto de cara al futuro).

## Checklist de implementación

- [ ] `Album.visibility` (`'PRIVATE' | 'PUBLIC'`, default `'PRIVATE'`) en el modelo/repositorio; fijable en `POST /albums` (opcional) y en `PATCH /albums/:id` (owner-only); reflejada en las respuestas de álbum (D17).
- [ ] Entidad `ShareLink` (id, albumId, token opaco, status `active`/`revoked`, createdAt) + `ShareLinkRepository` (interfaz + token `Symbol` + mock en memoria).
- [ ] `POST /api/v1/albums/:albumId/share-link` (owner-only; crea o devuelve el existente — uno por álbum, P5; token opaco; URL con `APP_SHARE_BASE_URL`, P2).
- [ ] `DELETE /api/v1/albums/:albumId/share-link` (owner-only, revoca).
- [ ] Estado del enlace consultable — en `GET /albums/:id` o endpoint dedicado.
- [ ] `GET /api/v1/shared/:token` **público** (sin guard): vista de solo lectura; **solo fotos disponibles**, `unavailable` omitidas (P3); superficie mínima sin PII (P4); token inválido/revocado/álbum eliminado → **404** (P1).
- [ ] Invalidación: revocar y eliminar álbum (D16) dejan el enlace inutilizable (404).
- [ ] Env `APP_SHARE_BASE_URL` documentada y en `test/jest-setup.ts` si aplica.
- [ ] Errores uniformes; validación manual (incl. valor de `visibility`); documentar que `/shared/:token` es público.
- [ ] Pruebas unitarias (crear/revocar; visibilidad crear/cambiar owner-only; resolución válido/ inválido; solo disponibles; superficie sin PII) y e2e (resolución **sin** Authorization funciona; token revocado/álbum eliminado → 404; owner-only para crear/revocar y para cambiar visibility).
- [ ] Documentar endpoints en el README del backend (marcando el público).
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- Un álbum tiene `visibility` (default `PRIVATE`); se puede fijar al crear y cambiar con `PATCH /albums/:id` solo el owner (D17).
- El owner crea un enlace; `GET /api/v1/shared/:token` **sin login** devuelve el álbum con sus fotos disponibles y `storageRef`.
- Revocar el enlace o eliminar el álbum → resolverlo da **404 uniforme** (P1), sin revelar existencia.
- La vista pública no expone identidad de personas ni datos internos (P4); solo fotos disponibles, `unavailable` omitidas (P3).
- El token es opaco/no enumerable; no hay endpoint que liste enlaces públicamente.
- Crear/revocar es owner-only (404 para ajeno); el endpoint de resolución es el único sin guard.
- El backend no sirve bytes; expone `storageRef`.
- `build`, `test`, `test:e2e` pasan; endpoints documentados (incl. el público).

## Dependencias

- `memora-backend/spec03-biblioteca-albumes.md` (álbum, patrón owner) — PASS.
- `memora-backend/spec05-colaboradores.md` (patrón de enlace/token, `AlbumAccessService`) — PASS.
- `memora-backend/spec07-disponibilidad.md` (mostrar solo disponibles) — PASS.
- `memora-backend/spec08-abstraccion-almacenamiento.md` (`storageRef` neutral en la vista pública) — PASS.
- `producto-mvp.md` (D2, D9, D16, **D17 visibilidad del álbum**).
- Habilita: **M8 (NFC/QR)** que resuelve a este mismo enlace/álbum, y el **visor** web/app (M7 en capas cliente).

## Notas de validación (Kiro) — PASS

**Veredicto: PASS** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK.
- `npm test` → **107 unit** pasan (10 suites; +18 respecto a M6, incluidos tests de visibilidad, share link y shared view).
- `npm run test:e2e` → **99/99** pasan tras reejecución (el primer run tuvo un flake de transporte conocido: "Parse Error: Expected HTTP/", ajeno a la lógica).
- Grep: "b2"/"drive.readonly" solo en **comentarios** (tipo `StorageProvider` deja lugar a futuro; scopes sin cambios).
- Test de neutralidad de dominio (`domain-storage-neutrality.spec.ts`) pasa.

**Criterios de la spec (todos cumplidos):**
- `Album.visibility` (`'PRIVATE'|'PUBLIC'`, default `'PRIVATE'`): fijable en `POST /albums` y cambiable en `PATCH /albums/:id` (owner-only, 404 para ajeno). Reflejado en respuestas.
- `ShareLink`: una fila por álbum (`byAlbumId` map en repo), token opaco. `POST` crea o devuelve el existente (P5). `DELETE` revoca. `findByToken` busca en todos los albums.
- Endpoint público `GET /api/v1/shared/:token` (sin `SessionAuthGuard`): vista de solo lectura; **solo fotos disponibles** (`unavailable` omitidas, P3); superficie mínima sin PII (P4); token inválido/revocado/álbum eliminado → **404 uniforme** (P1).
- El backend **no sirve bytes**: expone `storageRef` (spec08). El visor obtiene los bytes del proveedor por su cuenta.
- Revocar el enlace y eliminar el álbum (D16) dejan el enlace inutilizable (404).
- No hay B2, no cambió scopes OAuth, no se sirven bytes.

**Detalles de calidad:** buen uso del test de neutralidad de dominio para verificar que el dominio no menciona "driveFileId" ni "Drive". El endpoint público está claramente documentado como la única excepción al guard en el módulo.
