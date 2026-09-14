# spec07 — Disponibilidad de archivos en Drive (backend)

**Ámbito:** memora-backend
**Estado de validación:** ✅ PASS (validado por Kiro el 2026-09-14: build OK; 78 unit + 77 e2e; criterios críticos verificados por grep dirigido). Ver "Notas de validación (Kiro)" al final.
**Backlog:** M6 (Disponibilidad de archivos)

## Objetivo

Implementar en `memora-backend` el soporte de **disponibilidad perezosa** (D9) de las fotografías: reflejar y persistir si el archivo de una foto sigue accesible en el Drive de su propietario, sin sync activa (ni polling ni webhooks). El campo `Photo.availability` ya existe (spec04); esta spec define **cómo se actualiza, quién lo verifica y cómo se expone**. Con M5 diferido, esta es también la base de que las fotos de colaboradores "se vean mientras estén disponibles" (D5).

## Contexto y decisiones de producto que aplican

Ver `specs/producto-mvp.md`. Relevantes:

- **D9 — Verificación perezosa (opción A).** No hay sync activa en el MVP. Al mostrar una foto, Memora verifica disponibilidad. Si el archivo fue eliminado / está en papelera / inaccesible / sin permisos → se marca **"no disponible"** y no se muestra como disponible. **Renombrar o mover NO rompe la referencia** (se usa el `fileId` estable, nunca ruta/nombre). Si vuelve a estar disponible, se puede revalidar/recuperar.
- **D5** — Las fotos de un colaborador permanecen en el álbum **mientras sigan disponibles**. Esta spec es la que materializa ese "mientras sigan disponibles".
- **D8** — `Photo.availability` es parte de los metadatos mínimos.
- **Principio "no custodio" + Opción A (backend no maneja bytes) + scope `drive.file`.**

## Hallazgo técnico que condiciona el diseño (verificado)

- El backend **no maneja bytes** y **no tiene** un cliente de Drive que lea archivos: por diseño, no puede consultar la Drive API con las credenciales del usuario (el refresh token nunca se usa para leer archivos, solo para emitir el `drive-token` efímero al cliente).
- Con scope **`drive.file`**, solo el **propietario** de un archivo puede verificar su existencia/estado (su token ve solo sus propios archivos). El owner de un álbum **no puede** verificar la disponibilidad de las fotos de un **colaborador** (le darían 404 aunque existan). → La verificación de una foto la hace **el cliente de su propietario**.
- Por tanto, el patrón viable es: **el cliente verifica contra Drive** (con su `drive-token`, foto por foto usando el `driveFileId`), y **reporta el resultado al backend**, que **persiste** `availability`. El backend es la fuente de verdad del **estado conocido**; el cliente es quien **observa** Drive.

Esto es lo que fija P1.

## Alcance (backend)

- Persistir y exponer `Photo.availability` (`available` | `unavailable`) y la marca temporal de la última verificación conocida.
- Endpoint para que **el propietario de una foto** reporte el resultado de su verificación contra Drive (marca disponible/no disponible). Solo el owner de la foto puede reportar sobre ella (con `drive.file`, nadie más puede verificarla).
- Reflejar `availability` en las lecturas donde ya se muestran fotos: `GET /albums/:id` (detalle con fotos) y `GET /library`.
- Permitir **revalidar/recuperar** (D9): si una foto marcada `unavailable` vuelve a reportarse `available`, se actualiza (la referencia `driveFileId` es estable y nunca se borró).
- Distinguir explícitamente que **renombrar/mover no cambia disponibilidad** (se opera sobre `driveFileId`, no sobre nombre/ruta): esto se cumple por construcción y se cubre con un test.

## Fuera de alcance

- Sync activa, polling o webhooks (D9 lo excluye del MVP).
- Que el **backend** consulte la Drive API (no maneja bytes ni lee archivos; contradería la arquitectura).
- Verificación de fotos ajenas por el owner (imposible con `drive.file`).
- Adopción/copia (M5, diferido).
- Optimización/subida (app).
- Borrado del archivo en Drive (Memora nunca borra de Drive).

## Comportamiento esperado (normativo)

- El modelo `Photo` SHALL exponer `availability` y una marca de **última verificación** `availabilityCheckedAt?` que el backend actualiza al recibir un reporte (P4).
- El backend SHALL exponer los endpoints de reporte **(a) individual** `PATCH /api/v1/photos/:photoId/availability` y **(b) batch** `POST /api/v1/photos/availability` (P2) para que el **propietario de una foto** reporte su disponibilidad observada en Drive (`available` | `unavailable`). Reportar sobre una foto ajena o inexistente → **404 uniforme** (en batch, la entrada ajena/inexistente no se aplica y no hace fallar el resto).
- Al recibir un reporte, el backend SHALL actualizar `availability` y `availabilityCheckedAt`. Un reporte `available` sobre una foto antes `unavailable` la **recupera** (D9).
- `GET /albums/:id` y `GET /library` SHALL incluir `availability` y `availabilityCheckedAt` de cada foto y devolverlas **todas** sin filtrar; el cliente decide cómo mostrar las `unavailable` (P3, D9).
- La verificación es **perezosa**: no hay proceso del backend que verifique por su cuenta. El estado solo cambia cuando un cliente reporta.
- Renombrar/mover en Drive NO SHALL afectar `availability` (se referencia por `driveFileId`); solo eliminar/papelera/sin-permiso/inaccesible produce `unavailable`, según lo que el cliente observe y reporte.
- Todas las operaciones requieren sesión válida (401 sin ella).

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **P1 — Modelo de verificación:** **el cliente verifica contra Drive → el backend persiste.** El backend NO consulta la Drive API (no maneja bytes; `drive.file` solo deja al propietario ver sus archivos). La verificación real vive en la app (M6 app); el backend es la fuente de verdad del estado conocido.

- **P2 — Endpoints de reporte (ambos):**
  - **(a)** `PATCH /api/v1/photos/:photoId/availability`, body `{ availability: 'available' | 'unavailable' }` — reporte individual.
  - **(b)** `POST /api/v1/photos/availability`, body `{ reports: [{ photoId, availability }] }` — batch, para reportar varias tras revisar un álbum. En batch, cada entrada se valida por foto; una foto ajena/inexistente en la lista se ignora o se reporta como no aplicada (no debe hacer fallar todo el batch ni revelar existencia de fotos ajenas — el backend solo aplica sobre fotos del propietario).

- **P3 — El backend marca, no filtra:** `GET /albums/:id` y `GET /library` incluyen `availability` (y `availabilityCheckedAt`) y devuelven **todas** las fotos; el cliente decide cómo mostrar las `unavailable`. No se ocultan (D9: "no mostrar como disponible", no "ocultar"; además permite recuperar y dar feedback).

- **P4 — Se persiste `availabilityCheckedAt?: Date`:** marca temporal de la última verificación reportada. Se actualiza en cada reporte. Habilita heurísticas futuras sin sync activa.

## Checklist de implementación

- [ ] Añadir `availabilityCheckedAt?` al modelo `Photo` (P4) y a `PhotoRepository` (método de actualización de disponibilidad) — mock en memoria.
- [ ] Endpoints de reporte (a) `PATCH /photos/:photoId/availability` y (b) batch `POST /photos/availability` (P2), owner-only sobre la foto (404 uniforme para ajena/inexistente; en batch, entrada ajena no aplica sin romper el resto), body validado manualmente (`available`/`unavailable`).
- [ ] Actualizar `availability` + `availabilityCheckedAt`; recuperar (`unavailable` → `available`) soportado (D9).
- [ ] Incluir `availability` y `availabilityCheckedAt` en `GET /albums/:id` y `GET /library`; devolver todas sin filtrar (P3).
- [ ] Test que verifique que un cambio de nombre/ubicación (mismo `driveFileId`) no altera disponibilidad (por construcción; test de no-regresión del contrato).
- [ ] Errores uniformes y validación manual (patrón existente).
- [ ] Pruebas unitarias (reportar no disponible; recuperar; owner-only 404; reflejo en album/library) y e2e con login real (owner reporta sus fotos; un tercero no puede reportar → 404).
- [ ] Documentar endpoints en el README del backend.
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- El propietario reporta una foto como `unavailable` → queda marcada; aparece **marcada y no filtrada** en `GET /albums/:id` y `GET /library` (P3).
- Reportar `available` sobre una `unavailable` la recupera (D9).
- Un usuario que no es dueño de la foto no puede reportar → 404 uniforme.
- Renombrar/mover (mismo `driveFileId`) no cambia disponibilidad (test).
- El backend NO consulta la Drive API ni maneja bytes (verificado por grep/estructura).
- `availabilityCheckedAt` presente según P4.
- Sin sesión → 401.
- `build`, `test`, `test:e2e` pasan; endpoints documentados.

## Dependencias

- `memora-backend/spec04-fotografias.md` (Photo, `availability`, biblioteca, N:M) — PASS.
- `memora-backend/spec05-colaboradores.md` (lectura de álbum por owner/colaborador; fotos multi-Drive) — PASS.
- `memora-backend/spec02-autenticacion-google.md` (`drive-token` que el cliente usa para verificar) — PASS.
- `producto-mvp.md` (D9, D5, D8).
- Relacionado: M5 (diferido) — con M6, las fotos de colaboradores "se ven mientras estén disponibles" (D5) sin necesidad de copia.
- Habilita: M7 (visor) mostrará solo fotos disponibles; M6 app (la app verifica contra Drive y reporta).

## Notas de validación (Kiro) — PASS

**Veredicto: PASS** (validación quirúrgica, 2026-09-14).

**Evidencia:**
- `npm run build` → OK (exit 0).
- `npm test` → **78 unit** pasan (6 suites; +8 respecto a M6). El `ERROR [AllExceptionsFilter]` en el log es el caso de prueba intencional del filtro, no un fallo.
- `npm run test:e2e` → **77/77** pasan **a la primera** (sin flake esta vez).
- Grep dirigido: **no hay cliente Drive ni manejo de bytes** en `src/albums/photos/` (sin googleapis/fetch/axios/Buffer/createReadStream). El backend solo persiste lo reportado (P1 respetado).

**Criterios de la spec (todos cumplidos):**
- P1 (cliente verifica → backend persiste): `PhotosService.reportAvailability/reportAvailabilityBatch` solo escriben estado; ninguna llamada a Drive.
- P2: **(a)** `PATCH /api/v1/photos/:photoId/availability` y **(b)** batch `POST /api/v1/photos/availability`. Owner-only vía `requireOwnedPhoto` → **404** para foto ajena/inexistente (verificado sin mutar la foto ajena). En **batch**, las entradas de fotos ajenas/inexistentes se **saltan** sin romper el resto ni revelar existencia (unit + e2e).
- Recuperación `unavailable` → `available` soportada (D9) (unit + e2e).
- `availabilityCheckedAt` se sella en cada reporte y se expone (P4).
- P3: `GET /albums/:id` y `GET /library` incluyen `availability` + `availabilityCheckedAt` y **no filtran** las no disponibles (e2e dedicado).
- Renombrar/mover no cambia disponibilidad: test de no-regresión explícito (el modelo no tiene name/path; el reporte solo se ancla en `id`/`driveFileId`).
- Validación manual de entrada (`parse-availability-input.ts`): valor inválido → **400 uniforme**; body batch malformado → 400.
- Sesión requerida → 401 (e2e).

**Detalles de calidad:** buena separación (parser dedicado, método de repo `updateAvailability` que sella la fecha, batch tolerante a entradas ajenas). Comentarios que citan la spec y las decisiones P#. Sin deuda nueva.
