# spec08 — Visor de foto a pantalla completa (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones tomadas por Kiro con recomendación, confirmadas por el PO; 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** complemento de M3/M2 en app — visor de imagen a pantalla completa. FASE 2 (app). Consume el detalle de álbum de `memora-app/spec04`.

## Objetivo
Permitir que, dentro de la app y estando autenticado, al **tocar una miniatura** el usuario **abra la foto a pantalla completa** en resolución completa, con **zoom/pan** y **navegación (swipe) entre las fotos** del álbum. Cierra el vacío de spec04, que solo mostraba miniaturas.

## Contexto y decisiones que aplican
- `memora-app/spec04` muestra el grid de miniaturas del álbum (miniaturas descargadas de Drive con el `drive-token`). Esta spec añade la **vista de detalle a pantalla completa** de una foto.
- **D8 — Metadatos mínimos.** No se muestra geolocalización (no se guarda). Se pueden mostrar metadatos básicos si el backend los expone (dimensiones, fecha de captura), pero no es obligatorio en este corte.
- **M6 — Disponibilidad.** Una foto `unavailable` no se puede cargar desde Drive; el visor SHALL mostrar un estado claro de "no disponible" en vez de un error.
- **Scope `drive.file` + Opción A.** La imagen se obtiene de Drive con el `drive-token`, tratando Drive como endpoint HTTP (mismo patrón que las miniaturas de spec04); el backend no sirve bytes.

## Alcance (app)
- Abrir la foto **a pantalla completa** al tocar su miniatura en el detalle del álbum (spec04) y en cualquier grid de fotos de la app.
- Cargar la **imagen en resolución completa** desde Drive (no la miniatura escalada), con el `drive-token` en el header `Authorization`.
- **Zoom y pan** (pellizcar/doble toque) y **navegación por swipe** entre las fotos del álbum (misma lista/orden que el detalle).
- Indicador de carga mientras baja la imagen; manejo de foto `unavailable` (M6) y de error de carga.
- Reutiliza el servicio de lectura de Drive de spec04 (descarga con token + caché); no duplica el pipeline.

## Fuera de alcance
- Edición de la foto, borrar desde el visor (quitar del álbum vive en spec04), compartir la foto individual.
- Visor **público** anónimo (es web, FASE 3).
- Presentación tipo slideshow automático; descarga a galería.
- Diseño visual final.

## Comportamiento esperado (normativo)
- Al **tocar una miniatura**, la app SHALL abrir una vista a pantalla completa con la foto en **resolución completa** (descargada de Drive con el `drive-token`).
- La vista SHALL soportar **zoom** (pellizco y doble toque) y **pan**, y **swipe** para pasar a la foto anterior/siguiente del álbum, respetando el orden del detalle.
- Mientras la imagen carga, la app SHALL mostrar un indicador; ante error de red o token, SHALL mostrar un estado de error claro con opción de reintentar, sin romper la navegación.
- Si la foto es `unavailable` (M6), la app SHALL mostrar un estado "no disponible" en vez de intentar cargarla.
- Si al pedir/usar el `drive-token` se recibe `DRIVE_REAUTHORIZATION_REQUIRED`, la app SHALL delegar en el flujo de re-autorización de Drive (spec06), sin cerrar sesión (D10).
- El `drive-token` SHALL enviarse **solo** a la Drive API; ningún token SHALL escribirse en logs.
- NO SHALL mostrarse geolocalización (D8).

## Decisiones (tomadas por Kiro, confirmadas por el PO)
- **Imagen full-res desde Drive con el `drive-token` en header** (mismo patrón que las miniaturas de spec04), no la miniatura escalada. Coherente con `drive.file`.
- **Zoom/pan + swipe** con el paquete `photo_view` (`PhotoViewGallery`) o equivalente; no reinventar gestos.
- **Punto de entrada:** desde el detalle del álbum (spec04) y cualquier grid de fotos; la vista recibe la lista de fotos + índice inicial.
- **`unavailable`:** placeholder "no disponible", sin intento de descarga.

## Checklist de implementación
- [ ] Añadir dependencia de visor con zoom/pan y galería con swipe (`photo_view` o equivalente).
- [ ] Reutilizar el servicio de lectura de Drive de spec04 para bajar la **imagen full-res** (con `drive-token` en header + caché); no duplicar el pipeline.
- [ ] Pantalla/visor a pantalla completa: recibe la lista de fotos del álbum + índice inicial; zoom, pan, swipe entre fotos; indicador de carga; estado de error con reintento.
- [ ] Estado "no disponible" para fotos `unavailable` (M6).
- [ ] Integrar el `onTap` de las miniaturas del detalle de álbum (spec04) para abrir el visor en la foto tocada.
- [ ] Delegar `DRIVE_REAUTHORIZATION_REQUIRED` en el flujo de spec06; sin tokens en logs; sin geolocalización.
- [ ] `flutter analyze` pasa y compila.

## Criterios de validación (los valida el PO en el dispositivo)
- Tocar una miniatura abre la foto grande (resolución completa), no la miniatura ampliada borrosa.
- Se puede hacer zoom/pan y pasar entre fotos con swipe.
- Una foto no disponible muestra "no disponible" en vez de error.
- Errores de carga permiten reintentar sin romper la navegación.
- Ningún token en logs; no se muestra ubicación.
- `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec04-ui-albumes.md` (detalle de álbum, grid de miniaturas, servicio de lectura de Drive) — en implementación.
- `memora-app/spec06-sesion-y-reauth-drive.md` (re-autorización de Drive) — APROBADA.
- `memora-app/spec02-login-google.md` (`drive-token`) — PASS.
