# spec07 — Compartir, visor y NFC/QR (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones tomadas por Kiro con recomendación, informadas al PO; 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** M7 + M8 en app. FASE 2 (app), ítem F del ROADMAP. Consume `memora-backend/spec09` (M7, PASS) y `spec10` (M8, PASS WITH NOTES).

## Objetivo
Implementar en `memora-app` la interfaz para **compartir un álbum** (enlace de compartición del visor, M7), gestionar su **visibilidad** (D17), y **asociar/gestionar etiquetas NFC/QR** que apuntan al álbum (M8), reutilizando los endpoints del backend.

## Contexto y decisiones que aplican
- **D2 — Visor por enlace** (enlace/QR/NFC), no descubrible; gestión requiere auth.
- **D17 — Visibilidad del álbum** `PRIVATE`/`PUBLIC` (editable solo por owner; ya cubierta en la UI de álbumes spec04, aquí se relaciona con compartir).
- **D14 — NFC/QR** se asocian a un álbum ya creado; URL estable; posibilidad de bloquear (soft-delete).

## Contrato real del backend (M7/M8 — PASS)
- **Compartir (M7, spec09):** `POST /api/v1/albums/:albumId/share-link` (owner-only) → crea o devuelve el existente `{ token, url }` (URL sobre `APP_SHARE_BASE_URL`, `/s/{token}`); `DELETE /api/v1/albums/:albumId/share-link` (owner-only) revoca; estado del enlace consultable en el álbum. Público: `GET /api/v1/shared/:token` (resuelve la vista de solo lectura).
- **NFC/QR (M8, spec10):** `POST /api/v1/albums/:albumId/nfc-qr-tags` (owner-only) → crea etiqueta `{ id, type 'NFC'|'QR', token, url }` (URL `/n/{token}`); `PATCH /api/v1/nfc-qr-tags/:id/disable` (owner-only) bloquea (soft-delete); `GET /api/v1/nfc-qr-tags/:id` (owner-only) consulta. Público: `GET /api/v1/n/:token` → redirección 302 al ShareLink activo del álbum.

## Alcance (app)
- **Compartir (owner):** desde el detalle del álbum, generar/obtener el enlace de compartición y **compartirlo** con el share sheet; revocarlo. Mostrar si el álbum es `PRIVATE`/`PUBLIC` (D17) y enlazar a la edición de visibility (spec04).
- **NFC/QR (owner):** crear una etiqueta (NFC o QR) para el álbum; **mostrar el QR** en pantalla (para escanear/imprimir) y **la URL** de la etiqueta (para grabar en NFC); listar/consultar y **bloquear** (disable) una etiqueta.
- **Escritura NFC** (grabar el tag físico): ver decisiones.
- Extiende el detalle de álbum (spec04) con estas acciones owner-only.

## Fuera de alcance
- El **visor** como tal (ver un álbum compartido sin login) es principalmente **web** (FASE 3); esta spec cubre **generar y gestionar** el enlace/etiquetas desde la app, no renderizar el visor anónimo.
- Catálogo/descubrimiento público (no existe, KISS). Diseño visual final.

## Comportamiento esperado (normativo)
- La app SHALL permitir al **owner** crear/obtener el enlace de compartición (`POST .../share-link`) y compartir su `url` con el share sheet; y **revocarlo** (`DELETE .../share-link`) con confirmación.
- La app SHALL mostrar la **visibilidad** del álbum (D17) y permitir cambiarla (reusando la edición de spec04, owner-only).
- La app SHALL permitir al owner **crear una etiqueta NFC o QR** (`POST .../nfc-qr-tags`), **mostrar el código QR** generado a partir de la `url`, mostrar la `url` para NFC, y **bloquear** una etiqueta (`PATCH .../disable`) con confirmación.
- Todas estas acciones SHALL ser **owner-only**; ocultas/deshabilitadas para collaborator (D1).
- La app NO SHALL exponer PII ni datos internos al compartir; comparte solo la `url` que da el backend.
- Toda llamada por `ApiClient` (Bearer); ningún token en logs; errores con mensajes claros.

## Decisiones (tomadas por Kiro, informadas al PO)
- **Generación del QR:** en el **cliente**, a partir de la `url` que devuelve el backend (paquete `qr_flutter`), en vez de pedir una imagen al backend. Simple y offline.
- **Escritura NFC física:** **fuera de este corte.** La app **muestra la URL** de la etiqueta para que el usuario la grabe con la app/herramienta de NFC de su preferencia; la escritura NFC nativa (paquete `nfc_manager`) se difiere por complejidad y variabilidad de hardware. *Recomendación: validar primero compartir + QR, que cubren el caso de uso principal; añadir escritura NFC nativa después si el PO lo pide.*
- **Visor anónimo:** no se implementa en la app (es web, FASE 3); la app solo genera/gestiona los enlaces. La app puede abrir la `url` en el navegador del sistema para previsualizar.
- **Un enlace por álbum (M7 P5):** la UI refleja "el enlace del álbum" (uno), coherente con el backend.

## Checklist de implementación
- [ ] Extender `AlbumsApi` (o `SharingApi`) sobre `ApiClient`: crear/obtener share-link, revocar; crear tag NFC/QR, consultar, disable.
- [ ] UI owner en el detalle del álbum: sección "Compartir" (obtener/mostrar/compartir enlace, revocar) + estado de visibilidad (enlaza a editar, spec04).
- [ ] UI owner: crear etiqueta NFC/QR; **render del QR** desde la `url` (`qr_flutter`); mostrar la `url` para NFC; listar y bloquear (disable) con confirmación.
- [ ] Acciones owner-only (ocultas/deshabilitadas para collaborator).
- [ ] Compartir con share sheet del sistema; abrir `url` en navegador para previsualizar (opcional).
- [ ] Manejo de errores (404 ajeno, enlace revocado, tag disabled) con mensajes claros; sin tokens en logs.
- [ ] `flutter analyze` pasa y compila.

## Criterios de validación (los valida el PO en el dispositivo)
- El owner genera el enlace de compartición y lo comparte; puede revocarlo.
- El owner crea una etiqueta QR y ve el código en pantalla; crea una NFC y ve la URL para grabar; puede bloquear una etiqueta.
- Estas acciones no están disponibles para un colaborador.
- Al abrir la `url` compartida en un navegador, resuelve al visor del backend (o su redirección); las etiquetas bloqueadas dejan de resolver.
- Ningún token en logs. `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec04-ui-albumes.md` (detalle de álbum + visibility) — en implementación.
- `memora-backend/spec09-compartir-visor.md` (M7) — PASS. `memora-backend/spec10-nfc-qr.md` (M8) — PASS WITH NOTES.
- **Nota:** el visor anónimo (ver álbum compartido sin login) se implementa en **web** (FASE 3), no aquí.
