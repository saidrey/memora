# spec06 — Adoptar / "Guardar en mi biblioteca" (backend)

**Ámbito:** memora-backend
**Estado de validación:** ⏸️ DIFERIDA A POST-MVP (decisión del PO, 2026-09-14). No se implementa en el MVP. Ver "Decisión del PO" abajo.
**Backlog:** M5 (Adoptar / "Guardar en mi biblioteca") — parte backend

## Decisión del PO (2026-09-14) — M5 diferida a post-MVP

Tras analizar la viabilidad técnica (ver "Hallazgo técnico" más abajo), el PO decidió **no implementar la copia/adopción en el MVP**. Motivos:

1. Con el scope `drive.file` (ya fijado), copiar la foto de un colaborador al Drive del owner **no es viable server-side** y los mecanismos posibles (copia coordinada client-side, backend intermediando bytes, hacer que el aporte nazca en el Drive del owner) **introducen fricción o rompen decisiones técnicas aprobadas** (scope `drive.file`, "el backend no maneja bytes"). Ninguno ofrece un mecanismo transparente para el usuario en el MVP.
2. En su lugar, en el MVP las fotos aportadas por colaboradores **se ven mientras estén disponibles en el Drive de su propietario** (coherente con D5 y con la disponibilidad perezosa D9). Esto es el principio "Memora no es custodio" aplicado: no se copia; se referencia y se muestra mientras exista.

**Qué implica:** en el MVP NO existe el botón "Guardar en mi biblioteca". Si el colaborador borra su foto o abandona y borra el original, esa foto pasa a "no disponible" (D9) y deja de mostrarse. Esto es aceptable y esperado.

**Qué NO cambia:** D6 sigue siendo una decisión de producto válida a futuro. Esta spec queda como análisis técnico y se retomará cuando el PO decida (posiblemente requiriendo un cambio de scope o infraestructura). El siguiente módulo del backend pasa a ser **M6 — Disponibilidad**.

> El resto de este documento se conserva como **análisis técnico de referencia** para cuando se retome M5. No es de implementación en el MVP.

---

## Objetivo

Permitir que el **owner de un álbum** copie a **su propia biblioteca/Drive** una foto aportada por un colaborador (D6). La copia pertenece al owner y **sobrevive** aunque el colaborador se vaya o borre su original; el original del colaborador queda **intacto**. Esta spec define la coordinación en el backend y **decide el mecanismo técnico viable** dado el scope `drive.file`.

## Contexto y decisiones de producto que aplican

Ver `specs/producto-mvp.md`. Relevantes:

- **D6** — "Guardar en mi biblioteca": en el MVP **solo el owner** del álbum puede copiar una foto de un colaborador a su biblioteca. Es una **copia** al Drive del owner (no transferencia de propiedad); el original del colaborador queda intacto; la copia sobrevive aunque el colaborador se vaya o borre su original.
- **§Precisiones — M5 Adopción:** "la viabilidad de `drive.file` y el mecanismo de copia cross-Drive se validan en la spec de M5. **No se asume viable hasta confirmarlo.** Memora puede actuar como intermediario para ejecutar una copia **solicitada explícitamente** por el usuario; esto no lo convierte en almacenamiento de fotos."
- **D3/D4/D16** — Memora nunca borra de Drive; quitar/eliminar solo afecta relaciones.
- **D11** — Biblioteca personal = fotos que Memora conoce del usuario.

## Hallazgo técnico (verificado por el Tech Lead) — es la clave de esta spec

El scope actual de Memora es **`drive.file`** (decisión técnica fijada, aprobada por privacidad y para evitar la auditoría de scopes restringidos de Google). `drive.file` da acceso **únicamente a los archivos que la app creó, o que el usuario abrió explícitamente con el picker, en esa cuenta**. Consecuencias verificadas:

- El Drive del **owner** **NO** puede leer el archivo del **colaborador** con `drive.file`, aunque el archivo esté "compartido": otra cuenta con `drive.file` recibe **404** sobre ese `fileId` (comportamiento confirmado de la Drive API con `drive.file` cross-account).
- Por tanto, `files.copy` ejecutado con el token del owner sobre el `driveFileId` del colaborador **no es viable** (el owner no "ve" ese archivo).
- Memora **no maneja bytes** por diseño (Opción A): el backend no puede descargar el archivo del colaborador y resubirlo al Drive del owner sin romper ese principio y sin un scope de lectura amplio.

**Conclusión:** la "copia cross-Drive" de D6 **no se puede hacer server-side con `drive.file` sin más**. Hay que elegir un mecanismo. Eso es la decisión **P1** (bloqueante).

## Opciones de mecanismo para la copia (input para P1)

> Todas preservan: original del colaborador intacto, la copia pertenece al owner, Memora coordina pero no es custodio permanente de bytes.

- **Opción A — Copia client-side por el owner, con los bytes vía el colaborador (sin ampliar scope).**
  El **colaborador** (que sí puede leer su propio archivo con `drive.file`) genera, a petición de adopción, un acceso temporal a los bytes (p. ej. el cliente del colaborador sube una copia a una ubicación que el owner pueda abrir, o expone un enlace de descarga temporal). El **cliente del owner** obtiene esos bytes y los **sube a su propio Drive** con su `drive.file` (crea un archivo nuevo → la app lo posee). El backend solo orquesta el handshake y registra la nueva `Photo` del owner.
  - *Pros:* no amplía scope; respeta "backend no maneja bytes"; la copia la crea la app del owner (queda bajo `drive.file` del owner).
  - *Contras:* requiere que el colaborador esté disponible/haya dejado accesibles los bytes en el momento de adoptar (o un paso previo); coordinación cliente-cliente más compleja; si el colaborador ya borró el original, no hay de dónde copiar (coherente con D6: se adopta mientras el original exista).

- **Opción B — El backend intermedia la copia (bytes pasan por el backend solo en tránsito, no se almacenan).**
  El colaborador autoriza una lectura puntual; el backend descarga los bytes del archivo del colaborador y los sube al Drive del owner, **sin persistirlos** (stream en tránsito, borrado inmediato). Requiere que el backend pueda leer el archivo del colaborador → probablemente **ampliar el scope de lectura del colaborador** (p. ej. `drive.readonly` para el flujo de adopción) o que el colaborador cree y comparta explícitamente vía picker.
  - *Pros:* UX más simple (un botón, el backend hace el resto); no depende de coordinación cliente-cliente en vivo.
  - *Contras:* rompe parcialmente "el backend nunca maneja bytes" (aunque sea en tránsito); casi seguro exige **ampliar scope** → dispara la **auditoría de scopes restringidos de Google** (justo lo que se quiso evitar en la decisión técnica de scope). Impacto de privacidad y de proceso alto.

- **Opción C — Diferir M5 a post-MVP; en el MVP dejar el registro de intención sin copia real de bytes.**
  El backend modela la "adopción" (crea una `Photo` del owner que **referencia** la copia y marca el intento), pero la materialización real de los bytes se pospone hasta decidir scope/infra. Entrega el contrato y el modelo, no la copia funcional.
  - *Pros:* desbloquea el resto del backend sin comprometer la decisión de scope; no rompe principios.
  - *Contras:* M5 no queda funcionalmente completa en el MVP; hay que ser honestos con el backlog.

## Alcance (backend) — condicionado a P1

Independiente del mecanismo, el backend SHALL:

- Exponer `POST /api/v1/albums/:albumId/photos/:photoId/adopt` (autenticado, **owner-only** del álbum) que inicia/registra la adopción de una foto **de un colaborador** presente en ese álbum.
- Verificar que quien adopta es el **owner** del álbum (404 uniforme si no; patrón `AlbumAccessService.requireOwner` de M4) y que la `photoId` pertenece a una foto **de un colaborador** asociada a ese álbum (no una foto ya propia).
- Registrar la copia como una **nueva `Photo` propiedad del owner** (nuevo `driveFileId` del archivo en el Drive del owner), independiente del original: el original del colaborador y sus relaciones **no se tocan** (D6). La nueva Photo entra en la biblioteca del owner (D11) y, según P3, opcionalmente en el álbum.
- Garantizar que la copia **sobrevive** a que el colaborador abandone (M4) o borre su original: al ser una `Photo` distinta con su propio `driveFileId` en el Drive del owner, no depende del original.

El **detalle del mecanismo** (quién mueve los bytes y cómo) lo fija **P1**.

## Fuera de alcance

- Subida/optimización de bytes (app), salvo la coordinación mínima que P1 defina.
- Cambiar el scope de Google sin decisión explícita del PO (Opción B lo requeriría → es parte de P1).
- Disponibilidad (M6), visor (M7), NFC/QR (M8).
- Adopción por colaboradores o terceros (D6: solo el owner en el MVP).
- Transferencia de propiedad (D6 es copia, no transferencia).

## Comportamiento esperado (normativo, común a A/B/C)

- Solo el **owner** del álbum SHALL poder adoptar; cualquier otro → **404 uniforme** (no 403).
- Solo SHALL poder adoptarse una foto **de un colaborador** asociada al álbum. Adoptar una foto ya propia → error uniforme (ver P2 para el código).
- La adopción SHALL crear una `Photo` **nueva** cuyo `ownerId` es el owner y con **su propio `driveFileId`** (archivo en el Drive del owner). El backend NO SHALL reutilizar el `driveFileId` del colaborador para la copia.
- El original del colaborador (su `Photo`, su relación con el álbum, su archivo en Drive) NO SHALL modificarse.
- La copia SHALL persistir aunque después el colaborador abandone el álbum o borre su original.
- El backend NO SHALL almacenar bytes de forma persistente en ningún caso.
- Toda operación requiere sesión válida (401 sin ella).

## Decisiones de producto abiertas (requieren OK del PO)

- **P1 — Mecanismo de la copia (BLOQUEANTE).** Elige entre **Opción A** (copia client-side coordinada, sin ampliar scope), **Opción B** (backend intermedia bytes en tránsito, probablemente amplía scope → auditoría de Google), u **Opción C** (diferir la copia real a post-MVP; entregar modelo/contrato).
  - **Recomendación:** **Opción A.** Respeta las dos decisiones ya fijadas (scope `drive.file` y "el backend no maneja bytes") y mantiene a Memora como facilitador. Es más compleja de orquestar que B, pero B contradice frontalmente dos decisiones técnicas aprobadas y arrastra la auditoría de scopes restringidos de Google, con impacto real en privacidad, tiempos y publicación de la app. Si el PO prioriza UX simple por encima de eso, B; si prefiere no arriesgar el MVP con la copia real todavía, C.
  - **Impacto:** define toda la arquitectura de M5 (y parte de la app). Sin esta decisión no se puede cerrar la spec.

- **P2 — Código de error al adoptar algo no adoptable** (foto propia, foto no de colaborador, o foto no asociada al álbum).
  - **Recomendación:** **404 uniforme** cuando la foto no es un aporte de colaborador válido en ese álbum (coherente con el patrón "no revelar" de M2/M4); **400 `INVALID_REQUEST`** solo para entrada malformada. **Impacto:** UX del cliente (qué mensaje mostrar).

- **P3 — ¿La foto adoptada se asocia también al álbum, o solo entra en la biblioteca del owner?**
  - (a) Solo entra en la **biblioteca** del owner (queda como copia personal; el álbum sigue mostrando el original del colaborador).
  - (b) Además se **asocia al álbum** como foto del owner (el álbum tendría el original del colaborador y la copia del owner → posible duplicado visual).
  - **Recomendación:** **(a)** — "Guardar en **mi biblioteca**" es literal; evita duplicados en el álbum. **Impacto:** comportamiento visible en la UI del álbum.

- **P4 — ¿Qué metadatos hereda la copia?** (fecha de captura, dimensiones, tipo) del original del colaborador, o se recalculan al crear el archivo del owner.
  - **Recomendación:** heredar los metadatos mínimos (D8) conocidos por Memora (capturedAt, dimensiones, mime, tamaño) y fijar `createdAt` = fecha de adopción; `availability` = `available`. **Impacto:** bajo; consistencia de datos.

## Checklist de implementación (se completa tras aprobar P1–P4)

- [ ] Definir el contrato de `POST /api/v1/albums/:albumId/photos/:photoId/adopt` y el flujo según P1.
- [ ] Autorización owner-only vía `AlbumAccessService.requireOwner`; validar que la foto es aporte de un colaborador asociado al álbum (P2).
- [ ] Crear la `Photo` copia (nuevo `driveFileId` del owner, metadatos según P4), sin tocar el original.
- [ ] Asociación a álbum según P3.
- [ ] (Según P1) coordinación del traslado de bytes: contrato del handshake (A) / intermediación en tránsito sin persistir (B) / registro de intención (C).
- [ ] Errores uniformes (`adopt.errors.ts` o reutilizar `collaborators.errors.ts`) y validación manual.
- [ ] Env/config nuevas si P1 las requiere, documentadas y en `test/jest-setup.ts` si aplica.
- [ ] Pruebas unitarias (owner adopta; no-owner → 404; foto propia no adoptable; la copia sobrevive a que el colaborador borre/abandone) y e2e con login real de owner + colaborador.
- [ ] Documentar endpoints en el README del backend.
- [ ] `npm run build`, `npm test`, `npm run test:e2e` pasan.

## Criterios de validación (los revisa Kiro)

- El owner adopta una foto de un colaborador → se crea una `Photo` nueva del owner con su propio `driveFileId`; el original del colaborador queda intacto.
- La copia sobrevive a que el colaborador abandone el álbum o borre su original (verificado en test).
- No-owner no puede adoptar → 404 uniforme; adoptar algo no adoptable → error según P2.
- El backend no almacena bytes de forma persistente (por construcción / verificado por grep).
- Comportamiento de asociación al álbum coherente con P3; metadatos según P4.
- `build`, `test`, `test:e2e` pasan; endpoints documentados.

## Dependencias

- `memora-backend/spec05-colaboradores.md` (roles, membresía, aporte de colaboradores) — PASS.
- `memora-backend/spec04-fotografias.md` (Photo, biblioteca, N:M) — PASS.
- `memora-backend/spec02-autenticacion-google.md` (broker `drive-token`, scope `drive.file`) — PASS.
- `producto-mvp.md` (D6 y §Precisiones M5).
- **Decisión técnica de scope** (`specs/README.md`): scope `drive.file`. La Opción B de P1 la pondría en cuestión.
