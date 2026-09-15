# spec09 — Programar etiqueta NFC desde la app (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones P1–P3 cerradas por el PO, 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** M8 (NFC/QR) en app — **escritura NFC nativa**. Continúa lo que `memora-app/spec07-compartir-nfc-qr.md` dejó diferido ("la app muestra la URL para grabar; escritura NFC nativa después"). Consume el backend M8 (`memora-backend/spec10`, PASS WITH NOTES).

> **Nota de numeración (para el PO):** pediste "M8" pero el consecutivo real de la carpeta `memora-app/` es **spec09** (spec08 es el visor de fotos in-app). El módulo funcional sigue siendo **M8**.

## Objetivo
Permitir que, desde la app Flutter, el **owner** de un álbum **programe una etiqueta NFC física** escribiendo en ella un registro NDEF de tipo URI con la **URL estable de Memora** (`https://memora.app/n/{token}`) que le entrega el backend, verifique la escritura, e (opcionalmente y de forma explícita) **bloquee la etiqueta como solo lectura**. El backend sigue siendo la fuente de verdad de la relación `token → álbum`.

## Contexto y decisiones que aplican
- **D14 — NFC/QR se asocian a un álbum ya creado; URL estable.** El flujo del MVP es: crear álbum → seleccionar álbum → programar etiqueta → la etiqueta queda asociada al álbum (vía el token que resuelve el backend).
- **M8 backend (`memora-backend/spec10`, PASS):** ver contrato abajo. La app **no inventa el token**: lo obtiene del backend, que es la fuente de verdad de `token → álbum`.
- **El NFC contiene solo la URL de Memora**, nunca fotos, nombre de álbum, IDs internos ni PII. La URL no depende de Google Drive y sigue funcionando aunque cambie el proveedor de almacenamiento (la resolución es indirecta en el backend: token → álbum → ShareLink activo, spec10).
- **Owner-only** (D1): crear/programar etiquetas es acción de administración del álbum.

## Contrato real del backend (M8 — `memora-backend/spec10`, PASS)
- `POST /api/v1/albums/:albumId/nfc-qr-tags` (owner-only), body `{ type: 'NFC' | 'QR' }` → responde `{ id, albumId, type, token, status: 'enabled', url, createdAt, updatedAt }`, con **`url = https://memora.app/n/{token}`** (base configurable `APP_NFC_QR_BASE_URL`). Cada `POST` crea una etiqueta nueva (sin dedup).
- `GET /api/v1/nfc-qr-tags/:id` (owner-only) → consulta estado del tag.
- `PATCH /api/v1/nfc-qr-tags/:id/disable` (owner-only) → bloquea el tag en el **backend** (soft-delete: la resolución deja de funcionar). **OJO:** esto es distinto del bloqueo físico de la etiqueta a solo-lectura (ver decisiones).
- Público: `GET /api/v1/n/:token` → redirección 302 al visor del álbum (no lo usa la app para programar).

> La app **crea la etiqueta en el backend** (`POST .../nfc-qr-tags` con `type: 'NFC'`) para obtener la `url`, y **escribe esa `url`** en el chip físico. Si un nombre exacto de campo difiere, prevalece lo implementado en `memora-backend/spec10`.

## Flujo funcional propuesto
```
1. Owner abre un álbum (spec04) y elige "Programar etiqueta NFC" (owner-only).
2. La app pide al backend POST /albums/:albumId/nfc-qr-tags { type: 'NFC' }
   -> obtiene { token, url }  (url = https://memora.app/n/{token})
3. La app pide "Acerca la etiqueta NFC" e inicia una sesión NFC.
4. Detecta el tag y lee si ya contiene un NDEF existente:
     - vacío/formateable -> continúa
     - ya contiene datos -> AVISA y pide confirmación explícita antes de sobrescribir
5. Escribe un registro NDEF URI con la url.
6. Re-lee el tag y VERIFICA que el NDEF escrito coincide con la url.
7. Informa "Etiqueta programada".
8. (Opcional, explícito) Ofrece "Bloquear como solo lectura":
     - Android: soportado -> advierte que es IRREVERSIBLE y lo hace si el usuario confirma.
     - iOS: no soportado de forma fiable -> la opción se oculta/deshabilita con explicación.
```
Cancelación, tag incompatible, tag bloqueado o error de escritura → mensaje claro de qué pasó, sin dejar estado ambiguo.

## Alcance (app)
- Acción **"Programar etiqueta NFC"** en el detalle del álbum (owner-only), reutilizando la sección de compartir/NFC de spec07.
- Obtener `{ token, url }` del backend (`POST .../nfc-qr-tags { type: 'NFC' }`) vía `ApiClient`.
- **Sesión NFC** (con `nfc_manager`): detectar tag, **leer NDEF existente**, **escribir** NDEF URI con la `url`, **re-leer y verificar**.
- Detección de **tag ya usado** (NDEF existente) → confirmación explícita antes de sobrescribir.
- **Bloqueo a solo-lectura** como acción **separada y explícita**, solo donde la plataforma lo soporta (Android), con advertencia de irreversibilidad.
- Manejo de errores/cancelación con mensajes claros por caso (incompatible, bloqueado, cancelado, fallo de escritura, fallo de verificación).

## Fuera de alcance
- **QR:** conceptualmente `QR → misma url que NFC`. La generación/visualización del QR ya está contemplada en `spec07` (QR en cliente). Esta spec **no** la bloquea ni la reimplementa.
- Tags prefabricados/preasociados, gestión avanzada de múltiples etiquetas por álbum, inventario, marketplace, migración de etiquetas, personalización física, otros tipos de NFC. (Fuera del MVP.)
- Emulación HCE / que el teléfono actúe como tag. Lectura de tags para navegar al visor desde la app (el visor es web; el SO abre la url del tag en el navegador).
- Diseño visual final.

## Comportamiento esperado (normativo)
- La acción de programar NFC SHALL ser **owner-only**; oculta/deshabilitada para collaborator (D1).
- La app SHALL obtener la `url` a escribir del backend (`POST .../nfc-qr-tags { type: 'NFC' }`); NO SHALL construir el token por su cuenta.
- La app SHALL escribir en el tag **únicamente** un registro **NDEF de tipo URI** con la `url` de Memora; NO SHALL escribir fotos, nombre de álbum, IDs internos ni PII.
- Antes de escribir, la app SHALL **leer el tag** y, si ya contiene un NDEF con datos, SHALL pedir **confirmación explícita** antes de sobrescribir.
- Tras escribir, la app SHALL **re-leer y verificar** que el contenido coincide con la `url`; si la verificación falla, SHALL informarlo y NO dar la programación por exitosa.
- El **bloqueo a solo-lectura** SHALL ser una acción **explícita y separada** (nunca automática), SHALL advertir que es **irreversible**, y SHALL ofrecerse **solo en plataformas que lo soportan** (Android). En iOS, donde Core NFC no lo soporta de forma fiable, la opción SHALL ocultarse/deshabilitarse con una explicación.
- Ante **cancelación**, **tag incompatible** (no NDEF/Type 2), **tag ya bloqueado** o **error de escritura**, la app SHALL informar claramente el caso concreto, sin dejar estado ambiguo.
- La app SHALL manejar que iOS y Android tienen capacidades distintas (ver Riesgos); no SHALL asumir que lo disponible en Android existe en iOS.
- Ningún token/URL sensible SHALL escribirse en logs más allá de lo necesario para depurar; sin PII.

## Decisiones técnicas importantes
- **Paquete:** `nfc_manager` (estándar actual de Flutter para NDEF read/write en Android e iOS). En Android expone la clase `Ndef` (write + `makeReadOnly`); en iOS usa Core NFC.
- **Formato escrito:** un único registro **NDEF URI** (bien formado, con el prefijo de URI que corresponda) con la `url`. Cabe de sobra en MIFARE Ultralight (~137 bytes NDEF; una URL de Memora ronda ~30-60 bytes).
- **Verificación post-escritura:** re-leer el NDEF del mismo tag en la misma sesión y comparar la URI escrita.
- **Detección de tag usado:** leer el `Ndef` antes de escribir; si `cachedMessage`/records no está vacío, tratar como "ya usado" y pedir confirmación.
- **La app crea la etiqueta en el backend al programar** (para obtener token/url). El backend es la fuente de verdad de `token → álbum`; el chip solo lleva la URL.

## Decisiones de producto (aprobadas por el PO)

> Cerradas por el PO (2026-09-14). Vinculantes para la implementación.

- **P1 — La etiqueta se crea en el backend al INICIAR la programación** (`POST .../nfc-qr-tags` para obtener token/url), que es lo que el backend ya soporta (PASS) y mantiene el backend como fuente de verdad. Si la escritura física falla, el token puede quedar huérfano (inocuo: un `/n/{token}` sin chip nunca se escanea) y se limpia con `disable`.
- **P2 — "Bloquear en backend" (`disable`) y "bloquear el chip a solo-lectura" son cosas separadas.** En esta spec el bloqueo a solo-lectura es **solo físico y opcional** (Android). El `disable` lógico del backend (revocar la etiqueta) vive en la UI de spec07. Programar ≠ revocar; no se mezclan.
- **P3 — Si la escritura falla tras crear el token,** la app ofrece **reintentar con el mismo token**; si el usuario desiste, ofrece `disable` de ese token (limpieza), pero **nunca** de forma automática.

## Compatibilidad Android / iOS (análisis)
- **Android (NfcAdapter / `Ndef`):** lectura NDEF ✅, escritura NDEF URI ✅, `makeReadOnly()` para bloquear a solo-lectura ✅ (irreversible). MIFARE Ultralight = NFC Forum Type 2, NDEF-compatible. Requiere permiso `android.permission.NFC` en el manifest y NFC activado.
- **iOS (Core NFC):** lectura NDEF ✅, **escritura NDEF ✅** (desde iOS 13, `NFCNDEFReaderSession` con `writeNDEF`). **Bloqueo permanente a solo-lectura: NO soportado de forma fiable** por Core NFC (no expone un equivalente estable a `makeReadOnly`). Requiere capability **Near Field Communication Tag Reading** en el entitlement, la clave `NFCReaderUsageDescription` en `Info.plist`, y solo funciona en iPhone 7+ con iOS reciente. La sesión iOS muestra una hoja del sistema.
- **Diferencia clave a reflejar en UX:** el botón "Bloquear como solo lectura" solo aparece en Android; en iOS se explica que no está disponible.
- **Comportamiento con tag ya escrito:** ambas plataformas permiten leer el NDEF previo; la lógica de "pedir confirmación antes de sobrescribir" es de la app, no del SO.

## Checklist de implementación
- [ ] Añadir `nfc_manager` a `pubspec.yaml`. Android: permiso `NFC` en el manifest. iOS: capability NFC Tag Reading + `NFCReaderUsageDescription` en `Info.plist`.
- [ ] Extender la API de etiquetas (spec07/`AlbumsApi`) para `POST .../nfc-qr-tags { type: 'NFC' }` y obtener `{ token, url }`.
- [ ] Servicio NFC (`NfcProgrammingService` o similar): iniciar sesión, detectar tag, leer NDEF existente, escribir NDEF URI, re-leer y verificar; abstraer diferencias Android/iOS.
- [ ] Flujo/controlador (`ChangeNotifier`): estados (esperando tag, escribiendo, verificando, éxito, error por caso, cancelado).
- [ ] UI "Programar etiqueta NFC" en el detalle del álbum (owner-only): guía "acerca la etiqueta", confirmación de sobrescritura si el tag ya tiene datos, resultado.
- [ ] Acción separada y explícita "Bloquear como solo lectura" **solo en Android**, con advertencia de irreversibilidad; oculta/deshabilitada en iOS con explicación.
- [ ] Manejo de errores por caso (incompatible, bloqueado, cancelado, fallo de escritura, fallo de verificación) con mensajes claros.
- [ ] `flutter analyze` pasa y compila (Android e iOS).

## Criterios de validación (los valida el PO en el dispositivo)
- El owner programa una etiqueta NFC nueva: la app obtiene la url del backend, escribe el NDEF URI y verifica; al acercar el tag a un lector/teléfono, abre `https://memora.app/n/{token}`.
- Una etiqueta que ya tenía datos pide confirmación antes de sobrescribir.
- En Android, el bloqueo a solo-lectura funciona (tras confirmarlo) y luego el tag ya no se puede reescribir. En iOS, la opción no aparece (o explica que no está disponible).
- Cancelar, acercar un tag incompatible o un tag bloqueado, o un fallo de escritura, muestran mensajes claros y distintos.
- El chip contiene solo la URL (no fotos, nombre de álbum ni IDs). Sin PII en logs.
- `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec04-ui-albumes.md` (detalle de álbum, punto de entrada) — en implementación.
- `memora-app/spec07-compartir-nfc-qr.md` (sección de compartir/NFC/QR; QR ya cubierto ahí) — APROBADA.
- `memora-backend/spec10-nfc-qr.md` (M8: `POST .../nfc-qr-tags`, url estable, `disable`) — PASS WITH NOTES.
- `memora-app/spec02` (sesión, `ApiClient`) — PASS.
