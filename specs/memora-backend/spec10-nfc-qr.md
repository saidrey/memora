# Memora — spec10-nfc-qr (M8 NFC/QR)

**Estado de validación:** ✅ PASS WITH NOTES (validado por Kiro el 2026-09-14: build OK; 124 unit + 116 e2e; dos desviaciones intencionales aceptadas — ver "Notas de validación" al final).
**Backlog:** M8 — NFC/QR (asociar a álbum ya creado D14, URL estable, resolución)

## Contexto y problema

Tras M7 (Compartir/Visor), el usuario puede compartir un álbum con un enlace de compartición (ShareLink) que redirige al visor. Sin embargo, **NFC y códigos QR requieren un URL estable y pre-grabado en la etiqueta/código**, que no cambia si se revoca el ShareLink.

Por ejemplo:
- Una etiqueta NFC pegada en un local comercial con una foto de su interior.
- Un código QR en una invitación de boda con fotos del lugar.
- Una etiqueta en un atractivo turístico con fotos del entorno.

**Problema:** si el ShareLink cambia al revocarse o regenerarse, el NFC/QR se rompe.

**Solución:** entidades `NfcQrTag` que vinculan un identificador fijo (token opaco) a un álbum, con estado `enabled`/`disabled`. NFC/QR contienen este identificador. Resolución pública redirige al ShareLink del álbum (si está activo y el ShareLink existe).

## Decisiones de producto aplicables

- **D2 — Visibilidad (opción A).** El visor es accesible por **cualquiera con el enlace** (aplica a enlace/QR/NFC). **No indexable ni descubrible** públicamente.
- **D14 — Bloquear etiquetas tras programar.** Una vez programada una etiqueta NFC/QR, su URL debe ser **estable e irreversible** para evitar romper la etiqueta pegada o grabada.
- **D17 — Visibilidad del álbum (`PRIVATE` | `PUBLIC`).** La visibilidad del álbum determina si se requiere autenticación o no en el visor, pero **no afecta** el mecanismo de resolución NFC/QR.

## Alcance (backend)

- Entidad `NfcQrTag` (id, albumId, type `NFC`|`QR`, token opaco estable, `status` `enabled`|`disabled`, createdAt, updatedAt, disabledAt opcional).
- Repositorio `NfcQrTagRepository` (interfaz + token `Symbol` + mock en memoria).
- Endpoint owner-only:
  - `POST /api/v1/albums/:albumId/nfc-qr-tags` (asociar etiqueta: crea una nueva con token aleatorio y `enabled`).
  - `PATCH /api/v1/nfc-qr-tags/:id/disable` (bloquear soft: marca `disabled`, setea `disabledAt`; al bloquear, resolución falla).
  - `GET /api/v1/nfc-qr-tags/:id` (consultar estado y datos del tag).
- Endpoint público (sin guard):
  - `GET /api/v1/nfc-qr-tags/:id` → redirige HTTP 302 a `GET /api/v1/shared/:shareToken` del álbum asociado (si el tag está `enabled`, el álbum existe, y el ShareLink del álbum existe y está activo).
- Un tag por tipo por álbum (NFC o QR). Para múltiples NFC o múltiples QR, se crea más de una fila con el mismo `type` y distinto `id`.

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **P1 — Identificador:** **token opaco de 256-bit** (igual que ShareLink de M7), generado aleatoriamente, no enumerable, no derivable del `albumId` o `tagId`. URL: `https://memora.app/n/{token}` (placeholder `APP_SHARE_BASE_URL` con `/n/`).
- **P2 — Bloqueo:** **soft-delete** mediante estado `disabled`, fila persiste (audit trail), permite reactivar si se revoca por error (no es reactivable en MVP, pero la estructura lo permite).
- **P3 — Resolución pública:** **redirección HTTP 302** hacia el visor (ShareLink de M7).

## Decisiones técnicas

- El tag no contiene el ShareLink directamente: **resolución indirecta** (tag → albumId → ShareLink), para que si el ShareLink cambia, la etiqueta no se rompa (puede regenerarse sin tocar la NFC/QR).
- Token opaco de 256-bit (32 bytes, base64url sin padding) igual que ShareLink.
- Soft-delete: `status` (`enabled`/`disabled`) + `disabledAt` opcional. Al bloquear, la redirección → **404** (sin revelar si el tag existe, alineado con D2/M7).
- El tag está **asociado a un álbum** (no a un ShareLink), para que si el ShareLink se revoca y regenera, la NFC/QR siga funcionando.
- Si el álbum es eliminado (D16), los tags asociados también se eliminan (hard-delete). Si el tag está asociado a un álbum eliminado, redirección → 404.
- No se exponen tags en listados públicos ni en respuestas de álbum (solo consultas directas por id).
- En el cliente (app/web), mostrar el token o URL completa para que el usuario la grabe en la etiqueta.

## Checklist de implementación

- [ ] Entidad `NfcQrTag` (id, albumId, type `NFC`|`QR`, token opaco, status `enabled`|`disabled`, createdAt, updatedAt, disabledAt opcional) + `NfcQrTagRepository` (interfaz + token `Symbol` + mock en memoria).
- [ ] `POST /api/v1/albums/:albumId/nfc-qr-tags` (owner-only, crea nueva etiqueta con token aleatorio y `enabled`, respone id, type, token, url).
- [ ] `PATCH /api/v1/nfc-qr-tags/:id/disable` (owner-only, marca `disabled`, setea `disabledAt`; al bloquear, resolución → 404).
- [ ] `GET /api/v1/nfc-qr-tags/:id` (owner-only, consulta estado y datos del tag).
- [ ] `GET /api/v1/nfc-qr-tags/:id` **público** (sin guard) → redirección HTTP 302 a `GET /api/v1/shared/:shareToken` del álbum (si tag `enabled`, álbum existe, ShareLink existe y está activo); si no, → 404.
- [ ] Regenerar ShareLink (M7) no rompe la NFC/QR (tag → albumId → ShareLink).
- [ ] Si el tag está `disabled` o el álbum fue eliminado (D16), redirección → 404 uniforme (sin revelar existencia).
- [ ] Env `APP_SHARE_BASE_URL` documentada y en `test/jest-setup.ts` (placeholder: `https://memora.app/n/{token}` para URL de la etiqueta).
- [ ] Errores uniformes; validación manual; documentar que `/nfc-qr-tags/:id` público es redirección.
- [ ] Pruebas unitarias (crear, bloquear, consultar, redirección válido/inválido) y e2e (redirección sin Authorization funciona; tag bloqueado/álbum eliminado → 404; owner-only para crear/bloquear).
- [ ] Documentar endpoints en el README del backend (marcando el público).
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Criterios de validación

- El owner asocia un tag NFC/QR a un álbum; el tag recibe un token opaco y se puede obtener su URL (placeholder `APP_SHARE_BASE_URL`).
- Al grabar el token en la etiqueta NFC o en el código QR, la URL es estable (si se revoca el ShareLink del álbum, la NFC/QR sigue funcionando tras regenerar el ShareLink).
- Bloquear el tag (`PATCH /nfc-qr-tags/:id/disable`) hace que la redirección → **404 uniforme** (sin revelar si el tag existe).
- El tag no expone PII ni datos internos (id, albumId no se exponen en respuesta pública).
- Si el álbum es eliminado (D16), el tag ya no redirige a nada (404).
- `GET /nfc-qr-tags/:id` público (sin guard) redirige correctamente (302) o falla (404) según estado.
- `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Dependencias

- `specs/memora-backend/spec09-compartir-visor.md` (ShareLink, endpoint `GET /shared/:token`, `APP_SHARE_BASE_URL`).
- `producto-mvp.md` (D2, D14, D17).
- Habilita: el cliente (app/web) para generar/grabar URLs en NFC/QR.

## Notas de validación (Kiro) — PASS WITH NOTES

**Veredicto: PASS WITH NOTES** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK.
- `npm test` → **124 unit** pasan (12 suites; +17 respecto a M7, incluidos tests de `NfcQrTagsService` y `NfcQrResolveService`).
- `npm run test:e2e` → **116/116** pasan (incluye `nfc-qr.e2e-spec.ts`).

**Criterios de la spec (todos cumplidos):**
- Entidad `NfcQrTag` (`{ id, albumId, type 'NFC'|'QR', token, status 'enabled'|'disabled', createdAt, updatedAt, disabledAt? }`) + `NfcQrTagRepository` (interfaz + token `Symbol` + mock en memoria).
- Token **opaco 256-bit** (`randomBytes(32).toString('base64url')`, igual que ShareLink/Invitation).
- Endpoints owner-only: `POST /api/v1/albums/:albumId/nfc-qr-tags` (crea, `enabled`), `PATCH /api/v1/nfc-qr-tags/:id/disable` (soft-delete idempotente), `GET /api/v1/nfc-qr-tags/:id` (consulta). Owner-only vía `AlbumAccessService.requireOwner` → 404 uniforme.
- **Endpoint público** `GET /api/v1/n/:token` (sin guard, misma mecánica que `SharedController`) → **redirección HTTP 302** (`HttpStatus.FOUND`).
- **Resolución indirecta** (tag → albumId → ShareLink activo): regenerar el ShareLink de M7 no rompe la NFC/QR (D14).
- **404 uniforme** para todos los fallos (tag inexistente, `disabled`, álbum eliminado, sin ShareLink, ShareLink revocado) — no se distinguen (P1).
- Eliminar álbum (D16) hace hard-delete de los tags (+ defensa en profundidad en el resolve).
- Soft-delete: la fila persiste tras `disable`, con `disabledAt`.

**Desviaciones respecto al texto literal de la spec (intencionales, aceptadas):**
1. **Colisión de rutas resuelta.** La spec proponía `GET /nfc-qr-tags/:id` tanto owner-only como público (colisión). Claude usó rutas distintas: owner-only `GET /nfc-qr-tags/:id` (por **id interno**) y pública `GET /n/:token` (por **token opaco**, lo que se graba físicamente). Es la resolución correcta e indicada en el prompt.
2. **Env var propia `APP_NFC_QR_BASE_URL`** (placeholder `https://memora.app/n/{token}`) en vez de reutilizar `APP_SHARE_BASE_URL` (que tiene forma `/s/`). Correcto: reutilizarla habría cambiado silenciosamente la URL ya fijada de spec09. Sigue la convención de env por feature (`APP_INVITE_BASE_URL`, `APP_SHARE_BASE_URL`).
3. **La redirección 302 apunta al endpoint interno** `/api/v1/shared/:token` (no a la URL frontend `https://memora.app/...`, inexistente en el MVP). Comportamiento observable idéntico (302 al ShareLink activo) y verificable e2e.

Todas las desviaciones están documentadas en el código y en `memora-backend/README.md`. Ninguna viola una decisión de producto (D2, D14, D17). El punto #3 es una frontera a revisar cuando exista el dominio frontend real: en producción el 302 debería llevar a la URL pública del visor, no al endpoint de API. Anotado como deuda menor, no bloqueante.
